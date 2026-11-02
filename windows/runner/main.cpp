#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Named mutex that makes TokenBar a single-instance app. `Local\` scopes it to
// the current login session, so different users on the same machine can each
// run their own copy.
constexpr wchar_t kSingleInstanceMutex[] = L"Local\\dev.tokenbar.app.SingleInstance";

// Must match kWindowClassName in win32_window.cpp and the message registered in
// flutter_window.cpp.
constexpr wchar_t kWindowClassName[] = L"TOKENBAR_RUNNER_WIN32_WINDOW";
constexpr wchar_t kActivateMessageName[] = L"TokenBar.ActivateInstance";

// Asks the already running instance to bring its window forward. The other
// process may still be starting (it owns the mutex before its window exists),
// so retry for a few seconds.
void ActivateRunningInstance() {
  const UINT activate_message = ::RegisterWindowMessageW(kActivateMessageName);
  for (int attempt = 0; attempt < 50; ++attempt) {
    HWND existing = ::FindWindowW(kWindowClassName, nullptr);
    if (existing) {
      DWORD pid = 0;
      ::GetWindowThreadProcessId(existing, &pid);
      // This process was just launched by the user, so it may hand the
      // foreground right to the running instance.
      ::AllowSetForegroundWindow(pid);
      ::PostMessageW(existing, activate_message, 0, 0);
      return;
    }
    ::Sleep(100);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Only one TokenBar at a time: a second launch just wakes the first one.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"TokenBar", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // The normal teardown (Flutter engine / Dart VM shutdown) takes several
  // seconds, during which the window sat there frozen. Everything TokenBar
  // keeps is persisted at the moment it changes, and the Dart side removed the
  // tray icon before asking to quit, so there is nothing left to flush: hide
  // the window and end the process right away.
  if (window.GetHandle()) {
    ::ShowWindow(window.GetHandle(), SW_HIDE);
  }
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
