// lib/pages/riders/profile_rider.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_rider_profile.dart'; // ใช้ API ที่เพิ่มเมธอด update ไว้แล้ว
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class ProfileRider extends StatefulWidget {
  const ProfileRider({Key? key}) : super(key: key);

  @override
  State<ProfileRider> createState() => _ProfileRiderState();
}

class _ProfileRiderState extends State<ProfileRider> {
  static const bg = Color(0xFFF8F7F5);
  static const orange = Color(0xFFFD8700);
  static const lightOrange = Color(0xFFFFB84D);

  final _api = FirebaseRiderProfileApi();

  Future<void> _logout() async {
    await SessionStore.clearAll();
    if (!mounted) return;
    Get.offAll(() => const LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    final userId = (SessionStore.userId ?? '').trim();
    final phoneId = (SessionStore.phoneId ?? '').trim();

    if (userId.isEmpty && phoneId.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ไม่พบข้อมูลเซสชัน (userId/phoneId ว่าง)'),
              const SizedBox(height: 12),
              _LogoutButton(onPressed: _logout),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: customAppBar(),
      body: SafeArea(
        child: FutureBuilder<DocumentReference<Map<String, dynamic>>?>(
          future: _api.findRiderDocRef(userId: userId, phoneId: phoneId),
          builder: (context, refSnap) {
            if (refSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final ref = refSnap.data;
            if (ref == null) {
              final debugText =
                  'หา riders ไม่เจอจาก session:\nuserId=${SessionStore.userId}\nphoneId=${SessionStore.phoneId}\n'
                  'ตรวจสอบว่าคอลเลกชัน "riders" เก็บ field เป็น userId หรือ phoneNumber และค่าตรงกับเซสชันหรือไม่';
              return _NotFoundBox(
                text: debugText,
                onRetry: () => setState(() {}),
                onLogout: _logout,
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _api.watchRiderDoc(ref),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
                }
                if (!snap.hasData || !snap.data!.exists) {
                  return _NotFoundBox(
                    text: 'ไม่พบเอกสารไรเดอร์ที่ ${ref.path}',
                    onRetry: () => setState(() {}),
                    onLogout: _logout,
                  );
                }

                final m = snap.data!.data()!;
                return _RiderBody(
                  ref: ref,
                  m: m,
                  uidForName:
                      (m['userId'] ?? m['phoneNumber'] ?? '').toString(),
                  fallbackUserName: _api.fallbackUserName,
                  onLogout: _logout,
                  onEditProfile: () => _editProfile(ref, m),
                  onChangeAvatar: () => _changeAvatar(ref),
                  onEditVehicle: () => _editVehicle(ref, m),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _editProfile(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> m) async {
    final name0 = (m['name'] ?? '').toString();
    final phone0 = (m['phoneNumber'] ?? '').toString();

    final nameCtrl = TextEditingController(text: name0);
    final phoneCtrl = TextEditingController(text: phone0);
    final formKey = GlobalKey<FormState>();

    String? _validateName(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return 'กรุณากรอกชื่อ';
      if (s.length < 2) return 'ชื่อสั้นเกินไป';
      return null;
    }

    String? _validatePhone(String? v) {
      final s = (v ?? '').trim();
      if (s.isEmpty) return 'กรุณากรอกเบอร์โทร';
      final re = RegExp(r'^(0\d{9}|\+?66\d{8,10})$');
      if (!re.hasMatch(s)) return 'รูปแบบเบอร์โทรไม่ถูกต้อง';
      return null;
    }

    bool changed() =>
        nameCtrl.text.trim() != name0.trim() ||
        phoneCtrl.text.trim() != phone0.trim();

    final ok = await Get.dialog<bool>(
          Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: StatefulBuilder(builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                            'แก้ไขข้อมูลไรเดอร์',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
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
                            onPressed: () => Get.back(result: false),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('ยกเลิก',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (!changed() ||
                                    !(formKey.currentState?.validate() ??
                                        false))
                                ? null
                                : () => Get.back(result: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('บันทึก',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
          barrierDismissible: false,
        ) ??
        false;

    if (!ok) return;

    try {
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);
      await _api.updateRiderByRef(
        ref,
        name: nameCtrl.text.trim(),
        phoneNumber: phoneCtrl.text.trim(),
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

  Future<void> _changeAvatar(
      DocumentReference<Map<String, dynamic>> ref) async {
    final act = await Get.bottomSheet<String>(
      _pickerSheet(title: 'เปลี่ยนรูปโปรไฟล์'),
      isDismissible: true,
    );
    if (act == null)
      return;
    else if (act == 'camera' || act == 'gallery') {
      await _pickUploadAndSet(
        source: act == 'camera' ? ImageSource.camera : ImageSource.gallery,
        storagePathBuilder: (uid) =>
            'riders/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
        setter: (url) => _api.setAvatarUrlByRef(ref, url),
      );
      try {
        Get.snackbar('สำเร็จ', 'อัปเดตรูปโปรไฟล์แล้ว',
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('ผิดพลาด', '$e',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red.shade50);
      }
    }
  }

  Future<void> _editVehicle(DocumentReference<Map<String, dynamic>> ref,
      Map<String, dynamic> m) async {
    final plate0 = (m['plateNumber'] ?? '').toString();
    final plateCtrl = TextEditingController(text: plate0);

    final ok = await Get.dialog<bool>(
          Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('แก้ไขข้อมูลรถ',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: plateCtrl,
                    decoration: InputDecoration(
                      labelText: 'เลขทะเบียนรถ',
                      prefixIcon: const Icon(Icons.two_wheeler_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('ถ่ายรูปรถ'),
                          onPressed: () async {
                            Get.back(result: true);
                            await _pickUploadAndSet(
                              source: ImageSource.camera,
                              storagePathBuilder: (uid) =>
                                  'riders/$uid/vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg',
                              setter: (url) =>
                                  _api.setVehiclePhotoUrlByRef(ref, url),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('เลือกรูปรถ'),
                          onPressed: () async {
                            Get.back(result: true);
                            await _pickUploadAndSet(
                              source: ImageSource.gallery,
                              storagePathBuilder: (uid) =>
                                  'riders/$uid/vehicle_${DateTime.now().millisecondsSinceEpoch}.jpg',
                              setter: (url) =>
                                  _api.setVehiclePhotoUrlByRef(ref, url),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Get.back(result: false),
                          child: const Text('ปิด'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Get.back(result: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: orange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: const Text('บันทึกทะเบียน'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          barrierDismissible: true,
        ) ??
        false;

    if (!ok) return;

    try {
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);
      await _api.updateRiderByRef(ref, plateNumber: plateCtrl.text.trim());
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('สำเร็จ', 'อัปเดตทะเบียนรถแล้ว',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('ผิดพลาด', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade50);
    }
  }

  // ---------- Shared helpers ----------

  Widget _pickerSheet({required String title}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
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
          ],
        ),
      ),
    );
  }

  Future<void> _pickUploadAndSet({
    required ImageSource source,
    required String Function(String riderIdOrPhone) storagePathBuilder,
    required Future<void> Function(String url) setter,
  }) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
          source: source, imageQuality: 85, maxWidth: 1600);
      if (x == null) return;

      // progress
      Get.dialog(const Center(child: CircularProgressIndicator()),
          barrierDismissible: false);

      final riderIdOrPhone = (SessionStore.userId?.trim().isNotEmpty ?? false)
          ? SessionStore.userId!.trim()
          : (SessionStore.phoneId ?? '').trim();

      final file = File(x.path);
      final path = storagePathBuilder(riderIdOrPhone);
      final ref = FirebaseStorage.instance.ref(path);

      final snap = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await snap.ref.getDownloadURL();

      await setter(url);

      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('สำเร็จ', 'อัปโหลดและอัปเดตเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('ผิดพลาด', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.shade50);
    }
  }
}

// ---------------- UI ----------------

class _RiderBody extends StatefulWidget {
  const _RiderBody({
    required this.ref,
    required this.m,
    required this.uidForName,
    required this.fallbackUserName,
    required this.onLogout,
    required this.onEditProfile,
    required this.onChangeAvatar,
    required this.onEditVehicle,
  });

  final DocumentReference<Map<String, dynamic>> ref;
  final Map<String, dynamic> m;
  final String uidForName;
  final Future<String> Function(String uidOrPhone) fallbackUserName;
  final VoidCallback onLogout;

  final VoidCallback onEditProfile;
  final VoidCallback onChangeAvatar;
  final VoidCallback onEditVehicle;

  @override
  State<_RiderBody> createState() => _RiderBodyState();
}

class _RiderBodyState extends State<_RiderBody> {
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    final name = (widget.m['name'] ?? '').toString();
    if (name.isNotEmpty) {
      _displayName = name;
    } else {
      widget.fallbackUserName(widget.uidForName).then((n) {
        if (!mounted) return;
        setState(() => _displayName = n);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;

    final phoneNumber = (m['phoneNumber'] ?? '').toString();
    final plateNumber = (m['plateNumber'] ?? '').toString();
    final avatarUrl = (m['avatarUrl'] ?? '').toString();
    final vehiclePhotoUrl = (m['vehiclePhotoUrl'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Header + quick actions
          Stack(
            alignment: Alignment.topRight,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 0, right: 0),
                child: _ProfileHeader(
                  name: _displayName,
                  phone: phoneNumber.isNotEmpty
                      ? phoneNumber
                      : (SessionStore.phoneId ?? ''),
                  avatarUrl: avatarUrl,
                ),
              ),
              Material(
                color: Colors.transparent,
                child: IconButton(
                  tooltip: 'เปลี่ยนรูปโปรไฟล์',
                  onPressed: widget.onChangeAvatar,
                  icon: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFFFF5E8),
                    child: Icon(Icons.photo_camera_outlined,
                        color: Color(0xFFFD8700)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: widget.onEditProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFD8700),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit),
            label: const Text('แก้ไขข้อมูลไรเดอร์'),
          ),

          const SizedBox(height: 24),
          _PersonalInfoSection(
            name: _displayName,
            phone: phoneNumber.isNotEmpty
                ? phoneNumber
                : (SessionStore.phoneId ?? ''),
          ),
          const SizedBox(height: 28),
          _VehicleInfoSection(
            plateNumber: plateNumber,
            vehiclePhotoUrl: vehiclePhotoUrl,
            onEdit: widget.onEditVehicle,
          ),
          const SizedBox(height: 28),
          _LogoutButton(onPressed: widget.onLogout),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.phone,
    required this.avatarUrl,
  });

  final String name;
  final String phone;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
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
        const SizedBox(height: 20),
        Text(
          name.isEmpty ? 'ไรเดอร์' : name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        if (phone.isNotEmpty)
          Text(
            phone,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              letterSpacing: 0.3,
            ),
          ),
      ],
    );
  }
}

class _PersonalInfoSection extends StatelessWidget {
  const _PersonalInfoSection({
    required this.name,
    required this.phone,
  });

  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'ข้อมูลส่วนตัว'),
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

class _VehicleInfoSection extends StatelessWidget {
  const _VehicleInfoSection({
    required this.plateNumber,
    required this.vehiclePhotoUrl,
    this.onEdit,
  });

  final String plateNumber;
  final String vehiclePhotoUrl;
  final VoidCallback? onEdit;

  static const _orange = Color(0xFFFD8700);
  static const _lightOrange = Color(0xFFFFB84D);

  @override
  Widget build(BuildContext context) {
    final hasPhoto = vehiclePhotoUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'ข้อมูลรถ'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(color: Colors.orange.shade50, width: 1),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade50, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        color: _orange, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'ทะเบียน',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: .2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1D6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _orange.withOpacity(.15)),
                      ),
                      child: Text(
                        plateNumber.isEmpty ? '-' : plateNumber,
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 18, color: _orange),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _orange),
                  foregroundColor: _orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text(
                  'แก้ไข',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: hasPhoto
                    ? Image.network(
                        vehiclePhotoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                        loadingBuilder: (ctx, child, progress) {
                          if (progress == null) return child;
                          return _loading();
                        },
                      )
                    : _placeholder(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black54, Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.two_wheeler,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasPhoto ? 'รูปรถของคุณ' : 'ยังไม่มีรูปรถ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade100,
      child: Center(
        child:
            Icon(Icons.image_outlined, color: Colors.grey.shade400, size: 42),
      ),
    );
  }

  Widget _loading() {
    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: const Color(0xFFFD8700),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ],
      ),
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
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5E8),
              borderRadius: BorderRadius.circular(10),
            ),
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
                    color: Colors.black87,
                  ),
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

class _VehiclePhotoCard extends StatelessWidget {
  const _VehiclePhotoCard({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade200,
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: Colors.grey,
                size: 40,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey.shade100,
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
                    strokeWidth: 2,
                  ),
                ),
              ),
            );
          },
        ),
      ),
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
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: widget.onPressed,
            icon: const Icon(Icons.logout, size: 20),
            label: const Text(
              'ออกจากระบบ',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotFoundBox extends StatelessWidget {
  const _NotFoundBox({
    required this.text,
    required this.onRetry,
    required this.onLogout,
  });

  final String text;
  final VoidCallback onRetry;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.orange.shade400,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onRetry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFF5E8),
                          foregroundColor: const Color(0xFFFD8700),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('ลองดึงใหม่'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text('ออกจากระบบ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
