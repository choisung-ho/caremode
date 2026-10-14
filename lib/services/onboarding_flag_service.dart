// lib/services/onboarding_flag_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingFlagService {
  static const String _key = 'onboarding_completed';

  static Future<bool> isOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setOnboardingCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
