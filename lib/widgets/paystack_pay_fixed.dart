import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';
import 'dart:convert';

/// A secure checkout widget that takes a pre-generated authentication URL
/// and only tracks the WebView for completion.
class PaystackPayFixed extends StatefulWidget {
  final String authUrl;
  final String reference;
  final String deviceId;
  final String callbackUrl;
  final void Function() transactionCompleted;
  final void Function(String reason) transactionNotCompleted;

  const PaystackPayFixed({
    super.key,
    required this.authUrl,
    required this.reference,
    required this.deviceId,
    required this.callbackUrl,
    required this.transactionCompleted,
    required this.transactionNotCompleted,
  });

  @override
  State<PaystackPayFixed> createState() => _PaystackPayFixedState();
}

class _PaystackPayFixedState extends State<PaystackPayFixed> {
  final ApiService _apiService = ApiService();
  bool _isVerifying = false;

  Future<void> _verifyTransaction() async {
    if (_isVerifying) return;
    setState(() => _isVerifying = true);

    try {
      final response = await _apiService.postSigned("/paystack", {
        'action': 'verify',
        'reference': widget.reference,
        'device_id': widget.deviceId, 
      });

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded["success"] == true) {
          widget.transactionCompleted();
        } else {
          widget.transactionNotCompleted(decoded["status"].toString());
        }
      } else {
        widget.transactionNotCompleted("verification_failed");
      }
    } catch (e) {
      widget.transactionNotCompleted("network_error");
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isVerifying) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Verifying payment security..."),
            ],
          ),
        ),
      );
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = request.url;
            if (url.contains('paystack.co/close') || url.contains(widget.callbackUrl)) {
              await _verifyTransaction();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Secure Payment"),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
