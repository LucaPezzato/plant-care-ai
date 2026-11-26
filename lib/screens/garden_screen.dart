import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/plant_models.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';
import '../theme/expressive_motion.dart';

class GardenScreen extends StatefulWidget {
  final List<Plant> plants;
  final GardenStats stats;
  final Future<void> Function() onRefresh;
  final void Function(Plant plant) onOpenPlant;
  final Future<void> Function(Plant plant) onQuickWater;
  final void Function(Plant plant) onQuickPhotoCheck;
  final VoidCallback onAddPlant;

  const GardenScreen({
    super.key,
    required this.plants,
    required this.stats,
    required this.onRefresh,
    required this.onOpenPlant,
    required this.onQuickWater,
    required this.onQuickPhotoCheck,
    required this.onAddPlant,
  });

  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  String _filter = 'all';

  List<Plant> get _filteredPlants {
    return switch (_filter) {
      'water' => widget.plants.where((p) => p.needsWaterSoon).toList(),
      'photo' => widget.plants.where((p) => p.isPhotoCheckDue).toList(),
      'attention' => widget.plants
          .where((p) =>
              p.lastHealthStatus == HealthStatus.attention ||
              p.lastHealthStatus == HealthStatus.critical)
          .toList(),
      _ => widget.plants,
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;
    final plants = _filteredPlants;

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            sliver: SliverToBoxAdapter(
              child: _GardenHeroCard(stats: widget.stats),
            ),
          ),
          if (widget.plants.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              sliver: SliverToBoxAdapter(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterPill(
                        label: 'Tutte (${widget.plants.length})',
                        selected: _filter == 'all',
                        onTap: () => setState(() => _filter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: 'Da annaffiare (${widget.stats.overdueWaterings})',
                        selected: _filter == 'water',
                        accent: bot.water,
                        onTap: () => setState(() => _filter = 'water'),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: 'Foto check (${widget.stats.duePhotoChecks})',
                        selected: _filter == 'photo',
                        accent: bot.photo,
                        onTap: () => setState(() => _filter = 'photo'),
                      ),
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: 'Attenzione',
                        selected: _filter == 'attention',
                        accent: bot.attention,
                        onTap: () => setState(() => _filter = 'attention'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (widget.plants.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.potted_plant_rounded,
                        size: 44,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Il tuo giardino è ancora vuoto',
                      style: tt.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scatta una foto a una pianta: l\'AI la riconosce, imposta il calendario di annaffiatura e monitora la sua salute nel tempo.',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: widget.onAddPlant,
                      icon: const Icon(Symbols.add_a_photo_rounded),
                      label: const Text('Aggiungi prima pianta'),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            )
          else if (plants.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.all(32),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Icon(
                      Symbols.check_circle_rounded,
                      size: 42,
                      color: bot.healthy,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tutto in ordine in questa categoria!',
                      style: tt.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverList.separated(
                itemCount: plants.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final plant = plants[index];
                  return _PlantCard(
                    plant: plant,
                    onTap: () => widget.onOpenPlant(plant),
                    onQuickWater: () => widget.onQuickWater(plant),
                    onQuickPhotoCheck: () => widget.onQuickPhotoCheck(plant),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _GardenHeroCard extends StatelessWidget {
  final GardenStats stats;

  const _GardenHeroCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    final avgScore = stats.averageHealthScore;
    final headline = stats.totalPlants == 0
        ? 'Pronto a iniziare'
        : stats.overdueWaterings > 0
            ? '${stats.overdueWaterings} ${stats.overdueWaterings == 1 ? "pianta ha" : "piante hanno"} sete'
            : 'Tutte idratate';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusHero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PANORAMICA GIARDINO',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(headline, style: tt.headlineSmall),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Symbols.eco_rounded,
                      size: 18,
                      color: bot.healthy,
                      fill: 1,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      avgScore != null ? '${avgScore.toStringAsFixed(1)}/10' : '—',
                      style: tt.titleMedium?.copyWith(color: bot.healthy),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStatTile(
                  icon: Symbols.potted_plant_rounded,
                  value: '${stats.totalPlants}',
                  label: 'Piante',
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatTile(
                  icon: Symbols.water_drop_rounded,
                  value: '${stats.overdueWaterings}',
                  label: 'Da bere',
                  color: stats.overdueWaterings > 0 ? bot.water : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStatTile(
                  icon: Symbols.photo_camera_rounded,
                  value: '${stats.duePhotoChecks}',
                  label: 'Foto check',
                  color: stats.duePhotoChecks > 0 ? bot.photo : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _MiniStatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusInner),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color, fill: 1),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: tt.titleMedium),
              Text(
                label,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor:
          accent?.withValues(alpha: 0.22) ?? cs.primaryContainer,
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? (accent ?? cs.onPrimaryContainer) : cs.onSurface,
          ),
      onSelected: (_) => onTap(),
    );
  }
}

class _PlantCard extends StatelessWidget {
  final Plant plant;
  final VoidCallback onTap;
  final VoidCallback onQuickWater;
  final VoidCallback onQuickPhotoCheck;

  const _PlantCard({
    required this.plant,
    required this.onTap,
    required this.onQuickWater,
    required this.onQuickPhotoCheck,
  });

  Color _healthColor(BotanicalColors bot, ColorScheme cs) =>
      switch (plant.lastHealthStatus) {
        HealthStatus.healthy => bot.healthy,
        HealthStatus.attention => bot.attention,
        HealthStatus.critical => bot.critical,
        HealthStatus.unknown => cs.onSurfaceVariant,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    final waterColor = plant.isWateringOverdue
        ? bot.critical
        : (plant.isWateringDueToday ? bot.water : bot.healthy);
    final healthColor = _healthColor(bot, cs);
    final hasPhoto = plant.coverPhotoPath != null &&
        plant.coverPhotoPath!.isNotEmpty &&
        File(plant.coverPhotoPath!).existsSync();

    return ExpressiveTapScale(
      onTap: onTap,
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plant Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusInner),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: hasPhoto
                            ? Image.file(
                                File(plant.coverPhotoPath!),
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: cs.primaryContainer
                                    .withValues(alpha: 0.45),
                                child: Icon(
                                  Symbols.potted_plant_rounded,
                                  size: 34,
                                  color: cs.primary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plant.name,
                                  style: tt.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (plant.lastHealthScore != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: healthColor.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${plant.lastHealthScore!.toStringAsFixed(1)} • ${plant.lastHealthStatus.label}',
                                    style: tt.labelSmall?.copyWith(
                                      color: healthColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          if (plant.species.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              plant.species,
                              style: tt.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _MetaBadge(
                                icon: Symbols.location_on_rounded,
                                text: plant.location,
                              ),
                              _MetaBadge(
                                icon: Symbols.wb_sunny_rounded,
                                text: plant.lightLevel.shortLabel,
                                iconColor: bot.sunlight,
                              ),
                              if (plant.isPhotoCheckDue)
                                _MetaBadge(
                                  icon: Symbols.photo_camera_rounded,
                                  text: 'Check foto',
                                  iconColor: bot.photo,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Watering bar + quick actions
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Symbols.water_drop_rounded,
                                size: 15,
                                color: waterColor,
                                fill: 1,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                plant.wateringStatusLabel,
                                style: tt.labelMedium?.copyWith(
                                  color: waterColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '• ogni ${plant.wateringIntervalDays}g',
                                style: tt.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: plant.needsWaterSoon
                                  ? 0.08
                                  : plant.hydrationProgress,
                              minHeight: 6,
                              backgroundColor: cs.surfaceContainerHigh,
                              color: waterColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Check salute AI con foto',
                      onPressed: onQuickPhotoCheck,
                      icon: const Icon(
                        Symbols.photo_camera_rounded,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      onPressed: onQuickWater,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        backgroundColor: plant.needsWaterSoon
                            ? bot.water.withValues(alpha: 0.22)
                            : cs.surfaceContainerHigh,
                        foregroundColor:
                            plant.needsWaterSoon ? bot.water : cs.onSurface,
                      ),
                      icon: const Icon(
                        Symbols.water_drop_rounded,
                        size: 18,
                        fill: 1,
                      ),
                      label: const Text('Annaffia'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const _MetaBadge({
    required this.icon,
    required this.text,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
