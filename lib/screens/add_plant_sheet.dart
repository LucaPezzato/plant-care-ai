import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:uuid/uuid.dart';
import '../models/plant_models.dart';
import '../services/ai_plant_service.dart';
import '../services/photo_storage_service.dart';
import '../services/secure_keys_service.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';

class AddPlantSheet extends StatefulWidget {
  final AppSettings settings;
  final Plant? existingPlant;
  final bool openCameraOnStart;
  final Future<void> Function(Plant plant) onSave;

  const AddPlantSheet({
    super.key,
    required this.settings,
    this.existingPlant,
    this.openCameraOnStart = false,
    required this.onSave,
  });

  @override
  State<AddPlantSheet> createState() => _AddPlantSheetState();
}

class _AddPlantSheetState extends State<AddPlantSheet> {
  final _picker = ImagePicker();
  final _aiService = AiPlantService();
  final _keysService = SecureKeysService();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _speciesCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _catNotesCtrl;

  late LightLevel _lightLevel;
  late CatToxicity _catToxicity;
  late int _wateringDays;
  late int _photoDays;

  Uint8List? _pickedPhotoBytes;
  String? _existingPhotoPath;
  double? _aiInitialScore;
  HealthStatus _aiInitialStatus = HealthStatus.unknown;
  bool _analyzing = false;
  bool _saving = false;
  String? _errorText;

  static const _quickLocations = [
    'Salotto',
    'Balcone',
    'Cucina',
    'Camera',
    'Studio',
    'Giardino',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingPlant;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _speciesCtrl = TextEditingController(text: p?.species ?? '');
    _locationCtrl = TextEditingController(text: p?.location ?? 'Salotto');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
    _catNotesCtrl = TextEditingController(text: p?.catToxicityNotes ?? '');
    _lightLevel = p?.lightLevel ?? LightLevel.indirect;
    _catToxicity = p?.catToxicity ?? CatToxicity.unknown;
    _wateringDays = p?.wateringIntervalDays ?? 7;
    _photoDays = p?.photoCheckIntervalDays ?? 14;
    _existingPhotoPath = p?.coverPhotoPath;
    _aiInitialScore = p?.lastHealthScore;
    _aiInitialStatus = p?.lastHealthStatus ?? HealthStatus.unknown;

    if (widget.openCameraOnStart && p == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pickPhoto(ImageSource.camera);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _speciesCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    _catNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 82,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedPhotoBytes = bytes;
        _errorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Impossibile acquisire la foto: $e');
    }
  }

  Future<void> _identifyWithAi() async {
    if (_pickedPhotoBytes == null &&
        _nameCtrl.text.trim().isEmpty &&
        _speciesCtrl.text.trim().isEmpty) {
      setState(() {
        _errorText = 'Scatta una foto o scrivi almeno il nome della pianta.';
      });
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
          'Nessuna API Key AI configurata. Vai in Impostazioni per aggiungere Gemini, OpenAI o un endpoint OpenAI-compatibile.',
        );
      }

      final descParts = [
        if (_nameCtrl.text.trim().isNotEmpty) 'Nome: ${_nameCtrl.text.trim()}',
        if (_speciesCtrl.text.trim().isNotEmpty)
          'Specie: ${_speciesCtrl.text.trim()}',
        if (_notesCtrl.text.trim().isNotEmpty)
          'Note: ${_notesCtrl.text.trim()}',
      ].join('. ');

      final res = await _aiService.identifyPlant(
        credentials: creds,
        userDescription: descParts.isNotEmpty ? descParts : null,
        imageBytes: _pickedPhotoBytes,
      );

      if (!mounted) return;
      setState(() {
        if (_nameCtrl.text.trim().isEmpty) {
          _nameCtrl.text = res.commonName;
        }
        if (res.scientificName.isNotEmpty) {
          _speciesCtrl.text = res.scientificName;
        }
        _lightLevel = res.lightLevel;
        _wateringDays = res.wateringIntervalDays;
        _photoDays = res.photoCheckIntervalDays;
        if (res.careSummary.isNotEmpty) {
          _notesCtrl.text = res.careSummary;
        }
        if (res.initialHealthScore != null) {
          _aiInitialScore = res.initialHealthScore;
          _aiInitialStatus = res.initialHealthStatus;
        }
        _catToxicity = res.catToxicity;
        if (res.catToxicityNotes != null && res.catToxicityNotes!.isNotEmpty) {
          _catNotesCtrl.text = res.catToxicityNotes!;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Inserisci un nome per la pianta.');
      return;
    }

    setState(() => _saving = true);
    try {
      String? photoPath = _existingPhotoPath;
      if (_pickedPhotoBytes != null) {
        photoPath =
            await PhotoStorageService.instance.savePhotoBytes(_pickedPhotoBytes!);
      }

      final existing = widget.existingPlant;
      final plant = Plant(
        id: existing?.id ?? const Uuid().v4(),
        name: name,
        species: _speciesCtrl.text.trim(),
        location: _locationCtrl.text.trim().isEmpty
            ? 'Casa'
            : _locationCtrl.text.trim(),
        lightLevel: _lightLevel,
        wateringIntervalDays: _wateringDays,
        photoCheckIntervalDays: _photoDays,
        lastWateredAt: existing?.lastWateredAt,
        lastPhotoCheckAt: existing?.lastPhotoCheckAt,
        coverPhotoPath: photoPath,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        lastHealthScore: _aiInitialScore ?? existing?.lastHealthScore,
        lastHealthStatus: _aiInitialStatus != HealthStatus.unknown
            ? _aiInitialStatus
            : (existing?.lastHealthStatus ?? HealthStatus.unknown),
        catToxicity: _catToxicity,
        catToxicityNotes: _catNotesCtrl.text.trim().isEmpty
            ? null
            : _catNotesCtrl.text.trim(),
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await widget.onSave(plant);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
            Text(
              widget.existingPlant == null
                  ? 'Nuova Pianta'
                  : 'Modifica Pianta',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 14),

            // Photo + AI identify card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusInner),
                        child: SizedBox(
                          width: 78,
                          height: 78,
                          child: _pickedPhotoBytes != null
                              ? Image.memory(
                                  _pickedPhotoBytes!,
                                  fit: BoxFit.cover,
                                )
                              : (_existingPhotoPath != null &&
                                      File(_existingPhotoPath!).existsSync()
                                  ? Image.file(
                                      File(_existingPhotoPath!),
                                      fit: BoxFit.cover,
                                    )
                                  : Container(
                                      color: cs.primaryContainer
                                          .withValues(alpha: 0.4),
                                      child: Icon(
                                        Symbols.add_a_photo_rounded,
                                        color: cs.primary,
                                        size: 30,
                                      ),
                                    )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickPhoto(ImageSource.camera),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Symbols.photo_camera_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Foto'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _pickPhoto(ImageSource.gallery),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    icon: const Icon(
                                      Symbols.photo_library_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Galleria'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonalIcon(
                              onPressed: _analyzing ? null : _identifyWithAi,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                              ),
                              icon: _analyzing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Symbols.auto_awesome_rounded,
                                      size: 18,
                                    ),
                              label: Text(
                                _analyzing
                                    ? 'Analisi AI in corso...'
                                    : 'Riconosci & compila con AI',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
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

            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome pianta *',
                hintText: 'es. Monstera del salotto',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _speciesCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Specie (opzionale)',
                hintText: 'es. Monstera deliciosa',
              ),
            ),
            const SizedBox(height: 12),

            // Location quick chips + custom
            Text('Posizione', style: tt.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickLocations.map((loc) {
                final selected = _locationCtrl.text.trim() == loc;
                return ChoiceChip(
                  label: Text(loc),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _locationCtrl.text = loc),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Stanza / posizione personalizzata',
              ),
            ),

            const SizedBox(height: 14),
            Text('Esposizione luce', style: tt.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<LightLevel>(
              segments: const [
                ButtonSegment(
                  value: LightLevel.low,
                  label: Text('Ombra'),
                  icon: Icon(Symbols.cloud_rounded, size: 18),
                ),
                ButtonSegment(
                  value: LightLevel.indirect,
                  label: Text('Indiretta'),
                  icon: Icon(Symbols.partly_cloudy_day_rounded, size: 18),
                ),
                ButtonSegment(
                  value: LightLevel.brightDirect,
                  label: Text('Sole'),
                  icon: Icon(Symbols.wb_sunny_rounded, size: 18),
                ),
              ],
              selected: {_lightLevel},
              onSelectionChanged: (s) => setState(() => _lightLevel = s.first),
            ),

            const SizedBox(height: 14),
            Text('Sicurezza per gatti 🐱', style: tt.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<CatToxicity>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CatToxicity.safe, label: Text('Sicura')),
                ButtonSegment(value: CatToxicity.mild, label: Text('Irritante')),
                ButtonSegment(value: CatToxicity.toxic, label: Text('Tossica')),
                ButtonSegment(value: CatToxicity.unknown, label: Text('N/D')),
              ],
              selected: {_catToxicity},
              onSelectionChanged: (s) => setState(() => _catToxicity = s.first),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _catNotesCtrl,
              minLines: 1,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Dettagli tossicità gatti (compilato da AI)',
                hintText: 'es. Contiene ossalati di calcio, tenere in alto',
              ),
            ),

            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Annaffiatura', style: tt.labelLarge),
                Text(
                  'Ogni $_wateringDays ${_wateringDays == 1 ? "giorno" : "giorni"}',
                  style: tt.labelLarge?.copyWith(color: bot.water),
                ),
              ],
            ),
            Slider(
              value: _wateringDays.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              activeColor: bot.water,
              onChanged: (v) => setState(() => _wateringDays = v.round()),
            ),

            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Promemoria foto salute', style: tt.labelLarge),
                Text(
                  'Ogni $_photoDays giorni',
                  style: tt.labelLarge?.copyWith(color: bot.photo),
                ),
              ],
            ),
            Slider(
              value: _photoDays.toDouble(),
              min: 3,
              max: 45,
              divisions: 42,
              activeColor: bot.photo,
              onChanged: (v) => setState(() => _photoDays = v.round()),
            ),

            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note di cura',
                hintText: 'Terriccio drenante, nebulizzare foglie...',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Symbols.check_rounded),
              label: Text(
                widget.existingPlant == null ? 'Salva pianta' : 'Aggiorna pianta',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
