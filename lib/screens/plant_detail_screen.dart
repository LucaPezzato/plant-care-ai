import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../data/local_database.dart';
import '../models/plant_models.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';
import 'add_plant_sheet.dart';
import 'health_check_sheet.dart';

class PlantDetailScreen extends StatefulWidget {
  final Plant plant;
  final AppSettings settings;
  final Future<void> Function() onDataMutated;

  const PlantDetailScreen({
    super.key,
    required this.plant,
    required this.settings,
    required this.onDataMutated,
  });

  @override
  State<PlantDetailScreen> createState() => _PlantDetailScreenState();
}

class _PlantDetailScreenState extends State<PlantDetailScreen> {
  late Plant _plant = widget.plant;
  List<HealthCheckEntry> _healthChecks = [];
  List<WateringLog> _wateringLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final fresh = await LocalDatabase.instance.getPlant(_plant.id);
    final checks =
        await LocalDatabase.instance.getHealthChecksForPlant(_plant.id);
    final logs = await LocalDatabase.instance.getWateringLogsForPlant(_plant.id);
    if (!mounted) return;
    setState(() {
      if (fresh != null) _plant = fresh;
      _healthChecks = checks;
      _wateringLogs = logs;
      _loading = false;
    });
  }

  Future<void> _waterNow() async {
    await LocalDatabase.instance.logWatering(_plant.id);
    await _reload();
    await widget.onDataMutated();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Annaffiatura registrata per ${_plant.name} 💧')),
    );
  }

  Future<void> _openHealthCheck() async {
    await HealthCheckSheet.show(
      context,
      plant: _plant,
      settings: widget.settings,
      onSaved: (entry, {int? updatedWateringDays}) async {
        await LocalDatabase.instance.saveHealthCheck(entry);
        if (updatedWateringDays != null) {
          await LocalDatabase.instance.upsertPlant(
            _plant.copyWith(wateringIntervalDays: updatedWateringDays),
          );
        }
        await _reload();
        await widget.onDataMutated();
      },
    );
  }

  Future<void> _editPlant() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddPlantSheet(
        settings: widget.settings,
        existingPlant: _plant,
        onSave: (updated) async {
          await LocalDatabase.instance.upsertPlant(updated);
          await _reload();
          await widget.onDataMutated();
        },
      ),
    );
  }

  Future<void> _deletePlant() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare "${_plant.name}"?'),
        content: const Text(
          'Verranno eliminati anche lo storico annaffiature e il diario fotografico di questa pianta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDatabase.instance.deletePlant(_plant.id);
    await widget.onDataMutated();
    if (mounted) Navigator.of(context).pop();
  }

  void _openFullImage(String path) {
    if (!File(path).existsSync()) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(File(path), fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Symbols.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(HealthStatus s, BotanicalColors bot, ColorScheme cs) =>
      switch (s) {
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
    final dateFmt = DateFormat('dd/MM/yyyy • HH:mm');
    final shortDateFmt = DateFormat('dd/MM/yyyy');

    final hasCover = _plant.coverPhotoPath != null &&
        _plant.coverPhotoPath!.isNotEmpty &&
        File(_plant.coverPhotoPath!).existsSync();
    final waterColor = _plant.isWateringOverdue
        ? bot.critical
        : (_plant.isWateringDueToday ? bot.water : bot.healthy);
    final healthColor = _statusColor(_plant.lastHealthStatus, bot, cs);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_plant.name, style: tt.titleLarge),
        actions: [
          IconButton(
            tooltip: 'Modifica pianta',
            onPressed: _editPlant,
            icon: const Icon(Symbols.edit_rounded),
          ),
          IconButton(
            tooltip: 'Elimina pianta',
            onPressed: _deletePlant,
            icon: const Icon(Symbols.delete_outline_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                // Hero Cover Card
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusHero),
                  child: Stack(
                    children: [
                      SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: hasCover
                            ? GestureDetector(
                                onTap: () =>
                                    _openFullImage(_plant.coverPhotoPath!),
                                child: Image.file(
                                  File(_plant.coverPhotoPath!),
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Container(
                                color:
                                    cs.primaryContainer.withValues(alpha: 0.4),
                                child: Icon(
                                  Symbols.potted_plant_rounded,
                                  size: 72,
                                  color: cs.primary,
                                ),
                              ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.72),
                              ],
                              stops: const [0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _plant.name,
                                    style: tt.headlineSmall?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (_plant.species.isNotEmpty)
                                    Text(
                                      _plant.species,
                                      style: tt.bodyMedium?.copyWith(
                                        color: Colors.white70,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (_plant.lastHealthScore != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: healthColor.withValues(alpha: 0.8),
                                  ),
                                ),
                                child: Text(
                                  '${_plant.lastHealthScore!.toStringAsFixed(1)}/10 • ${_plant.lastHealthStatus.label}',
                                  style: tt.labelMedium?.copyWith(
                                    color: healthColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                // Quick Actions Row
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _waterNow,
                        style: FilledButton.styleFrom(
                          backgroundColor: bot.water,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(Symbols.water_drop_rounded, fill: 1),
                        label: const Text('Annaffia ora'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _openHealthCheck,
                        icon: const Icon(Symbols.photo_camera_rounded),
                        label: const Text('Check AI Foto'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                // Schedule & Care Details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Scheda di Cura', style: tt.titleMedium),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Symbols.water_drop_rounded,
                              iconColor: waterColor,
                              label: 'Prossima acqua',
                              value: _plant.wateringStatusLabel,
                              sub:
                                  'Ogni ${_plant.wateringIntervalDays}g • ${shortDateFmt.format(_plant.nextWateringDate)}',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InfoTile(
                              icon: Symbols.photo_camera_rounded,
                              iconColor: bot.photo,
                              label: 'Check fotografico',
                              value: _plant.photoCheckStatusLabel,
                              sub:
                                  'Ogni ${_plant.photoCheckIntervalDays}g • ${shortDateFmt.format(_plant.nextPhotoCheckDate)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoTile(
                              icon: Symbols.location_on_rounded,
                              iconColor: cs.primary,
                              label: 'Posizione',
                              value: _plant.location,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InfoTile(
                              icon: Symbols.wb_sunny_rounded,
                              iconColor: bot.sunlight,
                              label: 'Luce',
                              value: _plant.lightLevel.shortLabel,
                            ),
                          ),
                        ],
                      ),
                      if (_plant.catToxicity != CatToxicity.unknown ||
                          (_plant.catToxicityNotes != null &&
                              _plant.catToxicityNotes!.isNotEmpty)) ...[
                        const SizedBox(height: 10),
                        _CatSafetyBanner(
                          toxicity: _plant.catToxicity,
                          notes: _plant.catToxicityNotes,
                        ),
                      ],
                      if (_plant.notes != null && _plant.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusInner),
                          ),
                          child: Text(_plant.notes!, style: tt.bodyMedium),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // Photo Health Diary
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Diario Fotografico & Salute', style: tt.titleLarge),
                    TextButton.icon(
                      onPressed: _openHealthCheck,
                      icon: const Icon(Symbols.add_a_photo_rounded, size: 18),
                      label: const Text('Nuovo check'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_healthChecks.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Symbols.photo_camera_rounded,
                          size: 32,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nessun check fotografico ancora registrato.',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scatta foto periodiche per monitorare la crescita e far diagnosticare eventuali stress all\'AI.',
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  for (final entry in _healthChecks) ...[
                    _HealthCheckCard(
                      entry: entry,
                      dateLabel: dateFmt.format(entry.checkedAt),
                      statusColor: _statusColor(entry.status, bot, cs),
                      onTapPhoto: () => _openFullImage(entry.photoPath),
                      onDelete: () async {
                        await LocalDatabase.instance.deleteHealthCheck(entry);
                        await _reload();
                        await widget.onDataMutated();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],

                const SizedBox(height: 18),
                Text('Storico Annaffiature', style: tt.titleLarge),
                const SizedBox(height: 8),
                if (_wateringLogs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: Text(
                      'Nessuna annaffiatura registrata ancora.',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    ),
                    child: Column(
                      children: _wateringLogs.take(10).map((log) {
                        return ListTile(
                          leading: Icon(
                            Symbols.water_drop_rounded,
                            color: bot.water,
                            fill: 1,
                          ),
                          title: Text(dateFmt.format(log.wateredAt)),
                          subtitle: (log.wateredBy != null || log.notes != null)
                              ? Text(
                                  [
                                    if (log.wateredBy != null &&
                                        log.wateredBy!.isNotEmpty)
                                      'Da ${log.wateredBy}',
                                    if (log.notes != null &&
                                        log.notes!.isNotEmpty)
                                      log.notes!,
                                  ].join(' • '),
                                )
                              : null,
                          trailing: IconButton(
                            tooltip: 'Rimuovi',
                            icon: const Icon(Symbols.close_rounded, size: 18),
                            onPressed: () async {
                              await LocalDatabase.instance
                                  .deleteWateringLog(log);
                              await _reload();
                              await widget.onDataMutated();
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CatSafetyBanner extends StatelessWidget {
  final CatToxicity toxicity;
  final String? notes;

  const _CatSafetyBanner({required this.toxicity, this.notes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    final accent = switch (toxicity) {
      CatToxicity.safe => bot.healthy,
      CatToxicity.mild => bot.attention,
      CatToxicity.toxic => bot.critical,
      CatToxicity.unknown => cs.onSurfaceVariant,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusInner),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.pets_rounded, size: 20, color: accent, fill: 1),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Gatti: ${toxicity.label}',
                  style: tt.labelLarge?.copyWith(color: accent),
                ),
                if (notes != null && notes!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(notes!, style: tt.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? sub;

  const _InfoTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusInner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor, fill: 1),
              const SizedBox(width: 6),
              Text(
                label,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: tt.titleMedium),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthCheckCard extends StatelessWidget {
  final HealthCheckEntry entry;
  final String dateLabel;
  final Color statusColor;
  final VoidCallback onTapPhoto;
  final VoidCallback onDelete;

  const _HealthCheckCard({
    required this.entry,
    required this.dateLabel,
    required this.statusColor,
    required this.onTapPhoto,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;
    final hasFile =
        entry.photoPath.isNotEmpty && File(entry.photoPath).existsSync();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasFile)
                GestureDetector(
                  onTap: onTapPhoto,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusInner),
                    child: Image.file(
                      File(entry.photoPath),
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              if (hasFile) const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${entry.healthScore.toStringAsFixed(1)}/10 • ${entry.status.label}',
                            style: tt.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          entry.trend.label,
                          style: tt.labelSmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(entry.headline, style: tt.titleMedium),
                    Text(
                      dateLabel,
                      style:
                          tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.delete_outline_rounded, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
          if (entry.diagnosis.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(entry.diagnosis, style: tt.bodyMedium),
          ],
          if (entry.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: entry.issues
                  .map(
                    (i) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bot.attention.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        i,
                        style: tt.labelSmall?.copyWith(color: bot.attention),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (entry.careActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final action in entry.careActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✓ ', style: TextStyle(color: bot.healthy)),
                    Expanded(
                      child: Text(
                        action,
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
