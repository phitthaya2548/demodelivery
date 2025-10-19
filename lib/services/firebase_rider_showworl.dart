import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; // ✅ ใช้ระยะตาม Spherical ของ Google

/// API สำหรับฝั่งไรเดอร์ (คุยกับ Firestore)
/// - รับงาน: จะบันทึก rider_snapshot (ชื่อ/เบอร์/รูป/ทะเบียน/ที่อยู่/พิกัด) ลงที่ shipment ด้วย
class FirebaseRiderApi {
  FirebaseRiderApi({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  /// ระยะที่อนุญาต (เมตร)
  static const double _distanceThresholdM = 20.0;

  /// (ออปชัน) margin เล็กน้อยกัน jitter ของ GPS
  static const double _toleranceM = 3.0;

  // ---------- helpers ----------
  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  GeoPoint? _toGeoPoint(dynamic v) {
    if (v == null) return null;
    if (v is GeoPoint) return v;
    final m = _asMap(v);
    if (m.isNotEmpty) {
      final lat = m['lat'] ?? m['latitude'] ?? m['_latitude'];
      final lng = m['lng'] ?? m['longitude'] ?? m['_longitude'];
      if (lat is num && lng is num) {
        return GeoPoint(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  GeoPoint? _extractGeoPointDeep(dynamic v) {
    final gp = _toGeoPoint(v);
    if (gp != null) return gp;
    final m = _asMap(v);
    if (m.isEmpty) return null;
    final gp2 = _toGeoPoint(m['geopoint']);
    if (gp2 != null) return gp2;
    return _toGeoPoint(m);
  }

  /// ✅ ใช้ระยะทางแบบ Spherical ของ Google (ผ่าน geolocator)
  double _distanceMeters(GeoPoint a, GeoPoint b) {
    return Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
  }

  void _requireWithinDistance({
    required GeoPoint rider,
    required GeoPoint target,
    required String errorMessage,
  }) {
    final d = _distanceMeters(rider, target);
    if (d < (_distanceThresholdM + _toleranceM)) {
      throw Exception('$errorMessage (ระยะห่าง ${d.toStringAsFixed(1)} ม.)');
    }
  }

  // ดึงข้อมูลชื่อ/เบอร์/รูป/ทะเบียน/พิกัด/ที่อยู่จากเอกสารไรเดอร์หลายสคีมา
  Map<String, dynamic> _buildRiderSnapshot({
    required Map<String, dynamic> riderDoc,
    GeoPoint? fallbackLocation,
  }) {
    final name =
        (riderDoc['name'] ?? riderDoc['display_name'] ?? '').toString();
    final phone = (riderDoc['phone'] ?? '').toString();
    final photo =
        (riderDoc['photo_url'] ?? riderDoc['avatar'] ?? '').toString();
    final plate =
        (riderDoc['plate'] ?? riderDoc['plate_number'] ?? '').toString();
    final addressText = (riderDoc['address_text'] ??
            riderDoc['current_address_text'] ??
            riderDoc['detail'] ??
            '')
        .toString();

    GeoPoint? loc = _toGeoPoint(riderDoc['location']) ??
        _toGeoPoint(_asMap(riderDoc['profile'])['location']) ??
        fallbackLocation;

    final snap = <String, dynamic>{
      'name': name,
      'phone': phone,
      'photo_url': photo,
      'plate': plate,
      if (addressText.isNotEmpty) 'address_text': addressText,
      if (loc != null) 'location': loc,
    };
    return snap;
  }

  // ===== Streams =====
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRider(String riderId) {
    if (riderId.isEmpty) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return _fs.collection('riders').doc(riderId).snapshots();
  }

  /// งาน status == 1 (ว่าง)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchOpenShipments({
    int limit = 80,
  }) {
    return _fs
        .collection('shipments')
        .where('status', isEqualTo: 1)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs);
  }

  // ===== Single reads =====
  Future<String> addressTextById(String id) async {
    if (id.isEmpty) return '';
    final snap = await _fs.collection('addressuser').doc(id).get();
    if (!snap.exists) return '';
    final m = snap.data() ?? {};
    return (m['address_text'] ?? m['detail'] ?? '').toString();
  }

  // ===== Mutations =====
  /// รับงาน: ต้องอยู่ห่างจุดรับสินค้าไม่เกิน 20 เมตร (ระยะเส้นตรง)
  Future<void> acceptShipment({
    required String riderId,
    required String shipmentId,
  }) async {
    final riderRef = _fs.collection('riders').doc(riderId);
    final shipRef = _fs.collection('shipments').doc(shipmentId);
    final riderLocRef = _fs.collection('rider_location').doc(riderId);

    await _fs.runTransaction((tx) async {
      // ---- ตรวจไรเดอร์
      final riderSnap = await tx.get(riderRef);
      final riderData = (riderSnap.data() ?? {}) as Map<String, dynamic>;
      final current = (riderData['current_shipment_id'] ?? '').toString();
      if (current.isNotEmpty) {
        throw Exception('คุณมีงานที่กำลังทำอยู่ (#$current)');
      }

      // ---- ตรวจงาน
      final shipSnap = await tx.get(shipRef);
      if (!shipSnap.exists) throw Exception('งานถูกลบแล้ว');
      final m = (shipSnap.data() ?? {}) as Map<String, dynamic>;
      final s = m['status'];
      final status = (s is int) ? s : int.tryParse('$s') ?? 0;
      if (status != 1) throw Exception('งานนี้ถูกคนอื่นรับไปแล้ว');

      // ---- พิกัดไรเดอร์ล่าสุด
      final rlSnap = await tx.get(riderLocRef);
      final rl = rlSnap.data() as Map<String, dynamic>? ?? {};
      GeoPoint? riderGeo =
          _toGeoPoint(rl['last_location']) ?? _toGeoPoint(rl['geopoint']);
      if (riderGeo == null) {
        throw Exception('ไม่พบพิกัดปัจจุบันของไรเดอร์');
      }

      // ---- หา pickup geo (root → addressuser → sender_snapshot)
      GeoPoint? pickupGeo;
      pickupGeo = _extractGeoPointDeep(m['pickup_address']);

      if (pickupGeo == null) {
        final pickupId = (m['pickup_address_id'] ?? '').toString();
        if (pickupId.isNotEmpty) {
          final addrRef = _fs.collection('addressuser').doc(pickupId);
          final addrSnap = await tx.get(addrRef);
          final addr = addrSnap.data() as Map<String, dynamic>? ?? {};
          pickupGeo = _extractGeoPointDeep(addr);
        }
      }

      if (pickupGeo == null) {
        final senderSnap = _asMap(m['sender_snapshot']);
        pickupGeo = _extractGeoPointDeep(senderSnap['pickup_address']);
      }

      if (pickupGeo == null) {
        throw Exception('ไม่พบจุดรับสินค้าของงานนี้');
      }

      // ---- เงื่อนไขหลัก: ไรเดอร์ต้องอยู่ใกล้ pickup ≤ 20 ม.
      _requireWithinDistance(
        rider: riderGeo,
        target: pickupGeo,
        errorMessage:
            'ต้องอยู่ใกล้จุดรับสินค้าไม่เกิน $_distanceThresholdM เมตร',
      );

      // ---- สร้าง rider_snapshot
      final riderSnapshot = _buildRiderSnapshot(
        riderDoc: riderData,
        fallbackLocation: riderGeo,
      );

      // ---- อัปเดตทั้งสองฝั่ง
      tx.set(
        riderRef,
        {
          'current_shipment_id': shipmentId,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      tx.update(shipRef, {
        'status': 2,
        'rider_id': riderId,
        'rider_snapshot': riderSnapshot,
        'rider_snapshot_updated_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  
  Future<void> completeOrCancel({
    required String riderId,
    required String shipmentId,
    required bool complete,
  }) async {
    final riderRef = _fs.collection('riders').doc(riderId);
    final shipRef = _fs.collection('shipments').doc(shipmentId);
    final riderLocRef = _fs.collection('rider_location').doc(riderId);

    await _fs.runTransaction((tx) async {
      
      final riderSnap = await tx.get(riderRef);
      final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
      final current = (riderData['current_shipment_id'] ?? '').toString();
      if (current != shipmentId) {
        throw Exception('ไม่มีสิทธิ์หรือไม่มีงานนี้ในมือ');
      }

      // โหลดงาน
      final shipSnap = await tx.get(shipRef);
      if (!shipSnap.exists) throw Exception('งานถูกลบแล้ว');
      final m = (shipSnap.data() ?? {}) as Map<String, dynamic>;
      final s = m['status'];
      final status = (s is int) ? s : int.tryParse('$s') ?? 0;

      // ต้องเป็นงานที่กำลังทำอยู่และเป็นของไรเดอร์คนนี้
      final rid = (m['rider_id'] ?? '').toString();
      if (rid != riderId) throw Exception('ไม่มีสิทธิ์ปิดงานนี้');
      if (status != 2 && complete) {
        throw Exception('สถานะงานไม่ถูกต้องสำหรับการปิดงาน');
      }

      if (complete) {
        // ต้องอยู่ใกล้จุดส่ง ≤ 20 ม.
        // หา delivery geo
        GeoPoint? deliveryGeo;
        deliveryGeo = _extractGeoPointDeep(m['delivery_address']) ??
            _extractGeoPointDeep(m['delivery_address_snapshot']);

        if (deliveryGeo == null) {
          final delId = (m['delivery_address_id'] ?? '').toString();
          if (delId.isNotEmpty) {
            final addrRef = _fs.collection('addressuser').doc(delId);
            final addrSnap = await tx.get(addrRef);
            final addr = addrSnap.data() as Map<String, dynamic>? ?? {};
            deliveryGeo = _extractGeoPointDeep(addr);
          }
        }

        if (deliveryGeo == null) {
          final recv = _asMap(m['receiver_snapshot']);
          deliveryGeo = _extractGeoPointDeep(recv['delivery_address']) ??
              _extractGeoPointDeep(recv['delivery_address_snapshot']);
          if (deliveryGeo == null) {
            final addrId = (recv['address_id'] ?? '').toString();
            if (addrId.isNotEmpty) {
              final addrRef = _fs.collection('addressuser').doc(addrId);
              final addrSnap = await tx.get(addrRef);
              final addr = addrSnap.data() as Map<String, dynamic>? ?? {};
              deliveryGeo = _extractGeoPointDeep(addr);
            }
          }
        }

        if (deliveryGeo == null) {
          throw Exception('ไม่พบจุดส่งสินค้าของงานนี้');
        }

        // พิกัดไรเดอร์ล่าสุด
        final rlSnap = await tx.get(riderLocRef);
        final rl = rlSnap.data() as Map<String, dynamic>? ?? {};
        GeoPoint? riderGeo =
            _toGeoPoint(rl['last_location']) ?? _toGeoPoint(rl['geopoint']);
        if (riderGeo == null) {
          throw Exception('ไม่พบพิกัดปัจจุบันของไรเดอร์');
        }

        _requireWithinDistance(
          rider: riderGeo,
          target: deliveryGeo,
          errorMessage:
              'ต้องอยู่ใกล้จุดส่งสินค้าไม่เกิน $_distanceThresholdM เมตร',
        );
      }

      // อัปเดตสถานะทั้งสองฝั่ง
      tx.update(riderRef, {
        'current_shipment_id':
            FieldValue.delete(), // คืนงานก็ลบ, ปิดงานก็ลบเช่นกัน
        'updated_at': FieldValue.serverTimestamp(),
      });

      tx.update(shipRef, {
        'status': complete ? 3 : 1,
        if (!complete) 'rider_id': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }
}
