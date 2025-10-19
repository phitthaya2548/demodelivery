
import 'package:cloud_firestore/cloud_firestore.dart';

class AddressRepository {
  AddressRepository({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;


  Future<String?> resolveUidSmart({
    required String? sessionUserId,
    required String? sessionPhone,
  }) async {
    if (sessionUserId != null && sessionUserId.isNotEmpty) {
      final ok = await _fs.collection('users').doc(sessionUserId).get();
      if (ok.exists) return sessionUserId;
    }
    if (sessionPhone != null && sessionPhone.isNotEmpty) {
      final map = await _fs.collection('phone_to_uid').doc(sessionPhone).get();
      final mapped = (map.data()?['uid'] ?? '').toString();
      if (mapped.isNotEmpty) {
        final ok = await _fs.collection('users').doc(mapped).get();
        if (ok.exists) return mapped;
      }


      final q = await _fs
          .collection('users')
          .where('phone', isEqualTo: sessionPhone)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      final legacy = await _fs.collection('users').doc(sessionPhone).get();
      if (legacy.exists) return sessionPhone;
    }

    return null;
  }
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAddresses(String uid) {
    return _fs
        .collection('addressuser')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }


  Future<void> deleteAddress(String addressId) async {
    await _fs.collection('addressuser').doc(addressId).delete();
  }
  Future<void> setDefaultAddress(String uid, String addressId) async {
    final col = _fs.collection('addressuser');
    final batch = _fs.batch();
    final all = await col.where('userId', isEqualTo: uid).get();
    for (final d in all.docs) {
      batch.update(d.reference, {'is_default': d.id == addressId});
    }
    await batch.commit();
  }

  /// เพิ่มที่อยู่ใหม่ (รองรับใส่ lat/lng/GeoPoint ถ้ามี) และถ้าขอตั้ง default ก็จัดให้
  Future<void> addAddress({
    required String uid,
    required Map<String, dynamic> payload, // แปลงมาจาก model แล้ว
    required bool setDefault,
  }) async {
    final col = _fs.collection('addressuser');
    final now = FieldValue.serverTimestamp();

    final docRef = await col.add({
      ...payload,
      'userId': uid,
      'created_at': now,
      'updated_at': now,
    });

    if (setDefault) {
      final batch = _fs.batch();
      final all = await col.where('userId', isEqualTo: uid).get();
      for (final d in all.docs) {
        batch.update(d.reference, {'is_default': d.id == docRef.id});
      }
      await batch.commit();
    }
  }
}
