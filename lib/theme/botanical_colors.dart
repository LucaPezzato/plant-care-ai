import 'package:flutter/material.dart';

class BotanicalColors extends ThemeExtension<BotanicalColors> {
  final Color healthy;
  final Color water;
  final Color attention;
  final Color critical;
  final Color sunlight;
  final Color photo;

  const BotanicalColors({
    required this.healthy,
    required this.water,
    required this.attention,
    required this.critical,
    required this.sunlight,
    required this.photo,
  });

  static const dark = BotanicalColors(
    healthy: Color(0xFF4ADE80),
    water: Color(0xFF38BDF8),
    attention: Color(0xFFFBBF24),
    critical: Color(0xFFF87171),
    sunlight: Color(0xFFF59E0B),
    photo: Color(0xFFC084FC),
  );

  static const light = BotanicalColors(
    healthy: Color(0xFF16A34A),
    water: Color(0xFF0284C7),
    attention: Color(0xFFD97706),
    critical: Color(0xFFDC2626),
    sunlight: Color(0xFFB45309),
    photo: Color(0xFF9333EA),
  );

  @override
  BotanicalColors copyWith({
    Color? healthy,
    Color? water,
    Color? attention,
    Color? critical,
    Color? sunlight,
    Color? photo,
  }) {
    return BotanicalColors(
      healthy: healthy ?? this.healthy,
      water: water ?? this.water,
      attention: attention ?? this.attention,
      critical: critical ?? this.critical,
      sunlight: sunlight ?? this.sunlight,
      photo: photo ?? this.photo,
    );
  }

  @override
  BotanicalColors lerp(ThemeExtension<BotanicalColors>? other, double t) {
    if (other is! BotanicalColors) return this;
    return BotanicalColors(
      healthy: Color.lerp(healthy, other.healthy, t) ?? healthy,
      water: Color.lerp(water, other.water, t) ?? water,
      attention: Color.lerp(attention, other.attention, t) ?? attention,
      critical: Color.lerp(critical, other.critical, t) ?? critical,
      sunlight: Color.lerp(sunlight, other.sunlight, t) ?? sunlight,
      photo: Color.lerp(photo, other.photo, t) ?? photo,
    );
  }
}

extension BotanicalColorsContext on BuildContext {
  BotanicalColors get botanical =>
      Theme.of(this).extension<BotanicalColors>() ?? BotanicalColors.dark;
}
