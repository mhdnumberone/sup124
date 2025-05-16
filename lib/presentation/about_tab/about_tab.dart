import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart'; // Added for dynamic version

class AboutTab extends StatefulWidget {
  const AboutTab({super.key});

  @override
  State<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<AboutTab> {
  String _appVersion = '1.0.0'; // Default version

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
  }

  Future<void> _loadVersionInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = "${packageInfo.version}+${packageInfo.buildNumber}";
        });
      }
    } catch (e) {
      // Log error or handle if needed, for now, keep default
      print('Failed to get package info: $e');
    }
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildInfoTile(
      BuildContext context, IconData icon, String title, String subtitle,
      {VoidCallback? onTap, bool isExternalLink = false}) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: theme.primaryColor, size: 28),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style: TextStyle(color: theme.textTheme.bodySmall?.color?.withOpacity(0.8))),
        onTap: onTap,
        trailing: onTap != null
            ? Icon(isExternalLink ? Icons.open_in_new : Icons.arrow_forward_ios, size: 18, color: Colors.grey[600])
            : null,
      ),
    );
  }

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final Uri url = Uri.parse(urlString);
    final bool isMounted = mounted; // Capture mounted state before the async gap
    if (!await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    )) {
      if (isMounted) { // Check mounted state before using context
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح الرابط: $urlString'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendEmail(BuildContext context, String email) async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=استفسار بخصوص تطبيق مخفي الرسائل الآمن',
    );
    final bool isMounted = mounted;
    if (!await launchUrl(emailLaunchUri)) {
      if (isMounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر فتح تطبيق البريد: $email'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // appBar: AppBar(
        //   title: const Text('حول التطبيق'),
        //   elevation: 0.5,
        // ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.primaryColor.withOpacity(0.1),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3), width: 2)
                ),
                child: Icon(
                  Icons.security_rounded, // Consider a more unique app icon if available
                  size: 60,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'مخفي الرسائل الآمن',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'الإصدار: $_appVersion',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Text(
                'تم التطوير بواسطة: Zero One',
                style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const Divider(thickness: 0.8),

              _buildSectionTitle(context, 'وصف التطبيق'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  'تطبيق يهدف إلى توفير طريقة آمنة لتشفير وإخفاء رسائلك الخاصة. يستخدم التطبيق خوارزميات تشفير قوية (AES-GCM) وتقنيات إخفاء لحماية معلوماتك، مع واجهة سهلة الاستخدام وميزات متنوعة لضمان خصوصيتك.',
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              
              _buildSectionTitle(context, 'الميزات الرئيسية'),
              _buildInfoTile(
                context,
                Icons.enhanced_encryption_rounded,
                'تشفير متقدم',
                'استخدام تشفير AES-256 GCM الموثوق لضمان أقصى درجات السرية والسلامة لبياناتك.',
              ),
              _buildInfoTile(
                context,
                Icons.visibility_off_rounded,
                'إخفاء النصوص (Zero-Width)',
                'إمكانية إخفاء النص المشفر (أو أي نص آخر) داخل رسائل تبدو عادية باستخدام أحرف غير مرئية.',
              ),
               _buildInfoTile(
                context,
                Icons.image_search_rounded, // Icon for steganography
                'إخفاء في الصور (Steganography)',
                'إخفاء النصوص داخل الصور مع الحفاظ على جودة الصورة الأصلية.',
              ),
              _buildInfoTile(
                context,
                Icons.key_rounded,
                'حماية بكلمة مرور قوية',
                'اشتقاق آمن لمفتاح التشفير من كلمة المرور باستخدام PBKDF2 مع Salt لتعزيز الأمان.',
              ),
              _buildInfoTile(
                context,
                Icons.history_rounded,
                'سجل العمليات المحفوظ',
                'تتبع عمليات التشفير وفك التشفير السابقة بسهولة وأمان.',
              ),
              _buildInfoTile(
                context,
                Icons.palette_rounded,
                'تخصيص المظهر بالكامل',
                'دعم الوضع الداكن والفاتح مع إمكانية تغيير اللون الرئيسي للتطبيق ليناسب تفضيلاتك.',
              ),
              _buildInfoTile(
                context,
                Icons.no_encryption_gmailerrorred_rounded, // Decoy screen icon
                'شاشة التمويه',
                'إمكانية إعداد شاشة تمويه تظهر عند إدخال كلمة مرور خاطئة لحماية إضافية.',
              ),
               _buildInfoTile(
                context,
                Icons.delete_sweep_rounded, // Self-destruct icon
                'التدمير الذاتي للرسائل (تجريبي)',
                'خيار لحذف الرسائل بشكل آمن بعد فترة محددة (ميزة تحت التطوير).',
              ),

              const SizedBox(height: 12),
              const Divider(thickness: 0.8),
              _buildSectionTitle(context, 'دليل الاستخدام السريع'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    '1. اختر العملية المطلوبة من القائمة الرئيسية (تشفير، فك تشفير، إخفاء، كشف، إلخ).',
                    '2. أدخل النص الأصلي أو النص المشفر/المخفي في الحقل المخصص.',
                    '3. إذا كنت تستخدم ميزة الإخفاء، أدخل نص الغطاء الذي سيتم إخفاء المعلومة بداخله.',
                    '4. أدخل كلمة مرور قوية وآمنة إذا كنت تستخدم عمليات التشفير.',
                    '5. اضغط على زر "تنفيذ" أو ما يماثله للحصول على النتيجة.',
                    '6. يمكنك نسخ النتيجة إلى الحافظة أو مشاركتها مباشرة.',
                    '7. استكشف الإعدادات لتخصيص مظهر التطبيق وسلوكه.',
                  ]
                      .map((text) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('• ', style: TextStyle(color: theme.primaryColor, fontWeight: FontWeight.bold)),
                              Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(height: 1.4))),
                            ],
                          )))
                      .toList(),
                ),
              ),

              const SizedBox(height: 12),
              const Divider(thickness: 0.8),
              _buildSectionTitle(context, 'معلومات إضافية وروابط'),
              _buildInfoTile(
                context,
                Icons.contact_mail_rounded,
                'تواصل معنا',
                'للإبلاغ عن مشكلة أو لتقديم اقتراحات: contact@example.com',
                onTap: () => _sendEmail(context, 'contact@example.com'),
              ),
              _buildInfoTile(
                context,
                Icons.privacy_tip_rounded,
                'سياسة الخصوصية',
                'اطلع على كيفية تعاملنا مع بياناتك.',
                onTap: () => _launchUrl(context, 'https://example.com/privacy-policy'), // Replace with actual URL
                isExternalLink: true,
              ),
              _buildInfoTile(
                context,
                Icons.gavel_rounded,
                'شروط الخدمة',
                'اقرأ شروط وأحكام استخدام التطبيق.',
                onTap: () => _launchUrl(context, 'https://example.com/terms-of-service'), // Replace with actual URL
                isExternalLink: true,
              ),
              _buildInfoTile(
                context,
                Icons.code_rounded,
                'الكود المصدري (GitHub)',
                'المشروع مفتوح المصدر، يمكنك المساهمة أو الاطلاع على الكود هنا.',
                onTap: () => _launchUrl(context, 'https://github.com/YOUR_USERNAME/YOUR_REPOSITORY'), // Replace with actual URL
                isExternalLink: true,
              ),
              _buildInfoTile(
                context,
                Icons.favorite_rounded,
                'شكر وتقدير',
                'شكراً للمجتمعات والمكتبات مفتوحة المصدر التي ساهمت في بناء هذا التطبيق.',
              ),
              const SizedBox(height: 30),
              Text(
                '© ${DateTime.now().year} Zero One. جميع الحقوق محفوظة.',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

