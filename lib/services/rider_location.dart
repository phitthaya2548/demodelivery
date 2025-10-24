// lib/services/rider_location.dart
import 'dart:async';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class RiderLocationSender {
  RiderLocationSender({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;
  StreamSubscription<Position>? _sub;

  /// อัปเดตครั้งเดียว
  Future<void> updateOnce({
    required String riderId,
    required double lat,
    required double lng,
  }) async {
    if (riderId.isEmpty) return;
    final ref = _fs.collection('rider_location').doc(riderId);
    await ref.set({
      'last_location': {'lat': lat, 'lng': lng},
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> startLive({
    required String riderId,
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
    int distanceFilter = 5,
    Duration? throttle,
  }) async {
    await _sub?.cancel();

    DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    final settings =
        LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) async {
        final now = DateTime.now();
        if (throttle != null && now.difference(_lastSent) < throttle) return;
        _lastSent = now;
        await updateOnce(
            riderId: riderId, lat: pos.latitude, lng: pos.longitude);
      },
      onError: (e) => print('[RiderLocationSender] stream error: $e'),
    );
  }

  Future<void> stopLive() async {
    await _sub?.cancel();
    _sub = null;
  }

  Stream<Map<String, dynamic>?> getRiderLocation(String riderId) async* {
    try {
      final riderRef = _fs.collection('rider_location').doc(riderId);

      await for (var riderSnapshot in riderRef.snapshots()) {
        if (riderSnapshot.exists) {
          final riderData = riderSnapshot.data();
          if (riderData != null && riderData.containsKey('last_location')) {
            final lastLocation = riderData['last_location'];
            if (lastLocation != null) {
              yield lastLocation;
            } else {
              yield null;
            }
          } else {
            yield null;
          }
        } else {}
      }
    } catch (e) {
      log('[Error] Error fetching rider location: $e');
      yield null;
    }
  }

  Stream<Map<String, dynamic>?> getShipmentLocation(String shipmentId) async* {
    try {
      final shipmentRef = _fs.collection('shipments').doc(shipmentId);
      final shipmentSnapshot = await shipmentRef.get();

      if (!shipmentSnapshot.exists) {
        log('[Error] No shipment found for shipmentId: $shipmentId');
        yield {};
        return;
      }

      final shipmentData = shipmentSnapshot.data();
      final riderId = shipmentData?['rider_id'];

      if (riderId == null || riderId.isEmpty) {
        log('[Error] No riderId found for shipmentId: $shipmentId');
        yield {};
        return;
      }

      final riderLocationStream = getRiderLocation(riderId);

      // Yielding the rider's location
      yield* riderLocationStream;
    } catch (e) {
      log('[Error] Error fetching shipment and rider location: $e');
      yield {};
    }
  }

  Future<List<Map<String, dynamic>>> getShipmentsByUserId(String userId) async {
    userId = userId.trim();
    if (userId.isEmpty) {
      log('[Error] UserId is empty');
      return [];
    }

    Future<Map<String, dynamic>> _enrich(
        String id, Map<String, dynamic> data) async {
      final map = Map<String, dynamic>.from(data);
      map['id'] = (map['id'] ?? id).toString();

      // เผื่ออยากเก็บ sender_user_id ไว้ใช้งาน
      final senderSnap =
          (map['sender_snapshot'] as Map?)?.cast<String, dynamic>();
      map['sender_user_id'] = senderSnap?['user_id']?.toString() ?? '';

      // เติมตำแหน่งไรเดอร์ (เอา snapshot แรกพอ)
      final riderId = (map['rider_id'] ?? '').toString();
      if (riderId.isNotEmpty) {
        await for (final rl in getRiderLocation(riderId)) {
          if (rl != null) map['rider_location'] = rl;
          break;
        }
      }
      return map;
    }

    try {
      log('[Info] Fetching shipments for userId: $userId (try receiver first)');

      // 1) ผู้รับก่อน
      final byReceiver = await _fs
          .collection('shipments')
          .where('receiver_id', isEqualTo: userId)
          .where('status', whereIn: [2, 3]).get();
      if (byReceiver.docs.isNotEmpty) {
        log('[Info] Found ${byReceiver.docs.length} by receiver_id');
        return Future.wait(byReceiver.docs.map((d) => _enrich(d.id, d.data())));
      }

      // 2) ผู้ส่ง (ตามที่ debug เจอ: sender_snapshot.user_id)
      log('[Info] No shipments by receiver. Try sender_snapshot.user_id...');
      final bySender = await _fs
          .collection('shipments')
          .where('sender_snapshot.user_id', isEqualTo: userId)
          .where('status', whereIn: [2, 3]).get();

      if (bySender.docs.isNotEmpty) {
        log('[Info] Found ${bySender.docs.length} by sender_snapshot.user_id');
        return Future.wait(bySender.docs.map((d) => _enrich(d.id, d.data())));
      }

      log('[Info] No shipments found for userId: $userId (receiver & sender)');
      return [];
    } catch (e) {
      log('[Error] Error fetching shipments for userId $userId: $e');
      return [];
    }
  }

  Future<void> debugScanUserIdPaths(String userId) async {
    final qs = await _fs.collection('shipments').limit(200).get();

    // ค่าที่จะเทียบ (String)
    final target = userId.trim();

    // ค้นหาแบบ recursive ใน Map/List ทุกระดับ
    void dfs(dynamic node, List<String> path, String docId) {
      if (node is Map) {
        node.forEach((k, v) => dfs(v, [...path, k.toString()], docId));
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          dfs(node[i], [...path, '[$i]'], docId);
        }
      } else {
        final valStr = node?.toString() ?? 'null';
        if (valStr.trim() == target) {
          log('[DBG] MATCH doc=$docId path=${path.join('.')} value=$valStr type=${node.runtimeType}');
        }
      }
    }

    for (final d in qs.docs) {
      dfs(d.data(), [], d.id);
    }
  }

  Stream<Map<String, dynamic>?> getShipmentLocationForRider(String riderId) {
    final doc = _fs.collection('rider_location').doc(riderId);
    return doc.snapshots().map((s) {
      final d = s.data();
      if (d == null) return null;
      final ll = d['last_location'];
      if (ll is Map) return ll.cast<String, dynamic>();
      return null;
    });
  }

  Stream<List<Map<String, dynamic>>> watchShipmentsForUser(String userId) {
    userId = userId.trim();
    if (userId.isEmpty) return Stream.value(const []);

    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
    final byId = <String, Map<String, dynamic>>{}; // docId -> shipment
    final riderLocSubs = <String, StreamSubscription?>{}; // riderId -> sub loc
    final riderNameSubs =
        <String, StreamSubscription?>{}; // riderId -> sub name
    StreamSubscription? subReceiver;
    StreamSubscription? subSender;

    void _emit() => controller.add(byId.values.toList());

    void _attachRiderLocation(String riderId) {
      riderLocSubs[riderId] ??=
          getShipmentLocationForRider(riderId).listen((loc) {
        if (loc == null) return;
        for (final e in byId.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_location'] = loc;
          }
        }
        _emit();
      });
    }

    // 👇 ผูกชื่อไรเดอร์ จากคอลเลกชัน "riders"
    void _attachRiderName(String riderId) {
      riderNameSubs[riderId] ??=
          _fs.collection('riders').doc(riderId).snapshots().listen((doc) {
        final name = (doc.data()?['name'] ?? '').toString();
        for (final e in byId.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_name'] = name; // ✅ ใส่ชื่อเข้า shipment
          }
        }
        _emit();
      }, onError: (e) {
        // เงียบไว้ก็ได้
      });
    }

    void _upsertDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = (m['id'] ?? d.id).toString();

      final sx = (m['sender_snapshot'] as Map?)?.cast<String, dynamic>();
      m['sender_user_id'] = sx?['user_id']?.toString() ?? '';

      byId[d.id] = m;

      final riderId = (m['rider_id'] ?? '').toString();
      if (riderId.isNotEmpty) {
        _attachRiderLocation(riderId);
        _attachRiderName(riderId); // ✅ ผูกชื่อไว้ด้วย
      }
    }

    void _pruneMissing(Set<String> liveIds) {
      final removed = byId.keys.where((k) => !liveIds.contains(k)).toList();
      for (final id in removed) {
        final riderId = (byId[id]?['rider_id'] ?? '').toString();
        byId.remove(id);

        // ถ้าไม่มี shipment ไหนใช้ riderId นี้แล้ว ยกเลิกสตรีมทั้ง loc และ name
        final stillUsed = byId.values.any(
          (m) => (m['rider_id'] ?? '').toString() == riderId,
        );
        if (!stillUsed && riderId.isNotEmpty) {
          riderLocSubs.remove(riderId)?.cancel();
          riderNameSubs.remove(riderId)?.cancel();
        }
      }
    }

    subReceiver = _fs
        .collection('shipments')
        .where('receiver_id', isEqualTo: userId)
        .where('status', whereIn: [2, 3]) // <=
        .snapshots()
        .listen((qs) {
          final live = qs.docs.map((d) => d.id).toSet();
          for (final d in qs.docs) _upsertDoc(d);
          _pruneMissing(live.union(byId.keys.toSet()));
          _emit();
        });

    subSender = _fs
        .collection('shipments')
        .where('sender_snapshot.user_id', isEqualTo: userId)
        .where('status', whereIn: [2, 3])
        .snapshots()
        .listen((qs) {
          final live = qs.docs.map((d) => d.id).toSet();
          for (final d in qs.docs) _upsertDoc(d);
          _pruneMissing(live.union(byId.keys.toSet()));
          _emit();
        });

    controller.onCancel = () async {
      await subReceiver?.cancel();
      await subSender?.cancel();
      for (final s in riderLocSubs.values) {
        await s?.cancel();
      }
      for (final s in riderNameSubs.values) {
        await s?.cancel();
      }
    };

    return controller.stream;
  }
}
