// lib/data/firebase_rider_repository.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';



class GeoCoord {
  final double lat;
  final double lng;
  const GeoCoord(this.lat, this.lng);
}

class ResolvedShipment {
  final String id;
  final int status;
  final String itemName;
  final String itemDesc;
  final String photoUrl;

  // Sender
  final String senderName;
  final String senderPhone;
  final String senderAddressText;
  final GeoCoord? senderGeo;


  final String receiverName;
  final String receiverPhone;
  final String receiverAddressText;
  final GeoCoord? receiverGeo;

  const ResolvedShipment({
    required this.id,
    required this.status,
    required this.itemName,
    required this.itemDesc,
    required this.photoUrl,
    required this.senderName,
    required this.senderPhone,
    required this.senderAddressText,
    required this.senderGeo,
    required this.receiverName,
    required this.receiverPhone,
    required this.receiverAddressText,
    required this.receiverGeo,
  });
}


class FirebaseRiderRepository {
  FirebaseRiderRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _st;

  static const String kAvatarUrlField = 'photoUrl';
  static const String kAvatarVersionField = 'avatarVersion'; // epoch ms
  static const List<String> _legacyAvatarFields = [
    'photoUrl',
    'avatar_url',
    'photo_url'
  ];

  String _urlWithVersion(String url, Object? version) {
    if (url.isEmpty) return '';
    final v = version?.toString().trim();
    if (v == null || v.isEmpty) return url;
    return url.contains('?') ? '$url&v=$v' : '$url?v=$v';
  }

  String _normalizePhone(String phone) {
    final raw = phone.trim();
    if (raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.startsWith('0') && digits.length >= 9) {
      // ปรับตาม schema ที่คุณใช้ (ตัวอย่าง: ไทย)
      return '+66${digits.substring(1)}';
    }
    return digits;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  GeoCoord? _extractGeo(dynamic v) {
    if (v == null) return null;
    if (v is GeoPoint) return GeoCoord(v.latitude, v.longitude);
    final m = _asMap(v);
    if (m.isEmpty) return null;
    final lat = (m['latitude'] ?? m['_latitude'] ?? m['lat']);
    final lng = (m['longitude'] ?? m['_longitude'] ?? m['lng']);
    if (lat is num && lng is num) {
      return GeoCoord(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  String _pickAvatarUrl(Map<String, dynamic> m) {
    final direct = (m[kAvatarUrlField] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    for (final f in _legacyAvatarFields) {
      final v = (m[f] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  // ---------------------------------------------------------------------------
  // Streams / Reads (Rider / Shipment)
  // ---------------------------------------------------------------------------
  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRider(String riderId) =>
      _fs.collection('riders').doc(riderId).snapshots();

  Stream<String?> watchCurrentShipmentId(String riderId) {
    return watchRider(riderId).map((snap) {
      final m = snap.data();
      return (m == null) ? null : (m['current_shipment_id'] ?? '').toString();
    });
  }

  Future<String?> getCurrentShipmentIdOnce(String riderId) async {
    final snap = await _fs.collection('riders').doc(riderId).get();
    final m = snap.data();
    return (m == null) ? null : (m['current_shipment_id'] ?? '').toString();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchShipment(
          String shipmentId) =>
      _fs.collection('shipments').doc(shipmentId).snapshots();

  Future<Map<String, dynamic>?> getShipmentOnce(String shipmentId) async {
    final snap = await _fs.collection('shipments').doc(shipmentId).get();
    return snap.data();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchAvailableShipments({int limit = 80}) {
    final q = _fs
        .collection('shipments')
        .where('status', isEqualTo: 1)
        .orderBy('created_at', descending: true)
        .limit(limit);
    return q.snapshots().map((s) => s.docs);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchShipmentsOfRider({
    required String riderId,
    int limit = 80,
    List<int>? statusIn,
  }) {
    Query<Map<String, dynamic>> q =
        _fs.collection('shipments').where('rider_id', isEqualTo: riderId);

    if (statusIn != null && statusIn.isNotEmpty && statusIn.length <= 10) {
      q = q.where('status', whereIn: statusIn);
    }

    q = q.orderBy('updated_at', descending: true).limit(limit);
    return q.snapshots().map((s) => s.docs);
  }

  Future<String> loadAddressTextById(String addressId) async {
    if (addressId.isEmpty) return '';
    final snap = await _fs.collection('addressuser').doc(addressId).get();
    final m = snap.data() ?? {};
    return (m['address_text'] ?? m['detail'] ?? '').toString();
  }

  Stream<List<ResolvedShipment>> watchShipmentsOfRiderResolved({
    required String riderId,
    List<int>? statusIn,
    int limit = 80,
  }) {
    final base = watchShipmentsOfRider(
      riderId: riderId,
      statusIn: statusIn,
      limit: limit,
    );

    return base.asyncMap((docs) async {
      final futures = docs.map((d) async {
        final m = d.data();

        final id = (m['id'] ?? d.id).toString();
        final itemName = (m['item_name'] ?? '-').toString();
        final itemDesc = (m['item_description'] ?? '').toString();

        // อย่าฟอลแบ็กไปใช้ last_proof_url กับรูปสินค้า
        final photoUrl = (m['item_photo_url'] ??
                m['product_photo_url'] ??
                m['last_photo_url'] ??
                '')
            .toString();

        final s = m['status'];
        final statusVal = (s is int) ? s : int.tryParse('$s') ?? 0;

        final sender = _asMap(m['sender_snapshot']);
        final receiver = _asMap(m['receiver_snapshot']);
        final deliverySnap = _asMap(m['delivery_address_snapshot']);

        final sName = (sender['name'] ?? '').toString();
        final sPhone = (sender['phone'] ?? '').toString();
        final sPickup = _asMap(sender['pickup_address']);
        final sAddrImmediate = (sPickup['detail'] ??
                sPickup['address_text'] ??
                _asMap(sender['address'])['address_text'] ??
                '')
            .toString();
        final sPickupId =
            (sender['pickup_address_id'] ?? m['pickup_address_id'] ?? '')
                .toString();

        GeoCoord? senderGeo = _extractGeo(
            sPickup['location'] ?? sPickup['geopoint'] ?? sPickup['geo']);

        final rName = (receiver['name'] ?? '').toString();
        final rPhone = (receiver['phone'] ?? '').toString();
        final rAddrImmediate = (deliverySnap['detail'] ??
                deliverySnap['address_text'] ??
                _asMap(receiver['address'])['address_text'] ??
                '')
            .toString();
        final rAddrId =
            (receiver['address_id'] ?? m['delivery_address_id'] ?? '')
                .toString();

        GeoCoord? receiverGeo = _extractGeo(
          deliverySnap['location'] ??
              deliverySnap['geopoint'] ??
              deliverySnap['geo'],
        );

        final senderAddressText = (sAddrImmediate.isNotEmpty)
            ? sAddrImmediate
            : await loadAddressTextById(sPickupId);
        final receiverAddressText = (rAddrImmediate.isNotEmpty)
            ? rAddrImmediate
            : await loadAddressTextById(rAddrId);

        if (senderGeo == null && sPickupId.isNotEmpty) {
          final snap = await _fs.collection('addressuser').doc(sPickupId).get();
          final mm = snap.data() ?? {};
          senderGeo =
              _extractGeo(mm['geopoint'] ?? mm['location'] ?? mm['geo']);
        }
        if (receiverGeo == null && rAddrId.isNotEmpty) {
          final snap = await _fs.collection('addressuser').doc(rAddrId).get();
          final mm = snap.data() ?? {};
          receiverGeo =
              _extractGeo(mm['geopoint'] ?? mm['location'] ?? mm['geo']);
        }

        return ResolvedShipment(
          id: id,
          status: statusVal,
          itemName: itemName,
          itemDesc: itemDesc,
          photoUrl: photoUrl,
          senderName: sName,
          senderPhone: sPhone,
          senderAddressText: senderAddressText,
          senderGeo: senderGeo,
          receiverName: rName,
          receiverPhone: rPhone,
          receiverAddressText: receiverAddressText,
          receiverGeo: receiverGeo,
        );
      }).toList();

      return await Future.wait(futures);
    });
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      watchShipmentPhotos({
    required String shipmentId,
    int? status,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('shipments')
        .doc(shipmentId)
        .collection('Shipment_Photo')
        .orderBy('ts', descending: true)
        .limit(limit);

    if (status != null) {
      q = q.where('status', isEqualTo: status);
    }
    return q.snapshots().map((s) => s.docs);
  }

  // ---------------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------------
  Future<void> acceptShipment({
    required String riderId,
    required String shipmentId,
  }) async {
    final riderRef = _fs.collection('riders').doc(riderId);
    final shipRef = _fs.collection('shipments').doc(shipmentId);

    await _fs.runTransaction((tx) async {
      final riderSnap = await tx.get(riderRef);
      final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
      final current = (riderData['current_shipment_id'] ?? '').toString();
      if (current.isNotEmpty) {
        throw Exception('คุณมีงานที่กำลังทำอยู่ (#$current)');
      }

      final shipSnap = await tx.get(shipRef);
      if (!shipSnap.exists) throw Exception('งานถูกลบแล้ว');
      final m = shipSnap.data() as Map<String, dynamic>;
      final s = m['status'];
      final status = (s is int) ? s : int.tryParse('$s') ?? 0;
      if (status != 1) throw Exception('งานนี้ถูกคนอื่นรับไปแล้ว');

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
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateShipmentStatus({
    required String riderId,
    required String shipmentId,
    required int fromStatus,
    required int toStatus,
    File? proofFile,
  }) async {

    String? proofUrl;
    if (proofFile != null) {
      proofUrl = await uploadProofPhoto(
        shipmentId: shipmentId,
        file: proofFile,
        updateFields: false,
        riderId: riderId,
        currentStatus: toStatus,
      );
    }

    final riderRef = _fs.collection('riders').doc(riderId);
    final shipRef = _fs.collection('shipments').doc(shipmentId);

    await _fs.runTransaction((tx) async {
      final riderSnap = await tx.get(riderRef);
      final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
      final current = (riderData['current_shipment_id'] ?? '').toString();
      if (current != shipmentId) {
        throw Exception('งานนี้ไม่ใช่งานที่ถูกล็อกอยู่ (#$current)');
      }

      final snap = await tx.get(shipRef);
      if (!snap.exists) throw Exception('เอกสารถูกลบแล้ว');
      final m = snap.data() as Map<String, dynamic>;
      final belong = (m['rider_id'] ?? '').toString();
      final s = m['status'];
      final status = (s is int) ? s : int.tryParse('$s') ?? 0;

      if (belong != riderId) throw Exception('งานนี้ไม่ใช่ของคุณ');
      if (status != fromStatus) throw Exception('สถานะเปลี่ยนไปแล้ว');

      final update = <String, dynamic>{
        'status': toStatus,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // ✅ อัปเดตเฉพาะ last_proof_url / last_proof_uploaded_at
      if (proofUrl != null && proofUrl.isNotEmpty) {
        update.addAll({
          'last_proof_url': proofUrl,
          'last_proof_uploaded_at': FieldValue.serverTimestamp(),
        });
      }

      tx.update(shipRef, update);

      if (toStatus >= 4) {
        tx.update(riderRef, {
          'current_shipment_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> returnShipment({
    required String riderId,
    required String shipmentId,
  }) async {
    final riderRef = _fs.collection('riders').doc(riderId);
    final shipRef = _fs.collection('shipments').doc(shipmentId);

    await _fs.runTransaction((tx) async {
      final riderSnap = await tx.get(riderRef);
      final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
      final current = (riderData['current_shipment_id'] ?? '').toString();
      if (current != shipmentId) {
        throw Exception('ไม่มีสิทธิ์หรือไม่มีงานนี้ในมือ');
      }

      final shipSnap = await tx.get(shipRef);
      if (!shipSnap.exists) throw Exception('งานถูกลบแล้ว');
      final m = shipSnap.data() as Map<String, dynamic>;
      final belong = (m['rider_id'] ?? '').toString();
      final s = m['status'];
      final status = (s is int) ? s : int.tryParse('$s') ?? 0;
      if (belong != riderId || (status != 2 && status != 3)) {
        throw Exception('คืนงานไม่ได้ (สถานะปัจจุบัน: $status)');
      }

      tx.update(riderRef, {
        'current_shipment_id': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      tx.update(shipRef, {
        'status': 1,
        'rider_id': FieldValue.delete(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Storage helpers (ใช้ subcollection: Shipment_Photo)
  // ---------------------------------------------------------------------------
  Future<String> uploadProofPhoto({
    required String shipmentId,
    required File file,
    bool updateFields = true,
    String? riderId,
    int? currentStatus,
  }) async {
    final path =
        'shipments/$shipmentId/status_${currentStatus ?? 0}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _st.ref(path);
    final snap = await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=0, no-cache',
      ),
    );
    final url = await snap.ref.getDownloadURL();

    // เก็บรูปเป็น document แยกใน subcollection Shipment_Photo
    await _fs
        .collection('shipments')
        .doc(shipmentId)
        .collection('Shipment_Photo')
        .add({
      'url': url,
      'by': riderId,
      'status': currentStatus ?? 0,
      'ts': FieldValue.serverTimestamp(),
      'storage_path': path,
      'type': 'proof',
    });

    // ❗️อัปเดตเฉพาะ last_proof_* (ไม่แตะ last_photo_url ที่เป็น “รูปสินค้า”)
    if (updateFields) {
      await _fs.collection('shipments').doc(shipmentId).set({
        'last_proof_url': url,
        'last_proof_uploaded_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return url;
  }

 
  final Map<String, String> _avatarCache = {}; 

  Future<DocumentSnapshot<Map<String, dynamic>>> _getUserDoc(
    String uid, {
    bool forceServer = false,
  }) {
    final ref = _fs.collection('users').doc(uid);
    if (forceServer) {
      return ref.get(const GetOptions(source: Source.server));
    }
    return ref.get();
  }

  /// อัปโหลด avatar ใหม่ (ตั้งชื่อไฟล์ใหม่ + ปิด cache) และอัปเดต users/<uid>
  Future<String> updateUserAvatar({
    required String uid,
    required File file,
  }) async {
    if (uid.isEmpty) throw ArgumentError('uid is empty');
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'users/$uid/avatar_$now.jpg';
    final ref = _st.ref(path);

    final snap = await ref.putFile(
      file,
      SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public, max-age=0, no-cache',
      ),
    );
    final url = await snap.ref.getDownloadURL();

    await _fs.collection('users').doc(uid).set({
      kAvatarUrlField: url,
      kAvatarVersionField: now,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // ล้าง cache เก่าของ uid นี้
    _avatarCache.removeWhere((k, _) => k.startsWith('uid:$uid:'));

    return _urlWithVersion(url, now);
  }


  Future<String> fetchUserPhotoByUid(String uid,
      {bool forceServer = false}) async {
    if (uid.isEmpty) return '';
    try {
      final snap = await _getUserDoc(uid, forceServer: forceServer);
      if (!snap.exists) return '';
      final m = snap.data() ?? {};
      final url = _pickAvatarUrl(m);
      final ver = m[kAvatarVersionField];
      final finalUrl = _urlWithVersion(url, ver);

      _avatarCache['uid:$uid:v:${ver ?? ''}'] = finalUrl;
      return finalUrl;
    } catch (_) {
      return '';
    }
  }

  /// ดึง avatar ตามเบอร์ (normalize + phone_to_uid + fallback)
  Future<String> fetchUserPhotoByPhone(String phone,
      {bool forceServer = false}) async {
    final p = _normalizePhone(phone);
    if (p.isEmpty) return '';
    try {
      // 1) map phone -> uid
      final map = await _fs
          .collection('phone_to_uid')
          .doc(p)
          .get(forceServer ? const GetOptions(source: Source.server) : null);
      final uid = (map.data()?['uid'] ?? '').toString();
      if (uid.isNotEmpty) {
        return fetchUserPhotoByUid(uid, forceServer: forceServer);
      }

      // 2) fallback: query users by phone
      final q = await _fs
          .collection('users')
          .where('phone', isEqualTo: p)
          .limit(1)
          .get(forceServer ? const GetOptions(source: Source.server) : null);
      if (q.docs.isNotEmpty) {
        final m = q.docs.first.data();
        final url = _pickAvatarUrl(m);
        final ver = m[kAvatarVersionField];
        return _urlWithVersion(url, ver);
      }


      final legacy = await _fs
          .collection('users')
          .doc(p)
          .get(forceServer ? const GetOptions(source: Source.server) : null);
      if (legacy.exists) {
        final m = legacy.data() ?? {};
        final url = _pickAvatarUrl(m);
        final ver = m[kAvatarVersionField];
        return _urlWithVersion(url, ver);
      }
    } catch (_) {}
    return '';
  }

  /// Stream: avatar เด้งสดด้วย uid
  Stream<String> watchUserAvatarByUid(String uid) {
    if (uid.isEmpty) return const Stream.empty();
    return _fs.collection('users').doc(uid).snapshots().map((doc) {
      final m = doc.data() ?? {};
      final url = _pickAvatarUrl(m);
      final ver = m[kAvatarVersionField];
      return _urlWithVersion(url, ver);
    });
  }

  Stream<String> watchUserAvatarByPhone(String phone) {
    final p = _normalizePhone(phone);
    if (p.isEmpty) return const Stream.empty();
    final q = _fs.collection('users').where('phone', isEqualTo: p).limit(1);
    return q.snapshots().map((s) {
      if (s.docs.isEmpty) return '';
      final m = s.docs.first.data();
      final url = _pickAvatarUrl(m);
      final ver = m[kAvatarVersionField];
      return _urlWithVersion(url, ver);
    });
  }

  Future<String> findLiveUserAvatar(
      {String? uid, String? phone, bool forceServer = false}) async {
    try {
      final u = (uid ?? '').trim();
      if (u.isNotEmpty) {
        final v = await fetchUserPhotoByUid(u, forceServer: forceServer);
        if (v.startsWith('http')) return v;
      }
      final p = _normalizePhone(phone ?? '');
      if (p.isNotEmpty) {
        final v = await fetchUserPhotoByPhone(p, forceServer: forceServer);
        if (v.startsWith('http')) return v;
      }
    } catch (_) {}
    return '';
  }
}
