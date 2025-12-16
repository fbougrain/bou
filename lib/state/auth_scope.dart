import 'package:flutter/widgets.dart';
import '../data/auth_repository.dart';

class AuthScope extends InheritedNotifier<AuthRepository> {
  const AuthScope({super.key, required AuthRepository notifier, required super.child})
      : super(notifier: notifier);

  static AuthRepository of(BuildContext context, {bool listen = true}) {
    final widget = listen
        ? context.dependOnInheritedWidgetOfExactType<AuthScope>()
        : context.getInheritedWidgetOfExactType<AuthScope>();
    assert(widget != null, 'AuthScope not found in context');
    return widget!.notifier!;
  }
}
