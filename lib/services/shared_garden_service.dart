import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../data/local_database.dart';
import '../models/plant_models.dart';
import 'firebase_backup_service.dart';

/// Enables real-time family / multi-user plant sharing via Cloud Firestore.
///
/// Firestore structure:
/// - `gardens/{gardenId}`: metadata, inviteCode, ownerUid, memberUids, members
/// - `gardens/{gardenId}/plants/{plantId}`: shared plant records
/// - `gardens/{gardenId}/watering_logs/{logId}`: shared watering history with author
class SharedGardenService {
  static const _uuid = Uuid();
  static const _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final FirebaseBackupService firebaseService;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _plantsSub;

  SharedGardenService({required this.firebaseService});

  User? get _user => firebaseService.currentUser;

  String get currentUserLabel {
    final u = _user;
    if (u == null) return 'Tu';
    if (u.displayName != null && u.displayName!.trim().isNotEmpty) {
      return u.displayName!.trim();
    }
    if (u.email != null && u.email!.isNotEmpty) {
      return u.email!.split('@').first;
    }
    return 'Familiare';
  }

  static String generateInviteCode() {
    final rng = Random.secure();
    String part(int len) =>
        List.generate(len, (_) => _codeChars[rng.nextInt(_codeChars.length)])
            .join();
    return '${part(3)}-${part(3)}';
  }

  static String normalizeCode(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (cleaned.length == 6) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    }
    return raw.trim().toUpperCase();
  }

  Future<User> _requireSignedInUser() async {
    final ready = await firebaseService.initialize();
    if (!ready) {
      throw Exception(
        'Firebase non configurato: aggiungi android/app/google-services.json per condividere il giardino con i familiari.',
      );
    }
    final user = _user;
    if (user == null) {
      throw Exception(
        'Accedi prima con Google o Anonimo 1-Tap nella sezione Backup Cloud Firebase.',
      );
    }
    return user;
  }

  /// Creates a new shared family garden and uploads all current local plants.
  Future<SharedGarden> createSharedGarden({
    required String name,
    required List<Plant> localPlants,
  }) async {
    final user = await _requireSignedInUser();
    final gardenId = _uuid.v4();
    final inviteCode = generateInviteCode();
    final now = DateTime.now();

    final gardenRef =
        FirebaseFirestore.instance.collection('gardens').doc(gardenId);

    await gardenRef.set({
      'name': name.trim().isEmpty ? 'Giardino di Famiglia' : name.trim(),
      'inviteCode': inviteCode,
      'ownerUid': user.uid,
      'memberUids': [user.uid],
      'members': {
        user.uid: {
          'displayName': currentUserLabel,
          'email': user.email,
          'joinedAt': now.toIso8601String(),
        },
      },
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    for (final plant in localPlants) {
      await pushPlant(gardenId, plant);
    }

    return SharedGarden(
      id: gardenId,
      name: name.trim().isEmpty ? 'Giardino di Famiglia' : name.trim(),
      inviteCode: inviteCode,
      ownerUid: user.uid,
      members: [
        GardenMember(
          uid: user.uid,
          displayName: currentUserLabel,
          email: user.email,
          joinedAt: now,
        ),
      ],
    );
  }

  /// Joins an existing family garden using its 6-character invite code (e.g. K7P-4M2).
  Future<SharedGarden> joinGardenByCode(String rawCode) async {
    final user = await _requireSignedInUser();
    final code = normalizeCode(rawCode);
    if (code.length < 6) {
      throw Exception('Inserisci un codice invito valido (es. K7P-4M2).');
    }

    final query = await FirebaseFirestore.instance
        .collection('gardens')
        .where('inviteCode', isEqualTo: code)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Nessun giardino trovato con codice "$code".');
    }

    final doc = query.docs.first;
    final gardenId = doc.id;
    final now = DateTime.now();

    await doc.reference.update({
      'memberUids': FieldValue.arrayUnion([user.uid]),
      'members.${user.uid}': {
        'displayName': currentUserLabel,
        'email': user.email,
        'joinedAt': now.toIso8601String(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await syncFromCloud(gardenId);
    final info = await fetchGardenInfo(gardenId);
    if (info == null) {
      throw Exception('Errore nel caricamento del giardino condiviso.');
    }
    return info;
  }

  Future<SharedGarden?> fetchGardenInfo(String gardenId) async {
    if (!firebaseService.isInitialized || _user == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('gardens')
          .doc(gardenId)
          .get();
      if (!snap.exists || snap.data() == null) return null;
      final data = snap.data()!;
      final rawMembers =
          (data['members'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final members = rawMembers.entries.map((e) {
        final m = e.value is Map<String, dynamic>
            ? e.value as Map<String, dynamic>
            : <String, dynamic>{};
        return GardenMember(
          uid: e.key,
          displayName: (m['displayName'] as String?) ?? 'Familiare',
          email: m['email'] as String?,
          joinedAt: DateTime.tryParse((m['joinedAt'] as String?) ?? '') ??
              DateTime.now(),
        );
      }).toList();

      return SharedGarden(
        id: snap.id,
        name: (data['name'] as String?) ?? 'Giardino Condiviso',
        inviteCode: (data['inviteCode'] as String?) ?? '',
        ownerUid: (data['ownerUid'] as String?) ?? '',
        members: members,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> pushPlant(String gardenId, Plant plant) async {
    if (!firebaseService.isInitialized || _user == null) return;
    try {
      final payload = Map<String, dynamic>.from(plant.toMap())
        ..remove('cover_photo_path') // Local file paths stay per-device
        ..['updated_at'] = FieldValue.serverTimestamp();
      await FirebaseFirestore.instance
          .collection('gardens')
          .doc(gardenId)
          .collection('plants')
          .doc(plant.id)
          .set(payload, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> deletePlant(String gardenId, String plantId) async {
    if (!firebaseService.isInitialized || _user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('gardens')
          .doc(gardenId)
          .collection('plants')
          .doc(plantId)
          .delete();
    } catch (_) {}
  }

  Future<void> pushWateringLog(
    String gardenId,
    WateringLog log,
    Plant updatedPlant,
  ) async {
    if (!firebaseService.isInitialized || _user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('gardens')
          .doc(gardenId)
          .collection('watering_logs')
          .doc(log.id)
          .set(log.toMap(), SetOptions(merge: true));
      await pushPlant(gardenId, updatedPlant);
    } catch (_) {}
  }

  /// Pulls all shared plants & recent watering logs from Firestore into SQLite.
  Future<int> syncFromCloud(String gardenId) async {
    if (!firebaseService.isInitialized || _user == null) return 0;
    final gardenRef =
        FirebaseFirestore.instance.collection('gardens').doc(gardenId);

    final plantsSnap = await gardenRef.collection('plants').get();
    for (final doc in plantsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final plant = Plant.fromMap(data);
      await LocalDatabase.instance.upsertPlantFromSync(plant);
    }

    final logsSnap = await gardenRef
        .collection('watering_logs')
        .orderBy('watered_at', descending: true)
        .limit(80)
        .get();
    for (final doc in logsSnap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      final log = WateringLog.fromMap(data);
      await LocalDatabase.instance.upsertWateringLogFromSync(log);
    }

    return plantsSnap.docs.length;
  }

  /// Starts real-time Firestore listener so edits/waterings by family members appear immediately.
  void startRealtimeSync(
    String gardenId, {
    required Future<void> Function() onRemoteChange,
  }) {
    stopRealtimeSync();
    if (!firebaseService.isInitialized || _user == null) return;

    _plantsSub = FirebaseFirestore.instance
        .collection('gardens')
        .doc(gardenId)
        .collection('plants')
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.docs.isEmpty) return;
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        await LocalDatabase.instance.upsertPlantFromSync(Plant.fromMap(data));
      }
      await onRemoteChange();
    });
  }

  void stopRealtimeSync() {
    _plantsSub?.cancel();
    _plantsSub = null;
  }

  Future<void> leaveGarden(String gardenId) async {
    stopRealtimeSync();
    final user = _user;
    if (!firebaseService.isInitialized || user == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('gardens')
          .doc(gardenId)
          .update({
        'memberUids': FieldValue.arrayRemove([user.uid]),
        'members.${user.uid}': FieldValue.delete(),
      });
    } catch (_) {}
  }
}
