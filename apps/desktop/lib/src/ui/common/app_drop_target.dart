import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

/// Safe wrapper around [DropTarget] that avoids loading native FFI binaries
/// ('libdesktop_drop_plugin.so') during headless [flutter test] executions.
class AppDropTarget extends StatelessWidget {
  final Widget child;
  final void Function(DropDetails details)? onDrop;
  final void Function(DragDetails details)? onEnter;
  final VoidCallback? onLeave;

  const AppDropTarget({
    super.key,
    required this.child,
    this.onDrop,
    this.onEnter,
    this.onLeave,
  });

  static bool get isTestEnvironment => Platform.environment.containsKey('FLUTTER_TEST');

  @override
  Widget build(BuildContext context) {
    if (isTestEnvironment) {
      return child;
    }

    return DropTarget(
      onEnter: onEnter,
      onLeave: onLeave,
      onDrop: onDrop ?? (_) {},
      child: child,
    );
  }
}
