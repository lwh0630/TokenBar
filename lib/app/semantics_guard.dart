import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Whether this build must not publish a semantics (accessibility) tree.
///
/// Flutter 3.47's Windows engine dereferences a null parent in
/// `AccessibilityBridge::CreateRemoveReparentedNodesUpdate` (an `assert` that release builds
/// compile out) once an accessibility client (a screen reader, an input-method or
/// automation tool probing windows) is attached and a route is pushed or popped: the process
/// dies with an access violation (flutter/flutter#175041, #182444, #192689, #195144; our own
/// minidumps symbolize to the same frame, fault address 0x48). The malformed tree comes from
/// the framework side, so until a Flutter upgrade carries the fix the Windows app publishes
/// none. Other platforms are unaffected. Revisit after upgrading Flutter.
bool get skipSemanticsOnThisPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Drops everything below from the semantics tree on platforms that crash on it
/// ([skipSemanticsOnThisPlatform]); [exclude] overrides that for tests.
class SemanticsGuard extends StatelessWidget {
  const SemanticsGuard({super.key, required this.child, this.exclude});

  final Widget child;
  final bool? exclude;

  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(excluding: exclude ?? skipSemanticsOnThisPlatform, child: child);
}
