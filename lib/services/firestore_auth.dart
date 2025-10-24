import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class AuthResult {
  final bool ok;
  final String? uid;
  final String role;
  final String phone;
  final String name;
  final String avatarUrl;
  final String? error;

  const AuthResult({
    required this.ok,
    required this.uid,
    required this.role,
    required this.phone,
    required this.name,
    required this.avatarUrl,
    this.error,
  });
}

class FirestoreAuthRepo {
  final FirebaseFirestore fs;
  FirestoreAuthRepo({FirebaseFirestore? instance})
      : fs = instance ?? FirebaseFirestore.instance;

  String _normalizePhone(String s) {
    final only = s.replaceAll(RegExp(r'\D'), '');
    if (only.startsWith('66') && only.length >= 11) {
      return '0${only.substring(2)}';
    }
    return only;
  }

  String _sha256(String s) => sha256.convert(utf8.encode(s)).toString();
  String _hashWithPhone(String pass, String phone) => _sha256('$phone::$pass');

  T? _pick<T>(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) return v as T;
    }
    return null;
  }
  // ===========================================

  /// 1) แปลง phone -> uid (ครอบคลุมหลายสคีมา)
  Future<String?> _resolveUidByPhone(String phone) async {
    // phone_to_uid
    final map = await fs.collection('phone_to_uid').doc(phone).get();
    final mapped = (map.data()?['uid'] ?? '').toString();
    if (mapped.isNotEmpty) return mapped;

    // users (id = uid)
    final uq = await fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (uq.docs.isNotEmpty) return uq.docs.first.id;

    // users legacy: users/{phone}
    final legacy = await fs.collection('users').doc(phone).get();
    if (legacy.exists) return phone;

    // riders: phoneNumber -> userId/uid
    final rq1 = await fs
        .collection('riders')
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();
    if (rq1.docs.isNotEmpty) {
      final m = rq1.docs.first.data();
      final uid = (m['userId'] ?? '').toString();
      if (uid.isNotEmpty) return uid;
      return rq1.docs.first.id;
    }

    // เผื่อใส่ uid มาในช่องเบอร์
    final rq2 = await fs
        .collection('riders')
        .where('userId', isEqualTo: phone)
        .limit(1)
        .get();
    if (rq2.docs.isNotEmpty) {
      final m = rq2.docs.first.data();
      final uid = (m['userId'] ?? '').toString();
      if (uid.isNotEmpty) return uid;
      return rq2.docs.first.id;
    }

    // เผื่อ docId == phone
    final rdoc = await fs.collection('riders').doc(phone).get();
    if (rdoc.exists) {
      final m = rdoc.data() ?? {};
      final uid = (m['userId'] ?? '').toString();
      return uid.isNotEmpty ? uid : rdoc.id;
    }

    return null;
  }

  /// 2) users/{uid} (พร้อม fallback users/{phone}, where(phone==))
  Future<DocumentSnapshot<Map<String, dynamic>>?> _getUserSnapByUidOrPhone(
      String uid, String phone) async {
    var snap = await fs.collection('users').doc(uid).get();
    if (snap.exists) return snap;

    if (uid != phone) {
      snap = await fs.collection('users').doc(phone).get();
      if (snap.exists) return snap;
    }

    final q = await fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first;

    return null;
  }

  /// 3) หา rider จาก uid/phone (ครอบคลุมทุกเคส)
  Future<(bool isRider, DocumentSnapshot<Map<String, dynamic>>?)>
      _findRiderByUidOrPhone(String uid, String phone) async {
    // riders/{uid}
    var snap = await fs.collection('riders').doc(uid).get();
    if (snap.exists) return (true, snap);

    // userId == uid
    final q1 = await fs
        .collection('riders')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return (true, q1.docs.first);

    // userId == phone
    final q2 = await fs
        .collection('riders')
        .where('userId', isEqualTo: phone)
        .limit(1)
        .get();
    if (q2.docs.isNotEmpty) return (true, q2.docs.first);

    // phoneNumber == phone
    final q3 = await fs
        .collection('riders')
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();
    if (q3.docs.isNotEmpty) return (true, q3.docs.first);

    // docId == phone
    snap = await fs.collection('riders').doc(phone).get();
    if (snap.exists) return (true, snap);

    return (false, null);
  }

  // --- 4) [REFACTORED] ---
  /// ตรวจสอบรหัสผ่านสำหรับ entity เดียว (user หรือ rider)
  bool _verifyPasswordForEntity({
    required Map<String, dynamic> entity,
    required String pass,
    required String phone,
  }) {
    if (entity.isEmpty) {
      return false;
    }

    final storedHash =
        _pick<String>(entity, ['passwordHash', 'password_hash']) ?? '';
    final storedPlain = _pick<String>(entity, ['password']) ?? '';

    // The three verification methods
    final bool hashWithPhoneMatches =
        (storedHash.isNotEmpty && storedHash == _hashWithPhone(pass, phone));
    final bool genericHashMatches =
        (storedHash.isNotEmpty && storedHash == _sha256(pass));
    final bool plainTextMatches =
        (storedPlain.isNotEmpty && storedPlain == pass);

    return hashWithPhoneMatches || genericHashMatches || plainTextMatches;
  }
  // -------------------------

  Future<AuthResult> loginWithPhonePassword({
    required String phoneInput,
    required String password,
  }) async {
    final phone = _normalizePhone(phoneInput.trim());
    if (phone.isEmpty) {
      return const AuthResult(
        ok: false,
        uid: null,
        role: 'USER',
        phone: '',
        name: '',
        avatarUrl: '',
        error: 'กรอกเบอร์โทร',
      );
    }
    if (password.isEmpty) {
      return AuthResult(
        ok: false,
        uid: null,
        role: 'USER',
        phone: phone,
        name: '',
        avatarUrl: '',
        error: 'กรอกรหัสผ่าน',
      );
    }

    final uid = await _resolveUidByPhone(phone);
    if (uid == null) {
      return AuthResult(
        ok: false,
        uid: null,
        role: 'USER',
        phone: phone,
        name: '',
        avatarUrl: '',
        error: 'ไม่พบผู้ใช้เบอร์นี้',
      );
    }

    // Get user data
    final userSnap = await _getUserSnapByUidOrPhone(uid, phone);
    final user = userSnap?.data() ?? {};

    // Get rider data
    final (isRider, riderSnap) = await _findRiderByUidOrPhone(uid, phone);
    final rider = riderSnap?.data() ?? {};

    // --- 5) [REFACTORED LOGIC] ---

    // 5.1) ตรวจสอบรหัสผ่านสำหรับ User ก่อน
    final passOkForUser = _verifyPasswordForEntity(
      entity: user,
      pass: password.trim(),
      phone: phone,
    );

    if (passOkForUser) {
      // ถ้าตรง ให้ล็อกอินเป็น USER
      final role = 'USER';
      final base = user;
      final name = _pick<String>(base, ['name', 'fullname']) ??
          _pick<String>(user, ['name', 'fullname']) ??
          '';
      final avatarUrl = _pick<String>(base, ['avatarUrl', 'photoUrl']) ??
          _pick<String>(user, ['avatarUrl', 'photoUrl']) ??
          '';

      return AuthResult(
        ok: true,
        uid: uid,
        role: role,
        phone: phone,
        name: name,
        avatarUrl: avatarUrl,
      );
    }

    // 5.2) ถ้ารหัส User ไม่ตรง ค่อยมาตรวจรหัส Rider
    final passOkForRider = _verifyPasswordForEntity(
      entity: rider,
      pass: password.trim(),
      phone: phone,
    );

    if (passOkForRider) {
      // ถ้ารหัส Rider ตรง ให้ล็อกอินเป็น RIDER
      final role = 'RIDER';
      final base = rider;
      final name = _pick<String>(base, ['name', 'fullname']) ??
          _pick<String>(rider, ['name', 'fullname']) ??
          '';
      final avatarUrl = _pick<String>(base, ['avatarUrl', 'photoUrl']) ??
          _pick<String>(rider, ['avatarUrl', 'photoUrl']) ??
          '';

      return AuthResult(
        ok: true,
        uid: uid,
        role: role,
        phone: phone,
        name: name,
        avatarUrl: avatarUrl,
      );
    }

    // 5.3) ถ้าไม่ตรงทั้งคู่
    return AuthResult(
      ok: false,
      uid: uid,
      role: 'USER',
      phone: phone,
      name: '',
      avatarUrl: '',
      error: 'รหัสผ่านไม่ถูกต้อง',
    );
    // ----------------------------
  }
}
