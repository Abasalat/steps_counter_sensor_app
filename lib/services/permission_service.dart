import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> ensureActivityRecognition() async {
    final status = await Permission.activityRecognition.status;
    if (status.isGranted) return true;
    final req = await Permission.activityRecognition.request();
    return req.isGranted;
  }
}
