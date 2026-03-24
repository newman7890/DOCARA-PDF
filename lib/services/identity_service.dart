import 'dart:io';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

/// Service to handle unique device identification and metadata collection.
class IdentityService {
  static const String _installIdKey = 'install_id';
  static const String _customDeviceIdKey = 'custom_device_id';

  final _storage = const FlutterSecureStorage();
  final _deviceInfo = DeviceInfoPlugin();

  /// Gets a unique hardware-level identifier that survives app re-installs.
  /// On Android, it generates and securely stores a persistent UUID if a unique hardware ID isn't available.
  Future<String> getDeviceId() async {
    return await getHardwareId();
  }

  /// Gets the raw hardware ID without the install-specific components.
  Future<String> getHardwareId() async {
    if (Platform.isAndroid) {
      // FIX: Since some Android versions return a generic build string, 
      // we generate a persistent UUID stored in secure storage as the device ID.
      String? customId = await _storage.read(key: _customDeviceIdKey);
      if (customId == null) {
        customId = const Uuid().v4();
        await _storage.write(key: _customDeviceIdKey, value: customId);
      }
      return customId;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'ios_unknown';
    } else {
      return 'desktop_unknown';
    }
  }

  /// Reconstructs the old ID format (hardwareId_installId) for migration purposes.
  Future<String> getLegacyDeviceId() async {
    final hardwareId = await getHardwareId();
    final installId = await getInstallId();
    return "${hardwareId}_$installId";
  }

  /// Generates a persistent hardware fingerprint based on immutable device signals.
  /// This signature survives app re-installs and "Clear Data" operations.
  Future<String> getHardwareFingerprint() async {
    final metadata = await getDeviceMetadata();
    return getHardwareFingerprintByMetadata(metadata);
  }

  /// Hashes specific hardware signals to create a unique device signature.
  String getHardwareFingerprintByMetadata(Map<String, dynamic> metadata) {
    // Signals that are virtually impossible to change without root/jailbreak.
    // We EXCLUDE screen_resolution because it can be 0x0 during early startup,
    // which would cause the fingerprint to change later and reset trials.
    final signals = [
      metadata['manufacturer'] ?? '',
      metadata['device_model'] ?? '',
      metadata['product'] ?? '',
      metadata['board'] ?? '',
      metadata['hardware'] ?? '',
    ].join('|');

    return sha256.convert(utf8.encode(signals)).toString();
  }

  /// Gets or generates a secondary installation UUID stored in secure storage.
  Future<String> getInstallId() async {
    String? id = await _storage.read(key: _installIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await _storage.write(key: _installIdKey, value: id);
    }
    return id;
  }

  /// Collects comprehensive device metadata for backend registration.
  Future<Map<String, dynamic>> getDeviceMetadata({String? screenResolution}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final String language = Platform.localeName;
    final String timezone = DateTime.now().timeZoneName;
    
    // Attempt to get resolution if not provided
    String resolution = screenResolution ?? 'unknown';
    if (resolution == 'unknown') {
      try {
        final window = ui.PlatformDispatcher.instance.views.first.physicalSize;
        if (window.width > 0) {
          resolution = "${window.width.toInt()}x${window.height.toInt()}";
        }
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return {
        'device_id': await getHardwareId(),
        'install_id': await getInstallId(),
        'device_model': androidInfo.model,
        'manufacturer': androidInfo.manufacturer,
        'android_version': androidInfo.version.release,
        'cpu_architecture': androidInfo.supportedAbis.isNotEmpty ? androidInfo.supportedAbis.first : 'unknown',
        'language': language,
        'timezone': timezone,
        'screen_resolution': resolution,
        'app_version': packageInfo.version,
        'package_name': packageInfo.packageName,
        'product': androidInfo.product,
        'board': androidInfo.board,
        'hardware': androidInfo.hardware,
        'is_physical_device': androidInfo.isPhysicalDevice,
        'install_timestamp': DateTime.now().toIso8601String(),
      };
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return {
        'device_id': await getHardwareId(),
        'install_id': await getInstallId(),
        'device_model': iosInfo.utsname.machine,
        'product': 'ios_product',
        'board': 'ios_board',
        'hardware': iosInfo.model,
        'manufacturer': 'Apple',
        'android_version': iosInfo.systemVersion,
        'cpu_architecture': iosInfo.utsname.machine,
        'language': language,
        'timezone': timezone,
        'screen_resolution': resolution,
        'app_version': packageInfo.version,
        'package_name': packageInfo.packageName,
        'is_physical_device': iosInfo.isPhysicalDevice,
        'install_timestamp': DateTime.now().toIso8601String(),
      };
    }
    
    return {
      'device_id': 'desktop_unknown',
      'install_id': await getInstallId(),
      'app_version': packageInfo.version,
      'install_timestamp': DateTime.now().toIso8601String(),
    };
  }
}
