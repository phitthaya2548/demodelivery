// lib/data/firebase_shipments_api.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/shipment_photo.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseShipmentsApi {
  FirebaseShipmentsApi({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _st;

  // ---------- Rider resolve config ----------
  final List<String> _riderCollections = const ['riders', 'users', 'drivers'];

  final List<String> _nameKeys = const [
    'display_name',
    'name',
    'fullname',
    'full_name',
    'username',
    'first_last',
  ];
  final List<String> _phoneKeys = const [
    'phone',
    'phone_number',
    'phoneNumber',
    'mobile',
    'tel',
  ];
  final List<String> _photoKeys = const [
    'photo_url',
    'photoUrl',
    'avatar',
    'avatar_url',
    'avatarUrl',
    'profile_url',
    'image_url',
    'photo',
  ];
  final List<String> _plateKeys = const [
    'plate',
    'plateNumber',
    'plate_number',
    'car_plate',
    'license_plate',
    'licensePlate',
  ];
  final List<String> _addressTextKeys = const [
    'current_address_text',
    'address_text',
    'current_address',
    'detail',
  ];
  final List<String> _locationKeys = const [
    'current_location',
    'location',
    'geo',
    'geopoint',
    'last_location',
    'coords',
  ];

  // ---------- Utils ----------
  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  String _pickFromKeys(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickName(Map<String, dynamic> m) {
    final s1 = _pickFromKeys(m, _nameKeys);
    if (s1.isNotEmpty) return s1;
    return _pickFromKeys(_asMap(m['profile']), _nameKeys);
  }

  String _pickPhone(Map<String, dynamic> m) {
    final s1 = _pickFromKeys(m, _phoneKeys);
    if (s1.isNotEmpty) return s1;
    return _pickFromKeys(_asMap(m['profile']), _phoneKeys);
  }

  String _pickPhoto(Map<String, dynamic> m) {
    final s1 = _pickFromKeys(m, _photoKeys);
    if (s1.isNotEmpty) return s1;
    return _pickFromKeys(_asMap(m['profile']), _photoKeys);
  }

  String _pickPlate(Map<String, dynamic> m) {
    final s1 = _pickFromKeys(m, _plateKeys);
    if (s1.isNotEmpty) return s1;
    final profile = _asMap(m['profile']);
    final s2 = _pickFromKeys(profile, _plateKeys);
    if (s2.isNotEmpty) return s2;
    for (final nest in ['vehicle', 'car', 'motorcycle', 'bike']) {
      final mm = _asMap(m[nest]);
      final s = _pickFromKeys(mm, _plateKeys);
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  String _pickAddressText(Map<String, dynamic> m) {
    final s1 = _pickFromKeys(m, _addressTextKeys);
    if (s1.isNotEmpty) return s1;
    return _pickFromKeys(_asMap(m['profile']), _addressTextKeys);
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

  GeoPoint? _pickLocation(Map<String, dynamic> m) {
    final candSources = <Map<String, dynamic>>[
      m,
      _asMap(m['profile']),
      _asMap(m['vehicle']),
      _asMap(m['car']),
      _asMap(m['motorcycle']),
    ];
    for (final src in candSources) {
      for (final k in _locationKeys) {
        final gp = _toGeoPoint(src[k]);
        if (gp != null) return gp;
      }
      final loc = src['location'];
      final gp = _toGeoPoint(loc) ?? _toGeoPoint(_asMap(loc)['geopoint']);
      if (gp != null) return gp;
    }
    return null;
  }

  /// เน้นใช้ rider_id เป็นหลัก
  String? _readShipmentRiderId(Map<String, dynamic> m) {
    final riderId = (m['rider_id'] ?? m['riderId'])?.toString().trim();
    if (riderId != null && riderId.isNotEmpty) return riderId;

    // legacy schema
    final rider = _asMap(m['rider']);
    final rs = _asMap(m['rider_snapshot']);
    final cand = <String?>[
      rider['id']?.toString(),
      rider['uid']?.toString(),
      rider['userId']?.toString(),
      rs['id']?.toString(),
      rs['uid']?.toString(),
      rs['userId']?.toString(),
    ].where((e) => (e ?? '').toString().trim().isNotEmpty).toList();
    return cand.isEmpty ? null : cand.first;
  }

  // ---------- Firestore refs ----------
  DocumentReference<Map<String, dynamic>> _shipmentRef(String id) =>
      _fs.collection('shipments').doc(id);

  // ---------------- Streams ----------------
  Stream<QuerySnapshot<Map<String, dynamic>>> watchSent(String meAny) {
    return _fs
        .collection('shipments')
        .where('sender_id', isEqualTo: meAny)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchReceived({
    required String uid,
    required String phone,
  }) {
    final col = _fs.collection('shipments');
    if (uid.isNotEmpty) {
      return col.where('receiver_id', isEqualTo: uid).snapshots();
    }
    return col.where('receiver_snapshot.phone', isEqualTo: phone).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchShipment(String id) {
    return _shipmentRef(id).snapshots();
  }

  // ---------- รูป: แปลงให้เป็น downloadURL ก่อน ----------
  bool _isHttp(String s) => s.startsWith('http://') || s.startsWith('https://');

  Future<String> _resolveDownloadUrl(String raw) async {
    final v = raw.trim();
    if (v.isEmpty) return '';
    if (_isHttp(v)) return v;
    try {
      if (v.startsWith('gs://')) {
        final ref = _st.refFromURL(v);
        return await ref.getDownloadURL();
      } else {
        final ref = _st.ref(v);
        return await ref.getDownloadURL();
      }
    } catch (_) {
      return '';
    }
  }

  String _extractRawUrl(Map<String, dynamic> m) {
    for (final k in const [
      'url',
      'photo_url',
      'image_url',
      'downloadURL',
      'download_url',
      'path',
      'storage_path',
      'filePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// ✅ รวมรูปจากทั้ง `photos` (เก่า) และ `Shipment_Photo` (ไรเดอร์อัปโหลด)
  ///    และทำให้ field `url` เป็น https พร้อมใช้งานเสมอ
  Stream<List<ShipmentPhoto>> watchShipmentPhotos(String id,
      {int limit = 120}) {
    final sPhotos = _shipmentRef(id)
        .collection('photos')
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots();

    final sProofs = _shipmentRef(id)
        .collection('Shipment_Photo')
        .orderBy('ts', descending: true)
        .limit(limit)
        .snapshots();

    return Stream<List<ShipmentPhoto>>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? a;
      QuerySnapshot<Map<String, dynamic>>? b;

      Future<void> push() async {
        if (a == null && b == null) return;

        final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
          ...?a?.docs,
          ...?b?.docs,
        ];

        final futures = allDocs.map((d) async {
          final photo = ShipmentPhoto.fromDoc(d);

          // ดึง url ดิบจาก data หาก url ในโมเดลยังไม่เป็น http(s)
          String raw = photo.url;
          if (raw.isEmpty || !_isHttp(raw)) {
            raw = _extractRawUrl(d.data());
          }
          final resolved = await _resolveDownloadUrl(raw);

          // บางเอกสารอาจไม่มี status → ยังคงค่าเดิมในโมเดล (หรือ 0)
          final stRaw = d.data()['status'];
          final st =
              (stRaw is int) ? stRaw : int.tryParse('$stRaw') ?? photo.status;

          return photo.copyWith(url: resolved, status: st);
        }).toList();

        final list = await Future.wait(futures);

        // (ถ้าต้องการเรียงตาม ts จริง ๆ และโมเดลมีฟิลด์ ts ให้ sort ตรงนี้)

        controller.add(list);
      }

      final subA = sPhotos.listen((v) {
        a = v;
        push();
      }, onError: controller.addError);
      final subB = sProofs.listen((v) {
        b = v;
        push();
      }, onError: controller.addError);

      controller.onCancel = () {
        subA.cancel();
        subB.cancel();
      };
    });
  }

  Future<List<ShipmentPhoto>> getShipmentPhotosOnce(String id,
      {int limit = 120}) async {
    final q1 = await _shipmentRef(id)
        .collection('photos')
        .orderBy('ts', descending: true)
        .limit(limit)
        .get();

    final q2 = await _shipmentRef(id)
        .collection('Shipment_Photo')
        .orderBy('ts', descending: true)
        .limit(limit)
        .get();

    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
      ...q1.docs,
      ...q2.docs,
    ];

    final futures = allDocs.map((d) async {
      final photo = ShipmentPhoto.fromDoc(d);
      String raw = photo.url;
      if (raw.isEmpty || !_isHttp(raw)) {
        raw = _extractRawUrl(d.data());
      }
      final resolved = await _resolveDownloadUrl(raw);

      final stRaw = d.data()['status'];
      final st =
          (stRaw is int) ? stRaw : int.tryParse('$stRaw') ?? photo.status;

      return photo.copyWith(url: resolved, status: st);
    }).toList();

    final list = await Future.wait(futures);

    // (option) sort ตามเวลา ถ้าโมเดลมี ts
    return list;
  }

  // ---------------- Users / Address helpers ----------------
  Future<String?> resolveUidByPhone(String phone) async {
    final map = await _fs.collection('phone_to_uid').doc(phone).get();
    final mapped = (map.data()?['uid'] ?? '').toString();
    if (mapped.isNotEmpty) return mapped;

    final q = await _fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first.id;

    final legacy = await _fs.collection('users').doc(phone).get();
    if (legacy.exists) return phone;

    return null;
  }

  Future<Map<String, dynamic>?> loadUserProfile(String uid) async {
    final snap = await _fs.collection('users').doc(uid).get();
    return snap.data();
  }

  Future<List<Map<String, dynamic>>> loadUserAddresses({
    required String uid,
    required String phone,
  }) async {
    final list = <Map<String, dynamic>>[];

    final sub =
        await _fs.collection('users').doc(uid).collection('addresses').get();
    if (sub.docs.isNotEmpty) {
      for (final d in sub.docs) {
        list.add({'id': d.id, ...d.data()});
      }
    } else {
      final byUid = await _fs
          .collection('addressuser')
          .where('userId', isEqualTo: uid)
          .get();
      final docs = byUid.docs.isNotEmpty
          ? byUid.docs
          : (await _fs
                  .collection('addressuser')
                  .where('userId', isEqualTo: phone)
                  .get())
              .docs;
      for (final d in docs) {
        list.add({'id': d.id, ...d.data()});
      }
    }

    list.sort((a, b) {
      final da = (a['is_default'] == true) ? 0 : 1;
      final db = (b['is_default'] == true) ? 0 : 1;
      if (da != db) return da.compareTo(db);
      int ts(x) => x is Timestamp ? x.millisecondsSinceEpoch : 0;
      return ts(b['created_at']).compareTo(ts(a['created_at']));
    });

    return list;
  }

  Future<Map<String, dynamic>?> getSenderDefaultAddress({
    required String uid,
    required String phone,
  }) async {
    if (uid.isEmpty && phone.isEmpty) return null;

    final byUid = await _fs
        .collection('addressuser')
        .where('userId', isEqualTo: uid)
        .get();
    QuerySnapshot<Map<String, dynamic>>? byPhone;
    if (byUid.docs.isEmpty && phone.isNotEmpty) {
      byPhone = await _fs
          .collection('addressuser')
          .where('userId', isEqualTo: phone)
          .get();
    }

    final docs = byUid.docs.isNotEmpty ? byUid.docs : (byPhone?.docs ?? []);
    if (docs.isEmpty) return null;

    docs.sort((a, b) {
      final da = ((a.data()['is_default'] ?? false) == true) ? 0 : 1;
      final db = ((b.data()['is_default'] ?? false) == true) ? 0 : 1;
      if (da != db) return da.compareTo(db);
      int ts(d) => d is Timestamp ? d.millisecondsSinceEpoch : 0;
      return ts(b.data()['created_at']).compareTo(ts(a.data()['created_at']));
    });

    final d = docs.first;
    return {'id': d.id, ...d.data()};
  }

  // ---------------- Storage ----------------
  Future<String?> uploadItemPhoto(String parentId, File file) async {
    final path =
        'shipments/$parentId/item_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _st.ref(path);
    final snap =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await snap.ref.getDownloadURL();
  }

  // ---------------- สร้าง/แก้ไข Shipments ----------------
  Future<String> createShipment({
    required String senderId,
    required String receiverId,
    String? pickupAddressId,
    String? deliveryAddressId,
    required String itemName,
    String? itemDescription,
    Map<String, dynamic>? senderSnapshot,
    Map<String, dynamic>? receiverSnapshot,
    Map<String, dynamic>? deliveryAddressSnapshot,
    File? photoFile,
  }) async {
    final shipments = _fs.collection('shipments');
    final docRef = shipments.doc();
    final now = FieldValue.serverTimestamp();

    await docRef.set({
      'id': docRef.id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      if (pickupAddressId != null) 'pickup_address_id': pickupAddressId,
      if (deliveryAddressId != null) 'delivery_address_id': deliveryAddressId,
      'item_name': itemName,
      'item_description': (itemDescription ?? '').trim(),
      'status': 1,
      'created_at': now,
      'updated_at': now,
      if (senderSnapshot != null) 'sender_snapshot': senderSnapshot,
      if (receiverSnapshot != null) 'receiver_snapshot': receiverSnapshot,
      if (deliveryAddressSnapshot != null)
        'delivery_address_snapshot': deliveryAddressSnapshot,
      'item_photo_url': '',
      'last_photo_url': '',
      'last_photo_uploaded_at': null,
      'last_proof_url': '',
    });

    if (photoFile != null) {
      final url = await uploadItemPhoto(docRef.id, photoFile);
      if (url != null) {
        await docRef.update({
          'item_photo_url': url,
          'last_photo_url': url,
          'last_photo_uploaded_at': now,
          'updated_at': now,
        });
      }
    }

    return docRef.id;
  }

  Future<String> createDraft({
    required String senderId,
    required String receiverId,
    String? pickupAddressId,
    String? deliveryAddressId,
    required String itemName,
    String? itemDescription,
    Map<String, dynamic>? senderSnapshot,
    Map<String, dynamic>? receiverSnapshot,
    Map<String, dynamic>? deliveryAddressSnapshot,
    File? photoFile, // รูปสินค้าเริ่มต้น
  }) async {
    final shipments = _fs.collection('shipments');
    final docRef = shipments.doc();
    final now = FieldValue.serverTimestamp();

    String photoUrl = '';
    if (photoFile != null) {
      final url = await uploadItemPhoto(docRef.id, photoFile);
      if (url != null) photoUrl = url;
    }

    await docRef.set({
      'id': docRef.id,
      'status': 0, // draft
      'sender_id': senderId,
      'receiver_id': receiverId,
      if (pickupAddressId != null) 'pickup_address_id': pickupAddressId,
      if (deliveryAddressId != null) 'delivery_address_id': deliveryAddressId,
      'item_name': itemName,
      'item_description': (itemDescription ?? '').trim(),
      'created_at': now,
      'updated_at': now,
      if (senderSnapshot != null) 'sender_snapshot': senderSnapshot,
      if (receiverSnapshot != null) 'receiver_snapshot': receiverSnapshot,
      if (deliveryAddressSnapshot != null)
        'delivery_address_snapshot': deliveryAddressSnapshot,

      'item_photo_url': photoUrl,
      'last_photo_url': photoUrl, // (legacy) คงไว้
      'last_photo_uploaded_at': photoUrl.isEmpty ? null : now,
      'last_proof_url': '',
    });

    return docRef.id;
  }

  Future<int> confirmAllDraftsOf(String senderId) async {
    final q = await _fs
        .collection('shipments')
        .where('sender_id', isEqualTo: senderId)
        .where('status', isEqualTo: 0)
        .get();

    if (q.docs.isEmpty) return 0;

    final now = FieldValue.serverTimestamp();
    final batch = _fs.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'status': 1, 'updated_at': now});
    }
    await batch.commit();
    return q.docs.length;
  }

  Future<int> countDraftsOf(String senderId) async {
    final q = await _fs
        .collection('shipments')
        .where('sender_id', isEqualTo: senderId)
        .where('status', isEqualTo: 0)
        .get();
    return q.docs.length;
  }

  // ---------------- One-shot reads ----------------
  Future<Map<String, dynamic>?> getShipment(String id) async {
    final snap = await _shipmentRef(id).get();
    return snap.data();
  }

  Future<bool> shipmentExists(String id) async {
    final snap = await _shipmentRef(id).get();
    return snap.exists;
  }

  // ====== NEW: ดึงไรเดอร์ด้วย id โดยตรง ======
  Future<RiderResolved?> resolveRiderById(String riderId) async {
    if (riderId.isEmpty) return null;
    final fetched = await _fetchRiderById(riderId);
    if (fetched == null) return null;

    final m = fetched.data;
    return RiderResolved(
      riderId: riderId,
      name: _pickName(m).isEmpty ? '-' : _pickName(m),
      phone: _pickPhone(m).isEmpty ? '-' : _pickPhone(m),
      avatarUrl: _pickPhoto(m),
      plateNumber: _pickPlate(m),
      addressText: _pickAddressText(m),
      location: _pickLocation(m),
      sourceDocPath: fetched.path,
    );
  }

  /// ดึงข้อมูลไรเดอร์จาก shipment map:
  /// 1) ถ้ามี rider_id → ดึงเอกสารไรเดอร์ (return ทันที)
  /// 2) ไม่มี/หาไม่เจอ → fallback rider_snapshot (หรือค้นต่อด้วย phone)
  Future<RiderResolved> resolveRiderForShipmentMap(
      Map<String, dynamic> shipment) async {
    final m = _asMap(shipment);

    // 1) ใช้ rider_id ก่อน
    final riderId = _readShipmentRiderId(m);
    if (riderId != null && riderId.isNotEmpty) {
      final byId = await resolveRiderById(riderId);
      if (byId != null) return byId;
    }

    // 2) fallback: snapshot
    final rs = _asMap(m['rider_snapshot']);
    String name = _pickName(rs);
    String phone = _pickPhone(rs);
    String avatar = _pickPhoto(rs);
    String plate = _pickPlate(rs);
    String addrText = _pickAddressText(rs);
    GeoPoint? gp = _pickLocation(rs);

    // 3) ถ้ายังว่าง ลองค้นด้วย phone
    if ((name + phone + avatar + plate).isEmpty) {
      final sp = _pickPhone(rs);
      if (sp.isNotEmpty) {
        final fetched = await _fetchRiderByPhone(sp);
        if (fetched != null) {
          final fm = fetched.data;
          name = _pickName(fm);
          phone = _pickPhone(fm);
          avatar = _pickPhoto(fm);
          plate = _pickPlate(fm);
          addrText = _pickAddressText(fm);
          gp = _pickLocation(fm);
          return RiderResolved(
            riderId: null,
            name: name.isEmpty ? '-' : name,
            phone: phone.isEmpty ? '-' : phone,
            avatarUrl: avatar,
            plateNumber: plate,
            addressText: addrText,
            location: gp,
            sourceDocPath: fetched.path,
          );
        }
      }
    }

    return RiderResolved(
      riderId: riderId,
      name: name.isEmpty ? '-' : name,
      phone: phone.isEmpty ? '-' : phone,
      avatarUrl: avatar,
      plateNumber: plate,
      addressText: addrText,
      location: gp,
      sourceDocPath:
          (riderId != null) ? 'rider_snapshot + $riderId' : 'rider_snapshot',
    );
  }

  /// ดึงข้อมูลไรเดอร์จาก shipment id
  Future<RiderResolved> resolveRiderForShipmentId(String shipmentId) async {
    final snap = await _shipmentRef(shipmentId).get();
    final data = snap.data() ?? {};
    return resolveRiderForShipmentMap(data);
  }

  /// สตรีมตำแหน่งไรเดอร์จาก riderId
  Stream<GeoPoint?> watchRiderLocation(String riderId) {
    if (riderId.isEmpty) return const Stream<GeoPoint?>.empty();
    return _fs.collection('riders').doc(riderId).snapshots().map((d) {
      final m = _asMap(d.data());
      return _pickLocation(m);
    });
  }

  Stream<GeoPoint?> watchRiderLocationByShipment(String shipmentId) {
    return _shipmentRef(shipmentId).snapshots().asyncMap((snap) async {
      final m = _asMap(snap.data());
      final riderId = _readShipmentRiderId(m) ?? '';
      if (riderId.isEmpty) return null;
      final doc = await _fs.collection('riders').doc(riderId).get();
      return _pickLocation(_asMap(doc.data()));
    });
  }

  // ---------- private fetchers ----------
  Future<_DocWithPath?> _fetchRiderById(String id) async {
    for (final col in _riderCollections) {
      try {
        final doc = await _fs.collection(col).doc(id).get();
        if (doc.exists) return _DocWithPath(doc.data()!, '$col/${doc.id}');
      } catch (_) {}
    }
    return null;
  }

  Future<_DocWithPath?> _fetchRiderByPhone(String phone) async {
    if (phone.isEmpty) return null;
    for (final col in _riderCollections) {
      try {
        final qs = await _fs
            .collection(col)
            .where('phone', isEqualTo: phone)
            .limit(1)
            .get();
        if (qs.docs.isNotEmpty) {
          final d = qs.docs.first;
          return _DocWithPath(d.data(), '$col/${d.id}');
        }
        final qs2 = await _fs
            .collection(col)
            .where('phoneNumber', isEqualTo: phone)
            .limit(1)
            .get();
        if (qs2.docs.isNotEmpty) {
          final d = qs2.docs.first;
          return _DocWithPath(d.data(), '$col/${d.id}');
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> deleteShipmentIfCompleted(String shipmentId) async {
    try {
      // หาทางไปยังเอกสารที่เราต้องการลบใน Firestore
      final shipmentRef =
          FirebaseFirestore.instance.collection('shipments').doc(shipmentId);

      // ลบเอกสาร
      await shipmentRef.delete();

      print('Shipment $shipmentId has been deleted successfully');
    } catch (e) {
      print('Error deleting shipment: $e');
    }
  }
}

class _DocWithPath {
  final Map<String, dynamic> data;
  final String path;
  _DocWithPath(this.data, this.path);
}

class RiderResolved {
  final String? riderId;
  final String name;
  final String phone;
  final String avatarUrl;
  final String plateNumber;
  final String addressText;
  final GeoPoint? location;
  final String? sourceDocPath;

  const RiderResolved({
    required this.riderId,
    required this.name,
    required this.phone,
    required this.avatarUrl,
    required this.plateNumber,
    required this.addressText,
    required this.location,
    this.sourceDocPath,
  });
}