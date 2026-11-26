import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/plant_models.dart';

class ResolvedAiCredentials {
  final AiProviderType provider;
  final String modelName;
  final String apiKey;
  final String? baseUrl;

  const ResolvedAiCredentials({
    required this.provider,
    required this.modelName,
    required this.apiKey,
    this.baseUrl,
  });
}

class SecureKeysService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static String _keyNameFor(AiProviderType provider) => switch (provider) {
        AiProviderType.gemini => 'plant_ai_key_gemini',
        AiProviderType.openai => 'plant_ai_key_openai',
        AiProviderType.openaiCompatible => 'plant_ai_key_openai_compat',
      };

  static String sanitizeKey(String raw) {
    return raw.trim().replaceAll(RegExp(r'[\s"\x27]'), '');
  }

  Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, '.plant_ai_keys.json'));
  }

  Future<Map<String, String>> _readFallbackMap() async {
    try {
      final file = await _fallbackFile();
      if (!file.existsSync()) return {};
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeFallbackMap(Map<String, String> map) async {
    try {
      final file = await _fallbackFile();
      await file.writeAsString(jsonEncode(map), flush: true);
    } catch (_) {}
  }

  Future<String?> getApiKey(AiProviderType provider) async {
    final key = _keyNameFor(provider);
    try {
      final val = await _storage.read(key: key);
      if (val != null && val.trim().isNotEmpty) {
        return sanitizeKey(val);
      }
    } catch (_) {}
    final fallbackMap = await _readFallbackMap();
    final fallback = fallbackMap[key];
    return fallback != null && fallback.isNotEmpty
        ? sanitizeKey(fallback)
        : null;
  }

  Future<void> saveApiKey(AiProviderType provider, String apiKey) async {
    final key = _keyNameFor(provider);
    final cleaned = sanitizeKey(apiKey);
    try {
      await _storage.write(key: key, value: cleaned);
    } catch (_) {}
    final fallbackMap = await _readFallbackMap();
    fallbackMap[key] = cleaned;
    await _writeFallbackMap(fallbackMap);
  }

  Future<void> deleteApiKey(AiProviderType provider) async {
    final key = _keyNameFor(provider);
    try {
      await _storage.delete(key: key);
    } catch (_) {}
    final fallbackMap = await _readFallbackMap();
    fallbackMap.remove(key);
    await _writeFallbackMap(fallbackMap);
  }

  /// Resolves credentials for [settings.preferredAiProvider], falling back to
  /// another configured provider automatically if available.
  Future<ResolvedAiCredentials?> resolveActiveCredentials(
    AppSettings settings,
  ) async {
    final primary = settings.preferredAiProvider;
    final primaryKey = await getApiKey(primary);

    if (primary == AiProviderType.openaiCompatible) {
      final url = settings.customBaseUrl.trim();
      final model = settings.customModelName.trim();
      if (url.isNotEmpty && model.isNotEmpty) {
        // Local OpenAI-compatible servers (e.g. Ollama / LM Studio) may not need a key
        return ResolvedAiCredentials(
          provider: primary,
          modelName: model,
          apiKey: primaryKey ?? '',
          baseUrl: url,
        );
      }
    } else if (primaryKey != null && primaryKey.isNotEmpty) {
      return ResolvedAiCredentials(
        provider: primary,
        modelName: settings.preferredAiModel,
        apiKey: primaryKey,
      );
    }

    // Automatic fallback to Gemini or OpenAI if a key exists
    for (final candidate in [AiProviderType.gemini, AiProviderType.openai]) {
      if (candidate == primary) continue;
      final key = await getApiKey(candidate);
      if (key != null && key.isNotEmpty) {
        return ResolvedAiCredentials(
          provider: candidate,
          modelName: candidate == AiProviderType.gemini
              ? 'gemini-3-flash-preview'
              : 'gpt-4o-mini',
          apiKey: key,
        );
      }
    }

    return null;
  }
}
