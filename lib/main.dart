import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'data/local_database.dart';
import 'models/plant_models.dart';
import 'screens/add_plant_sheet.dart';
import 'screens/calendar_screen.dart';
import 'screens/family_garden_sheet.dart';
import 'screens/garden_screen.dart';
import 'screens/health_check_sheet.dart';
import 'screens/plant_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/firebase_backup_service.dart';
import 'services/plant_reminder_service.dart';
import 'services/shared_garden_service.dart';
import 'theme/app_theme.dart';
import 'theme/botanical_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await PlantReminderService.instance.initialize();
  } catch (_) {}
  runApp(const PlantCareAiApp());
}

class PlantCareAiApp extends StatefulWidget {
  const PlantCareAiApp({super.key});

  @override
  State<PlantCareAiApp> createState() => _PlantCareAiAppState();
}

class _PlantCareAiAppState extends State<PlantCareAiApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void _handleThemeModeChanged(int themeModeIndex) {
    final next = switch (themeModeIndex) {
      1 => ThemeMode.light,
      2 => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    if (next != _themeMode) {
      setState(() => _themeMode = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: 'Plant Care AI',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: AppTheme.buildTheme(
            dynamicScheme: lightDynamic,
            brightness: Brightness.light,
          ),
          darkTheme: AppTheme.buildTheme(
            dynamicScheme: darkDynamic,
            brightness: Brightness.dark,
          ),
          home: SplashScreen(
            nextScreen: MainShellScreen(
              onThemeModeChanged: _handleThemeModeChanged,
            ),
          ),
        );
      },
    );
  }
}

class MainShellScreen extends StatefulWidget {
  final ValueChanged<int> onThemeModeChanged;

  const MainShellScreen({
    super.key,
    required this.onThemeModeChanged,
  });

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen>
    with WidgetsBindingObserver {
  final FirebaseBackupService _firebaseService = FirebaseBackupService();
  late final SharedGardenService _sharedGardenService =
      SharedGardenService(firebaseService: _firebaseService);
  int _selectedIndex = 0;
  List<Plant> _plants = [];
  AppSettings _settings = const AppSettings();
  GardenStats _stats = const GardenStats(
    totalPlants: 0,
    overdueWaterings: 0,
    duePhotoChecks: 0,
    wateringsThisMonth: 0,
    totalHealthChecks: 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _firebaseService.initialize().then((_) {
      if (mounted) setState(() {});
    });
    LocalDatabase.instance.onDataMutated = () {
      if (_settings.autoBackupEnabled && _firebaseService.currentUser != null) {
        _firebaseService.scheduleAutoBackup();
      }
    };
    _loadData();
  }

  @override
  void dispose() {
    _sharedGardenService.stopRealtimeSync();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadData();
    }
  }

  Future<void> _loadData() async {
    final plants = await LocalDatabase.instance.getAllPlants();
    final settings = await LocalDatabase.instance.getAppSettings();
    final stats = await LocalDatabase.instance.getGardenStats();

    if (!mounted) return;
    setState(() {
      _plants = plants;
      _settings = settings;
      _stats = stats;
    });
    widget.onThemeModeChanged(settings.themeModeIndex);

    await PlantReminderService.instance.syncReminders(
      settings: settings,
      plants: plants,
    );

    if (settings.hasSharedGarden && _firebaseService.currentUser != null) {
      _sharedGardenService.startRealtimeSync(
        settings.activeGardenId!,
        onRemoteChange: _refreshLocalOnly,
      );
    } else {
      _sharedGardenService.stopRealtimeSync();
    }
  }

  Future<void> _refreshLocalOnly() async {
    final plants = await LocalDatabase.instance.getAllPlants();
    final stats = await LocalDatabase.instance.getGardenStats();
    if (!mounted) return;
    setState(() {
      _plants = plants;
      _stats = stats;
    });
  }

  Future<void> _waterPlant(Plant plant) async {
    final log = await LocalDatabase.instance.logWatering(
      plant.id,
      wateredBy: _sharedGardenService.currentUserLabel,
    );
    if (_settings.hasSharedGarden) {
      final fresh = await LocalDatabase.instance.getPlant(plant.id);
      if (fresh != null) {
        await _sharedGardenService.pushWateringLog(
          _settings.activeGardenId!,
          log,
          fresh,
        );
      }
    }
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${plant.name} annaffiata! Prossima tra ${plant.wateringIntervalDays}g 💧',
        ),
      ),
    );
  }

  void _openFamilyGarden() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FamilyGardenSheet(
        settings: _settings,
        localPlants: _plants,
        sharedGardenService: _sharedGardenService,
        onSettingsUpdated: (updated) async {
          await LocalDatabase.instance.saveAppSettings(updated);
          await _loadData();
        },
        onSynced: _loadData,
      ),
    );
  }

  void _openAddPlant({bool openCamera = false}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddPlantSheet(
        settings: _settings,
        openCameraOnStart: openCamera,
        onSave: (plant) async {
          await LocalDatabase.instance.upsertPlant(plant);
          if (_settings.hasSharedGarden) {
            await _sharedGardenService.pushPlant(
              _settings.activeGardenId!,
              plant,
            );
          }
          await _loadData();
        },
      ),
    );
  }

  void _openPhotoCheck(Plant plant) {
    HealthCheckSheet.show(
      context,
      plant: plant,
      settings: _settings,
      onSaved: (entry, {int? updatedWateringDays}) async {
        await LocalDatabase.instance.saveHealthCheck(entry);
        if (updatedWateringDays != null) {
          await LocalDatabase.instance.upsertPlant(
            plant.copyWith(wateringIntervalDays: updatedWateringDays),
          );
        }
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Check salute salvato per ${plant.name} (${entry.healthScore.toStringAsFixed(1)}/10) 📸',
            ),
          ),
        );
      },
    );
  }

  void _openPlantDetail(Plant plant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlantDetailScreen(
          plant: plant,
          settings: _settings,
          onDataMutated: _loadData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          switch (_selectedIndex) {
            0 => 'Le mie Piante',
            1 => 'Calendario Cure',
            _ => 'Impostazioni',
          },
          style: tt.headlineSmall,
        ),
        actions: [
          IconButton(
            tooltip: _settings.hasSharedGarden
                ? 'Giardino Condiviso: ${_settings.activeGardenName}'
                : 'Condividi giardino con familiari',
            onPressed: _openFamilyGarden,
            icon: Icon(
              Symbols.diversity_3_rounded,
              size: 22,
              color: _settings.hasSharedGarden
                  ? context.botanical.healthy
                  : cs.onSurfaceVariant,
            ),
          ),
          if (_selectedIndex != 2)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ActionChip(
                avatar: Icon(
                  Symbols.auto_awesome_rounded,
                  size: 16,
                  color: cs.primary,
                ),
                label: Text(_settings.preferredAiProvider.shortLabel),
                onPressed: () => setState(() => _selectedIndex = 2),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: _firebaseService.currentUser != null
                  ? 'Backup Cloud Firebase attivo'
                  : 'Dati salvati in locale (tocca per configurare Firebase)',
              onPressed: () => setState(() => _selectedIndex = 2),
              icon: Icon(
                _firebaseService.currentUser != null
                    ? Symbols.cloud_done_rounded
                    : Symbols.cloud_off_rounded,
                size: 20,
                color: _firebaseService.currentUser != null
                    ? context.botanical.healthy
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          GardenScreen(
            plants: _plants,
            stats: _stats,
            onRefresh: _loadData,
            onOpenPlant: _openPlantDetail,
            onQuickWater: _waterPlant,
            onQuickPhotoCheck: _openPhotoCheck,
            onAddPlant: () => _openAddPlant(),
          ),
          CalendarScreen(
            plants: _plants,
            onWaterPlant: _waterPlant,
            onStartPhotoCheck: _openPhotoCheck,
            onOpenPlant: _openPlantDetail,
          ),
          SettingsScreen(
            settings: _settings,
            stats: _stats,
            firebaseService: _firebaseService,
            onOpenFamilyGarden: _openFamilyGarden,
            onSettingsChanged: (updated) async {
              await LocalDatabase.instance.saveAppSettings(updated);
              await _loadData();
            },
            onDatabaseRestored: _loadData,
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: IgnorePointer(
        ignoring: _selectedIndex != 0,
        child: AnimatedSlide(
          offset: _selectedIndex == 0 ? Offset.zero : const Offset(0, 0.14),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _selectedIndex == 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'fab_camera_identify',
                  tooltip: 'Identifica pianta con fotocamera AI',
                  backgroundColor: cs.secondaryContainer,
                  foregroundColor: cs.onSecondaryContainer,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onPressed: () => _openAddPlant(openCamera: true),
                  child: const Icon(Symbols.photo_camera_rounded),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_add_plant',
                  onPressed: () => _openAddPlant(),
                  icon: const Icon(Symbols.add_rounded),
                  label: const Text('Aggiungi pianta'),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Symbols.potted_plant_rounded, fill: 0),
            selectedIcon: Icon(Symbols.potted_plant_rounded, fill: 1),
            label: 'Piante',
          ),
          NavigationDestination(
            icon: Icon(Symbols.calendar_month_rounded, fill: 0),
            selectedIcon: Icon(Symbols.calendar_month_rounded, fill: 1),
            label: 'Calendario',
          ),
          NavigationDestination(
            icon: Icon(Symbols.tune_rounded, fill: 0),
            selectedIcon: Icon(Symbols.tune_rounded, fill: 1),
            label: 'Impostazioni',
          ),
        ],
      ),
    );
  }
}
