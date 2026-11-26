import 'dart:convert';

enum AiProviderType {
  gemini,
  openai,
  openaiCompatible;

  String get label => switch (this) {
        AiProviderType.gemini => 'Google Gemini',
        AiProviderType.openai => 'OpenAI / ChatGPT',
        AiProviderType.openaiCompatible => 'OpenAI-Compatibile',
      };

  String get shortLabel => switch (this) {
        AiProviderType.gemini => 'Gemini',
        AiProviderType.openai => 'OpenAI',
        AiProviderType.openaiCompatible => 'Custom API',
      };

  static AiProviderType fromName(String? raw) {
    return AiProviderType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AiProviderType.gemini,
    );
  }
}

enum LightLevel {
  low,
  indirect,
  brightDirect;

  String get label => switch (this) {
        LightLevel.low => 'Luce bassa / ombra',
        LightLevel.indirect => 'Luce indiretta',
        LightLevel.brightDirect => 'Sole diretto',
      };

  String get shortLabel => switch (this) {
        LightLevel.low => 'Ombra',
        LightLevel.indirect => 'Indiretta',
        LightLevel.brightDirect => 'Sole diretto',
      };

  static LightLevel fromName(String? raw) {
    if (raw == null) return LightLevel.indirect;
    final norm = raw.toLowerCase().trim();
    if (norm.contains('low') || norm.contains('bass') || norm.contains('ombr')) {
      return LightLevel.low;
    }
    if (norm.contains('direct') || norm.contains('dirett') || norm.contains('pien')) {
      return LightLevel.brightDirect;
    }
    return LightLevel.indirect;
  }
}

enum HealthStatus {
  healthy,
  attention,
  critical,
  unknown;

  String get label => switch (this) {
        HealthStatus.healthy => 'In salute',
        HealthStatus.attention => 'Attenzione',
        HealthStatus.critical => 'Critica',
        HealthStatus.unknown => 'Da valutare',
      };

  static HealthStatus fromName(String? raw) {
    if (raw == null) return HealthStatus.unknown;
    final norm = raw.toLowerCase().trim();
    if (norm == 'healthy' || norm.contains('salut') || norm.contains('ottim')) {
      return HealthStatus.healthy;
    }
    if (norm == 'attention' || norm.contains('attenz') || norm.contains('moder')) {
      return HealthStatus.attention;
    }
    if (norm == 'critical' || norm.contains('critic') || norm.contains('grave')) {
      return HealthStatus.critical;
    }
    return HealthStatus.unknown;
  }
}

enum HealthTrend {
  improving,
  stable,
  declining,
  firstCheck;

  String get label => switch (this) {
        HealthTrend.improving => 'In miglioramento',
        HealthTrend.stable => 'Stabile',
        HealthTrend.declining => 'In peggioramento',
        HealthTrend.firstCheck => 'Prima analisi',
      };

  static HealthTrend fromName(String? raw) {
    if (raw == null) return HealthTrend.firstCheck;
    final norm = raw.toLowerCase().trim();
    if (norm.contains('improv') || norm.contains('miglior')) {
      return HealthTrend.improving;
    }
    if (norm.contains('stabl') || norm.contains('stabil')) {
      return HealthTrend.stable;
    }
    if (norm.contains('declin') || norm.contains('peggior')) {
      return HealthTrend.declining;
    }
    return HealthTrend.firstCheck;
  }
}

enum CatToxicity {
  safe,
  mild,
  toxic,
  unknown;

  String get label => switch (this) {
        CatToxicity.safe => 'Sicura per gatti',
        CatToxicity.mild => 'Irritante per gatti',
        CatToxicity.toxic => 'Tossica per gatti',
        CatToxicity.unknown => 'Non verificata',
      };

  String get shortLabel => switch (this) {
        CatToxicity.safe => 'Sicura gatti',
        CatToxicity.mild => 'Irritante gatti',
        CatToxicity.toxic => 'Tossica gatti',
        CatToxicity.unknown => 'N/D',
      };

  static CatToxicity fromName(String? raw) {
    if (raw == null) return CatToxicity.unknown;
    final norm = raw.toLowerCase().trim();
    if (norm == 'safe' || norm.contains('sicur') || norm.contains('non tossic')) {
      return CatToxicity.safe;
    }
    if (norm == 'mild' || norm.contains('irrit') || norm.contains('liev') || norm.contains('moder')) {
      return CatToxicity.mild;
    }
    if (norm == 'toxic' || norm.contains('tossic') || norm.contains('velen')) {
      return CatToxicity.toxic;
    }
    return CatToxicity.unknown;
  }
}

DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

class AppSettings {
  final AiProviderType preferredAiProvider;
  final String preferredAiModel;
  final String customBaseUrl;
  final String customModelName;
  final bool wateringReminderEnabled;
  final bool photoReminderEnabled;
  final int reminderHour;
  final int reminderMinute;
  final int themeModeIndex; // 0 = dark, 1 = light, 2 = system
  final bool autoBackupEnabled;
  final DateTime? lastCloudBackupAt;
  final String? activeGardenId;
  final String? activeGardenName;
  final String? activeGardenInviteCode;

  const AppSettings({
    this.preferredAiProvider = AiProviderType.gemini,
    this.preferredAiModel = 'gemini-3-flash-preview',
    this.customBaseUrl = 'https://openrouter.ai/api/v1',
    this.customModelName = 'google/gemini-3-flash-preview',
    this.wateringReminderEnabled = true,
    this.photoReminderEnabled = true,
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.themeModeIndex = 0,
    this.autoBackupEnabled = true,
    this.lastCloudBackupAt,
    this.activeGardenId,
    this.activeGardenName,
    this.activeGardenInviteCode,
  });

  bool get hasSharedGarden =>
      activeGardenId != null && activeGardenId!.isNotEmpty;

  String get formattedReminderTime =>
      '${reminderHour.toString().padLeft(2, '0')}:${reminderMinute.toString().padLeft(2, '0')}';

  AppSettings copyWith({
    AiProviderType? preferredAiProvider,
    String? preferredAiModel,
    String? customBaseUrl,
    String? customModelName,
    bool? wateringReminderEnabled,
    bool? photoReminderEnabled,
    int? reminderHour,
    int? reminderMinute,
    int? themeModeIndex,
    bool? autoBackupEnabled,
    DateTime? lastCloudBackupAt,
    String? activeGardenId,
    String? activeGardenName,
    String? activeGardenInviteCode,
    bool clearSharedGarden = false,
  }) {
    return AppSettings(
      preferredAiProvider: preferredAiProvider ?? this.preferredAiProvider,
      preferredAiModel: preferredAiModel ?? this.preferredAiModel,
      customBaseUrl: customBaseUrl ?? this.customBaseUrl,
      customModelName: customModelName ?? this.customModelName,
      wateringReminderEnabled:
          wateringReminderEnabled ?? this.wateringReminderEnabled,
      photoReminderEnabled: photoReminderEnabled ?? this.photoReminderEnabled,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      themeModeIndex: themeModeIndex ?? this.themeModeIndex,
      autoBackupEnabled: autoBackupEnabled ?? this.autoBackupEnabled,
      lastCloudBackupAt: lastCloudBackupAt ?? this.lastCloudBackupAt,
      activeGardenId: clearSharedGarden
          ? null
          : (activeGardenId ?? this.activeGardenId),
      activeGardenName: clearSharedGarden
          ? null
          : (activeGardenName ?? this.activeGardenName),
      activeGardenInviteCode: clearSharedGarden
          ? null
          : (activeGardenInviteCode ?? this.activeGardenInviteCode),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': 1,
        'preferred_ai_provider': preferredAiProvider.name,
        'preferred_ai_model': preferredAiModel,
        'custom_base_url': customBaseUrl,
        'custom_model_name': customModelName,
        'watering_reminder_enabled': wateringReminderEnabled ? 1 : 0,
        'photo_reminder_enabled': photoReminderEnabled ? 1 : 0,
        'reminder_hour': reminderHour,
        'reminder_minute': reminderMinute,
        'theme_mode_index': themeModeIndex,
        'auto_backup_enabled': autoBackupEnabled ? 1 : 0,
        'last_cloud_backup_at': lastCloudBackupAt?.toIso8601String(),
        'active_garden_id': activeGardenId,
        'active_garden_name': activeGardenName,
        'active_garden_invite_code': activeGardenInviteCode,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      preferredAiProvider:
          AiProviderType.fromName(map['preferred_ai_provider'] as String?),
      preferredAiModel:
          (map['preferred_ai_model'] as String?) ?? 'gemini-3-flash-preview',
      customBaseUrl: (map['custom_base_url'] as String?) ??
          'https://openrouter.ai/api/v1',
      customModelName: (map['custom_model_name'] as String?) ??
          'google/gemini-3-flash-preview',
      wateringReminderEnabled:
          ((map['watering_reminder_enabled'] as int?) ?? 1) == 1,
      photoReminderEnabled: ((map['photo_reminder_enabled'] as int?) ?? 1) == 1,
      reminderHour: (map['reminder_hour'] as int?) ?? 9,
      reminderMinute: (map['reminder_minute'] as int?) ?? 0,
      themeModeIndex: (map['theme_mode_index'] as int?) ?? 0,
      autoBackupEnabled: ((map['auto_backup_enabled'] as int?) ?? 1) == 1,
      lastCloudBackupAt: map['last_cloud_backup_at'] != null
          ? DateTime.tryParse(map['last_cloud_backup_at'] as String)
          : null,
      activeGardenId: map['active_garden_id'] as String?,
      activeGardenName: map['active_garden_name'] as String?,
      activeGardenInviteCode: map['active_garden_invite_code'] as String?,
    );
  }
}

class Plant {
  final String id;
  final String name;
  final String species;
  final String location;
  final LightLevel lightLevel;
  final int wateringIntervalDays;
  final int photoCheckIntervalDays;
  final DateTime? lastWateredAt;
  final DateTime? lastPhotoCheckAt;
  final String? coverPhotoPath;
  final String? notes;
  final double? lastHealthScore;
  final HealthStatus lastHealthStatus;
  final CatToxicity catToxicity;
  final String? catToxicityNotes;
  final DateTime createdAt;

  const Plant({
    required this.id,
    required this.name,
    this.species = '',
    this.location = 'Casa',
    this.lightLevel = LightLevel.indirect,
    this.wateringIntervalDays = 7,
    this.photoCheckIntervalDays = 14,
    this.lastWateredAt,
    this.lastPhotoCheckAt,
    this.coverPhotoPath,
    this.notes,
    this.lastHealthScore,
    this.lastHealthStatus = HealthStatus.unknown,
    this.catToxicity = CatToxicity.unknown,
    this.catToxicityNotes,
    required this.createdAt,
  });

  DateTime get nextWateringDate {
    final base = dateOnly(lastWateredAt ?? createdAt);
    return base.add(Duration(days: wateringIntervalDays.clamp(1, 90)));
  }

  int get daysUntilWatering {
    final today = dateOnly(DateTime.now());
    return nextWateringDate.difference(today).inDays;
  }

  bool get isWateringOverdue => daysUntilWatering < 0;
  bool get isWateringDueToday => daysUntilWatering == 0;
  bool get needsWaterSoon => daysUntilWatering <= 0;

  double get hydrationProgress {
    final interval = wateringIntervalDays.clamp(1, 90);
    final remaining = daysUntilWatering.clamp(0, interval);
    return (remaining / interval).clamp(0.0, 1.0);
  }

  String get wateringStatusLabel {
    final d = daysUntilWatering;
    if (d < -1) return 'In ritardo di ${-d}g';
    if (d == -1) return 'In ritardo di 1g';
    if (d == 0) return 'Annaffia oggi';
    if (d == 1) return 'Domani';
    return 'Tra $d giorni';
  }

  DateTime get nextPhotoCheckDate {
    final base = dateOnly(lastPhotoCheckAt ?? createdAt);
    return base.add(Duration(days: photoCheckIntervalDays.clamp(3, 120)));
  }

  int get daysUntilPhotoCheck {
    final today = dateOnly(DateTime.now());
    return nextPhotoCheckDate.difference(today).inDays;
  }

  bool get isPhotoCheckDue => daysUntilPhotoCheck <= 0;

  String get photoCheckStatusLabel {
    final d = daysUntilPhotoCheck;
    if (d < 0) return 'Check in ritardo (${-d}g)';
    if (d == 0) return 'Foto check oggi';
    if (d == 1) return 'Foto domani';
    return 'Foto tra $d giorni';
  }

  /// Projects all scheduled watering dates within [start, end] (inclusive).
  List<DateTime> scheduledWateringDatesInRange(DateTime start, DateTime end) {
    final results = <DateTime>[];
    final interval = wateringIntervalDays.clamp(1, 90);
    final s = dateOnly(start);
    final e = dateOnly(end);
    var cursor = nextWateringDate;
    // If nextWateringDate is after end, nothing to add in future
    if (cursor.isAfter(e)) return results;
    while (cursor.isBefore(s)) {
      cursor = cursor.add(Duration(days: interval));
    }
    while (!cursor.isAfter(e)) {
      results.add(cursor);
      cursor = cursor.add(Duration(days: interval));
    }
    return results;
  }

  /// Projects all scheduled photo check dates within [start, end] (inclusive).
  List<DateTime> scheduledPhotoDatesInRange(DateTime start, DateTime end) {
    final results = <DateTime>[];
    final interval = photoCheckIntervalDays.clamp(3, 120);
    final s = dateOnly(start);
    final e = dateOnly(end);
    var cursor = nextPhotoCheckDate;
    if (cursor.isAfter(e)) return results;
    while (cursor.isBefore(s)) {
      cursor = cursor.add(Duration(days: interval));
    }
    while (!cursor.isAfter(e)) {
      results.add(cursor);
      cursor = cursor.add(Duration(days: interval));
    }
    return results;
  }

  Plant copyWith({
    String? id,
    String? name,
    String? species,
    String? location,
    LightLevel? lightLevel,
    int? wateringIntervalDays,
    int? photoCheckIntervalDays,
    DateTime? lastWateredAt,
    bool clearLastWateredAt = false,
    DateTime? lastPhotoCheckAt,
    bool clearLastPhotoCheckAt = false,
    String? coverPhotoPath,
    bool clearCoverPhotoPath = false,
    String? notes,
    double? lastHealthScore,
    HealthStatus? lastHealthStatus,
    CatToxicity? catToxicity,
    String? catToxicityNotes,
    DateTime? createdAt,
  }) {
    return Plant(
      id: id ?? this.id,
      name: name ?? this.name,
      species: species ?? this.species,
      location: location ?? this.location,
      lightLevel: lightLevel ?? this.lightLevel,
      wateringIntervalDays: wateringIntervalDays ?? this.wateringIntervalDays,
      photoCheckIntervalDays:
          photoCheckIntervalDays ?? this.photoCheckIntervalDays,
      lastWateredAt:
          clearLastWateredAt ? null : (lastWateredAt ?? this.lastWateredAt),
      lastPhotoCheckAt: clearLastPhotoCheckAt
          ? null
          : (lastPhotoCheckAt ?? this.lastPhotoCheckAt),
      coverPhotoPath:
          clearCoverPhotoPath ? null : (coverPhotoPath ?? this.coverPhotoPath),
      notes: notes ?? this.notes,
      lastHealthScore: lastHealthScore ?? this.lastHealthScore,
      lastHealthStatus: lastHealthStatus ?? this.lastHealthStatus,
      catToxicity: catToxicity ?? this.catToxicity,
      catToxicityNotes: catToxicityNotes ?? this.catToxicityNotes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'species': species,
        'location': location,
        'light_level': lightLevel.name,
        'watering_interval_days': wateringIntervalDays,
        'photo_check_interval_days': photoCheckIntervalDays,
        'last_watered_at': lastWateredAt?.toIso8601String(),
        'last_photo_check_at': lastPhotoCheckAt?.toIso8601String(),
        'cover_photo_path': coverPhotoPath,
        'notes': notes,
        'last_health_score': lastHealthScore,
        'last_health_status': lastHealthStatus.name,
        'cat_toxicity': catToxicity.name,
        'cat_toxicity_notes': catToxicityNotes,
        'created_at': createdAt.toIso8601String(),
      };

  factory Plant.fromMap(Map<String, dynamic> map) {
    return Plant(
      id: map['id'] as String,
      name: map['name'] as String,
      species: (map['species'] as String?) ?? '',
      location: (map['location'] as String?) ?? 'Casa',
      lightLevel: LightLevel.fromName(map['light_level'] as String?),
      wateringIntervalDays: (map['watering_interval_days'] as int?) ?? 7,
      photoCheckIntervalDays: (map['photo_check_interval_days'] as int?) ?? 14,
      lastWateredAt: map['last_watered_at'] != null
          ? DateTime.tryParse(map['last_watered_at'] as String)
          : null,
      lastPhotoCheckAt: map['last_photo_check_at'] != null
          ? DateTime.tryParse(map['last_photo_check_at'] as String)
          : null,
      coverPhotoPath: map['cover_photo_path'] as String?,
      notes: map['notes'] as String?,
      lastHealthScore: (map['last_health_score'] as num?)?.toDouble(),
      lastHealthStatus:
          HealthStatus.fromName(map['last_health_status'] as String?),
      catToxicity: CatToxicity.fromName(map['cat_toxicity'] as String?),
      catToxicityNotes: map['cat_toxicity_notes'] as String?,
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

class WateringLog {
  final String id;
  final String plantId;
  final DateTime wateredAt;
  final String? notes;
  final String? wateredBy;

  const WateringLog({
    required this.id,
    required this.plantId,
    required this.wateredAt,
    this.notes,
    this.wateredBy,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'plant_id': plantId,
        'watered_at': wateredAt.toIso8601String(),
        'notes': notes,
        'watered_by': wateredBy,
      };

  factory WateringLog.fromMap(Map<String, dynamic> map) {
    return WateringLog(
      id: map['id'] as String,
      plantId: map['plant_id'] as String,
      wateredAt: DateTime.tryParse((map['watered_at'] as String?) ?? '') ??
          DateTime.now(),
      notes: map['notes'] as String?,
      wateredBy: map['watered_by'] as String?,
    );
  }
}

class GardenMember {
  final String uid;
  final String displayName;
  final String? email;
  final DateTime joinedAt;

  const GardenMember({
    required this.uid,
    required this.displayName,
    this.email,
    required this.joinedAt,
  });
}

class SharedGarden {
  final String id;
  final String name;
  final String inviteCode;
  final String ownerUid;
  final List<GardenMember> members;

  const SharedGarden({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerUid,
    this.members = const [],
  });
}

class HealthCheckEntry {
  final String id;
  final String plantId;
  final DateTime checkedAt;
  final String photoPath;
  final double healthScore;
  final HealthStatus status;
  final String headline;
  final String diagnosis;
  final List<String> issues;
  final List<String> careActions;
  final HealthTrend trend;
  final int? suggestedWateringDays;
  final String? userNotes;

  const HealthCheckEntry({
    required this.id,
    required this.plantId,
    required this.checkedAt,
    required this.photoPath,
    required this.healthScore,
    required this.status,
    required this.headline,
    required this.diagnosis,
    this.issues = const [],
    this.careActions = const [],
    this.trend = HealthTrend.firstCheck,
    this.suggestedWateringDays,
    this.userNotes,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'plant_id': plantId,
        'checked_at': checkedAt.toIso8601String(),
        'photo_path': photoPath,
        'health_score': healthScore,
        'status': status.name,
        'headline': headline,
        'diagnosis': diagnosis,
        'issues_json': jsonEncode(issues),
        'care_actions_json': jsonEncode(careActions),
        'trend': trend.name,
        'suggested_watering_days': suggestedWateringDays,
        'user_notes': userNotes,
      };

  factory HealthCheckEntry.fromMap(Map<String, dynamic> map) {
    List<String> decodeList(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is List) {
            return parsed.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
      return const [];
    }

    return HealthCheckEntry(
      id: map['id'] as String,
      plantId: map['plant_id'] as String,
      checkedAt: DateTime.tryParse((map['checked_at'] as String?) ?? '') ??
          DateTime.now(),
      photoPath: (map['photo_path'] as String?) ?? '',
      healthScore: ((map['health_score'] as num?) ?? 7.5).toDouble(),
      status: HealthStatus.fromName(map['status'] as String?),
      headline: (map['headline'] as String?) ?? 'Controllo salute',
      diagnosis: (map['diagnosis'] as String?) ?? '',
      issues: decodeList(map['issues_json']),
      careActions: decodeList(map['care_actions_json']),
      trend: HealthTrend.fromName(map['trend'] as String?),
      suggestedWateringDays: (map['suggested_watering_days'] as num?)?.toInt(),
      userNotes: map['user_notes'] as String?,
    );
  }
}

class AiPlantIdentification {
  final String commonName;
  final String scientificName;
  final LightLevel lightLevel;
  final int wateringIntervalDays;
  final int photoCheckIntervalDays;
  final String careSummary;
  final double? initialHealthScore;
  final HealthStatus initialHealthStatus;
  final CatToxicity catToxicity;
  final String? catToxicityNotes;

  const AiPlantIdentification({
    required this.commonName,
    required this.scientificName,
    required this.lightLevel,
    required this.wateringIntervalDays,
    required this.photoCheckIntervalDays,
    required this.careSummary,
    this.initialHealthScore,
    this.initialHealthStatus = HealthStatus.unknown,
    this.catToxicity = CatToxicity.unknown,
    this.catToxicityNotes,
  });
}

class GardenStats {
  final int totalPlants;
  final int overdueWaterings;
  final int duePhotoChecks;
  final double? averageHealthScore;
  final int wateringsThisMonth;
  final int totalHealthChecks;

  const GardenStats({
    required this.totalPlants,
    required this.overdueWaterings,
    required this.duePhotoChecks,
    this.averageHealthScore,
    required this.wateringsThisMonth,
    required this.totalHealthChecks,
  });
}
