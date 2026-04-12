import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperInfoScreen extends StatefulWidget {
  const DeveloperInfoScreen({super.key});

  @override
  State<DeveloperInfoScreen> createState() => _DeveloperInfoScreenState();
}

class _DeveloperInfoScreenState extends State<DeveloperInfoScreen> {
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _getVersionInfo();
  }

  Future<void> _getVersionInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _version = 'Version: ${packageInfo.version}';
      });
    } catch (e) {
      setState(() {
        _version = 'Version: 1.0.1';
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'About the Developer',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.black,
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSmallScreen = constraints.maxHeight < 700;
          final isLargeScreen = constraints.maxHeight > 800;

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: isSmallScreen ? 35 : 45,
                          backgroundImage: const AssetImage(
                            'assets/images/developer_avatar.png',
                          ),
                          backgroundColor: Colors.transparent,
                          child: Icon(
                            Icons.person,
                            size: isSmallScreen ? 40 : 50,
                            color: Theme.of(context)
                                .iconTheme
                                .color
                                ?.withValues(alpha: 0.5),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 10 : 15),
                        Text(
                          'Arafat Mahmud',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 20 : 24,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Software Developer',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white70
                                : Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.6),
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 15 : 20),
                        _buildInfoCard(
                          context,
                          title: 'Expense Tracker',
                          titleFontSize: isSmallScreen ? 14 : 15,
                          content:
                              'A comprehensive expense tracking application for personal finance management, featuring categorized expenses, budget tracking, and detailed analytics.',
                          contentFontSize: isSmallScreen ? 10 : 11,
                        ),
                        SizedBox(height: isSmallScreen ? 8 : 10),
                        _buildContactInfo(context),
                        if (isLargeScreen) const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom + 16,
                  top: 8,
                  left: 16,
                  right: 16,
                ),
                child: Text(
                  _version,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 9 : 10,
                    color: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.color
                        ?.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required String title,
    required String content,
    double titleFontSize = 20,
    double contentFontSize = 15,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              content,
              style: TextStyle(fontSize: contentFontSize, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfo(BuildContext context) {
    return Column(
      children: [
        _buildInfoTile(
          icon: Icons.email,
          title: 'Email',
          titleFontSize: 14,
          subtitle: 'arafat.mahmud.2001@gmail.com',
          subtitleFontSize: 11,
          onTap: () => _launchUrl('mailto:arafat.mahmud.2001@gmail.com'),
        ),
        const Divider(height: 20),
        _buildInfoTile(
          icon: Icons.code,
          title: 'GitHub',
          titleFontSize: 14,
          subtitle: 'github.com/arafat-mahmud',
          subtitleFontSize: 11,
          onTap: () => _launchUrl('https://github.com/arafat-mahmud'),
        ),
        const Divider(height: 20),
        _buildInfoTile(
          icon: Icons.language,
          title: 'Website',
          titleFontSize: 14,
          subtitle: 'arafat-mahmud.netlify.app',
          subtitleFontSize: 11,
          onTap: () => _launchUrl('http://arafat-mahmud.netlify.app'),
        ),
        if (MediaQuery.of(context).size.height < 800) const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    double titleFontSize = 15,
    double subtitleFontSize = 15,
  }) {
    return Builder(
      builder: (context) {
        return ListTile(
          leading: Icon(icon, color: Theme.of(context).primaryColor),
          title: Text(
            title,
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: titleFontSize),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: subtitleFontSize,
            ),
          ),
          onTap: onTap,
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }
}
