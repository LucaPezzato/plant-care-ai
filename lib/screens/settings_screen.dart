import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/plant_models.dart';
import '../services/ai_plant_service.dart';
import '../services/app_update_service.dart';
import '../services/firebase_backup_service.dart';
import '../services/plant_reminder_service.dart';
import '../services/secure_keys_service.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final GardenStats stats;
  final FirebaseBackupService firebaseService;
  final VoidCallback onOpenFamilyGarden;
  final Future<void> Function(AppSettings updated) onSettingsChanged;
  final Future<void> Function() onDatabaseRestored;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.stats,
    required this.firebaseService,
    required this.onOpenFamilyGarden,
    required this.onSettingsChanged,
    required this.onDatabaseRestored,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keysService = SecureKeysService();
  final _aiService = AiPlantService();

  late AppSettings _settings = widget.settings;
  final _apiKeyCtrl = TextEditingController();
  late final TextEditingController _modelCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _customModelCtrl;

  bool _obscureKey = true;
  bool _hasSavedKey = false;
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _loadingLiveModels = false;
  DateTime? _lastCloudBackupAt;
  List<String> _geminiModels = [
    'gemini-3-flash-preview',
    'gemini-3.1-pro',
    'gemini-3-pro-preview',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.5-flash-lite',
  ];

  List<String> _openaiModels = [
    'gpt-4.1-mini',
    'gpt-4.1',
    'gpt-4o-mini',
    'gpt-4o',
  ];

  List<String> _compatLiveModels = [];

  static const _compatPresets = <({String label, String url, String model})>[
    (
      label: 'OpenRouter',
      url: 'https://openrouter.ai/api/v1',
      model: 'google/gemini-2.5-flash',
    ),
    (
      label: 'Groq',
      url: 'https://api.groq.com/openai/v1',
      model: 'meta-llama/llama-4-scout-17b-16e-instruct',
    ),
    (
      label: 'Ollama',
      url: 'http://192.168.1.10:11434/v1',
      model: 'llava',
    ),
    (
      label: 'LM Studio',
      url: 'http://192.168.1.10:1234/v1',
      model: 'local-model',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _modelCtrl = TextEditingController(text: _settings.preferredAiModel);
    _baseUrlCtrl = TextEditingController(text: _settings.customBaseUrl);
    _customModelCtrl = TextEditingController(text: _settings.customModelName);
    _lastCloudBackupAt = _settings.lastCloudBackupAt;
    _loadKeyForCurrentProvider();
    _refreshCloudBackupDate();
  }

  Future<void> _refreshCloudBackupDate() async {
    final dt = await widget.firebaseService.getLatestBackupDate();
    if (dt != null && mounted) {
      setState(() => _lastCloudBackupAt = dt);
    }
  }

  Future<void> _handleFirebaseGoogleSignIn() async {
    try {
      final user = await widget.firebaseService.signInWithGoogle();
      if (!mounted) return;
      setState(() {});
      if (user != null) {
        await _refreshCloudBackupDate();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connesso a Firebase come ${user.email}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _handleFirebaseAnonSignIn() async {
    try {
      final user = await widget.firebaseService.signInAnonymously();
      if (!mounted) return;
      setState(() {});
      if (user != null) {
        await _refreshCloudBackupDate();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accesso anonimo Firebase attivato!')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _handleFirebaseBackupNow() async {
    setState(() => _isBackingUp = true);
    try {
      final ok = await widget.firebaseService.uploadBackup();
      if (!mounted) return;
      if (ok) {
        final now = DateTime.now();
        setState(() => _lastCloudBackupAt = now);
        await _updateSettings(_settings.copyWith(lastCloudBackupAt: now));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup su Firebase completato! ☁️')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossibile eseguire il backup: verifica connessione e accesso Firebase.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _handleFirebaseRestore() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristina da Firebase'),
        content: const Text(
          'Tutti i dati locali (piante, calendario e diario) verranno sostituiti con l\'ultimo backup salvato su Firestore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ripristina'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isRestoring = true);
    try {
      final ok = await widget.firebaseService.restoreBackup();
      if (!mounted) return;
      if (ok) {
        await widget.onDatabaseRestored();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database ripristinato da Firebase!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nessun backup trovato su Firebase per questo account.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _settings = widget.settings;
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _modelCtrl.dispose();
    _baseUrlCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKeyForCurrentProvider() async {
    final key = await _keysService.getApiKey(_settings.preferredAiProvider);
    if (!mounted) return;
    setState(() {
      _hasSavedKey = key != null && key.isNotEmpty;
      _apiKeyCtrl.text = key ?? '';
    });
    // Automatically refresh live models in the background when credentials exist
    if ((key != null && key.isNotEmpty) ||
        (_settings.preferredAiProvider == AiProviderType.openaiCompatible &&
            _baseUrlCtrl.text.trim().isNotEmpty)) {
      _refreshLiveModels(silent: true);
    }
  }

  Future<void> _refreshLiveModels({bool silent = false}) async {
    final provider = _settings.preferredAiProvider;
    final key = _apiKeyCtrl.text.trim();
    if (provider != AiProviderType.openaiCompatible && key.isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Inserisci prima la tua API Key ${provider.shortLabel} per scaricare l\'elenco live dei modelli.',
            ),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _loadingLiveModels = true);
    try {
      final live = await _aiService.fetchAvailableModels(
        provider: provider,
        apiKey: key,
        customBaseUrl: _baseUrlCtrl.text.trim(),
      );
      if (!mounted) return;
      if (live.isNotEmpty) {
        setState(() {
          switch (provider) {
            case AiProviderType.gemini:
              _geminiModels = live;
            case AiProviderType.openai:
              _openaiModels = live;
            case AiProviderType.openaiCompatible:
              _compatLiveModels = live;
          }
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Caricati ${live.length} modelli live da ${provider.shortLabel}!',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingLiveModels = false);
    }
  }

  Future<void> _openAllModelsPicker(
    List<String> models,
    TextEditingController targetCtrl,
  ) async {
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filtered = query.isEmpty
              ? models
              : models
                  .where((m) => m.toLowerCase().contains(query.toLowerCase()))
                  .toList();
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.92,
            builder: (_, scrollCtrl) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  Text(
                    'Modelli Live (${models.length})',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Symbols.search_rounded),
                      hintText: 'Cerca modello (es. flash, pro, gpt-4.1...)',
                    ),
                    onChanged: (v) => setSheetState(() => query = v),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final id = filtered[i];
                        final selected = targetCtrl.text.trim() == id;
                        return ListTile(
                          dense: true,
                          title: Text(id),
                          trailing: selected
                              ? Icon(
                                  Symbols.check_circle_rounded,
                                  color: Theme.of(ctx).colorScheme.primary,
                                )
                              : null,
                          onTap: () {
                            setState(() => targetCtrl.text = id);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _updateSettings(AppSettings next) async {
    setState(() => _settings = next);
    await widget.onSettingsChanged(next);
  }

  Future<void> _switchProvider(AiProviderType provider) async {
    String nextModel = _settings.preferredAiModel;
    if (provider == AiProviderType.gemini &&
        !nextModel.startsWith('gemini')) {
      nextModel = 'gemini-3-flash-preview';
    } else if (provider == AiProviderType.openai &&
        nextModel.startsWith('gemini')) {
      nextModel = 'gpt-4.1-mini';
    }
    _modelCtrl.text = nextModel;
    await _updateSettings(
      _settings.copyWith(
        preferredAiProvider: provider,
        preferredAiModel: nextModel,
      ),
    );
    await _loadKeyForCurrentProvider();
  }

  Future<void> _saveAiConfig() async {
    final rawKey = _apiKeyCtrl.text.trim();
    if (rawKey.isNotEmpty) {
      await _keysService.saveApiKey(_settings.preferredAiProvider, rawKey);
    } else if (_settings.preferredAiProvider ==
        AiProviderType.openaiCompatible) {
      await _keysService.deleteApiKey(AiProviderType.openaiCompatible);
    }

    await _updateSettings(
      _settings.copyWith(
        preferredAiModel: _modelCtrl.text.trim().isNotEmpty
            ? _modelCtrl.text.trim()
            : _settings.preferredAiModel,
        customBaseUrl: _baseUrlCtrl.text.trim(),
        customModelName: _customModelCtrl.text.trim(),
      ),
    );

    await _loadKeyForCurrentProvider();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Configurazione ${_settings.preferredAiProvider.label} salvata!',
        ),
      ),
    );
  }

  Future<void> _deleteCurrentKey() async {
    await _keysService.deleteApiKey(_settings.preferredAiProvider);
    await _loadKeyForCurrentProvider();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key rimossa.')),
    );
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _settings.reminderHour,
        minute: _settings.reminderMinute,
      ),
    );
    if (picked == null) return;
    await _updateSettings(
      _settings.copyWith(
        reminderHour: picked.hour,
        reminderMinute: picked.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;

    final isCompat =
        _settings.preferredAiProvider == AiProviderType.openaiCompatible;
    final modelPresets = _settings.preferredAiProvider == AiProviderType.gemini
        ? _geminiModels
        : _openaiModels;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // Garden Stats Summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatColumn(
                value: '${widget.stats.totalPlants}',
                label: 'Piante',
                color: cs.primary,
              ),
              _StatColumn(
                value: '${widget.stats.wateringsThisMonth}',
                label: 'Acqua / mese',
                color: bot.water,
              ),
              _StatColumn(
                value: '${widget.stats.totalHealthChecks}',
                label: 'Foto Check',
                color: bot.photo,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // AI Provider Configuration
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.auto_awesome_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Motore AI Vision', style: tt.titleLarge),
                  ),
                  if (_hasSavedKey)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: bot.healthy.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Chiave attiva',
                        style: tt.labelSmall?.copyWith(color: bot.healthy),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Scegli tra Google Gemini, OpenAI (ChatGPT) o qualsiasi server compatibile OpenAI (OpenRouter, Groq, Ollama, LM Studio).',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SegmentedButton<AiProviderType>(
                segments: const [
                  ButtonSegment(
                    value: AiProviderType.gemini,
                    label: Text('Gemini'),
                  ),
                  ButtonSegment(
                    value: AiProviderType.openai,
                    label: Text('OpenAI'),
                  ),
                  ButtonSegment(
                    value: AiProviderType.openaiCompatible,
                    label: Text('Custom'),
                  ),
                ],
                selected: {_settings.preferredAiProvider},
                onSelectionChanged: (s) => _switchProvider(s.first),
              ),
              const SizedBox(height: 14),

              if (!isCompat) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...modelPresets.take(6).map((m) {
                      return ChoiceChip(
                        label: Text(m),
                        selected: _modelCtrl.text.trim() == m,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _modelCtrl.text = m),
                      );
                    }),
                    ActionChip(
                      avatar: _loadingLiveModels
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Symbols.refresh_rounded, size: 16),
                      label: const Text('Aggiorna live'),
                      onPressed: _loadingLiveModels
                          ? null
                          : () => _refreshLiveModels(),
                    ),
                    if (modelPresets.length > 6)
                      ActionChip(
                        avatar: const Icon(Symbols.search_rounded, size: 16),
                        label: Text('Tutti (${modelPresets.length})'),
                        onPressed: () =>
                            _openAllModelsPicker(modelPresets, _modelCtrl),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _modelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Modello AI',
                  ),
                ),
              ] else ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._compatPresets.map((preset) {
                      return ActionChip(
                        label: Text(preset.label),
                        onPressed: () {
                          setState(() {
                            _baseUrlCtrl.text = preset.url;
                            _customModelCtrl.text = preset.model;
                          });
                        },
                      );
                    }),
                    ActionChip(
                      avatar: _loadingLiveModels
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Symbols.refresh_rounded, size: 16),
                      label: const Text('Lista live /models'),
                      onPressed: _loadingLiveModels
                          ? null
                          : () => _refreshLiveModels(),
                    ),
                    if (_compatLiveModels.isNotEmpty)
                      ActionChip(
                        avatar: const Icon(Symbols.search_rounded, size: 16),
                        label: Text('Scegli (${_compatLiveModels.length})'),
                        onPressed: () => _openAllModelsPicker(
                          _compatLiveModels,
                          _customModelCtrl,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _baseUrlCtrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Base URL OpenAI-compatibile',
                    hintText: 'https://openrouter.ai/api/v1',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _customModelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Model ID (con supporto Vision)',
                    hintText: 'google/gemini-2.5-flash',
                  ),
                ),
              ],

              const SizedBox(height: 10),
              TextField(
                controller: _apiKeyCtrl,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: isCompat
                      ? 'API Key (opzionale per server locali)'
                      : 'API Key ${_settings.preferredAiProvider.shortLabel}',
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                    icon: Icon(
                      _obscureKey
                          ? Symbols.visibility_rounded
                          : Symbols.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saveAiConfig,
                      icon: const Icon(Symbols.save_rounded, size: 18),
                      label: const Text('Salva configurazione AI'),
                    ),
                  ),
                  if (_hasSavedKey) ...[
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Elimina chiave',
                      onPressed: _deleteCurrentKey,
                      icon: const Icon(Symbols.delete_outline_rounded),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // Notifications & Reminders
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.notifications_active_rounded, color: bot.water),
                  const SizedBox(width: 8),
                  Text('Promemoria & Calendario', style: tt.titleLarge),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promemoria annaffiatura'),
                subtitle: const Text(
                  'Notifica nei giorni in cui almeno una pianta ha bisogno d\'acqua',
                ),
                value: _settings.wateringReminderEnabled,
                onChanged: (v) async {
                  if (v) {
                    await PlantReminderService.instance.requestPermission();
                  }
                  await _updateSettings(
                    _settings.copyWith(wateringReminderEnabled: v),
                  );
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Promemoria foto periodiche'),
                subtitle: const Text(
                  'Ricordami di scattare le foto di controllo salute AI',
                ),
                value: _settings.photoReminderEnabled,
                onChanged: (v) async {
                  if (v) {
                    await PlantReminderService.instance.requestPermission();
                  }
                  await _updateSettings(
                    _settings.copyWith(photoReminderEnabled: v),
                  );
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Symbols.schedule_rounded),
                title: const Text('Orario promemoria'),
                trailing: FilledButton.tonal(
                  onPressed: _pickReminderTime,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 38),
                  ),
                  child: Text(_settings.formattedReminderTime),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () async {
                  await PlantReminderService.instance.requestPermission();
                  await PlantReminderService.instance.sendTestNotification();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Notifica di test inviata!'),
                    ),
                  );
                },
                icon: const Icon(Symbols.notifications_rounded, size: 18),
                label: const Text('Invia notifica di test'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // Shared Family Garden
        _buildFamilyGardenCard(cs, tt, bot),

        const SizedBox(height: 16),
        // Firebase Cloud Backup
        _buildFirebaseCard(cs, tt, bot),

        const SizedBox(height: 16),
        // Appearance
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.palette_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Aspetto Material You', style: tt.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Scuro')),
                  ButtonSegment(value: 1, label: Text('Chiaro')),
                  ButtonSegment(value: 2, label: Text('Sistema')),
                ],
                selected: {_settings.themeModeIndex},
                onSelectionChanged: (s) => _updateSettings(
                  _settings.copyWith(themeModeIndex: s.first),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // App Updates (GitHub Releases)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Symbols.system_update_rounded, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Aggiornamenti App', style: tt.titleLarge),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Controlla automaticamente nuove release su GitHub e installa l\'APK direttamente dall\'app.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => AppUpdateService.plantCare
                    .checkAndPrompt(context, silent: false),
                icon: const Icon(Symbols.refresh_rounded, size: 18),
                label: const Text('Controlla aggiornamenti'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFamilyGardenCard(
    ColorScheme cs,
    TextTheme tt,
    BotanicalColors bot,
  ) {
    final active = _settings.hasSharedGarden;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Symbols.diversity_3_rounded,
                color: active ? bot.healthy : cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Giardino Condiviso (Famiglia)', style: tt.titleLarge),
              ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bot.healthy.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _settings.activeGardenInviteCode ?? 'Attivo',
                    style: tt.labelSmall?.copyWith(color: bot.healthy),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            active
                ? 'Connesso a "${_settings.activeGardenName}". Le annaffiature e le piante si sincronizzano tra i familiari.'
                : 'Crea un giardino condiviso con codice invito (es. K7P-4M2) per gestire le piante insieme a partner o familiari.',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: widget.onOpenFamilyGarden,
            icon: Icon(
              active ? Symbols.group_rounded : Symbols.group_add_rounded,
              size: 18,
            ),
            label: Text(
              active
                  ? 'Gestisci familiari & codice invito'
                  : 'Condividi o unisciti a un giardino',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirebaseCard(ColorScheme cs, TextTheme tt, BotanicalColors bot) {
    final user = widget.firebaseService.currentUser;
    final initialized = widget.firebaseService.isInitialized;
    final dateFmt = DateFormat('dd/MM/yyyy • HH:mm');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                user != null
                    ? Symbols.cloud_done_rounded
                    : Symbols.cloud_upload_rounded,
                color: user != null ? bot.healthy : cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Backup Cloud Firebase', style: tt.titleLarge),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (user != null ? bot.healthy : cs.surfaceContainerHigh)
                      .withValues(alpha: user != null ? 0.16 : 1.0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  user != null
                      ? 'Connesso'
                      : (initialized ? 'Pronto' : 'Offline'),
                  style: tt.labelSmall?.copyWith(
                    color: user != null ? bot.healthy : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            user != null
                ? 'Account: ${user.email ?? "Utente Anonimo Firebase"}'
                : (initialized
                    ? 'Sincronizza automaticamente il database SQLite compresso su Cloud Firestore (0 €/mese).'
                    : 'Aggiungi android/app/google-services.json per attivare il backup cloud su Firebase Firestore.'),
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (_lastCloudBackupAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Ultimo backup: ${dateFmt.format(_lastCloudBackupAt!)}',
              style: tt.labelSmall?.copyWith(color: bot.healthy),
            ),
          ],
          const SizedBox(height: 12),
          if (user == null) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _handleFirebaseGoogleSignIn,
                    icon: const Icon(Symbols.account_circle_rounded, size: 18),
                    label: const Text('Accedi Google'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _handleFirebaseAnonSignIn,
                    icon: const Icon(Symbols.key_rounded, size: 18),
                    label: const Text('Anonimo 1-Tap'),
                  ),
                ),
              ],
            ),
          ] else ...[
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-backup automatico'),
              subtitle: const Text('Salva su Firestore 15s dopo ogni modifica'),
              value: _settings.autoBackupEnabled,
              onChanged: (v) =>
                  _updateSettings(_settings.copyWith(autoBackupEnabled: v)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isBackingUp ? null : _handleFirebaseBackupNow,
                    icon: _isBackingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.cloud_upload_rounded, size: 18),
                    label: const Text('Backup ora'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isRestoring ? null : _handleFirebaseRestore,
                    icon: _isRestoring
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Symbols.cloud_download_rounded, size: 18),
                    label: const Text('Ripristina'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () async {
                await widget.firebaseService.signOut();
                if (mounted) setState(() {});
              },
              child: const Text('Disconnetti Firebase'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _StatColumn({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value, style: tt.headlineSmall?.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(label, style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
