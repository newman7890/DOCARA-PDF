import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Service to handle app integrity, root detection, and environment safety.
class SecurityService {
  
  /// Performs a comprehensive security check of the device environment.
  /// Returns a 'risk_score' (0-100) where 0 is safe.
  Future<int> calculateRiskScore() async {
    int score = 0;

    try {
      // 1. Root/Jailbreak Detection
      final bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) score += 50;

      // 2. Emulator Detection
      final bool isRealDevice = await SafeDevice.isRealDevice;
      if (!isRealDevice) score += 40;

      // 3. Debugger Detection 
      final bool isDevelopmentMode = await SafeDevice.isDevelopmentModeEnable;
      if (isDevelopmentMode && !kDebugMode) score += 20;

      // 4. External Storage / Tampered Paths (Android only)
      if (Platform.isAndroid) {
         final bool isOnExternalStorage = await SafeDevice.isOnExternalStorage;
         if (isOnExternalStorage) score += 10;
      }

    } catch (e) {
      debugPrint("Security Check Error: $e");
    }

    return score.clamp(0, 100);
  }

  /// Verifies if the request is coming from a trusted environment.
  Future<bool> isEnvironmentSafe() async {
    final risk = await calculateRiskScore();
    return risk < 80;
  }

  /// Checks if the device has a high risk score.
  Future<bool> isSuspicious() async {
    final risk = await calculateRiskScore();
    return risk >= 50;
  }

  /// Gets the application's package signature hash (Android).
  Future<String> getAppSignature() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final signature = packageInfo.buildSignature;
    return "SIGNED_${signature.isNotEmpty ? signature : 'v1_production'}";
  }

  /// Placeholder for Play Integrity API integration.
  /// In a real production app, you'd use a Play Integrity plugin.
  Future<String> getIntegrityToken() async {
    // Simulation: In reality, you'd call PlayIntegrity.getToken()
    return "INTEGRITY_TOKEN_MOCK_${DateTime.now().millisecondsSinceEpoch}";
  }
}
