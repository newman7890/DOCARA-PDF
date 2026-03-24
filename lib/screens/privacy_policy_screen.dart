import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(50),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.security_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Privacy First',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your documents never leave your device. We prioritize your data sovereignty above all else.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last Updated: March 2026',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildSection(
                    context,
                    Icons.inventory_2_outlined,
                    '1. Local Data Processing',
                    'Our application is built on the principle of local-first processing. All PDF generation, document scanning, and text recognition occur entirely on your smartphone. We do not operate any cloud servers to store your files, and we have explicitly disabled OS-level cloud backups for your documents.',
                  ),
                  _buildSection(
                    context,
                    Icons.vpn_key_outlined,
                    '2. Necessary Permissions',
                    'To function correctly, we require access to your Camera (for scanning) and Storage (for saving/opening PDFs). These permissions are used exclusively for app features and are never shared with third parties.',
                  ),
                  _buildSection(
                    context,
                    Icons.auto_awesome_outlined,
                    '3. Smart Recognition',
                    'We utilize Google ML Kit for high-performance, on-device text recognition. This integration is designed to work offline, ensuring your document content remains private and secure.',
                  ),
                  _buildSection(
                    context,
                    Icons.shield_outlined,
                    '4. Security Recommendations',
                    'Since you are the sole controller of your data, we recommend utilizing your device\'s built-in security features (FaceID, TouchID, or Passcodes) to protect your scanned documents.',
                  ),
                  _buildSection(
                    context,
                    Icons.update_outlined,
                    '5. Policy Updates',
                    'We may periodically update this policy to reflect new features or changes in legislation. Significant changes will be announced via app updates.',
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      '© 2026 PDF PROJECTT Team',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    IconData icon,
    String title,
    String content,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
