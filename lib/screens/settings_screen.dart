import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/storage_service.dart';
import 'privacy_policy_screen.dart';
import 'onboarding_screen.dart';
import 'paywall_screen.dart';
import '../services/api_service.dart';
import '../services/identity_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSubscriptionSection(context),
          const SizedBox(height: 16),
          _buildCardSection(context, 'Support & Feedback', [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share_outlined, color: Colors.green),
              ),
              title: const Text('Share App'),
              subtitle: const Text('Tell your friends about us'),
              onTap: () => _shareApp(context),
            ),
            const Divider(indent: 56),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mail_outline, color: Colors.orange),
              ),
              title: const Text('Email Support'),
              subtitle: const Text('Need help? Contact us'),
              onTap: () => _emailSupport(context),
            ),
            const Divider(indent: 56),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_outline, color: Colors.amber),
              ),
              title: const Text('Rate App'),
              subtitle: const Text('Support our development'),
              onTap: () => _rateApp(context),
            ),
            const Divider(indent: 56),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.help_outline, color: Colors.indigo),
              ),
              title: const Text('User Guide'),
              subtitle: const Text('Learn how to use all features'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const OnboardingScreen(isFromSettings: true),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 16),
          _buildCardSection(context, 'Legal & Info', [
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.privacy_tip_outlined,
                  color: Colors.indigo,
                ),
              ),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyScreen(),
                  ),
                );
              },
            ),
            const Divider(indent: 56),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.description_outlined,
                  color: Colors.grey,
                ),
              ),
              title: const Text('Licenses'),
              onTap: () => showLicensePage(context: context),
            ),
            const Divider(indent: 56),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('App Version'),
              trailing: Text(
                '1.0.0',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _buildCardSection(context, 'Danger Zone', [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Clear Cache',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onTap: () => _showClearCacheDialog(context),
            ),
          ]),
          const SizedBox(height: 48),
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/images/app_logo.png',
                  height: 64,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    Icons.description_rounded,
                    size: 64,
                    color: theme.colorScheme.primary.withAlpha(50),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Docara',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text('Version 1.0.0', style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                Text(
                  '© 2024 Emmanuel Arkutu Kwabla',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCardSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, title),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey[200]!, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  void _shareApp(BuildContext context) {
    Share.share(
      'Check out Docara! It processes everything locally for maximum privacy. Download it now!',
    );
  }

  void _emailSupport(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Support'),
        content: const Text(
          'Please send your feedback or issues to newm5811@gmail.com.\n\nWe typically respond within 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Share.share(
                'Contact newm5811@gmail.com for help with Docara.',
              );
            },
            child: const Text('Copy Email'),
          ),
        ],
      ),
    );
  }

  void _rateApp(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon to App Store and Google Play!'),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSubscriptionSection(BuildContext context) {
    final theme = Theme.of(context);
    final api = context.read<ApiService>();
    final identity = context.read<IdentityService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Subscription'),
        FutureBuilder<List<dynamic>>(
          future: Future.wait([
            identity.getDeviceId(),
            identity.getHardwareFingerprint(),
          ]),
          builder: (context, idSnapshot) {
            if (!idSnapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final String deviceId = idSnapshot.data![0];
            final String fingerprint = idSnapshot.data![1];

            return FutureBuilder<List<dynamic>>(
              future: Future.wait([
                api.isPremium(deviceId, fingerprint),
                api.getGlobalTrialUsage(deviceId, fingerprint),
              ]),
              builder: (context, statusSnapshot) {
                final results = statusSnapshot.data ?? [false, 0];
                final bool isPremium = results[0] as bool;
                final int count = results[1] as int;
                final int remaining = 3 - count > 0 ? 3 - count : 0;
                final bool isLocked = count >= 3 && !isPremium;

                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isPremium
                          ? Colors.amber.withAlpha(100)
                          : (isLocked
                              ? Colors.red.withAlpha(50)
                              : theme.colorScheme.primary.withAlpha(50)),
                      width: 1.5,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          (isPremium
                                  ? Colors.amber
                                  : (isLocked
                                      ? Colors.red
                                      : theme.colorScheme.primary))
                              .withAlpha(20),
                          (isPremium
                                  ? Colors.amber
                                  : (isLocked
                                      ? Colors.red
                                      : theme.colorScheme.primary))
                              .withAlpha(5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isPremium
                                  ? Colors.amber
                                  : (isLocked
                                      ? Colors.red
                                      : Colors.indigo.withAlpha(50)),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isPremium
                                  ? Icons.verified
                                  : (isLocked ? Icons.lock : Icons.star),
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            isPremium
                                ? 'Premium Plan'
                                : (isLocked
                                    ? 'Account Locked'
                                    : 'Account Status'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(isPremium
                              ? 'Unlimited Access'
                              : (isLocked
                                  ? 'Trial Expired'
                                  : 'Free Trial ($remaining uses left)')),
                          trailing: isPremium
                              ? null
                              : TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const PaywallScreen()),
                                    );
                                  },
                                  child: Text(isLocked ? 'UNLOCK' : 'UPGRADE'),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text(
                            isPremium
                                ? 'Thank you for supporting us! You have unlimited access to all features.'
                                : (isLocked
                                    ? 'Your free trial has ended. Please subscribe to unlock all features.'
                                    : 'Unlock unlimited PDF scans, high-resolution text extraction, and advanced editing tools.'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will delete temporary preview files. Your documents will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final storage = context.read<StorageService>();
              await storage.clearCache();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Cache cleared')));
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
