import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../widgets/paystack_pay_fixed.dart';
import '../constants/secrets.dart';
import '../services/api_service.dart';

class PaymentService {
  final String publicKey = AppSecrets.paystackPublicKey;
  final ApiService _apiService = ApiService();

  /// Processes a payment through the secure Paystack Edge Function.
  /// Returns true if the payment was successful, false otherwise.
  Future<void> processPayment(
    BuildContext context, {
    required double amountGhs,
    required String email,
    required String deviceId,
  }) async {
    final completer = Completer<void>();

    try {
      // 1. Initialize Payment Securely via Backend
      final initResponse = await _apiService.postSigned("/paystack", {
        'action': 'initialize',
        'email': email,
        'amount': amountGhs,
        'device_id': deviceId,
      });

      if (initResponse.statusCode != 200) {
        throw Exception("Server Error (${initResponse.statusCode}): ${initResponse.body}");
      }

      final data = jsonDecode(initResponse.body);
      if (data['success'] != true) {
        throw Exception("Payment Init Failed: ${data['error'] ?? data['debug']}");
      }

      final authUrl = data['authUrl'];
      final reference = data['reference'];

      // 2. Open secure WebView
      if (!context.mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PaystackPayFixed(
            authUrl: authUrl,
            reference: reference,
            deviceId: deviceId,
            callbackUrl: "https://standard.paystack.co/close",
            transactionCompleted: () {
              if (!completer.isCompleted) completer.complete();
            },
            transactionNotCompleted: (message) {
              if (!completer.isCompleted) completer.completeError(Exception("Transaction failed: $message"));
            },
          ),
        ),
      );

      return completer.future;
    } catch (e) {
      debugPrint("Paystack checkout Error: \$e");
      rethrow;
    }
  }
}
