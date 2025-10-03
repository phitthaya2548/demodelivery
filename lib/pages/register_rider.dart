import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class RegisterRider extends StatefulWidget {
  const RegisterRider({super.key});
  @override
  State<RegisterRider> createState() => _RegisterRiderState();
}

class _RegisterRiderState extends State<RegisterRider> {
  final _tel = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _plate = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _loading = false;

  File? _avatarFile;
  File? _vehicleFile;

  // ===== helpers =====
  String _normalizePhone(String s) => s.replaceAll(RegExp(r'\D'), '');
  String _hashPasswordNoSalt(String password, String phone) =>
      sha256.convert(utf8.encode('$phone::$password')).toString();

  void _toast(String msg, {bool success = false}) {
    Get.showSnackbar(
      GetSnackBar(
        margin: const EdgeInsets.all(16),
        borderRadius: 14,
        snackPosition: SnackPosition.TOP,
        backgroundColor:
            success ? const Color(0xFF22c55e) : const Color(0xFFef4444),
        icon: Icon(success ? Icons.check_circle : Icons.error_outline,
            color: Colors.white),
        titleText: Text(success ? 'สำเร็จ' : 'ผิดพลาด',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
        messageText: Text(msg, style: const TextStyle(color: Colors.white)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------- Image pickers (กล้อง/แกลเลอรี) ----------
  Future<void> _selectImage({required bool forAvatar}) async {
    final src = await _chooseImageSource();
    if (src == null) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: src,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (x == null) return;

    setState(() {
      if (forAvatar) {
        _avatarFile = File(x.path);
      } else {
        _vehicleFile = File(x.path);
      }
    });
  }

  Future<ImageSource?> _chooseImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              height: 5,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายด้วยกล้อง'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากคลังภาพ'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Future<String> _uploadToStorage({
    required String path,
    required File file,
    String contentType = 'image/jpeg',
  }) async {
    final ref = FirebaseStorage.instance.ref(path);
    final snap =
        await ref.putFile(file, SettableMetadata(contentType: contentType));
    debugPrint(
        '[Storage] uploaded bucket=${snap.ref.bucket} path=${snap.ref.fullPath}');
    return await snap.ref.getDownloadURL();
  }

  /// เช็คซ้ำด้วยตารางแมป phone_to_uid (ไม่ผูก users กับเบอร์แล้ว)
  Future<bool> _phoneAlreadyRegistered(String phone) async {
    final map = await FirebaseFirestore.instance
        .collection('phone_to_uid')
        .doc(phone)
        .get();
    return map.exists;
  }

  /// สร้างเอกสาร users/{uid}, riders/{uid}, และ phone_to_uid/{phone} ใน Transaction เดียว
  Future<void> _createRiderWithMapping({
    required String uid,
    required String phone,
    required String name,
    required String passwordHash,
    required String plate,
    String? avatarUrl,
    String? vehicleUrl,
  }) async {
    final fs = FirebaseFirestore.instance;
    final users = fs.collection('users').doc(uid);
    final riders = fs.collection('riders').doc(uid);
    final phones = fs.collection('phone_to_uid').doc(phone);
    final now = FieldValue.serverTimestamp();

    await fs.runTransaction((tx) async {
      // ป้องกันเบอร์ซ้ำซ้อนอีกชั้น
      final mapSnap = await tx.get(phones);
      if (mapSnap.exists) {
        throw Exception('เบอร์นี้ถูกใช้งานแล้ว');
      }

      tx.set(riders, {
        'userId': uid,
        'name': name,
        'phoneNumber': phone,
        'passwordHash': passwordHash,
        'plateNumber': plate,
        'avatarUrl': avatarUrl,
        'vehiclePhotoUrl': vehicleUrl,
        'createdAt': now,
        'updatedAt': now,
      });

      // mapping: phone -> uid
      tx.set(phones, {'uid': uid});
    });
  }

  void _showSuccessDialog({
    required String name,
    required String phone,
    String? avatarUrl,
    String? plate,
  }) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle, color: Color(0xFF22c55e), size: 54),
            const SizedBox(height: 10),
            const Text('สมัครไรเดอร์สำเร็จ',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (avatarUrl != null && avatarUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(avatarUrl,
                    height: 84, width: 84, fit: BoxFit.cover),
              ),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontSize: 16)),
            Text('เบอร์: $phone', style: const TextStyle(color: Colors.grey)),
            if (plate != null && plate.isNotEmpty)
              Text('ทะเบียนรถ: $plate',
                  style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFD8700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  Get.back(); // ปิด dialog
                  Get.back(); // กลับหน้าเดิม
                },
                child:
                    const Text('ตกลง', style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = _normalizePhone(_tel.text.trim());
    final name = _name.text.trim();
    final pass = _pass.text.trim();
    final plate = _plate.text.trim();

    if (_avatarFile == null) {
      _toast('กรุณาเลือกรูปโปรไฟล์ไรเดอร์', success: false);
      return;
    }

    setState(() => _loading = true);

    try {
      // 1) กันซ้ำด้วย phone_to_uid
      if (await _phoneAlreadyRegistered(phone)) {
        _toast('เบอร์นี้ถูกสมัครแล้ว');
        return;
      }

      // 2) สร้าง uid ใหม่ก่อน แล้วค่อยอัปโหลดโดยอิง uid
      final fs = FirebaseFirestore.instance;
      final uid = fs.collection('users').doc().id;

      // 3) อัปโหลดรูป (ผูกพาธกับ uid แทนการใช้เบอร์)
      final ts = DateTime.now().millisecondsSinceEpoch;
      final avatarUrl = await _uploadToStorage(
        path: 'riders/$uid/avatar_$ts.jpg',
        file: _avatarFile!,
      );

      String? vehicleUrl;
      if (_vehicleFile != null) {
        vehicleUrl = await _uploadToStorage(
          path: 'riders/$uid/vehicle_$ts.jpg',
          file: _vehicleFile!,
        );
      }

      // 4) แฮชรหัสผ่าน (ตามสูตรเดิม)
      final hash = _hashPasswordNoSalt(pass, phone);

      // 5) เขียน Firestore ทั้งหมดใน Transaction
      await _createRiderWithMapping(
        uid: uid,
        phone: phone,
        name: name,
        passwordHash: hash,
        plate: plate,
        avatarUrl: avatarUrl,
        vehicleUrl: vehicleUrl,
      );

      _toast('สมัครไรเดอร์สำเร็จ', success: true);
      _showSuccessDialog(
        name: name,
        phone: phone,
        avatarUrl: avatarUrl,
        plate: plate,
      );
    } on FirebaseException catch (e) {
      _toast('สมัครไม่สำเร็จ: [${e.code}] ${e.message}');
    } catch (e) {
      _toast('สมัครไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _tel.dispose();
    _name.dispose();
    _pass.dispose();
    _plate.dispose();
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
                            'Register\nRider',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: Colors.orange[800],
                            ),
                          ),
                          SizedBox(height: h * 0.02),

                          // Avatar (แตะเพื่อเลือก "กล้อง/คลัง")
                          GestureDetector(
                            onTap: () => _selectImage(forAvatar: true),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 52,
                                  backgroundColor: Colors.orange.shade100,
                                  backgroundImage: _avatarFile != null
                                      ? FileImage(_avatarFile!)
                                      : null,
                                  child: _avatarFile == null
                                      ? Icon(Icons.person,
                                          size: 48, color: Colors.orange[800])
                                      : null,
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.orange[800],
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: const Icon(Icons.add_a_photo,
                                      color: Colors.white, size: 18),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: h * 0.02),

                          // Tel
                          TextFormField(
                            controller: _tel,
                            keyboardType: TextInputType.phone,
                            decoration:
                                deco('Tel.', Icons.phone_android_outlined),
                            validator: (v) {
                              final p = _normalizePhone(v ?? '');
                              if (p.isEmpty) return 'กรอกเบอร์โทร';
                              if (p.length < 9) return 'เบอร์ไม่ถูกต้อง';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Full name
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: deco('Full name', Icons.person_outline),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'กรอกชื่อ'
                                : null,
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
                            validator: (v) => (v == null || v.length < 6)
                                ? 'อย่างน้อย 6 ตัวอักษร'
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Plate number
                          TextFormField(
                            controller: _plate,
                            decoration: deco('ทะเบียนรถ',
                                Icons.confirmation_number_outlined),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'กรอกทะเบียนรถ'
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Vehicle doc/photo picker block (มีปุ่มเลือก กล้อง/คลัง)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF5E8),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFFFE0B2)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  height: 64,
                                  width: 64,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: Colors.orange.shade300,
                                        width: 1.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: _vehicleFile == null
                                      ? const Icon(Icons.image_outlined)
                                      : ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Image.file(
                                            _vehicleFile!,
                                            fit: BoxFit.cover,
                                            width: 64,
                                            height: 64,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('เอกสาร/รูปรถ',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      SizedBox(height: 4),
                                      Text(
                                          'อัปโหลดรูปบัตร/รูปรถเพื่อยืนยันตัวตน',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54)),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    elevation: 2,
                                    shadowColor: Colors.black12,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                  ),
                                  onPressed: () =>
                                      _selectImage(forAvatar: false),
                                  icon: const Icon(Icons.add_a_photo_outlined,
                                      color: Color(0xFFFD8700)),
                                  label: const Text('เลือกรูป/ถ่าย',
                                      style:
                                          TextStyle(color: Color(0xFFFD8700))),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: h * 0.03),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange[800],
                                elevation: 6,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _loading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Text(
                                      'Register',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Get.back(),
                            child: const Text('back',
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
