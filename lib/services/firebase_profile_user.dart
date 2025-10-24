import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/sesstion.dart';

/// รวมทุกการติดต่อ Firestore ของหน้าผู้ใช้ให้อยู่ที่เดียว
class UserRepository {
  final FirebaseFirestore _fs;

  UserRepository({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  Future<String?> resolveUidSmart() async {
    // 1) จาก session
    final ssUid = SessionStore.userId;
    if (ssUid != null && ssUid.isNotEmpty) {
      final ok = await _fs.collection('users').doc(ssUid).get();
      if (ok.exists) return ssUid;
    }

    // 2) จาก mapping phone_to_uid
    final phone = SessionStore.phoneId;
    if (phone != null && phone.isNotEmpty) {
      final map = await _fs.collection('phone_to_uid').doc(phone).get();
      final uidFromMap = (map.data()?['uid'] ?? '').toString();
      if (uidFromMap.isNotEmpty) {
        final ok = await _fs.collection('users').doc(uidFromMap).get();
        if (ok.exists) return uidFromMap;
      }

      // 3) query users ด้วย phone
      final q = await _fs
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      // 4) fallback เอกสารเก่า users/{phone}
      final legacy = await _fs.collection('users').doc(phone).get();
      if (legacy.exists) return phone;
    }

    return null;
  }

  /// stream เอกสารผู้ใช้
  Stream<DocumentSnapshot<Map<String, dynamic>>> userDocStream(String uid) {
    return _fs.collection('users').doc(uid).snapshots();
  }

  /// stream รายการที่อยู่จากคอลเลกชันราก `addressuser` ที่ userId = uid
  Stream<QuerySnapshot<Map<String, dynamic>>> addressesStream(String uid) {
    return _fs
        .collection('addressuser')
        .where('userId', isEqualTo: uid)
        .snapshots();
  }

  Future<void> updateUserProfile(
    String uid, {
    String? name,
    String? phone,
    String? photoUrl,
  }) async {
    final data = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': phone.trim(),
      if (photoUrl != null) 'photoUrl': photoUrl.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    };

    final ref = _fs.collection('users').doc(uid);
    try {
      await ref.update(data);
    } catch (_) {
      await ref.set(data, SetOptions(merge: true)); 
    }

    if (phone != null && phone.trim().isNotEmpty) {
      await _fs
          .collection('phone_to_uid')
          .doc(phone.trim())
          .set({'uid': uid}, SetOptions(merge: true));
    }
  }

  /// เพิ่มที่อยู่ใหม่ลงคอลเลกชันราก `addressuser` (แนวเรียบง่าย)
  Future<String> addAddress({
    required String uid,
    required String label,
    required String detail,
    String? phone,
    GeoPoint? location,
    bool isDefault = false,
  }) async {
    final ref = _fs.collection('addressuser').doc();
    final now = FieldValue.serverTimestamp();

    // ถ้าจะตั้งเป็นค่าเริ่มต้น ต้องเคลียร์อันเก่าให้ไม่ default ก่อน
    if (isDefault) {
      await _unsetDefaultAddresses(uid);
    }

    await ref.set({
      'userId': uid,
      'label': label.trim(),
      'detail': detail.trim(),
      if (phone != null) 'phone': phone.trim(),
      if (location != null) 'location': location,
      'is_default': isDefault,
      'created_at': now,
      'updated_at': now,
    });

    return ref.id;
  }

  /// แก้ไขที่อยู่ (partial update)
  Future<void> updateAddress({
    required String addressId,
    String? label,
    String? detail,
    String? phone,
    GeoPoint? location,
    bool? isDefault, // ส่ง true เพื่อทำเป็นค่าเริ่มต้น
  }) async {
    final ref = _fs.collection('addressuser').doc(addressId);

    // ถ้าจะตั้ง default ให้ตัวนี้ → เคลียร์ของเดิมของ user นี้ก่อน
    if (isDefault == true) {
      final snap = await ref.get();
      final uid = (snap.data()?['userId'] ?? '').toString();
      if (uid.isNotEmpty) {
        await _unsetDefaultAddresses(uid);
      }
    }

    await ref.update({
      if (label != null) 'label': label.trim(),
      if (detail != null) 'detail': detail.trim(),
      if (phone != null) 'phone': phone.trim(),
      if (location != null) 'location': location,
      if (isDefault != null) 'is_default': isDefault,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// ลบที่อยู่
  Future<void> deleteAddress(String addressId) async {
    await _fs.collection('addressuser').doc(addressId).delete();
  }

  /// ตั้งที่อยู่ใด ๆ ให้เป็นค่าเริ่มต้น (ตัวอื่นของ user จะถูกปรับเป็น false ทั้งหมด)
  Future<void> setDefaultAddress({
    required String uid,
    required String addressId,
  }) async {
    await _unsetDefaultAddresses(uid);
    await _fs.collection('addressuser').doc(addressId).update({
      'is_default': true,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// เคลียร์ default ทั้งหมดของผู้ใช้ (ภายในใช้ batch)
  Future<void> _unsetDefaultAddresses(String uid) async {
    final q = await _fs
        .collection('addressuser')
        .where('userId', isEqualTo: uid)
        .where('is_default', isEqualTo: true)
        .get();

    if (q.docs.isEmpty) return;
    final batch = _fs.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {
        'is_default': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}
