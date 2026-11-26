import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/plant_models.dart';
import '../services/shared_garden_service.dart';
import '../theme/app_theme.dart';
import '../theme/botanical_colors.dart';

class FamilyGardenSheet extends StatefulWidget {
  final AppSettings settings;
  final List<Plant> localPlants;
  final SharedGardenService sharedGardenService;
  final Future<void> Function(AppSettings updated) onSettingsUpdated;
  final Future<void> Function() onSynced;

  const FamilyGardenSheet({
    super.key,
    required this.settings,
    required this.localPlants,
    required this.sharedGardenService,
    required this.onSettingsUpdated,
    required this.onSynced,
  });

  @override
  State<FamilyGardenSheet> createState() => _FamilyGardenSheetState();
}

class _FamilyGardenSheetState extends State<FamilyGardenSheet> {
  final _nameCtrl = TextEditingController(text: 'Giardino di Famiglia');
  final _codeCtrl = TextEditingController();

  SharedGarden? _garden;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.settings.hasSharedGarden) {
      _loadGardenInfo();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGardenInfo() async {
    final id = widget.settings.activeGardenId;
    if (id == null) return;
    final info = await widget.sharedGardenService.fetchGardenInfo(id);
    if (mounted) {
      setState(() => _garden = info);
    }
  }

  Future<void> _createGarden() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await widget.sharedGardenService.createSharedGarden(
        name: _nameCtrl.text.trim(),
        localPlants: widget.localPlants,
      );
      await widget.onSettingsUpdated(
        widget.settings.copyWith(
          activeGardenId: created.id,
          activeGardenName: created.name,
          activeGardenInviteCode: created.inviteCode,
        ),
      );
      if (!mounted) return;
      setState(() => _garden = created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Giardino "${created.name}" creato! Codice invito: ${created.inviteCode}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinGarden() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final joined =
          await widget.sharedGardenService.joinGardenByCode(_codeCtrl.text);
      await widget.onSettingsUpdated(
        widget.settings.copyWith(
          activeGardenId: joined.id,
          activeGardenName: joined.name,
          activeGardenInviteCode: joined.inviteCode,
        ),
      );
      await widget.onSynced();
      if (!mounted) return;
      setState(() => _garden = joined);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unito al giardino "${joined.name}"! Piante sincronizzate 🌿'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    final id = widget.settings.activeGardenId;
    if (id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final count = await widget.sharedGardenService.syncFromCloud(id);
      await _loadGardenInfo();
      await widget.onSynced();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sincronizzate $count piante dal giardino condiviso!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveGarden() async {
    final id = widget.settings.activeGardenId;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      await widget.sharedGardenService.leaveGarden(id);
      await widget.onSettingsUpdated(
        widget.settings.copyWith(clearSharedGarden: true),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hai lasciato il giardino condiviso.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final bot = context.botanical;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final hasGarden = widget.settings.hasSharedGarden || _garden != null;
    final gardenName =
        _garden?.name ?? widget.settings.activeGardenName ?? 'Giardino Condiviso';
    final inviteCode =
        _garden?.inviteCode ?? widget.settings.activeGardenInviteCode ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, bottomInset + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Symbols.diversity_3_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Giardino Condiviso (Famiglia)',
                    style: tt.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Condividi piante, calendario annaffiature e storico con i tuoi familiari in tempo reale tramite Firebase.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bot.critical.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Text(
                  _error!,
                  style: tt.bodyMedium?.copyWith(color: bot.critical),
                ),
              ),
            ],

            const SizedBox(height: 16),

            if (hasGarden) ...[
              // Active shared garden card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(gardenName, style: tt.titleLarge),
                    const SizedBox(height: 10),
                    Text(
                      'CODICE INVITO FAMILIARI',
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            inviteCode,
                            style: tt.titleLarge?.copyWith(
                              color: cs.onPrimaryContainer,
                              letterSpacing: 2.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    'Unisciti al nostro giardino "$gardenName" su Plant Care AI! Codice invito: $inviteCode',
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Codice invito copiato! Invialo ai tuoi familiari.',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Symbols.content_copy_rounded, size: 18),
                          label: const Text('Copia'),
                        ),
                      ],
                    ),
                    if (_garden != null && _garden!.members.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        'Membri (${_garden!.members.length})',
                        style: tt.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      for (final m in _garden!.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: cs.secondaryContainer,
                                child: Text(
                                  m.displayName.isNotEmpty
                                      ? m.displayName[0].toUpperCase()
                                      : 'F',
                                  style: tt.labelMedium,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.displayName, style: tt.labelLarge),
                                    if (m.email != null)
                                      Text(
                                        m.email!,
                                        style: tt.labelSmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _syncNow,
                      icon: const Icon(Symbols.sync_rounded, size: 18),
                      label: const Text('Sincronizza ora'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _leaveGarden,
                    child: const Text('Lascia'),
                  ),
                ],
              ),
            ] else ...[
              // Create new family garden
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Crea un Giardino di Famiglia', style: tt.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome del giardino',
                        hintText: 'es. Casa nostra / Balcone',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createGarden,
                      icon: const Icon(Symbols.group_add_rounded, size: 18),
                      label: const Text('Crea e genera codice invito'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Join existing family garden
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Unisciti con Codice Invito', style: tt.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Codice invito (6 caratteri)',
                        hintText: 'es. K7P-4M2',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _joinGarden,
                      icon: const Icon(Symbols.login_rounded, size: 18),
                      label: const Text('Unisciti al giardino'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
