// lib/data/firebase_rider_profile_api.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class FirebaseRiderProfileApi {
  FirebaseRiderProfileApi({FirebaseFirestore? firestore})
      : _fs = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _fs;

  Future<DocumentReference<Map<String, dynamic>>?> findRiderDocRef({
    required String userId,
    required String phoneId,
  }) async {
    final col = _fs.collection('riders');
    final uid = userId.trim();
    final ph = phoneId.trim();

    if (uid.isNotEmpty) {
      final byId = await col.doc(uid).get();
      if (byId.exists) return byId.reference;

      final byField = await col.where('userId', isEqualTo: uid).limit(1).get();
      if (byField.docs.isNotEmpty) return byField.docs.first.reference;
    }

    if (ph.isNotEmpty) {
      final byPhoneDoc = await col.doc(ph).get();
      if (byPhoneDoc.exists) return byPhoneDoc.reference;

      final byUserId = await col.where('userId', isEqualTo: ph).limit(1).get();
      if (byUserId.docs.isNotEmpty) return byUserId.docs.first.reference;

      final byPhoneField =
          await col.where('phoneNumber', isEqualTo: ph).limit(1).get();
      if (byPhoneField.docs.isNotEmpty)
        return byPhoneField.docs.first.reference;
    }

    return null;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchRiderDoc(
      DocumentReference<Map<String, dynamic>> ref) {
    return ref.snapshots();
  }

  Future<String> fallbackUserName(String uidOrPhone) async {
    if (uidOrPhone.trim().isEmpty) return '';
    try {
      final u = await _fs.collection('users').doc(uidOrPhone).get();
      final m = u.data() ?? {};
      return (m['name'] ?? m['fullname'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> updateRiderByRef(
    DocumentReference<Map<String, dynamic>> ref, {
    String? name,
    String? phoneNumber,
    String? plateNumber,
    String? avatarUrl,
    String? vehiclePhotoUrl,
    Map<String, dynamic>? extra,
  }) async {
    final data = <String, dynamic>{
      if (name != null) 'name': name.trim(),
      if (phoneNumber != null) 'phoneNumber': _normalizePhone(phoneNumber),
      if (plateNumber != null) 'plateNumber': plateNumber.trim(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl.trim(),
      if (vehiclePhotoUrl != null) 'vehiclePhotoUrl': vehiclePhotoUrl.trim(),
      'updated_at': FieldValue.serverTimestamp(),
      ...?extra,
    };

    if (data.containsKey('phoneNumber')) {
      final ok = _validPhone(data['phoneNumber'] as String);
      if (!ok) {
        throw 'รูปแบบเบอร์โทรไม่ถูกต้อง';
      }
    }

    await ref.update(data);
  }
  Future<void> updateRiderById(
    String riderDocId, {
    String? name,
    String? phoneNumber,
    String? plateNumber,
    String? avatarUrl,
    String? vehiclePhotoUrl,
    Map<String, dynamic>? extra,
  }) async {
    final ref = _fs.collection('riders').doc(riderDocId.trim());
    await updateRiderByRef(
      ref,
      name: name,
      phoneNumber: phoneNumber,
      plateNumber: plateNumber,
      avatarUrl: avatarUrl,
      vehiclePhotoUrl: vehiclePhotoUrl,
      extra: extra,
    );
  }

  /// อัปเดตโดยค้นหาเอกสารจาก session (userId/phoneId) ภายใน
  Future<void> updateRiderFromSession({
    required String userId,
    required String phoneId,
    String? name,
    String? phoneNumber,
    String? plateNumber,
    String? avatarUrl,
    String? vehiclePhotoUrl,
    Map<String, dynamic>? extra,
  }) async {
    final ref = await findRiderDocRef(userId: userId, phoneId: phoneId);
    if (ref == null) throw 'ไม่พบเอกสารไรเดอร์จาก session';
    await updateRiderByRef(
      ref,
      name: name,
      phoneNumber: phoneNumber,
      plateNumber: plateNumber,
      avatarUrl: avatarUrl,
      vehiclePhotoUrl: vehiclePhotoUrl,
      extra: extra,
    );
  }

  Future<void> setAvatarUrlByRef(
      DocumentReference<Map<String, dynamic>> ref, String url) {
    return updateRiderByRef(ref, avatarUrl: url);
  }

  Future<void> setVehiclePhotoUrlByRef(
      DocumentReference<Map<String, dynamic>> ref, String url) {
    return updateRiderByRef(ref, vehiclePhotoUrl: url);
  }

  Future<void> setPlateNumberByRef(
      DocumentReference<Map<String, dynamic>> ref, String plate) {
    return updateRiderByRef(ref, plateNumber: plate);
  }
  String _normalizePhone(String raw) {
    final s = raw.trim();
    final digits = s.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^66\d+$').hasMatch(digits)) return '+$digits';
    return digits;
  }

  bool _validPhone(String s) {
    
    final re = RegExp(r'^(0\d{9}|\+?66\d{8,10})$');
    return re.hasMatch(s);
  }
}
