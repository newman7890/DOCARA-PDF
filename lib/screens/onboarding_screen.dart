import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final bool isFromSettings;
  const OnboardingScreen({super.key, this.isFromSettings = false});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      title: 'Welcome to\nDocara',
      subtitle: 'Your all-in-one document toolkit',
      tips: [
        'Scan physical documents with your camera',
        'Create and edit Smart Spreadsheets',
        'Import PDFs and Excel files from your phone',
        'Edit, annotate, and share with ease',
      ],
      icon: Icons.description_rounded,
      gradient: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
    ),
    OnboardingPage(
      title: 'Scan & Import',
      subtitle: 'Get your documents into the app',
      tips: [
        'Tap "Add Document" on the home screen',
        'Choose "Scan" for camera or "Import" for files',
        'Auto-crop cleans up your scans automatically',
        'Open external documents directly with Docara',
      ],
      icon: Icons.camera_alt_rounded,
      gradient: [Color(0xFF1565C0), Color(0xFF42A5F5)],
    ),
    OnboardingPage(
      title: 'Smart Spreadsheets',
      subtitle: 'Powerful multi-sheet data grids',
      tips: [
        'Create professional tables with multiple sheets',
        'Live Auto-Save captures your typing instantly',
        'Import .xlsx and .csv files from other apps',
        'Export to Excel or beautiful smart PDFs',
      ],
      icon: Icons.table_chart_rounded,
      gradient: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    ),
    OnboardingPage(
      title: 'Pro PDF Export',
      subtitle: 'Premium "One-Line" Layouts',
      tips: [
        'Smart Auto-Fit keeps all text on a single line',
        'Automatic Landscape & Legal paper switching',
        'Zebra stripes and bold headers for clarity',
        'Perfect for inventory, logs, and business reports',
      ],
      icon: Icons.picture_as_pdf_rounded,
      gradient: [Color(0xFFC62828), Color(0xFFEF5350)],
    ),
    OnboardingPage(
      title: 'AI Text Extraction',
      subtitle: 'Turn images into editable text',
      tips: [
        'Open any document and tap "Extract & Refine"',
        'AI reads the text from scans automatically',
        'Works 100% offline — nothing leaves your phone',
        'Edit the extracted text with full formatting tools',
      ],
      icon: Icons.psychology_rounded,
      gradient: [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
    ),
    OnboardingPage(
      title: 'Text Formatting',
      subtitle: 'Professional document styling',
      tips: [
        'Use H1, H2, H3 for headings',
        'Bold, Italic, Underline, and Strikethrough',
        'Align text: [:left:], [:center:], or [:right:]',
        'Add fillable text boxes with [:field:] markers',
        'Create horizontal separators with three dashes ---',
        'Tap "Fix %" to correct OCR ordinal errors (1st, 2nd)',
      ],
      icon: Icons.format_paint_rounded,
      gradient: [Color(0xFFE65100), Color(0xFFFF9800)],
    ),
    OnboardingPage(
      title: 'Edit & Save',
      subtitle: 'Your edits are always safe',
      tips: [
        'All changes save to a new "Edited_" copy',
        'Original PDF is never modified',
        'Re-edit saved documents anytime',
        'Share via email, WhatsApp, or any app',
      ],
      icon: Icons.save_rounded,
      gradient: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    ),
    OnboardingPage(
      title: 'Clean vs Erase',
      subtitle: 'Know which tool to use',
      tips: [
        'The scanner "Clean" tool is for small stains or dust.',
        'To remove text, use the "Draw" tool in the Editor.',
        'Select the White color and a large Brush width.',
        'Simply paint over text to "white it out" perfectly.',
      ],
      icon: Icons.auto_fix_high_rounded,
      gradient: [Color(0xFF00796B), Color(0xFF4DB6AC)],
    ),
    OnboardingPage(
      title: 'Premium Support',
      subtitle: 'Unlock everything for 70 GHS',
      tips: [
        'Unlimited scans and Smart Spreadsheets',
        'Permanent Offline Access - no internet needed',
        'Self-Locking Expiry Guard protects your plan',
        'Priority feature updates and premium support',
      ],
      icon: Icons.star_rounded,
      gradient: [Colors.indigo, Colors.deepPurple],
    ),
    OnboardingPage(
      title: 'Privacy & Security',
      subtitle: 'Your documents stay yours',
      tips: [
        'All processing happens on your device',
        'No account or cloud uploads required',
        'Documents survive app re-installs',
        'Clear cache anytime from Settings',
      ],
      icon: Icons.shield_rounded,
      gradient: [Color(0xFF00695C), Color(0xFF26A69A)],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_shown', true);
    if (mounted) {
      if (widget.isFromSettings) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_currentPage];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.isFromSettings
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(200),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: page.gradient[0],
                    size: 20,
                  ),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'User Guide',
                style: TextStyle(
                  color: page.gradient[0],
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              centerTitle: true,
            )
          : null,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Animated gradient background
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.fastOutSlowIn,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    page.gradient[0].withAlpha(25),
                    page.gradient[1].withAlpha(15),
                    Colors.white,
                  ],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),

            // Page content
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemCount: _pages.length,
              itemBuilder: (context, index) {
                final p = _pages[index];
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 40, 28, 180),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header with icon
                          Center(
                            child: Column(
                              children: [
                                if (p.showLogo)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Image.asset(
                                      'assets/images/app_logo.png',
                                      height: 80,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const SizedBox.shrink(),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: p.gradient,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: p.gradient[0].withAlpha(80),
                                        blurRadius: 20,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    p.icon,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  p.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p.subtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Tips card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.lightbulb_outline_rounded,
                                      size: 20,
                                      color: p.gradient[0],
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'How it works',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: p.gradient[0],
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ...p.tips.asMap().entries.map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: p.gradient,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '${entry.key + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            entry.value,
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey.shade800,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Bottom navigation
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 16, 28, 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withAlpha(0),
                      Colors.white.withAlpha(240),
                      Colors.white,
                    ],
                    stops: const [0.0, 0.3, 0.5],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Page count
                    Text(
                      '${_currentPage + 1} of ${_pages.length}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Dot indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.fastOutSlowIn,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _currentPage == index ? 28 : 8,
                          height: 6,
                          decoration: BoxDecoration(
                            gradient: _currentPage == index
                                ? LinearGradient(colors: page.gradient)
                                : null,
                            color: _currentPage == index
                                ? null
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Action button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _currentPage == _pages.length - 1
                            ? _completeOnboarding
                            : () => _pageController.nextPage(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.fastOutSlowIn,
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: page.gradient[0],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage == _pages.length - 1
                                  ? 'Get Started'
                                  : 'Next',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (_currentPage < _pages.length - 1) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_currentPage < _pages.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: _completeOnboarding,
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingPage {
  final String title;
  final String subtitle;
  final List<String> tips;
  final IconData icon;
  final List<Color> gradient;
  final bool showLogo;

  OnboardingPage({
    required this.title,
    required this.subtitle,
    required this.tips,
    required this.icon,
    required this.gradient,
    this.showLogo = false,
  });
}
