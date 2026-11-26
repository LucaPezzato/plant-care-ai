import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/plant_models.dart';

class PlantReminderService {
  PlantReminderService._();
  static final PlantReminderService instance = PlantReminderService._();

  static const int _waterBaseId = 3000;
  static const int _photoBaseId = 3100;
  static const int _horizonDays = 14;

  static const String _waterChannelId = 'plant_watering_reminders';
  static const String _waterChannelName = 'Promemoria Annaffiatura';
  static const String _waterChannelDesc =
      'Notifiche giornaliere per ricordarti quali piante annaffiare.';

  static const String _photoChannelId = 'plant_photo_reminders';
  static const String _photoChannelName = 'Promemoria Foto Salute';
  static const String _photoChannelDesc =
      'Promemoria periodici per scattare una foto di controllo salute alle tue piante.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    _configureLocalTimezone();

    const androidInit = AndroidInitializationSettings('@drawable/ic_stat_plant');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings: initSettings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _waterChannelId,
        _waterChannelName,
        description: _waterChannelDesc,
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _photoChannelId,
        _photoChannelName,
        description: _photoChannelDesc,
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
  }

  void _configureLocalTimezone() {
    final nowOffsetMs = DateTime.now().timeZoneOffset.inMilliseconds;
    try {
      final rome = tz.getLocation('Europe/Rome');
      if (rome.currentTimeZone.offset == nowOffsetMs) {
        tz.setLocalLocation(rome);
        return;
      }
    } catch (_) {}

    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.currentTimeZone.offset == nowOffsetMs) {
        tz.setLocalLocation(loc);
        return;
      }
    }
    tz.setLocalLocation(tz.UTC);
  }

  Future<bool> requestPermission() async {
    await initialize();
    if (!Platform.isAndroid) return true;
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final granted = await androidPlugin.requestNotificationsPermission();
    return granted ?? true;
  }

  Future<void> cancelAllReminders() async {
    await initialize();
    for (int i = 0; i < _horizonDays + 2; i++) {
      await _plugin.cancel(id: _waterBaseId + i);
      await _plugin.cancel(id: _photoBaseId + i);
    }
  }

  Future<void> syncReminders({
    required AppSettings settings,
    required List<Plant> plants,
  }) async {
    await initialize();
    await cancelAllReminders();
    if (plants.isEmpty) return;

    final now = tz.TZDateTime.now(tz.local);
    final today = dateOnly(DateTime.now());
    final horizonEnd = today.add(const Duration(days: _horizonDays));

    final waterByDay = <DateTime, List<String>>{};
    final photoByDay = <DateTime, List<String>>{};

    for (final plant in plants) {
      if (settings.wateringReminderEnabled) {
        if (plant.isWateringOverdue) {
          waterByDay.putIfAbsent(today, () => []).add(plant.name);
        }
        for (final d in plant.scheduledWateringDatesInRange(today, horizonEnd)) {
          final list = waterByDay.putIfAbsent(d, () => []);
          if (!list.contains(plant.name)) list.add(plant.name);
        }
      }
      if (settings.photoReminderEnabled) {
        if (plant.isPhotoCheckDue) {
          photoByDay.putIfAbsent(today, () => []).add(plant.name);
        }
        for (final d in plant.scheduledPhotoDatesInRange(today, horizonEnd)) {
          final list = photoByDay.putIfAbsent(d, () => []);
          if (!list.contains(plant.name)) list.add(plant.name);
        }
      }
    }

    const waterDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _waterChannelId,
        _waterChannelName,
        channelDescription: _waterChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_plant',
        color: Color(0xFF10B981),
      ),
    );

    const photoDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        _photoChannelId,
        _photoChannelName,
        channelDescription: _photoChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_plant',
        color: Color(0xFF10B981),
      ),
    );

    for (int offset = 0; offset < _horizonDays; offset++) {
      final day = today.add(Duration(days: offset));
      final scheduledWater = tz.TZDateTime(
        tz.local,
        day.year,
        day.month,
        day.day,
        settings.reminderHour.clamp(0, 23),
        settings.reminderMinute.clamp(0, 59),
      );

      final waterPlants = waterByDay[day];
      if (waterPlants != null &&
          waterPlants.isNotEmpty &&
          scheduledWater.isAfter(now)) {
        final body = waterPlants.length == 1
            ? 'È il momento di annaffiare ${waterPlants.first}.'
            : 'Piante da annaffiare: ${waterPlants.take(3).join(", ")}${waterPlants.length > 3 ? " (+${waterPlants.length - 3})" : ""}.';
        await _plugin.zonedSchedule(
          id: _waterBaseId + offset,
          title: 'Promemoria Annaffiatura 💧',
          body: body,
          scheduledDate: scheduledWater,
          notificationDetails: waterDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }

      // Offset photo reminders by 15 minutes so they don't collide with watering
      final scheduledPhoto = scheduledWater.add(const Duration(minutes: 15));
      final photoPlants = photoByDay[day];
      if (photoPlants != null &&
          photoPlants.isNotEmpty &&
          scheduledPhoto.isAfter(now)) {
        final body = photoPlants.length == 1
            ? 'Scatta una foto a ${photoPlants.first} per il check salute AI.'
            : 'Check fotografico previsto per: ${photoPlants.take(3).join(", ")}${photoPlants.length > 3 ? " (+${photoPlants.length - 3})" : ""}.';
        await _plugin.zonedSchedule(
          id: _photoBaseId + offset,
          title: 'Check Salute Piante 📸',
          body: body,
          scheduledDate: scheduledPhoto,
          notificationDetails: photoDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    }
  }

  Future<void> sendTestNotification() async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _waterChannelId,
        _waterChannelName,
        channelDescription: _waterChannelDesc,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@drawable/ic_stat_plant',
        color: Color(0xFF10B981),
      ),
    );
    await _plugin.show(
      id: _waterBaseId + 99,
      title: 'Plant Care AI 🌿',
      body: 'Notifiche attive! Ti ricorderemo annaffiature e foto periodiche.',
      notificationDetails: details,
    );
  }
}
