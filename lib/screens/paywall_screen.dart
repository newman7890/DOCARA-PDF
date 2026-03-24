import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/identity_service.dart';

import '../services/payment_service.dart';
import 'premium_success_screen.dart';

/// A premium Paywall Screen for the $15/month subscription.
class PaywallScreen extends StatelessWidget {
  const PaywallScreen({super.key});

  Future<void> _subscribe(BuildContext context) async {
    final identity = context.read<IdentityService>();
    final api = context.read<ApiService>();
    final payment = context.read<PaymentService>();

    // 1. Show global loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 2. Get Device ID
      final String deviceId = await identity.getDeviceId();
      
      if (!context.mounted) return;
      Navigator.pop(context); // Close loading dialog before opening Paystack

      // 3. Process Payment via Paystack (Live)
      final String fingerprint = await identity.getHardwareFingerprint();
      
      if (!context.mounted) return;

      await payment.processPayment(
        context,
        amountGhs: 1.0,
        email: "customer@gmail.com", // In a real app, collect this from user
        deviceId: deviceId,
      );

      // 4. Upgrade locally on success if we reach here without exceptions
      final success = await api.upgradeToPremium(deviceId, fingerprint);

      if (success && context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const PremiumSuccessScreen()),
        );
      } else {
        throw Exception("Server failed to activate your premium status. Please contact support with your device ID.");
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Safety close
        String errorMessage = 'Error: $e';
        if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
          errorMessage = 'No internet connection. Please check your network and try again.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.indigo, Colors.deepPurple],
              ),
            ),
          ),
          
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            const Icon(Icons.star_rounded, size: 80, color: Colors.amber),
                            const SizedBox(height: 24),
                            const Text(
                              'Unlock Full Power',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Get unlimited document scans, OCR, and PDF editing with the Pro Plan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 18, color: Colors.white70),
                            ),
                            
                            const SizedBox(height: 48),
                            
                            // Price Card
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    '70.0 GHS / Month',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Lock/Unlock Monthly Cycle',
                                    style: TextStyle(color: Colors.amber, fontSize: 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Subscribe Button
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () => _subscribe(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text(
                                  'PAY WITH MOBILE MONEY / CARD',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            const SizedBox(height: 16),
                            const Text(
                              'Secured by Device Locking System',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
