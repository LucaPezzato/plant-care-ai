import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';
import '../models/plant_models.dart';
import '../services/ai_plant_service.dart';
import '../services/photo_storage_service.dart';
import '../services/secure_keys_service.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';

class HealthCheckSheet extends StatefulWidget {
  final Plant plant;
  final AppSettings settings;
  final HealthCheckEntry? previousCheck;
  final Future<void> Function(
    HealthCheckEntry entry, {
    int? updatedWateringDays,
  }) onSaved;

  const HealthCheckSheet({
    super.key,
    required this.plant,
    required this.settings,
    this.previousCheck,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required Plant plant,
    required AppSettings settings,
    required Future<void> Function(
      HealthCheckEntry entry, {
      int? updatedWateringDays,
    }) onSaved,
  }) async {
    final checks = await LocalDatabase.instance.getHealthChecksForPlant(
      plant.id,
      limit: 1,
    );
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HealthCheckSheet(
        plant: plant,
        settings: settings,
        previousCheck: checks.isNotEmpty ? checks.first : null,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<HealthCheckSheet> createState() => _HealthCheckSheetState();
}

class _HealthCheckSheetState extends State<HealthCheckSheet> {
  final _picker = ImagePicker();
  final _aiService = AiPlantService();
  final _keysService = SecureKeysService();
  final _notesCtrl = TextEditingController();

  Uint8List? _photoBytes;
  String? _savedPhotoPath;
  HealthCheckEntry? _result;
  bool _applySuggestedWatering = true;
  bool _analyzing = false;
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 84,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _savedPhotoPath = null;
        _result = null;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Errore acquisizione foto: $e');
    }
  }

  Future<void> _analyzeWithAi() async {
    if (_photoBytes == null) {
      setState(() => _errorText = 'Scatta o scegli prima una foto della pianta.');
      return;
    }

    setState(() {
      _analyzing = true;
      _errorText = null;
    });

    try {
      final creds =
          await _keysService.resolveActiveCredentials(widget.settings);
      if (creds == null) {
        throw Exception(
          'Nessuna API Key AI configurata. Vai in Impostazioni per configurare Gemini, OpenAI o un server OpenAI-compatibile.',
        );
      }

      _savedPhotoPath ??=
          await PhotoStorageService.instance.savePhotoBytes(_photoBytes!);

      Uint8List? prevPhotoBytes;
      if (widget.previousCheck != null) {
        prevPhotoBytes = await PhotoStorageService.instance
            .readPhotoBytes(widget.previousCheck!.photoPath);
      }

      final entry = await _aiService.analyzePlantHealth(
        credentials: creds,
        plant: widget.plant,
        savedPhotoPath: _savedPhotoPath!,
        currentPhotoBytes: _photoBytes!,
        previousCheck: widget.previousCheck,
        previousPhotoBytes: prevPhotoBytes,
        userNotes: _notesCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _result = entry;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _saveManualWithoutAi() async {
    if (_photoBytes == null) return;
    setState(() => _saving = true);
    try {
      final path = _savedPhotoPath ??
          await PhotoStorageService.instance.savePhotoBytes(_photoBytes!);
      final entry = HealthCheckEntry(
        id: const Uuid().v4(),
        plantId: widget.plant.id,
        checkedAt: DateTime.now(),
        photoPath: path,
        healthScore: widget.plant.lastHealthScore ?? 8.0,
        status: widget.plant.lastHealthStatus == HealthStatus.unknown
            ? HealthStatus.healthy
            : widget.plant.lastHealthStatus,
        headline: 'Foto periodica registrata',
        diagnosis: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : 'Controllo visivo salvato nel diario fotografico.',
        trend: widget.previousCheck == null
            ? HealthTrend.firstCheck
            : HealthTrend.stable,
        userNotes:
            _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      );
      await widget.onSaved(entry);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAiResult() async {
    final res = _result;
    if (res == null) return;
    setState(() => _saving = true);
    try {
      final suggested =
          _applySuggestedWatering ? res.suggestedWateringDays : null;
      await widget.onSaved(res, updatedWateringDays: suggested);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Check Salute AI', style: tt.headlineSmall),
            const SizedBox(height: 2),
            Text(
              widget.previousCheck != null
                  ? '${widget.plant.name} • Confronto automatico con la foto precedente'
                  : '${widget.plant.name} • Prima foto diagnostica',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),

            // Photo preview
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: Container(
                height: 210,
                color: cs.surfaceContainer,
                child: _photoBytes != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(_photoBytes!, fit: BoxFit.cover),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Row(
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () =>
                                      _pickPhoto(ImageSource.camera),
                                  icon: const Icon(Symbols.photo_camera_rounded),
                                ),
                                const SizedBox(width: 6),
                                IconButton.filledTonal(
                                  onPressed: () =>
                                      _pickPhoto(ImageSource.gallery),
                                  icon:
                                      const Icon(Symbols.photo_library_rounded),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Symbols.add_a_photo_rounded,
                            size: 40,
                            color: cs.primary,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: () => _pickPhoto(ImageSource.camera),
                                icon: const Icon(Symbols.photo_camera_rounded),
                                label: const Text('Fotocamera'),
                              ),
                              const SizedBox(width: 10),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _pickPhoto(ImageSource.gallery),
                                icon: const Icon(Symbols.photo_library_rounded),
                                label: const Text('Galleria'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note o sintomi osservati (opzionale)',
                hintText: 'es. Punte marroni sulle foglie basse, terreno umido...',
              ),
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bot.critical.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  _errorText!,
                  style: tt.bodyMedium?.copyWith(color: bot.critical),
                ),
              ),
            ],

            if (_result == null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed:
                    (_photoBytes == null || _analyzing) ? null : _analyzeWithAi,
                icon: _analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Symbols.auto_awesome_rounded),
                label: Text(
                  _analyzing
                      ? 'Analisi botanica AI in corso...'
                      : 'Analizza stato di salute con AI',
                ),
              ),
              if (_photoBytes != null && !_analyzing) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : _saveManualWithoutAi,
                  child: const Text('Salva foto nel diario senza AI'),
                ),
              ],
            ] else ...[
              const SizedBox(height: 16),
              _AiResultCard(
                entry: _result!,
                statusColor: _statusColor(_result!.status, bot, cs),
                currentWateringDays: widget.plant.wateringIntervalDays,
                applySuggestedWatering: _applySuggestedWatering,
                onToggleApplyWatering: (v) =>
                    setState(() => _applySuggestedWatering = v),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _saving ? null : _saveAiResult,
                icon: const Icon(Symbols.check_rounded),
                label: const Text('Salva nel Diario Salute'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiResultCard extends StatelessWidget {
  final HealthCheckEntry entry;
  final Color statusColor;
  final int currentWateringDays;
  final bool applySuggestedWatering;
  final ValueChanged<bool> onToggleApplyWatering;

  const _AiResultCard({
    required this.entry,
    required this.statusColor,
    required this.currentWateringDays,
    required this.applySuggestedWatering,
    required this.onToggleApplyWatering,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: statusColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${entry.healthScore.toStringAsFixed(1)}/10 • ${entry.status.label}',
                  style: tt.labelLarge?.copyWith(color: statusColor),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.trend.label,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.headline, style: tt.titleMedium),
          const SizedBox(height: 6),
          Text(entry.diagnosis, style: tt.bodyMedium),
          if (entry.issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Criticità rilevate',
              style: tt.labelLarge?.copyWith(color: bot.attention),
            ),
            const SizedBox(height: 4),
            for (final issue in entry.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: bot.attention)),
                    Expanded(child: Text(issue, style: tt.bodyMedium)),
                  ],
                ),
              ),
          ],
          if (entry.careActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Azioni consigliate',
              style: tt.labelLarge?.copyWith(color: bot.healthy),
            ),
            const SizedBox(height: 4),
            for (final action in entry.careActions)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✓ ', style: TextStyle(color: bot.healthy)),
                    Expanded(child: Text(action, style: tt.bodyMedium)),
                  ],
                ),
              ),
          ],
          if (entry.suggestedWateringDays != null &&
              entry.suggestedWateringDays != currentWateringDays) ...[
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Aggiorna annaffiatura a ogni ${entry.suggestedWateringDays} giorni',
                style: tt.labelLarge,
              ),
              subtitle: Text(
                'Attualmente impostata ogni $currentWateringDays giorni',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: applySuggestedWatering,
              onChanged: onToggleApplyWatering,
            ),
          ],
        ],
      ),
    );
  }
}
