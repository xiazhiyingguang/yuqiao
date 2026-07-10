import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensitiveLocalStore {
  SensitiveLocalStore._();

  static const _fallbackPrefix = 'sensitive_fallback_';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static Future<String?> readString(
    String key, {
    String? legacySharedPreferencesKey,
  }) async {
    final secureValue = await _readSecure(key);
    if (secureValue != null) return secureValue;

    final prefs = await SharedPreferences.getInstance();
    final fallbackValue = prefs.getString('$_fallbackPrefix$key');
    if (fallbackValue != null) return fallbackValue;

    final legacyKey = legacySharedPreferencesKey;
    if (legacyKey == null) return null;
    final legacyValue = prefs.getString(legacyKey);
    if (legacyValue == null) return null;
    await writeString(key, legacyValue);
    await prefs.remove(legacyKey);
    return legacyValue;
  }

  static Future<void> writeString(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_fallbackPrefix$key');
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_fallbackPrefix$key', value);
    }
  }

  static Future<void> delete(String key,
      {String? legacySharedPreferencesKey}) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_fallbackPrefix$key');
    final legacyKey = legacySharedPreferencesKey;
    if (legacyKey != null) await prefs.remove(legacyKey);
  }

  static Future<List<String>> readStringList(
    String key, {
    String? legacySharedPreferencesKey,
  }) async {
    final raw = await readString(key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.whereType<String>().toList();
      } catch (_) {}
    }
    final legacyKey = legacySharedPreferencesKey;
    if (legacyKey != null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyList = prefs.getStringList(legacyKey);
      if (legacyList != null) {
        await writeStringList(key, legacyList);
        await prefs.remove(legacyKey);
        return legacyList;
      }
    }
    return const [];
  }

  static Future<void> writeStringList(String key, List<String> values) {
    return writeString(key, jsonEncode(values));
  }

  static Future<String?> _readSecure(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
