import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/pages/users/address_user.dart';
import 'package:deliverydomo/services/firebase_profile_user.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class ProfileUser extends StatelessWidget {
  const ProfileUser({Key? key, this.repo}) : super(key: key);

  final UserRepository? repo;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF8F7F5);
    final r = repo ?? UserRepository();

    return FutureBuilder<String?>(
      future: r.resolveUidSmart(),
      builder: (context, uidSnap) {
        if (uidSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final uid = uidSnap.data ?? '';
        if (uid.isEmpty) {
          return const Scaffold(
            body: Center(
                child: Text('ยังไม่ได้ล็อกอิน หรือหา uid ของผู้ใช้ไม่เจอ')),
          );
        }

        return Scaffold(
          backgroundColor: bg,
          appBar: customAppBar(),
          body: SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: r.userDocStream(uid),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return Center(child: Text('ไม่พบผู้ใช้ (users/$uid)'));
                }

                final data = snap.data!.data() ?? {};
                final name = (data['name'] ?? '').toString();
                final phone =
                    (data['phone'] ?? SessionStore.phoneId ?? '').toString();
                final avatarUrl = (data['photoUrl'] ?? data['avatarUrl'] ?? data['photo_url'] ?? '').toString();


                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _ProfileHeader(
                        uid: uid,
                        repo: r,
                        name: name,
                        phone: phone,
                        avatarUrl: avatarUrl,
                      ),
                      const SizedBox(height: 32),
                      _PersonalInfoSection(
                        uid: uid,
                        repo: r,
                        name: name,
                        phone: phone,
                      ),
                      const SizedBox(height: 28),
                      _AddressSection(uid: uid, repo: r),
                      const SizedBox(height: 28),
                      _LogoutButton(
                        onPressed: () async {
                          await SessionStore.clearAll();
                          Get.offAll(() => const LoginPage());
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.uid,
    required this.repo,
    required this.name,
    required this.phone,
    required this.avatarUrl,
  });

  final String uid;
  final UserRepository repo;
  final String name;
  final String phone;
  final String avatarUrl;

  Future<void> _editAvatar() async {
    // เลือกแหล่งรูปแบบ bottom sheet
    final action = await Get.bottomSheet<String>(
      Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('เปลี่ยนรูปโปรไฟล์',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูปด้วยกล้อง'),
              onTap: () => Get.back(result: 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากเครื่อง'),
              onTap: () => Get.back(result: 'gallery'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
      isDismissible: true,
    );

    if (action == null) return;

    if (action == 'camera' || action == 'gallery') {
      await _pickAndUpload(
          action == 'camera' ? ImageSource.camera : ImageSource.gallery);
      return;
    }

    if (action == 'url') {
      final ctrl = TextEditingController(text: avatarUrl);
      final ok = await Get.dialog<bool>(
            AlertDialog(
              title: const Text('วางแกไขรูปโปรไฟล์'),
              actions: [
                TextButton(
                    onPressed: () => Get.back(result: false),
                    child: const Text('ยกเลิก')),
                TextButton(
                    onPressed: () => Get.back(result: true),
                    child: const Text('บันทึก')),
              ],
            ),
            barrierDismissible: false,
          ) ??
          false;

      if (!ok) return;

      try {
        await repo.updateUserProfile(uid, photoUrl: ctrl.text.trim());
        Get.snackbar('สำเร็จ', 'อัปเดตรูปโปรไฟล์เรียบร้อย',
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('ผิดพลาด', '$e',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.shade50);
      }
    }
  }

// ===== helper: เลือกรูป + อัปโหลด Storage + อัปเดตโปรไฟล์ =====
  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: source, imageQuality: 85, maxWidth: 1600);
      if (x == null) return;

      // progress
      Get.dialog(
        const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      final file = File(x.path);
      final path =
          'users/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(path);

      final snap = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await snap.ref.getDownloadURL();

      await repo.updateUserProfile(uid, photoUrl: url);

      if (Get.isDialogOpen ?? false) Get.back(); // close progress
      Get.snackbar('สำเร็จ', 'อัปโหลดและอัปเดตรูปโปรไฟล์แล้ว',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('ผิดพลาด', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade50);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: _editAvatar,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFD8700).withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 4,
                )
              ],
            ),
            child: CircleAvatar(
              radius: 56,
              backgroundColor: const Color(0xFFFFF5E8),
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 60, color: Color(0xFFFD8700))
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'แตะรูปเพื่อแก้ไข',
          style: TextStyle(fontSize: 12, color: Colors.black38),
        ),
        const SizedBox(height: 12),
        Text(
          name.isEmpty ? 'ผู้ใช้' : name,
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        if (phone.isNotEmpty)
          Text(
            phone,
            style: const TextStyle(
                fontSize: 13, color: Colors.black54, letterSpacing: 0.3),
          ),
      ],
    );
  }
}

class _PersonalInfoSection extends StatelessWidget {
  const _PersonalInfoSection({
    required this.uid,
    required this.repo,
    required this.name,
    required this.phone,
  });

  final String uid;
  final UserRepository repo;
  final String name;
  final String phone;

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: name);
    final phoneCtrl = TextEditingController(text: phone);
    final formKey = GlobalKey<FormState>();
    final orange = const Color(0xFFFD8700);
    final lightOrange = const Color(0xFFFFB84D);

    bool changed() =>
        nameCtrl.text.trim() != name.trim() ||
        phoneCtrl.text.trim() != phone.trim();

    String? _validateName(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return 'กรุณากรอกชื่อ';
      if (s.length < 2) return 'ชื่อสั้นเกินไป';
      return null;
    }

    String? _validatePhone(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return 'กรุณากรอกเบอร์โทร';
      // รองรับ 09xxxxxxxx (10 หลัก) หรือ +66xxxxxxxx (อย่างน้อย 9–12 ตัวเลข)
      final re = RegExp(r'^(\+?\d{9,12}|0\d{9})$');
      if (!re.hasMatch(s)) return 'รูปแบบเบอร์โทรไม่ถูกต้อง';
      return null;
    }

    final ok = await Get.dialog<bool>(
          Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [orange, lightOrange],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: const [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.edit,
                                color: Color(0xFFFD8700), size: 18),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'แก้ไขข้อมูลส่วนตัว',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: .2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                      child: Form(
                        key: formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextFormField(
                              controller: nameCtrl,
                              decoration: InputDecoration(
                                labelText: 'ชื่อ',
                                prefixIcon: const Icon(Icons.person_outline),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              textInputAction: TextInputAction.next,
                              validator: _validateName,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: phoneCtrl,
                              decoration: InputDecoration(
                                labelText: 'เบอร์โทร',
                                hintText: 'เช่น 0912345678 หรือ +66912345678',
                                prefixIcon: const Icon(Icons.phone_outlined),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: _validatePhone,
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'หมายเหตุ: เบอร์โทรใช้ยืนยันตัวตนและค้นพบบัญชีของคุณ',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                side: BorderSide(color: Colors.grey.shade300),
                                foregroundColor: Colors.grey.shade800,
                              ),
                              onPressed: () => Get.back(result: false),
                              child: const Text('ยกเลิก',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                backgroundColor: orange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                              ),
                              onPressed: (!changed() ||
                                      !(formKey.currentState?.validate() ??
                                          false))
                                  ? null
                                  : () => Get.back(result: true),
                              child: const Text('บันทึก',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          barrierDismissible: false,
        ) ??
        false;

    if (!ok) return;

    try {
      // แสดง progress ขณะบันทึก
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);

      await repo.updateUserProfile(
        uid,
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
      );

      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('สำเร็จ', 'อัปเดตข้อมูลเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('ผิดพลาด', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade50);
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFD8700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                    color: orange, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              const Text(
                'ข้อมูลส่วนตัว',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.black87),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _editProfile,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('แก้ไข'),
                style: TextButton.styleFrom(foregroundColor: orange),
              ),
            ],
          ),
        ),
        _InfoCard(
          icon: Icons.person_outline,
          label: 'ชื่อ',
          value: name.isEmpty ? '-' : name,
          isFirst: true,
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.phone_outlined,
          label: 'เบอร์โทร',
          value: phone.isEmpty ? '-' : phone,
          isFirst: false,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.isFirst,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF5E8),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: const Color(0xFFFD8700), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressSection extends StatelessWidget {
  const _AddressSection({required this.uid, required this.repo});

  final String uid;
  final UserRepository repo;

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFD8700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Row(
            children: [
              Container(
                  width: 3,
                  height: 18,
                  decoration: BoxDecoration(
                      color: orange, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 10),
              const Text('ที่อยู่',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: Colors.black87)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Get.to(() => const AddressUser()),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('เพิ่ม'),
                style: TextButton.styleFrom(
                    foregroundColor: orange,
                    padding: const EdgeInsets.symmetric(horizontal: 12)),
              ),
            ],
          ),
        ),
        _AddressList(uid: uid, repo: repo),
      ],
    );
  }
}

class _AddressList extends StatelessWidget {
  const _AddressList({required this.uid, required this.repo});

  final String uid;
  final UserRepository repo;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: repo.addressesStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 2))
              ],
            ),
            child: const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        if (snapshot.hasError) {
          return _EmptyCard(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }

        var docs = snapshot.data?.docs.toList() ?? [];
        if (docs.isEmpty) {
          return _EmptyCard(
            child: Column(
              children: [
                Icon(Icons.location_off_outlined,
                    size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                const Text('ยังไม่มีที่อยู่',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.black54)),
                const SizedBox(height: 4),
                const Text('กด "เพิ่ม" เพื่อเพิ่มที่อยู่ใหม่',
                    style: TextStyle(fontSize: 12, color: Colors.black38)),
              ],
            ),
          );
        }

        docs.sort((a, b) {
          final da = (a.data()['is_default'] ?? false) == true ? 0 : 1;
          final db = (b.data()['is_default'] ?? false) == true ? 0 : 1;
          if (da != db) return da.compareTo(db);
          final ta = a.data()['created_at'];
          final tb = b.data()['created_at'];
          final ai = (ta is Timestamp) ? ta.millisecondsSinceEpoch : 0;
          final bi = (tb is Timestamp) ? tb.millisecondsSinceEpoch : 0;
          return bi.compareTo(ai);
        });

        final show = docs.take(2).toList();

        return Column(
          children: show.asMap().entries.map((entry) {
            final idx = entry.key;
            final d = entry.value;
            final m = d.data();
            final label = (m['label'] ?? m['name'] ?? 'ที่อยู่').toString();
            final detail = (m['detail'] ?? m['address_text'] ?? '').toString();
            final phone = (m['phone'] ?? '').toString();
            final isDefault = (m['is_default'] ?? false) == true;

            return GestureDetector(
              onTap: () => Get.to(() => const AddressUser()),
              child: Container(
                margin: EdgeInsets.only(bottom: idx < show.length - 1 ? 12 : 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Get.to(() => const AddressUser()),
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: const Color(0xFFFFF5E8),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(
                                isDefault
                                    ? Icons.location_on
                                    : Icons.location_on_outlined,
                                color: const Color(0xFFFD8700),
                                size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Colors.black87),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isDefault)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFFFF1D6),
                                            borderRadius:
                                                BorderRadius.circular(20)),
                                        child: const Text('หลัก',
                                            style: TextStyle(
                                                color: Color(0xFFFD8700),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 11)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  detail,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      height: 1.4),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(phone,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.chevron_right_rounded,
                              color: Colors.black26),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _LogoutButton extends StatefulWidget {
  const _LogoutButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<_LogoutButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: _isHovered ? const Color(0xFFE53935) : const Color(0xFFFFE9E9),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            onPressed: widget.onPressed,
            icon: const Icon(Icons.logout, size: 20),
            label: const Text('ออกจากระบบ',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Center(child: child),
    );
  }
}
