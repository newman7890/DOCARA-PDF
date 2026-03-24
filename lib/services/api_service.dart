import 'dart:io' as io;
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/security_service.dart';
import '../constants/secrets.dart';

/// Service to handle secure API communication with HMAC request signing and SSL pinning.
class ApiService {
  final String baseUrl = "https://rhxoxmqthsumhgudkcvk.supabase.co/functions/v1"; 
  final String apiSecret = AppSecrets.supabaseApiSecret; 
  
  // SSL Pinning: Public Key Fingerprint (SHA-256) for rhxoxmqthsumhgudkcvk.supabase.co
  final String _pinnedFingerprint = "398BCCE2D995CB23CB092A937B5B58BD95B408A45FBF89AB7BB114034789AE7D"; 

  late final http.Client _client;
  final _security = SecurityService();

  ApiService() {
    _client = _createSecureClient();
  }

  /// Creates an IOClient with a SecurityContext that enforces certificate validation.
  http.Client _createSecureClient() {
    final io.HttpClient httpClient = io.HttpClient()
      ..badCertificateCallback = (io.X509Certificate cert, String host, int port) {
        // Verification: Compare incoming certificate's SHA-256 hash with pinned fingerprint
        final String serverFingerprint = sha256.convert(cert.der).toString().toUpperCase();
        
        if (serverFingerprint == _pinnedFingerprint) {
          debugPrint("✅ SSL Pinning Verified for $host");
          return true; // Trusted
        } else {
          debugPrint("🚨 SSL PINNING MISMATCH! Expected: $_pinnedFingerprint, Got: $serverFingerprint");
          return false; // Reject connection
        }
      };

    return IOClient(httpClient);
  }

  /// Sends a signed POST request to the backend with anti-tamper headers.
  Future<http.Response> postSigned(
    String endpoint, 
    Map<String, dynamic> body, {
    String? featureName,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final url = Uri.parse("$baseUrl$endpoint");
    
    // Get Device ID for signing
    final String deviceId = body['device_id'] ?? 'unknown';

    // 1. App Identity Signals & Integrity
    final packageInfo = await PackageInfo.fromPlatform();
    final integrityToken = await _security.getIntegrityToken();
    final appSignature = await _security.getAppSignature();
    final riskScore = await _security.calculateRiskScore();

    // 2. Generate HMAC signature: HMAC_SHA256(Secret, Timestamp + DeviceId + FeatureName + RawBody)
    // We stringify the body ONCE to ensure the signature matches exactly what the server receives
    final String bodyText = json.encode(body);
    final String signPayload = timestamp + deviceId + (featureName ?? '') + bodyText;
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    final signature = hmac.convert(utf8.encode(signPayload)).toString();

    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'x-signature': signature,
          'x-timestamp': timestamp,
          'x-package-name': packageInfo.packageName,
          'x-app-signature': appSignature,
          'x-integrity-token': integrityToken,
          'x-risk-score': riskScore.toString(),
          ...featureName != null ? {'x-feature-name': featureName} : {},
        },
        body: bodyText,
      );
      
      return response;
    } catch (e) {
      debugPrint("API Error on $endpoint: $e");
      rethrow;
    }
  }

  /// Fetches a short-lived one-time token for a specific feature.
  Future<String?> getFeatureToken(String deviceId, String hardwareFingerprint, String featureName) async {
    try {
      final response = await postSigned("/verify-device", {
        'action': 'get_token',
        'device_id': deviceId,
        'hardware_fingerprint': hardwareFingerprint,
        'feature_name': featureName,
      });
      if (response.statusCode == 200) {
        return json.decode(response.body)['feature_token'];
      }
    } catch (_) {}
    return null;
  }

  /// Registers the device with the backend for analytics and security tracking.
  Future<bool> registerDevice(Map<String, dynamic> metadata, {required String fingerprint}) async {
    try {
      final response = await postSigned("/verify-device", {
        ...metadata,
        'action': 'register',
        'hardware_fingerprint': fingerprint,
      });
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static const String _localUsageKey = 'local_usage_count';
  static const String _premiumStatusKey = 'is_premium_user_flag';
  static const String _premiumExpiryKey = 'premium_expiry_date_ms'; // Stores timestamp in ms
  static const String _offlineQueueKey = 'offline_usage_queue';

  /// Checks if the device is a premium user (Offline-First + Self-Locking).
  Future<bool> isPremium(String deviceId, String hardwareFingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Check local cache
    bool cachedStatus = prefs.getBool(_premiumStatusKey) ?? false;
    final int? expiryMs = prefs.getInt(_premiumExpiryKey);

    // 2. SELF-LOCKING: Check if time has run out (Even if offline)
    if (cachedStatus && expiryMs != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now > expiryMs) {
        debugPrint("🚨 PREMIUM EXPIRED (Offline Guard). Locking access.");
        await prefs.setBool(_premiumStatusKey, false);
        cachedStatus = false;
        // Optionally keep expiryMs as history or clear it
      }
    }
    
    // 3. Try to verify/sync with server if possible
    try {
      final response = await postSigned("/verify-device", {
        'action': 'get_status',
        'device_id': deviceId,
        'hardware_fingerprint': hardwareFingerprint,
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Sync Expiry Date if provided by server
        if (data.containsKey('premium_until')) {
          final untilStr = data['premium_until']; // Expecting ISO8601 or timestamp
          int? serverExpiry;
          if (untilStr is int) {
            serverExpiry = untilStr;
          } else if (untilStr is String) {
            serverExpiry = DateTime.tryParse(untilStr)?.millisecondsSinceEpoch;
          }
          if (serverExpiry != null) {
            await prefs.setInt(_premiumExpiryKey, serverExpiry);
          }
        }

        if (data.containsKey('is_premium')) {
          bool serverStatus = data['is_premium'];
          if (serverStatus != cachedStatus) {
            await prefs.setBool(_premiumStatusKey, serverStatus);
            cachedStatus = serverStatus;
          }
        }
      }
    } catch (_) {
      debugPrint("isPremium: Offline mode, using self-locking status: $cachedStatus");
    }

    return cachedStatus;
  }

  /// Gets usage count from Server (Server Authorized) mixed with local offline data.
  Future<int> getGlobalTrialUsage(String deviceId, String hardwareFingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    int localUsage = prefs.getInt(_localUsageKey) ?? 0;

    try {
      final response = await postSigned("/verify-device", {
        'action': 'get_status',
        'device_id': deviceId,
        'hardware_fingerprint': hardwareFingerprint,
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        // Optimistic sync of premium status while we're fetching usage
        if (data.containsKey('is_premium')) {
          await prefs.setBool(_premiumStatusKey, data['is_premium']);
        }
        
        if (data.containsKey('premium_until')) {
          final until = data['premium_until'];
          if (until is int) {
            await prefs.setInt(_premiumExpiryKey, until);
          }
          else if (until is String) {
            final parsed = DateTime.tryParse(until)?.millisecondsSinceEpoch;
            if (parsed != null) await prefs.setInt(_premiumExpiryKey, parsed);
          }
        }

        if (data.containsKey('usage_count')) {
          int serverUsage = data['usage_count'];
          
          localUsage = serverUsage > localUsage ? serverUsage : localUsage;
          await prefs.setInt(_localUsageKey, localUsage);
          
          await _syncOfflineQueue(deviceId, hardwareFingerprint);
        }
      }
    } catch (_) {}

    return localUsage; // Return accurate count even if offline
  }

  /// Tracks a specific usage event and queues it if offline.
  Future<void> trackUsage({
    required String deviceId,
    required String hardwareFingerprint,
    required String featureName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    int localUsage = prefs.getInt(_localUsageKey) ?? 0;
    localUsage++;
    await prefs.setInt(_localUsageKey, localUsage);

    List<String> queue = prefs.getStringList(_offlineQueueKey) ?? [];
    queue.add(featureName);
    await prefs.setStringList(_offlineQueueKey, queue);

    await _syncOfflineQueue(deviceId, hardwareFingerprint);
  }

  /// Attempts to empty the offline queue to the server
  Future<void> _syncOfflineQueue(String deviceId, String hardwareFingerprint) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> queue = prefs.getStringList(_offlineQueueKey) ?? [];
    
    if (queue.isEmpty) return;

    List<String> remainingQueue = List.from(queue);

    for (String feature in queue) {
      try {
        await postSigned("/verify-device", {
          'action': 'track_usage',
          'device_id': deviceId,
          'hardware_fingerprint': hardwareFingerprint,
          'feature_name': feature,
        }, featureName: feature); // Correct signature
        remainingQueue.remove(feature);
      } catch (_) {
        break; // Network failed, stop trying the rest for now
      }
    }

    await prefs.setStringList(_offlineQueueKey, remainingQueue);
  }

  /// Directly upgrades to premium (Registers with Server + Local Cache).
  Future<bool> upgradeToPremium(String deviceId, String hardwareFingerprint) async {
    try {
      final response = await postSigned("/verify-device", {
        'action': 'upgrade',
        'device_id': deviceId,
        'hardware_fingerprint': hardwareFingerprint,
      });
      
      debugPrint("Upgrade Response (${response.statusCode}): ${response.body}");
      
      if (response.statusCode == 200) {
        // PERMANENTLY UNLOCK LOCALLY (Set fallback 30-day expiry if server doesn't provide more detail)
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_premiumStatusKey, true);
        
        // Calculate 30 days from now in ms as a safety fallback
        final fallbackExpiry = DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch;
        await prefs.setInt(_premiumExpiryKey, fallbackExpiry);
        
        return true;
      }
    } catch (e) {
      debugPrint("Upgrade API Error: $e");
    }
    return false;
  }

  /// Fetches the real-time USD to GHS exchange rate directly from Google.
  Future<double> fetchExchangeRate() async {
    const double fallbackRate = 15.12; 
    const String cacheKey = "cached_usd_ghs_rate_google";

    try {
      final prefs = await SharedPreferences.getInstance();
      
      final response = await http.get(
        Uri.parse('https://www.google.com/search?q=1+usd+to+ghs'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36'
        },
      );
      
      if (response.statusCode == 200) {
        final RegExp regExp = RegExp(r'data-value="([0-9.]+)"');
        final match = regExp.firstMatch(response.body);
        
        if (match != null && match.group(1) != null) {
          final double liveRate = double.parse(match.group(1)!);
          await prefs.setDouble(cacheKey, liveRate);
          return liveRate;
        }
      }

      final double? cachedRate = prefs.getDouble(cacheKey);
      return cachedRate ?? fallbackRate;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(cacheKey) ?? fallbackRate;
    }
  }
}
