import 'package:flutter_test/flutter_test.dart';
import 'package:plant_care_ai/models/plant_models.dart';
import 'package:plant_care_ai/services/shared_garden_service.dart';

void main() {
  group('Plant scheduling logic', () {
    test('calculates next watering and overdue status accurately', () {
      final now = DateTime.now();
      final plantOverdue = Plant(
        id: 'p1',
        name: 'Monstera',
        wateringIntervalDays: 5,
        lastWateredAt: now.subtract(const Duration(days: 7)),
        createdAt: now.subtract(const Duration(days: 30)),
      );

      expect(plantOverdue.isWateringOverdue, isTrue);
      expect(plantOverdue.daysUntilWatering, -2);
      expect(plantOverdue.wateringStatusLabel, 'In ritardo di 2g');
    });

    test('projects scheduled watering dates across a month range', () {
      final base = DateTime(2026, 5, 1);
      final plant = Plant(
        id: 'p2',
        name: 'Pothos',
        wateringIntervalDays: 7,
        lastWateredAt: base,
        createdAt: base,
      );

      final projected = plant.scheduledWateringDatesInRange(
        DateTime(2026, 5, 1),
        DateTime(2026, 5, 31),
      );
      expect(
        projected,
        [
          DateTime(2026, 5, 8),
          DateTime(2026, 5, 15),
          DateTime(2026, 5, 22),
          DateTime(2026, 5, 29),
        ],
      );
    });

    test('serializes and deserializes HealthCheckEntry cleanly', () {
      final entry = HealthCheckEntry(
        id: 'hc1',
        plantId: 'p1',
        checkedAt: DateTime(2026, 5, 10, 9, 30),
        photoPath: '/tmp/test.jpg',
        healthScore: 8.5,
        status: HealthStatus.healthy,
        headline: 'Foglie rigogliose',
        diagnosis: 'Ottimo stato vegetativo.',
        issues: const [],
        careActions: const ['Continua così'],
        trend: HealthTrend.improving,
        suggestedWateringDays: 6,
      );

      final restored = HealthCheckEntry.fromMap(entry.toMap());
      expect(restored.id, entry.id);
      expect(restored.healthScore, 8.5);
      expect(restored.status, HealthStatus.healthy);
      expect(restored.trend, HealthTrend.improving);
      expect(restored.suggestedWateringDays, 6);
      expect(restored.careActions, ['Continua così']);
    });

    test('generates and normalizes family invite codes', () {
      final code = SharedGardenService.generateInviteCode();
      expect(RegExp(r'^[A-Z0-9]{3}-[A-Z0-9]{3}$').hasMatch(code), isTrue);
      expect(SharedGardenService.normalizeCode('k7p 4m2'), 'K7P-4M2');
      expect(SharedGardenService.normalizeCode('k7p-4m2'), 'K7P-4M2');
    });
  });
}
