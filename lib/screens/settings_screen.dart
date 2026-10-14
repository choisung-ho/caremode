// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import '../theme_state.dart';
import 'select_role_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              "설정",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'Pyeongtaek',
              ),
            ),
            const SizedBox(height: 30),

            // 1. 내 정보 카드 (프로필)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 13),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: scheme.primary,
                    child: const Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "김철수 보호자님",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "guardian@email.com",
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(
                            context,
                          ).textTheme.bodySmall?.color?.withValues(alpha: 204),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(
                      Icons.edit,
                      color: Theme.of(
                        context,
                      ).iconTheme.color?.withValues(alpha: 204),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // 2. 앱 설정 섹션
            const Text(
              "앱 설정",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),

            // 다크모드 스위치
            _buildSettingTile(
              context,
              icon: isDark ? Icons.dark_mode : Icons.light_mode,
              title: "다크 모드",
              trailing: Switch(
                value: isDark,
                activeThumbColor: scheme.primary,
                onChanged: (value) => toggleTheme(),
              ),
            ),

            _buildSettingTile(
              context,
              icon: Icons.notifications_outlined,
              title: "알림 설정",
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(
                  context,
                ).iconTheme.color?.withValues(alpha: 153),
              ),
            ),
            _buildSettingTile(
              context,
              icon: Icons.lock_outline,
              title: "비밀번호 변경",
              trailing: Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Theme.of(
                  context,
                ).iconTheme.color?.withValues(alpha: 153),
              ),
            ),

            const SizedBox(height: 30),

            // 3. 기타
            const Text(
              "기타",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _buildSettingTile(
              context,
              icon: Icons.logout,
              title: "로그아웃",
              textColor: Colors.red,
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SelectRoleScreen(),
                  ),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
    Color? textColor,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (textColor ?? scheme.primary).withValues(alpha: 26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: textColor ?? scheme.primary),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
        ),
        trailing: trailing,
      ),
    );
  }
}
