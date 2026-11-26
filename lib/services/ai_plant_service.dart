import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/plant_models.dart';
import 'secure_keys_service.dart';

class AiPlantService {
  static const _uuid = Uuid();

  static const String _identifySystemPrompt = '''
Sei un botanico esperto italiano specializzato in piante da appartamento, balcone e giardino.
Identifica la pianta dalla foto e/o dalla descrizione fornita dall'utente e proponi un piano di cura realistico.
Rispondi ESCLUSIVAMENTE con un oggetto JSON valido con questa struttura esatta:
{
  "common_name": "Nome comune in italiano (es. Monstera Deliciosa)",
  "scientific_name": "Nome scientifico (es. Monstera deliciosa)",
  "light_level": "low | indirect | brightDirect",
  "watering_interval_days": 7,
  "photo_check_interval_days": 14,
  "care_summary": "Breve guida pratica in italiano (2-3 frasi su terreno, umidità e posizionamento).",
  "initial_health_score": 8.5,
  "initial_health_status": "healthy | attention | critical | unknown",
  "cat_toxicity": "safe | mild | toxic | unknown",
  "cat_toxicity_notes": "Breve indicazione chiara in italiano sulla sicurezza per i gatti (es. 'Tossica per i gatti: contiene ossalati di calcio, tenere fuori portata' oppure 'Sicura e non tossica per i gatti')."
}
Se non è stata fornita una foto, imposta initial_health_score a null e initial_health_status a "unknown".
Valuta sempre con precisione ASPCA la tossicità per i gatti in base alla specie identificata.
Non aggiungere markdown o testo fuori dal JSON.
''';

  static const String _healthSystemPrompt = '''
Sei un botanico e fitopatologo esperto italiano.
Analizza la foto attuale della pianta (e, se presente, confrontala con la diagnosi o la foto precedente) per valutarne lo stato di salute.
Rispondi ESCLUSIVAMENTE con un oggetto JSON valido con questa struttura esatta:
{
  "health_score": 8.2,
  "status": "healthy | attention | critical",
  "headline": "Titolo sintetico dello stato (max 55 caratteri)",
  "diagnosis": "Valutazione chiara e concreta in italiano di 2-3 frasi su foglie, colore, vigore e possibili stress.",
  "issues": ["Eventuale problema rilevato 1", "Eventuale problema 2"],
  "care_actions": ["Azione pratica consigliata 1", "Azione pratica consigliata 2"],
  "trend": "improving | stable | declining | firstCheck",
  "suggested_watering_days": 7
}
Regole:
- health_score deve essere un numero tra 1.0 e 10.0.
- Se la pianta sta bene, issues può essere una lista vuota [].
- suggested_watering_days deve essere un intero tra 1 e 45 solo se consigli di cambiare la frequenza di annaffiatura, altrimenti null.
- Non aggiungere markdown o testo fuori dal JSON.
''';

  Future<AiPlantIdentification> identifyPlant({
    required ResolvedAiCredentials credentials,
    String? userDescription,
    Uint8List? imageBytes,
  }) async {
    final prompt = StringBuffer();
    if (userDescription != null && userDescription.trim().isNotEmpty) {
      prompt.writeln('Descrizione utente: ${userDescription.trim()}');
    } else {
      prompt.writeln('Identifica la pianta nella foto allegata e suggerisci il piano di cura.');
    }

    final rawJson = await _dispatchRequest(
      credentials: credentials,
      systemPrompt: _identifySystemPrompt,
      userPrompt: prompt.toString(),
      images: imageBytes != null ? [imageBytes] : const [],
    );

    final map = _extractJsonObject(rawJson);
    return AiPlantIdentification(
      commonName: (map['common_name'] ?? 'Pianta').toString().trim(),
      scientificName: (map['scientific_name'] ?? '').toString().trim(),
      lightLevel: LightLevel.fromName(map['light_level']?.toString()),
      wateringIntervalDays:
          ((map['watering_interval_days'] as num?)?.toInt() ?? 7).clamp(1, 60),
      photoCheckIntervalDays:
          ((map['photo_check_interval_days'] as num?)?.toInt() ?? 14)
              .clamp(3, 60),
      careSummary: (map['care_summary'] ?? '').toString().trim(),
      initialHealthScore: (map['initial_health_score'] as num?)
          ?.toDouble()
          .clamp(1.0, 10.0),
      initialHealthStatus:
          HealthStatus.fromName(map['initial_health_status']?.toString()),
      catToxicity: CatToxicity.fromName(map['cat_toxicity']?.toString()),
      catToxicityNotes: (map['cat_toxicity_notes'] as String?)?.trim(),
    );
  }

  Future<HealthCheckEntry> analyzePlantHealth({
    required ResolvedAiCredentials credentials,
    required Plant plant,
    required String savedPhotoPath,
    required Uint8List currentPhotoBytes,
    HealthCheckEntry? previousCheck,
    Uint8List? previousPhotoBytes,
    String? userNotes,
  }) async {
    final prompt = StringBuffer()
      ..writeln('DATI DELLA PIANTA:')
      ..writeln('- Nome: ${plant.name}')
      ..writeln(
        '- Specie: ${plant.species.isNotEmpty ? plant.species : "Non specificata"}',
      )
      ..writeln('- Posizione: ${plant.location}')
      ..writeln('- Esposizione luce: ${plant.lightLevel.label}')
      ..writeln(
        '- Frequenza annaffiatura attuale: ogni ${plant.wateringIntervalDays} giorni',
      );

    if (plant.lastWateredAt != null) {
      final daysAgo = DateTime.now().difference(plant.lastWateredAt!).inDays;
      prompt.writeln('- Ultima annaffiatura: $daysAgo giorni fa');
    }

    if (userNotes != null && userNotes.trim().isNotEmpty) {
      prompt.writeln('\nOSSERVAZIONI / SINTOMI UTENTE: ${userNotes.trim()}');
    }

    final images = <Uint8List>[currentPhotoBytes];
    if (previousCheck != null) {
      final daysSincePrev =
          DateTime.now().difference(previousCheck.checkedAt).inDays;
      prompt
        ..writeln('\nCONTROLLO PRECEDENTE ($daysSincePrev giorni fa):')
        ..writeln('- Punteggio precedente: ${previousCheck.healthScore.toStringAsFixed(1)}/10 (${previousCheck.status.label})')
        ..writeln('- Diagnosi precedente: ${previousCheck.headline} — ${previousCheck.diagnosis}');
      if (previousPhotoBytes != null) {
        prompt.writeln(
          'Ti allego 2 foto: la PRIMA è la foto di OGGI, la SECONDA è la foto del controllo precedente per confrontare l\'andamento.',
        );
        images.add(previousPhotoBytes);
      }
    } else {
      prompt.writeln(
        '\nQuesto è il primo check fotografico della pianta: imposta trend a "firstCheck".',
      );
    }

    final rawJson = await _dispatchRequest(
      credentials: credentials,
      systemPrompt: _healthSystemPrompt,
      userPrompt: prompt.toString(),
      images: images,
    );

    final map = _extractJsonObject(rawJson);

    List<String> toStrList(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    final score =
        ((map['health_score'] as num?)?.toDouble() ?? 7.5).clamp(1.0, 10.0);
    var status = HealthStatus.fromName(map['status']?.toString());
    if (status == HealthStatus.unknown) {
      status = score >= 7.5
          ? HealthStatus.healthy
          : (score >= 5.0 ? HealthStatus.attention : HealthStatus.critical);
    }

    final suggestedDaysRaw = (map['suggested_watering_days'] as num?)?.toInt();
    final suggestedDays =
        (suggestedDaysRaw != null && suggestedDaysRaw >= 1 && suggestedDaysRaw <= 60)
            ? suggestedDaysRaw
            : null;

    return HealthCheckEntry(
      id: _uuid.v4(),
      plantId: plant.id,
      checkedAt: DateTime.now(),
      photoPath: savedPhotoPath,
      healthScore: score,
      status: status,
      headline: (map['headline'] ?? 'Analisi completata').toString().trim(),
      diagnosis: (map['diagnosis'] ?? '').toString().trim(),
      issues: toStrList(map['issues']),
      careActions: toStrList(map['care_actions']),
      trend: previousCheck == null
          ? HealthTrend.firstCheck
          : HealthTrend.fromName(map['trend']?.toString()),
      suggestedWateringDays: suggestedDays,
      userNotes: userNotes?.trim().isNotEmpty == true ? userNotes!.trim() : null,
    );
  }

  Future<String> _dispatchRequest({
    required ResolvedAiCredentials credentials,
    required String systemPrompt,
    required String userPrompt,
    List<Uint8List> images = const [],
  }) {
    return switch (credentials.provider) {
      AiProviderType.gemini => _callGemini(
          modelName: credentials.modelName,
          apiKey: credentials.apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          images: images,
        ),
      AiProviderType.openai => _callOpenAiCompatible(
          baseUrl: 'https://api.openai.com/v1',
          modelName: credentials.modelName,
          apiKey: credentials.apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          images: images,
        ),
      AiProviderType.openaiCompatible => _callOpenAiCompatible(
          baseUrl: credentials.baseUrl ?? 'https://openrouter.ai/api/v1',
          modelName: credentials.modelName,
          apiKey: credentials.apiKey,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          images: images,
        ),
    };
  }

  Future<String> _callGemini({
    required String modelName,
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    List<Uint8List> images = const [],
  }) async {
    final cleanKey = SecureKeysService.sanitizeKey(apiKey);
    final candidateModels = <String>{
      modelName,
      'gemini-3-flash-preview',
      'gemini-2.5-flash',
      'gemini-flash-latest',
    }.toList();

    final parts = <Map<String, dynamic>>[
      {'text': '$systemPrompt\n\nRichiesta:\n$userPrompt'},
    ];
    for (final img in images) {
      parts.add({
        'inlineData': {
          'mimeType': 'image/jpeg',
          'data': base64Encode(img),
        },
      });
    }

    String lastError = 'Nessuna risposta da Gemini';
    for (final candidate in candidateModels) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$candidate:generateContent?key=$cleanKey',
      );
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {'role': 'user', 'parts': parts},
              ],
              'generationConfig': {
                'temperature': 0.2,
                'responseMimeType': 'application/json',
              },
            }),
          )
          .timeout(const Duration(seconds: 35));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List<dynamic>? ?? [];
        if (candidates.isEmpty) {
          throw Exception('Gemini non ha restituito candidati validi.');
        }
        final content =
            (candidates.first as Map<String, dynamic>)['content']
                as Map<String, dynamic>? ??
            {};
        final respParts = content['parts'] as List<dynamic>? ?? [];
        final buffer = StringBuffer();
        for (final p in respParts) {
          if (p is Map<String, dynamic> && p['thought'] != true) {
            final t = p['text'];
            if (t is String) buffer.write(t);
          }
        }
        final text = buffer.toString().trim();
        if (text.isNotEmpty) return text;
        lastError = 'Risposta vuota dal modello $candidate';
      } else {
        try {
          final errMap = jsonDecode(response.body) as Map<String, dynamic>;
          final errObj = errMap['error'] as Map<String, dynamic>?;
          lastError =
              errObj?['message']?.toString() ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          lastError = 'HTTP ${response.statusCode}: ${response.body}';
        }
        if (lastError.toLowerCase().contains('api key not valid') ||
            lastError.toLowerCase().contains('api_key_invalid')) {
          throw Exception('API Key Gemini non valida: controlla la chiave.');
        }
      }
    }

    throw Exception('Gemini: $lastError');
  }

  Uri _buildChatCompletionsUri(String rawBaseUrl) {
    var base = rawBaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      return Uri.parse(base);
    }
    return Uri.parse('$base/chat/completions');
  }

  Future<String> _callOpenAiCompatible({
    required String baseUrl,
    required String modelName,
    required String apiKey,
    required String systemPrompt,
    required String userPrompt,
    List<Uint8List> images = const [],
  }) async {
    final cleanKey = SecureKeysService.sanitizeKey(apiKey);
    final uri = _buildChatCompletionsUri(baseUrl);

    final userContent = <Map<String, dynamic>>[
      {'type': 'text', 'text': userPrompt},
    ];
    for (final img in images) {
      userContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,${base64Encode(img)}'},
      });
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (cleanKey.isNotEmpty) 'Authorization': 'Bearer $cleanKey',
    };

    Future<http.Response> send({required bool includeJsonFormat}) {
      return http
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'model': modelName,
              if (includeJsonFormat) 'response_format': {'type': 'json_object'},
              'temperature': 0.2,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userContent},
              ],
            }),
          )
          .timeout(const Duration(seconds: 40));
    }

    var response = await send(includeJsonFormat: true);
    // Some OpenAI-compatible servers reject response_format=json_object on vision models
    if (response.statusCode == 400 &&
        response.body.toLowerCase().contains('response_format')) {
      response = await send(includeJsonFormat: false);
    }

    if (response.statusCode != 200) {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final err = jsonDecode(response.body) as Map<String, dynamic>;
        final errObj = err['error'];
        if (errObj is Map<String, dynamic> && errObj['message'] != null) {
          msg = errObj['message'].toString();
        } else if (errObj is String) {
          msg = errObj;
        }
      } catch (_) {
        if (response.body.isNotEmpty) {
          msg = '${response.statusCode}: ${response.body}';
        }
      }
      throw Exception('Errore API AI: $msg');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) {
      throw Exception('Risposta AI vuota (nessuna scelta restituita).');
    }
    final content = choices.first['message']?['content'];
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map<String, dynamic>>()
          .map((e) => e['text']?.toString() ?? '')
          .join();
    }
    return '{}';
  }

  Uri _buildModelsUri(String rawBaseUrl) {
    var base = rawBaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    }
    if (base.endsWith('/models')) {
      return Uri.parse(base);
    }
    return Uri.parse('$base/models');
  }

  /// Fetches live available models from the provider's official `/models` endpoint
  /// (Google Gemini, OpenAI, or any OpenAI-compatible server like OpenRouter, Groq, Ollama, LM Studio).
  Future<List<String>> fetchAvailableModels({
    required AiProviderType provider,
    required String apiKey,
    String? customBaseUrl,
  }) async {
    return switch (provider) {
      AiProviderType.gemini => fetchAvailableGeminiModels(apiKey),
      AiProviderType.openai => _fetchOpenAiCompatibleModels(
          baseUrl: 'https://api.openai.com/v1',
          apiKey: apiKey,
          filterOpenAiChatOnly: true,
        ),
      AiProviderType.openaiCompatible => _fetchOpenAiCompatibleModels(
          baseUrl: customBaseUrl ?? 'https://openrouter.ai/api/v1',
          apiKey: apiKey,
          filterOpenAiChatOnly: false,
        ),
    };
  }

  Future<List<String>> _fetchOpenAiCompatibleModels({
    required String baseUrl,
    required String apiKey,
    required bool filterOpenAiChatOnly,
  }) async {
    final cleanKey = SecureKeysService.sanitizeKey(apiKey);
    if (filterOpenAiChatOnly && cleanKey.isEmpty) {
      throw Exception('Inserisci prima la tua API Key OpenAI.');
    }
    final uri = _buildModelsUri(baseUrl);
    final res = await http
        .get(
          uri,
          headers: {
            if (cleanKey.isNotEmpty) 'Authorization': 'Bearer $cleanKey',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('Impossibile recuperare i modelli (HTTP ${res.statusCode}).');
    }

    final decoded = jsonDecode(res.body);
    final rawList = decoded is Map<String, dynamic>
        ? (decoded['data'] as List<dynamic>? ??
            decoded['models'] as List<dynamic>? ??
            [])
        : (decoded is List ? decoded : []);

    final ids = <String>[];
    for (final item in rawList) {
      String id = '';
      if (item is Map<String, dynamic>) {
        id = (item['id'] ?? item['name'] ?? '').toString().trim();
      } else if (item is String) {
        id = item.trim();
      }
      if (id.isEmpty) continue;
      if (filterOpenAiChatOnly) {
        final low = id.toLowerCase();
        final isChat = low.startsWith('gpt-') ||
            low.startsWith('chatgpt-') ||
            low.startsWith('o1') ||
            low.startsWith('o3') ||
            low.startsWith('o4');
        final isExcluded = low.contains('audio') ||
            low.contains('realtime') ||
            low.contains('transcribe') ||
            low.contains('tts') ||
            low.contains('instruct') ||
            low.contains('search');
        if (!isChat || isExcluded) continue;
      }
      ids.add(id);
    }
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  /// Fetches live generateContent-capable Gemini models available for [apiKey].
  Future<List<String>> fetchAvailableGeminiModels(String apiKey) async {
    final cleanKey = SecureKeysService.sanitizeKey(apiKey);
    if (cleanKey.isEmpty) {
      throw Exception('Inserisci prima una API Key Gemini.');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models?key=$cleanKey&pageSize=100',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception('Impossibile recuperare i modelli (HTTP ${res.statusCode}).');
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (decoded['models'] as List<dynamic>? ?? []);
    final ids = <String>[];
    for (final raw in models) {
      if (raw is! Map<String, dynamic>) continue;
      final methods = (raw['supportedGenerationMethods'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList();
      if (!methods.contains('generateContent')) continue;
      final fullName = (raw['name'] ?? '').toString();
      final id = fullName.replaceFirst('models/', '');
      if (!id.startsWith('gemini-')) continue;
      if (id.contains('embedding') ||
          id.contains('tts') ||
          id.contains('audio') ||
          id.contains('robotics')) {
        continue;
      }
      ids.add(id);
    }
    // Sort newest generations (3.x, 2.5, etc.) first
    ids.sort((a, b) => b.compareTo(a));
    return ids;
  }

  Map<String, dynamic> _extractJsonObject(String raw) {
    var cleaned = raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
    if (match != null) {
      cleaned = match.group(0)!;
    }
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception('La risposta AI non contiene un oggetto JSON valido.');
  }
}
