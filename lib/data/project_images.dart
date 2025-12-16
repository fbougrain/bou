import 'package:flutter/foundation.dart';

/// Global in-memory store for project pictures keyed by project name.
/// Not persisted across restarts; used to reflect updates app-wide instantly.
class ProjectImages extends ChangeNotifier {
  ProjectImages._();
  static final ProjectImages instance = ProjectImages._();

  final Map<String, Uint8List> _byName = <String, Uint8List>{};

  Uint8List? get(String projectName) => _byName[projectName];

  void set(String projectName, Uint8List bytes) {
    _byName[projectName] = bytes;
    notifyListeners();
  }

  void clear(String projectName) {
    if (_byName.remove(projectName) != null) {
      notifyListeners();
    }
  }
}
