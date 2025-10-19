import 'package:cloud_firestore/cloud_firestore.dart'; // ใช้จับ FirebaseException
import 'package:deliverydomo/pages/riders/widgets/bottom.dart';
import 'package:deliverydomo/pages/selectrule.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // SessionStore / AuthSession
import 'package:deliverydomo/pages/users/widgets/bottom.dart';
import 'package:deliverydomo/services/firestore_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _authRepo = FirestoreAuthRepo();

  final _focusPhone = FocusNode();
  final _focusPass = FocusNode();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _tel.dispose();
    _pass.dispose();
    _focusPhone.dispose();
    _focusPass.dispose();
    super.dispose();
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

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final result = await _authRepo.loginWithPhonePassword(
        phoneInput: _tel.text,
        password: _pass.text,
      );

      if (!result.ok) {
        _toast(result.error ?? 'ล็อกอินไม่สำเร็จ');
        return;
      }

      await SessionStore.saveAuth(AuthSession(
        role: result.role,
        userId: result.uid!, // ใช้ uid เสมอ
        fullname: result.name,
        phoneId: result.phone,
      ));
      await SessionStore.saveProfile({
        'name': result.name,
        'phone': result.phone,
        'uid': result.uid,
        'role': result.role,
        'avatarUrl': result.avatarUrl,
      });

      _toast(
        'ล็อกอินสำเร็จ ยินดีต้อนรับ ${result.name.isEmpty ? result.phone : result.name}',
        success: true,
      );

      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted) return;
      if (result.role == 'RIDER') {
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

  // --- UI helpers ---
  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
        prefixIcon: Icon(icon, color: Colors.orange[800]),
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderSide:
              BorderSide(color: Colors.white.withOpacity(.8), width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        filled: true,
        fillColor: Colors.white,
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.orange.shade800, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFD8700), Color(0xFFFFDE98)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  EdgeInsets.symmetric(horizontal: w < 380 ? 16 : w * 0.08),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    children: [
                      Image.asset('assets/images/logo.png',
                          fit: BoxFit.contain),
                      const SizedBox(height: 8),
                      Card(
                        color: Colors.white,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Login Delivery\nWarpSong',
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                                  focusNode: _focusPhone,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber
                                  ],
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(
                                        12), // กันยาวเกิน
                                  ],
                                  onFieldSubmitted: (_) =>
                                      _focusPass.requestFocus(),
                                  decoration: _deco(
                                      'Phone', Icons.phone_android_outlined),
                                  validator: (v) {
                                    final p = _digitsOnly(v ?? '');
                                    if (p.isEmpty) return 'กรอกเบอร์โทร';
                                    if (p.length < 9) return 'เบอร์ไม่ถูกต้อง';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),

                                // Password
                                TextFormField(
                                  controller: _pass,
                                  focusNode: _focusPass,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) =>
                                      _loading ? null : _login(),
                                  decoration:
                                      _deco('Password', Icons.lock_outline)
                                          .copyWith(
                                    suffixIcon: IconButton(
                                      tooltip: _obscure
                                          ? 'แสดงรหัสผ่าน'
                                          : 'ซ่อนรหัสผ่าน',
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
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                    ),
                                    child: _loading
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Login',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                  ),
                                ),

                                // Register link
                                TextButton(
                                  onPressed: () => Get.to(
                                      () => const SelectMemberTypePage()),
                                  child: const Text('Register',
                                      style: TextStyle(color: Colors.orange)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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
