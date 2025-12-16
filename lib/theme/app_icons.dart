import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/widgets.dart';

/// Central place to manage icons (regular + filled) used in navigation and actions.
/// Makes it easy to adjust style or sizes later.
class AppIcons {
  static const IconData send = FluentIcons.send_24_regular;
  static const IconData attachment = FluentIcons.attach_24_regular;
  // Bottom navigation pairs
  static const NavIcon home = NavIcon(
    regular: FluentIcons.home_24_regular,
    filled: FluentIcons.home_24_filled,
  );
  static const NavIcon project = NavIcon(
    regular: FluentIcons.building_24_regular,
    filled: FluentIcons.building_24_filled,
  );
  static const NavIcon media = NavIcon(
    regular: FluentIcons.folder_24_regular,
    filled: FluentIcons.folder_24_filled,
  );
  static const NavIcon profile = NavIcon(
    regular: FluentIcons.person_24_regular,
    filled: FluentIcons.person_24_filled,
  );

  // Header / actions
  static const IconData chevronRight = FluentIcons.chevron_right_16_regular;
  static const IconData chevronDown = FluentIcons.chevron_down_16_regular;
  static const IconData chevronUp = FluentIcons.chevron_up_16_regular;
  static const IconData checkmark = FluentIcons.checkmark_circle_24_regular;
  static const IconData team = FluentIcons.people_community_24_regular;
  static const IconData notifications = FluentIcons.alert_24_regular;
  static const IconData chats = FluentIcons.chat_24_regular;
  static const IconData multiplechats = FluentIcons.chat_multiple_24_regular;
  static const IconData back = FluentIcons.ios_arrow_ltr_24_regular;
  static const IconData backright = FluentIcons.ios_arrow_rtl_24_regular;
  static const IconData options = FluentIcons.options_24_regular;
  static const IconData edit = FluentIcons.edit_24_regular;
  static const IconData close = FluentIcons.dismiss_24_filled;
  static const IconData copy = FluentIcons.copy_24_regular;
  static const IconData add = FluentIcons.add_24_filled;
  static const IconData addChat = FluentIcons.chat_add_24_regular;
  static const IconData pin = FluentIcons.pin_24_filled;
  static const IconData mute = FluentIcons.alert_off_24_filled;
  static const IconData report = FluentIcons.person_warning_24_filled;
  static const IconData deleteFilled = FluentIcons.delete_24_filled;
  static const IconData delete = FluentIcons.delete_24_regular;
  static const IconData search = FluentIcons.search_24_filled;
  static const IconData file = FluentIcons.document_24_filled;
  static const IconData folderOpen = FluentIcons.folder_open_24_filled;
  static const IconData mic = FluentIcons.mic_24_filled;
  static const IconData locationFilled = FluentIcons.location_24_filled;
  static const IconData title = FluentIcons.briefcase_24_regular;
  static const IconData phone = FluentIcons.call_24_regular;
  static const IconData mail = FluentIcons.mail_24_regular;
  static const IconData refresh = FluentIcons.arrow_sync_24_filled;
  static const IconData location = FluentIcons.location_24_regular;
  static const IconData calender = FluentIcons.calendar_24_regular;
  static const IconData camera = FluentIcons.camera_24_regular;
  static const IconData person = FluentIcons.person_24_regular;
  static const IconData receipt = FluentIcons.receipt_24_regular;
  static const IconData logout = FluentIcons.sign_out_24_filled;
  static const IconData link = FluentIcons.link_multiple_24_regular;
  static const IconData joinProjectLink = FluentIcons.link_24_regular;
}

/// Immutable pair of regular + filled icon variants.
class NavIcon {
  const NavIcon({required this.regular, required this.filled});
  final IconData regular;
  final IconData filled;
}
