import 'package:flutter/widgets.dart';
import '../data/profile_repository.dart';

class ProfileScope extends InheritedNotifier<ProfileRepository> {
  const ProfileScope({super.key, required ProfileRepository notifier, required super.child})
      : super(notifier: notifier);

  static ProfileRepository of(BuildContext context, {bool listen = true}) {
    final widget = listen
        ? context.dependOnInheritedWidgetOfExactType<ProfileScope>()
        : context.getInheritedWidgetOfExactType<ProfileScope>();
    assert(widget != null, 'ProfileScope not found in context');
    return widget!.notifier!;
  }
}
