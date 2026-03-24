import 'package:permission_handler/permission_handler.dart';

/// Service to handle app permissions for Camera and Storage.
class PermissionService {
  /// Requests camera permission.
  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Requests storage/media permission based on Android version.
  /// On Android 13+ (API 33+), READ_EXTERNAL_STORAGE is deprecated.
  /// FilePicker handles file access natively on API 33+ without needing
  /// explicit READ_EXTERNAL_STORAGE permission, so we just return true.
  Future<bool> requestStoragePermission() async {
    // Try READ_MEDIA_IMAGES first (Android 13+)
    if (await Permission.photos.request().isGranted) {
      return true;
    }

    // Fallback: try legacy READ_EXTERNAL_STORAGE (Android 12 and below)
    if (await Permission.storage.request().isGranted) {
      return true;
    }

    // If neither is granted, return false to respect user denial.
    return false;
  }

  /// Checks if camera permission is already granted.
  Future<bool> isCameraGranted() async {
    return await Permission.camera.isGranted;
  }

  /// Checks if storage permission is already granted.
  Future<bool> isStorageGranted() async {
    return await Permission.storage.isGranted ||
        await Permission.photos.isGranted;
  }
}
