import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../data/local_database.dart';
import '../models/plant_models.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';

class CalendarScreen extends StatefulWidget {
  final List<Plant> plants;
  final Future<void> Function(Plant plant) onWaterPlant;
  final void Function(Plant plant) onStartPhotoCheck;
  final void Function(Plant plant) onOpenPlant;

  const CalendarScreen({
    super.key,
    required this.plants,
    required this.onWaterPlant,
    required this.onStartPhotoCheck,
    required this.onOpenPlant,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDay = dateOnly(DateTime.now());
  List<WateringLog> _monthWaterLogs = [];
  List<HealthCheckEntry> _monthHealthChecks = [];

  static const _monthsIt = [
    'Gennaio',
    'Febbraio',
    'Marzo',
    'Aprile',
    'Maggio',
    'Giugno',
    'Luglio',
    'Agosto',
    'Settembre',
    'Ottobre',
    'Novembre',
    'Dicembre',
  ];

  static const _weekdaysIt = ['L', 'M', 'M', 'G', 'V', 'S', 'D'];

  @override
  void initState() {
    super.initState();
    _loadMonthHistory();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadMonthHistory();
  }

  Future<void> _loadMonthHistory() async {
    final start = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final end =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0, 23, 59, 59);
    final logs = await LocalDatabase.instance.getWateringLogsInRange(start, end);
    final checks =
        await LocalDatabase.instance.getHealthChecksInRange(start, end);
    if (!mounted) return;
    setState(() {
      _monthWaterLogs = logs;
      _monthHealthChecks = checks;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
    _loadMonthHistory();
  }

  Map<DateTime, ({bool hasWater, bool hasPhoto, bool hasDone})>
      _buildDayMarkers() {
    final start = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final end = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final today = dateOnly(DateTime.now());
    final markers = <DateTime, ({bool hasWater, bool hasPhoto, bool hasDone})>{};

    void mark(DateTime d, {bool water = false, bool photo = false, bool done = false}) {
      final key = dateOnly(d);
      final prev = markers[key] ?? (hasWater: false, hasPhoto: false, hasDone: false);
      markers[key] = (
        hasWater: prev.hasWater || water,
        hasPhoto: prev.hasPhoto || photo,
        hasDone: prev.hasDone || done,
      );
    }

    for (final plant in widget.plants) {
      if (plant.isWateringOverdue &&
          !today.isBefore(start) &&
          !today.isAfter(end)) {
        mark(today, water: true);
      }
      for (final d in plant.scheduledWateringDatesInRange(start, end)) {
        mark(d, water: true);
      }
      if (plant.isPhotoCheckDue &&
          !today.isBefore(start) &&
          !today.isAfter(end)) {
        mark(today, photo: true);
      }
      for (final d in plant.scheduledPhotoDatesInRange(start, end)) {
        mark(d, photo: true);
      }
    }

    for (final log in _monthWaterLogs) {
      mark(log.wateredAt, done: true);
    }
    for (final check in _monthHealthChecks) {
      mark(check.checkedAt, done: true);
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    final today = dateOnly(DateTime.now());
    final markers = _buildDayMarkers();

    final firstOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1; // Monday = 0
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    // Compute tasks for _selectedDay
    final plantsById = {for (final p in widget.plants) p.id: p};
    final scheduledWaterPlants = <Plant>[];
    final scheduledPhotoPlants = <Plant>[];
    for (final plant in widget.plants) {
      final isToday = _selectedDay == today;
      final waterDates =
          plant.scheduledWateringDatesInRange(_selectedDay, _selectedDay);
      if (waterDates.isNotEmpty || (isToday && plant.isWateringOverdue)) {
        scheduledWaterPlants.add(plant);
      }
      final photoDates =
          plant.scheduledPhotoDatesInRange(_selectedDay, _selectedDay);
      if (photoDates.isNotEmpty || (isToday && plant.isPhotoCheckDue)) {
        scheduledPhotoPlants.add(plant);
      }
    }

    final completedWaterings = _monthWaterLogs
        .where((l) => dateOnly(l.wateredAt) == _selectedDay)
        .toList();
    final completedChecks = _monthHealthChecks
        .where((c) => dateOnly(c.checkedAt) == _selectedDay)
        .toList();

    final overduePlants =
        widget.plants.where((p) => p.isWateringOverdue).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (overduePlants.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bot.critical.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              border: Border.all(color: bot.critical.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(Symbols.warning_rounded, color: bot.critical, fill: 1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${overduePlants.length} ${overduePlants.length == 1 ? "annaffiatura in ritardo" : "annaffiature in ritardo"}',
                        style: tt.titleMedium?.copyWith(color: bot.critical),
                      ),
                      Text(
                        overduePlants.map((p) => p.name).join(', '),
                        style: tt.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Calendar Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusHero),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => _changeMonth(-1),
                    icon: const Icon(Symbols.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_monthsIt[_focusedMonth.month - 1]} ${_focusedMonth.year}',
                        style: tt.titleLarge,
                      ),
                    ),
                  ),
                  if (_focusedMonth.year != today.year ||
                      _focusedMonth.month != today.month ||
                      _selectedDay != today)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _focusedMonth = DateTime(today.year, today.month);
                          _selectedDay = today;
                        });
                        _loadMonthHistory();
                      },
                      child: const Text('Oggi'),
                    ),
                  IconButton(
                    onPressed: () => _changeMonth(1),
                    icon: const Icon(Symbols.chevron_right_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: _weekdaysIt
                    .map(
                      (w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              for (int r = 0; r < rows; r++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: List.generate(7, (c) {
                      final cellIndex = r * 7 + c;
                      final dayNum = cellIndex - leadingBlanks + 1;
                      if (dayNum < 1 || dayNum > daysInMonth) {
                        return const Expanded(child: SizedBox(height: 44));
                      }
                      final cellDate = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month,
                        dayNum,
                      );
                      final isSelected = cellDate == _selectedDay;
                      final isToday = cellDate == today;
                      final m = markers[cellDate];

                      return Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => setState(() => _selectedDay = cellDate),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? cs.primaryContainer
                                  : (isToday
                                      ? cs.surfaceContainerHigh
                                      : Colors.transparent),
                              borderRadius: BorderRadius.circular(12),
                              border: isToday && !isSelected
                                  ? Border.all(
                                      color: cs.primary.withValues(alpha: 0.6),
                                    )
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$dayNum',
                                  style: tt.labelMedium?.copyWith(
                                    color: isSelected
                                        ? cs.onPrimaryContainer
                                        : cs.onSurface,
                                    fontWeight: isSelected || isToday
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (m?.hasWater == true)
                                      _Dot(color: bot.water),
                                    if (m?.hasPhoto == true)
                                      _Dot(color: bot.photo),
                                    if (m?.hasDone == true)
                                      _Dot(color: bot.healthy),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              const SizedBox(height: 10),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendItem(color: bot.water, label: 'Annaffiatura'),
                  const SizedBox(width: 14),
                  _LegendItem(color: bot.photo, label: 'Foto check'),
                  const SizedBox(width: 14),
                  _LegendItem(color: bot.healthy, label: 'Completato'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),
        Text(
          _selectedDay == today
              ? 'Programma di Oggi'
              : 'Programma del ${_selectedDay.day} ${_monthsIt[_selectedDay.month - 1]}',
          style: tt.titleLarge,
        ),
        const SizedBox(height: 10),

        if (scheduledWaterPlants.isEmpty &&
            scheduledPhotoPlants.isEmpty &&
            completedWaterings.isEmpty &&
            completedChecks.isEmpty)
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: Row(
              children: [
                Icon(Symbols.event_available_rounded, color: cs.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Nessuna attività prevista o registrata per questa data.',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),

        for (final plant in scheduledWaterPlants) ...[
          _TaskCard(
            icon: Symbols.water_drop_rounded,
            accent: plant.isWateringOverdue ? bot.critical : bot.water,
            title: 'Annaffia ${plant.name}',
            subtitle: plant.isWateringOverdue
                ? '${plant.wateringStatusLabel} • ${plant.location}'
                : 'Ogni ${plant.wateringIntervalDays} giorni • ${plant.location}',
            actionLabel: 'Annaffia',
            onTap: () => widget.onOpenPlant(plant),
            onAction: () async {
              await widget.onWaterPlant(plant);
              await _loadMonthHistory();
            },
          ),
          const SizedBox(height: 8),
        ],

        for (final plant in scheduledPhotoPlants) ...[
          _TaskCard(
            icon: Symbols.photo_camera_rounded,
            accent: bot.photo,
            title: 'Foto Check Salute: ${plant.name}',
            subtitle:
                'Ogni ${plant.photoCheckIntervalDays} giorni • Confronto AI stato di salute',
            actionLabel: 'Scatta',
            onTap: () => widget.onOpenPlant(plant),
            onAction: () => widget.onStartPhotoCheck(plant),
          ),
          const SizedBox(height: 8),
        ],

        for (final log in completedWaterings) ...[
          _CompletedRow(
            icon: Symbols.check_circle_rounded,
            accent: bot.healthy,
            title:
                'Annaffiata: ${plantsById[log.plantId]?.name ?? "Pianta"}',
            subtitle:
                'Alle ${log.wateredAt.hour.toString().padLeft(2, '0')}:${log.wateredAt.minute.toString().padLeft(2, '0')}',
          ),
          const SizedBox(height: 6),
        ],

        for (final check in completedChecks) ...[
          _CompletedRow(
            icon: Symbols.verified_rounded,
            accent: bot.photo,
            title:
                'Check Salute: ${plantsById[check.plantId]?.name ?? "Pianta"} (${check.healthScore.toStringAsFixed(1)}/10)',
            subtitle: check.headline,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _TaskCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, fill: 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor: accent.withValues(alpha: 0.2),
                  foregroundColor: accent,
                ),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedRow extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _CompletedRow({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent, fill: 1),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.labelLarge),
                Text(
                  subtitle,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
