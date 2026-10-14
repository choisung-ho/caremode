import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// 앱 전체에서 공유하는 테마 상태 관리자
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

const String _prefsThemeModeKey = 'caremode_theme_mode';

Future<void> loadThemeModeFromPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefsThemeModeKey);
  switch (saved) {
    case 'dark':
      themeNotifier.value = ThemeMode.dark;
      break;
    case 'light':
      themeNotifier.value = ThemeMode.light;
      break;
    case 'system':
      themeNotifier.value = ThemeMode.system;
      break;
    default:
      // keep default
      break;
  }
}

/// 테마 저장
Future<void> saveThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsThemeModeKey, mode.name);
  } catch (e) {
    debugPrint('Failed to save theme: $e');
  }
}

/// 테마 토글 (라이트 <-> 다크)
void toggleTheme() {
  final newMode = themeNotifier.value == ThemeMode.dark
      ? ThemeMode.light
      : ThemeMode.dark;
  saveThemeMode(newMode);
}

/// 현재 다크모드인지 확인
bool get isDarkMode => themeNotifier.value == ThemeMode.dark;
