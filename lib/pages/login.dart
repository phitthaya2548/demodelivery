import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:deliverydomo/pages/riders/widgets/bottom.dart';
import 'package:deliverydomo/pages/selectrule.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // SessionStore / AuthSession
import 'package:deliverydomo/pages/users/widgets/bottom.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _tel = TextEditingController();
  final _pass = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _loading = false;

  // ================= Helpers =================
  String _normalizePhone(String s) {
    final only = s.replaceAll(RegExp(r'\D'), '');
    // รองรับ +66 หรือ 66xxxxxxxxx -> 0xxxxxxxxx
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

  void _toast(String msg, {bool success = false}) {
    Get.rawSnackbar(
      messageText: Text(
        msg,
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      backgroundColor:
          success ? const Color(0xFF22c55e) : const Color(0xFFef4444),
      duration: const Duration(seconds: 2),
    );
  }
  // ============================================

  /// หา uid จากเบอร์ (รองรับ users + riders + phone_to_uid + legacy)
  Future<String?> _resolveUidByPhone(String phone) async {
    final fs = FirebaseFirestore.instance;

    // 1) phone_to_uid mapping
    final map = await fs.collection('phone_to_uid').doc(phone).get();
    final mapped = (map.data()?['uid'] ?? '').toString();
    if (mapped.isNotEmpty) return mapped;

    // 2) users (สคีมาใหม่ id เป็น auto uid)
    final uq = await fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (uq.docs.isNotEmpty) return uq.docs.first.id;

    // 3) users legacy: users/{phone}
    final legacy = await fs.collection('users').doc(phone).get();
    if (legacy.exists) return phone;

    // 4) RIDERS: มีเฉพาะไรเดอร์ (ไม่มี users) ก็ให้ล็อกอินได้
    //    - โครงสร้างที่พบ: fields: userId (uid), phoneNumber, avatarUrl, passwordHash
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

    // เผื่อกรอกเป็น uid มาในช่องเบอร์ (กรณีทดสอบ)
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

    // เผื่อ docId ใน riders เก็บเป็นเบอร์
    final rdoc = await fs.collection('riders').doc(phone).get();
    if (rdoc.exists) {
      final m = rdoc.data() ?? {};
      final uid = (m['userId'] ?? '').toString();
      return uid.isNotEmpty ? uid : rdoc.id;
    }

    return null;
  }

  /// อ่าน users/{uid} (พร้อม fallback users/{phone} และ where(phone==))
  Future<DocumentSnapshot<Map<String, dynamic>>?> _getUserSnapByUidOrPhone(
      String uid, String phone) async {
    final fs = FirebaseFirestore.instance;
    // ลอง uid ก่อน
    var snap = await fs.collection('users').doc(uid).get();
    if (snap.exists) return snap;

    // เผื่อเป็นเอกสารเก่า users/{phone}
    if (uid != phone) {
      snap = await fs.collection('users').doc(phone).get();
      if (snap.exists) return snap;
    }

    // final fallback: query อีกครั้ง
    final q = await fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first;

    return null;
  }

  /// ตรวจว่าผู้นี้เป็นไรเดอร์ไหม (ใช้ uid/phone ครอบคลุมทุกเคส)
  Future<(bool isRider, DocumentSnapshot<Map<String, dynamic>>? snap)>
      _findRiderByUidOrPhone(String uid, String phone) async {
    final fs = FirebaseFirestore.instance;

    // 1) riders/{uid}
    var snap = await fs.collection('riders').doc(uid).get();
    if (snap.exists) return (true, snap);

    // 2) where userId == uid
    final q1 = await fs
        .collection('riders')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();
    if (q1.docs.isNotEmpty) return (true, q1.docs.first);

    // 3) where userId == phone
    final q2 = await fs
        .collection('riders')
        .where('userId', isEqualTo: phone)
        .limit(1)
        .get();
    if (q2.docs.isNotEmpty) return (true, q2.docs.first);

    // 4) where phoneNumber == phone
    final q3 = await fs
        .collection('riders')
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();
    if (q3.docs.isNotEmpty) return (true, q3.docs.first);

    // 5) เผื่อ docId == phone
    snap = await fs.collection('riders').doc(phone).get();
    if (snap.exists) return (true, snap);

    return (false, null);
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = _normalizePhone(_tel.text.trim());
    final pass = _pass.text.trim();
    setState(() => _loading = true);

    try {
      // ---------- 1) แปลง phone -> uid ----------
      final uid = await _resolveUidByPhone(phone);
      if (uid == null) {
        _toast('ไม่พบผู้ใช้เบอร์นี้');
        return;
      }

      // ---------- 2) โหลด users/{uid} ----------
      final userSnap = await _getUserSnapByUidOrPhone(uid, phone);
      final user = userSnap?.data() ?? {};

      // ---------- 3) โหลด/ตรวจ rider ----------
      final (isRider, riderSnap) = await _findRiderByUidOrPhone(uid, phone);
      final rider = riderSnap?.data() ?? {};

      // ---------- 4) ตรวจรหัสผ่าน ----------
      // ลำดับตรวจ: users.passwordHash -> users.sha256(pass) -> users.password (plain)
      // ถ้า users ไม่มี (หรือไม่ผ่าน) และมี riders.passwordHash ค่อยตรวจจาก riders
      bool passOk = false;

      // จาก users
      if (user.isNotEmpty) {
        final uStoredHash =
            _pick<String>(user, ['passwordHash', 'password_hash']) ?? '';
        final uStoredPlain = _pick<String>(user, ['password']) ?? '';
        passOk = (uStoredHash.isNotEmpty &&
                uStoredHash == _hashWithPhone(pass, phone)) ||
            (uStoredHash.isNotEmpty && uStoredHash == _sha256(pass)) ||
            (uStoredPlain.isNotEmpty && uStoredPlain == pass);
      }

      // จาก riders (กรณี users ไม่มีหรือไม่ผ่าน)
      if (!passOk && rider.isNotEmpty) {
        final rHash =
            _pick<String>(rider, ['passwordHash', 'password_hash']) ?? '';
        final rPlain = _pick<String>(rider, ['password']) ?? '';
        passOk = (rHash.isNotEmpty && rHash == _hashWithPhone(pass, phone)) ||
            (rHash.isNotEmpty && rHash == _sha256(pass)) ||
            (rPlain.isNotEmpty && rPlain == pass);
      }

      if (!passOk) {
        _toast('รหัสผ่านไม่ถูกต้อง');
        return;
      }

      // ---------- 5) ตัดสินบทบาท ----------
      final role = isRider ? 'RIDER' : 'USER';

      // ---------- 6) เตรียมข้อมูลสำหรับ session ----------
      // ถ้าเป็น RIDER ให้ดึงชื่อ/รูปจาก riders ก่อน (ถ้ามี) มาตกแต่งทักทาย
      final base = isRider && rider.isNotEmpty ? rider : user;
      final name = _pick<String>(base, ['name', 'fullname']) ??
          _pick<String>(user, ['name', 'fullname']) ??
          '';
      final avatarUrl = _pick<String>(base, ['avatarUrl', 'photoUrl']) ??
          _pick<String>(user, ['avatarUrl', 'photoUrl']) ??
          '';

      // ---------- 7) Save Session ----------
      await SessionStore.saveAuth(AuthSession(
        role: role,
        userId: uid, // ใช้ uid เสมอ
        fullname: name,
        phoneId: phone,
      ));
      await SessionStore.saveProfile({
        'name': name,
        'phone': phone,
        'uid': uid,
        'role': role,
        'avatarUrl': avatarUrl,
      });

      _toast('ล็อกอินสำเร็จ ยินดีต้อนรับ ${name.isEmpty ? phone : name}',
          success: true);

      // ---------- 8) นำทาง ----------
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      if (role == 'RIDER') {
        Get.offAll(() => BottomRider());
      } else {
        Get.offAll(() => BottomUser());
      }
    } on FirebaseException catch (e) {
      _toast('ล็อกอินไม่สำเร็จ: [${e.code}] ${e.message}');
    } catch (e) {
      _toast('ล็อกอินไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tel.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    InputDecoration deco(String hint, IconData icon) => InputDecoration(
          prefixIcon: Icon(icon, color: Colors.orange[800]),
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderSide:
                BorderSide(color: Colors.white.withOpacity(.8), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.white,
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.orange.shade800, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
        );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFD8700), Color(0xFFFFDE98)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: w * 0.08),
            child: Column(
              children: [
                Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  elevation: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Login Delivery\nWarpSong',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.orange[800],
                            ),
                          ),
                          SizedBox(height: h * 0.02),

                          // Phone
                          TextFormField(
                            controller: _tel,
                            keyboardType: TextInputType.phone,
                            decoration:
                                deco('Phone', Icons.phone_android_outlined),
                            validator: (v) {
                              final p = _normalizePhone(v ?? '');
                              if (p.isEmpty) return 'กรอกเบอร์โทร';
                              if (p.length < 9) return 'เบอร์ไม่ถูกต้อง';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Password
                          TextFormField(
                            controller: _pass,
                            obscureText: _obscure,
                            decoration:
                                deco('Password', Icons.lock_outline).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: Colors.orange[800],
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'กรอกรหัสผ่าน'
                                : null,
                          ),
                          SizedBox(height: h * 0.03),

                          // Login button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[800],
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Login',
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                            ),
                          ),

                          // Link to register
                          TextButton(
                            onPressed: () =>
                                Get.to(() => const SelectMemberTypePage()),
                            child: const Text('Register',
                                style: TextStyle(color: Colors.orange)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
