#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // A second launch asked this (already running) instance to come forward.
  void HandleActivateRequest();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native -> Dart channel used to bring the window forward (the Dart side
  // knows about tray-panel mode and restores the right layout).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> instance_channel_;

  // Dart -> native channel for window styling the window_manager plugin does
  // not offer (rounded corners of the tray panel).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> window_channel_;

  // Registered window message sent by a second launch (see main.cpp).
  UINT activate_message_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
