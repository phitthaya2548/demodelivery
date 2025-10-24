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

  /// อัปเดตตำแหน่งไรเดอร์ครั้งเดียว
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

  /// เริ่มแชร์โลเกชันแบบสด (มี throttle/distanceFilter)
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
          riderId: riderId,
          lat: pos.latitude,
          lng: pos.longitude,
        );
      },
      onError: (e) => log('[RiderLocationSender] stream error: $e'),
    );
  }

  Future<void> stopLive() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// สตรีมตำแหน่งไรเดอร์จากคอลเลกชัน rider_location/{riderId}
  Stream<Map<String, dynamic>?> getRiderLocation(String riderId) async* {
    try {
      if (riderId.trim().isEmpty) {
        yield null;
        return;
      }
      final riderRef = _fs.collection('rider_location').doc(riderId);
      await for (final snap in riderRef.snapshots()) {
        if (!snap.exists) {
          yield null;
          continue;
        }
        final data = snap.data();
        final ll = (data?['last_location']);
        if (ll is Map) {
          yield ll.cast<String, dynamic>();
        } else {
          yield null;
        }
      }
    } catch (e) {
      log('[Error] getRiderLocation: $e');
      yield null;
    }
  }

  /// สตรีมตำแหน่งไรเดอร์ "ตาม shipment" แบบเรียลไทม์จริง:
  /// - ถ้า shipment เปลี่ยน rider_id จะยกเลิกสตรีมเก่าแล้วตาม id ใหม่ให้อัตโนมัติ
  Stream<Map<String, dynamic>?> getShipmentLocation(String shipmentId) {
    final controller = StreamController<Map<String, dynamic>?>.broadcast();
    StreamSubscription? subShipment;
    StreamSubscription? subRiderLoc;

    void _followRider(String riderId) {
      subRiderLoc?.cancel();
      if (riderId.trim().isEmpty) {
        controller.add({});
        return;
      }
      subRiderLoc = getRiderLocation(riderId).listen(
        (loc) => controller.add(loc ?? {}),
        onError: (e) {
          log('[Error] rider_location stream: $e');
          controller.add({});
        },
      );
    }

    subShipment =
        _fs.collection('shipments').doc(shipmentId).snapshots().listen(
      (snap) {
        if (!snap.exists) {
          log('[Error] shipment not found: $shipmentId');
          controller.add({});
          return;
        }
        final data = snap.data() ?? {};
        final riderId = (data['rider_id'] ?? '').toString();
        _followRider(riderId);
      },
      onError: (e) {
        log('[Error] getShipmentLocation shipment stream: $e');
        controller.add({});
      },
    );

    controller.onCancel = () async {
      await subShipment?.cancel();
      await subRiderLoc?.cancel();
    };

    return controller.stream;
  }

  /// ดึงรายการ shipment ของ user แบบ one-shot และ enrich โลเกชันไรเดอร์ (เฉพาะ snapshot แรก)
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

      final senderSnap =
          (map['sender_snapshot'] as Map?)?.cast<String, dynamic>();
      map['sender_user_id'] = senderSnap?['user_id']?.toString() ?? '';

      final riderId = (map['rider_id'] ?? '').toString();
      if (riderId.isNotEmpty) {
        await for (final rl in getRiderLocation(riderId)) {
          if (rl != null) map['rider_location'] = rl;
          break; // เอาแค่ค่าล่าสุดครั้งเดียว
        }
      }
      return map;
    }

    try {
      log('[Info] Fetch shipments for userId=$userId (receiver first)');

      final byReceiver = await _fs
          .collection('shipments')
          .where('receiver_id', isEqualTo: userId)
          .where('status', whereIn: [2, 3]).get();

      if (byReceiver.docs.isNotEmpty) {
        log('[Info] Found ${byReceiver.docs.length} by receiver_id');
        return Future.wait(byReceiver.docs.map((d) => _enrich(d.id, d.data())));
      }

      log('[Info] Try sender_snapshot.user_id ...');
      final bySender = await _fs
          .collection('shipments')
          .where('sender_snapshot.user_id', isEqualTo: userId)
          .where('status', whereIn: [2, 3]).get();

      if (bySender.docs.isNotEmpty) {
        log('[Info] Found ${bySender.docs.length} by sender_snapshot.user_id');
        return Future.wait(bySender.docs.map((d) => _enrich(d.id, d.data())));
      }

      log('[Info] No shipments for userId=$userId');
      return [];
    } catch (e) {
      log('[Error] getShipmentsByUserId: $e');
      return [];
    }
  }

  /// ดีบักหา path ที่ค่าตรงกับ userId
  Future<void> debugScanUserIdPaths(String userId) async {
    final qs = await _fs.collection('shipments').limit(200).get();
    final target = userId.trim();

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

  /// (ภายใน) สตรีมตำแหน่งของไรเดอร์คนหนึ่ง
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

  // ---------------------------------------------------------------------------
  // 🧠 สตรีมหลัก: ดู shipment ของผู้ใช้ (ส่ง/รับ) แบบเรียลไทม์ + โลเกชัน/ชื่อไรเดอร์
  // แก้บั๊ก "ไรเดอร์ฝั่งส่งไปโผล่ฝั่งรับ" ด้วยการ prune จาก live IDs จริงสองฝั่ง
  // ---------------------------------------------------------------------------
  Stream<Map<String, List<Map<String, dynamic>>>> watchShipmentsForUser(
      String userId) {
    userId = userId.trim();
    if (userId.isEmpty) {
      return Stream.value(const {'sending': [], 'receiving': []});
    }

    final controller =
        StreamController<Map<String, List<Map<String, dynamic>>>>.broadcast();

    // แยกกองอย่างชัดเจน
    final byIdSend = <String, Map<String, dynamic>>{}; // sender side only
    final byIdRecv = <String, Map<String, dynamic>>{}; // receiver side only

    // สตรีมย่อยของไรเดอร์ (แชร์ตาม riderId)
    final riderLocSubs = <String, StreamSubscription?>{};
    final riderNameSubs = <String, StreamSubscription?>{};

    // live ids ของแต่ละฝั่ง
    final liveReceiverIds = <String>{};
    final liveSenderIds = <String>{};

    StreamSubscription? subReceiver;
    StreamSubscription? subSender;

    void _emit() {
      controller.add({
        'sending': byIdSend.values.toList(),
        'receiving': byIdRecv.values.toList(),
      });
    }

    void _attachRiderLocation(String riderId) {
      riderLocSubs[riderId] ??=
          getShipmentLocationForRider(riderId).listen((loc) {
        if (loc == null) return;

        // อัปเดตทั้งสองกองที่มี riderId นี้
        for (final e in byIdSend.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_location'] = loc;
          }
        }
        for (final e in byIdRecv.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_location'] = loc;
          }
        }
        _emit();
      }, onError: (_) {});
    }

    void _attachRiderName(String riderId) {
      riderNameSubs[riderId] ??=
          _fs.collection('riders').doc(riderId).snapshots().listen((doc) {
        final name = (doc.data()?['name'] ?? '').toString();

        for (final e in byIdSend.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_name'] = name;
          }
        }
        for (final e in byIdRecv.entries) {
          if ((e.value['rider_id'] ?? '').toString() == riderId) {
            e.value['rider_name'] = name;
          }
        }
        _emit();
      }, onError: (_) {});
    }

    Map<String, dynamic> _baseMapFromDoc(
        QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = (m['id'] ?? d.id).toString();
      final sx = (m['sender_snapshot'] as Map?)?.cast<String, dynamic>();
      m['sender_user_id'] = sx?['user_id']?.toString() ?? '';
      return m;
    }

    void _upsertSenderDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final m = _baseMapFromDoc(d);
      byIdSend[d.id] = m;

      final riderId = (m['rider_id'] ?? '').toString();
      if (riderId.isNotEmpty) {
        _attachRiderLocation(riderId);
        _attachRiderName(riderId);
      }
    }

    void _upsertReceiverDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final m = _baseMapFromDoc(d);
      byIdRecv[d.id] = m;

      final riderId = (m['rider_id'] ?? '').toString();
      if (riderId.isNotEmpty) {
        _attachRiderLocation(riderId);
        _attachRiderName(riderId);
      }
    }

    void _pruneMissingSets() {
      // ลบ sender ที่ไม่อยู่ในผลลัพธ์ sender สด
      final removedSend =
          byIdSend.keys.where((k) => !liveSenderIds.contains(k)).toList();
      for (final id in removedSend) {
        byIdSend.remove(id);
      }

      // ลบ receiver ที่ไม่อยู่ในผลลัพธ์ receiver สด
      final removedRecv =
          byIdRecv.keys.where((k) => !liveReceiverIds.contains(k)).toList();
      for (final id in removedRecv) {
        byIdRecv.remove(id);
      }

      // เก็บกวาดสตรีมไรเดอร์ที่ไม่มี shipment ไหนใช้แล้ว
      final allStillUsedRiderIds = <String>{};
      for (final m in byIdSend.values) {
        final r = (m['rider_id'] ?? '').toString();
        if (r.isNotEmpty) allStillUsedRiderIds.add(r);
      }
      for (final m in byIdRecv.values) {
        final r = (m['rider_id'] ?? '').toString();
        if (r.isNotEmpty) allStillUsedRiderIds.add(r);
      }

      final toCancelLoc = riderLocSubs.keys
          .where((rid) => !allStillUsedRiderIds.contains(rid))
          .toList();
      for (final rid in toCancelLoc) {
        riderLocSubs.remove(rid)?.cancel();
      }

      final toCancelName = riderNameSubs.keys
          .where((rid) => !allStillUsedRiderIds.contains(rid))
          .toList();
      for (final rid in toCancelName) {
        riderNameSubs.remove(rid)?.cancel();
      }
    }

    subReceiver = _fs
        .collection('shipments')
        .where('receiver_id', isEqualTo: userId)
        .where('status', whereIn: [2, 3])
        .snapshots()
        .listen((qs) {
          liveReceiverIds
            ..clear()
            ..addAll(qs.docs.map((d) => d.id));
          for (final d in qs.docs) _upsertReceiverDoc(d);
          _pruneMissingSets();
          _emit();
        }, onError: (e) => log('[Error] watchShipmentsForUser(receiver): $e'));

    subSender = _fs
        .collection('shipments')
        .where('sender_snapshot.user_id', isEqualTo: userId)
        .where('status', whereIn: [2, 3])
        .snapshots()
        .listen((qs) {
          liveSenderIds
            ..clear()
            ..addAll(qs.docs.map((d) => d.id));
          for (final d in qs.docs) _upsertSenderDoc(d);
          _pruneMissingSets();
          _emit();
        }, onError: (e) => log('[Error] watchShipmentsForUser(sender): $e'));

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
