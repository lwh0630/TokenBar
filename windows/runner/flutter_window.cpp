#include "flutter_window.h"

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <dwmapi.h>
#include <winhttp.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

namespace {

// Read the interactive user's manual proxy. WinHTTP owns the returned strings
// until the caller frees them with GlobalFree.
flutter::EncodableValue SystemProxySettings() {
  WINHTTP_CURRENT_USER_IE_PROXY_CONFIG config = {};
  if (!::WinHttpGetIEProxyConfigForCurrentUser(&config)) {
    return flutter::EncodableValue();
  }
  const std::string proxy = Utf8FromUtf16(config.lpszProxy);
  const std::string bypass = Utf8FromUtf16(config.lpszProxyBypass);
  ::GlobalFree(config.lpszProxy);
  ::GlobalFree(config.lpszProxyBypass);
  ::GlobalFree(config.lpszAutoConfigUrl);
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("proxy"), flutter::EncodableValue(proxy)},
      {flutter::EncodableValue("bypass"), flutter::EncodableValue(bypass)},
  });
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project),
      activate_message_(::RegisterWindowMessageW(L"TokenBar.ActivateInstance")) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  instance_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "tokenbar/instance",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "tokenbar/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setRoundedCorners") {
          result->NotImplemented();
          return;
        }
        const auto* round = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
        HWND hwnd = GetHandle();
        if (!round || !hwnd) {
          result->Success(flutter::EncodableValue(false));
          return;
        }
        // Windows 11 only (DWMWA_WINDOW_CORNER_PREFERENCE = 33): a frameless
        // popup is square unless it opts in. Older Windows rejects the
        // attribute; the reply tells Dart whether the corners really are round
        // so it only draws a rounded outline when the window is clipped to match.
        const DWORD preference = *round ? 2 /* DWMWCP_ROUND */ : 0 /* DWMWCP_DEFAULT */;
        const HRESULT hr = ::DwmSetWindowAttribute(hwnd, 33, &preference, sizeof(preference));
        result->Success(flutter::EncodableValue(SUCCEEDED(hr) && *round));
      });
  proxy_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dev.tokenbar.app/system_proxy",
          &flutter::StandardMethodCodec::GetInstance());
  proxy_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "get") {
          result->Success(SystemProxySettings());
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::HandleActivateRequest() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  // Preferred: let Dart restore the window, so tray-panel mode is left properly.
  // If Dart is not listening yet (still starting up), fall back to a plain
  // native restore.
  auto fallback = [hwnd]() {
    if (::IsIconic(hwnd)) {
      ::ShowWindow(hwnd, SW_RESTORE);
    } else {
      ::ShowWindow(hwnd, SW_SHOW);
    }
    ::SetForegroundWindow(hwnd);
  };
  if (!instance_channel_) {
    fallback();
    return;
  }
  instance_channel_->InvokeMethod(
      "activate", nullptr,
      std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
          nullptr, nullptr, fallback));
}

void FlutterWindow::OnDestroy() {
  instance_channel_ = nullptr;
  window_channel_ = nullptr;
  proxy_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == activate_message_) {
    HandleActivateRequest();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
