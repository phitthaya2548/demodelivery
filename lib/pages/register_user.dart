import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/services/firebase_user.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class RegisterUser extends StatefulWidget {
  const RegisterUser({super.key});

  @override
  State<RegisterUser> createState() => _RegisterUserState();
}

class _RegisterUserState extends State<RegisterUser> {
  final _tel = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _loading = false;
  File? _imageFile;

  final _api = FirebaseUserApi();

  String _normalizePhone(String s) {
    final only = s.replaceAll(RegExp(r'\D'), '');
    if (only.startsWith('66') && only.length >= 11) {
      return '0${only.substring(2)}';
    }
    return only;
  }

  String _hashPasswordNoSalt(String password, String phone) {
    return sha256.convert(utf8.encode('$phone::$password')).toString();
  }

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
  // -----------------------------

  // ---------- เลือกรูป: กล้อง / คลัง ----------
  Future<void> _selectImage() async {
    final src = await _chooseImageSource();
    if (src == null) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: src,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (x != null) setState(() => _imageFile = File(x.path));
  }

  Future<ImageSource?> _chooseImageSource() {
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
  // ---------------------------------------------

  void _showSuccessDialog({
    required String name,
    required String phone,
    String? photoUrl,
  }) {
    Get.dialog(
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  color: Color(0xFF22c55e), size: 52),
              const SizedBox(height: 12),
              const Text('สมัครสมาชิกสำเร็จ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (photoUrl != null && photoUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(photoUrl,
                      height: 84, width: 84, fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
              ],
              Text(name, style: const TextStyle(fontSize: 16)),
              Text('เบอร์: $phone', style: const TextStyle(color: Colors.grey)),
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
                    Get.to(() => const LoginPage());
                  },
                  child:
                      const Text('ตกลง', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: false,
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final rawPhone = _tel.text.trim();
    final phone = _normalizePhone(rawPhone); // ✅ แปลงแบบเดียวกับ Login
    final name = _name.text.trim();
    final pass = _pass.text.trim();

    setState(() => _loading = true);

    try {
      final passwordHash = _hashPasswordNoSalt(pass, phone);
      final res = await _api.createUser(
        phone: phone,
        name: name,
        passwordHash: passwordHash,
        avatarFile: _imageFile,
      );

      _toast('สมัครสมาชิกสำเร็จ', success: true);
      _showSuccessDialog(name: name, phone: phone, photoUrl: res.photoUrl);
    } on FirebaseUserApiError catch (e) {
      if (e.code == 'PHONE_TAKEN') {
        _toast('เบอร์นี้ถูกสมัครแล้ว');
      } else {
        _toast('สมัครไม่สำเร็จ: ${e.code}');
      }
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
            borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
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
            child: Card(
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
                      Text(
                        'Register\nUser',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                      SizedBox(height: h * 0.02),

                      // Avatar (แตะเพื่อเลือก "กล้อง/คลัง")
                      GestureDetector(
                        onTap: _selectImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: Colors.orange.shade100,
                              backgroundImage: _imageFile != null
                                  ? FileImage(_imageFile!)
                                  : null,
                              child: _imageFile == null
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

                      // Phone
                      TextFormField(
                        controller: _tel,
                        keyboardType: TextInputType.phone,
                        decoration: deco('Tel.', Icons.phone_android_outlined),
                        validator: (v) {
                          final p = _normalizePhone(v ?? '');
                          if (p.isEmpty) return 'กรอกเบอร์โทร';
                          if (p.length < 9) return 'เบอร์ไม่ถูกต้อง';
                          return null;
                        },
                      ),
                      SizedBox(height: h * 0.015),

                      // Full name
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: deco('Full name', Icons.person_outline),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'กรอกชื่อ' : null,
                      ),
                      SizedBox(height: h * 0.015),

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
                      SizedBox(height: h * 0.03),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[800],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
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
          ),
        ),
      ),
    );
  }
}
