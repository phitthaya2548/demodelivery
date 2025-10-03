import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // SessionStore (GetStorage)
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileRider extends StatefulWidget {
  const ProfileRider({Key? key}) : super(key: key);

  @override
  State<ProfileRider> createState() => _ProfileRiderState();
}

class _ProfileRiderState extends State<ProfileRider> {
  static const orange = Color(0xFFFD8700);
  static const bg = Color(0xFFFFF5E8);

  Future<void> _logout() async {
    await SessionStore.clearAll();
    if (!mounted) return;
    Get.offAll(() => const LoginPage());
  }

  /// หาตัวเอกสาร riders ที่ตรงกับเซสชันที่มีอยู่
  /// ลองตามลำดับนี้:
  /// 1) riders/{userId}
  /// 2) riders where userId == userId
  /// 3) riders/{phoneId}
  /// 4) riders where userId == phoneId
  /// 5) riders where phoneNumber == phoneId
  Future<DocumentReference<Map<String, dynamic>>?> _findRiderDocRef() async {
    final fs = FirebaseFirestore.instance;
    final riders = fs.collection('riders');

    final userId = (SessionStore.userId ?? '').trim();
    final phoneId = (SessionStore.phoneId ?? '').trim();

    // 1) doc(userId)
    if (userId.isNotEmpty) {
      final doc = await riders.doc(userId).get();
      if (doc.exists) return doc.reference;
    }

    // 2) where userId == userId
    if (userId.isNotEmpty) {
      final q = await riders.where('userId', isEqualTo: userId).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    // 3) doc(phoneId)
    if (phoneId.isNotEmpty) {
      final doc = await riders.doc(phoneId).get();
      if (doc.exists) return doc.reference;
    }

    // 4) where userId == phoneId (บางสคีมาเก็บ userId เป็นเบอร์)
    if (phoneId.isNotEmpty) {
      final q = await riders.where('userId', isEqualTo: phoneId).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    // 5) where phoneNumber == phoneId (จากตัวอย่างที่คุณส่งมา)
    if (phoneId.isNotEmpty) {
      final q =
          await riders.where('phoneNumber', isEqualTo: phoneId).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    }

    return null;
  }

  /// ดึงชื่อจาก users/{uidOrPhone} เผื่อ riders ไม่มี name
  Future<String> _fallbackUserName(String uidOrPhone) async {
    try {
      final u = await FirebaseFirestore.instance
          .collection('users')
          .doc(uidOrPhone)
          .get();
      final m = u.data() ?? {};
      return (m['name'] ?? m['fullname'] ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneId = SessionStore.phoneId ?? '';

    if (phoneId.isEmpty) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('ไม่พบหมายเลขในเซสชัน (phoneId ว่าง)'),
              const SizedBox(height: 12),
              _LogoutButton(onPressed: _logout),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar:  customAppBar(),
      body: SafeArea(
        child: FutureBuilder<DocumentReference<Map<String, dynamic>>?>(
          future: _findRiderDocRef(),
          builder: (context, refSnap) {
            if (refSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final ref = refSnap.data;
            if (ref == null) {
              // แสดงค่าที่มีเพื่อไล่บั๊กได้ง่าย
              final debugText =
                  'หา riders ไม่เจอจาก session:\nuserId=${SessionStore.userId}\nphoneId=${SessionStore.phoneId}\n'
                  'ลองตรวจสอบว่า field ใน riders เป็น userId หรือ phoneNumber และค่าตรงกับเซสชันหรือไม่';
              return _NotFoundBox(
                text: debugText,
                onRetry: () => setState(() {}),
                onLogout: _logout,
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: ref.snapshots(),
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
                  m: m,
                  // เลือกค่าอ้างอิงชื่อผู้ใช้จาก userId ถ้ามี ไม่งั้นลองใช้ phoneNumber
                  uidForName:
                      (m['userId'] ?? m['phoneNumber'] ?? '').toString(),
                  fallbackUserName: _fallbackUserName,
                  onLogout: _logout,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RiderBody extends StatefulWidget {
  const _RiderBody({
    required this.m,
    required this.uidForName,
    required this.fallbackUserName,
    required this.onLogout,
  });

  final Map<String, dynamic> m;
  final String uidForName;
  final Future<String> Function(String uidOrPhone) fallbackUserName;
  final VoidCallback onLogout;

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

    final phoneNumber =
        (m['phoneNumber'] ?? '').toString(); // บางสคีมาเก็บเบอร์
    final status = (m['status'] ?? '').toString();
    final plateNumber = (m['plateNumber'] ?? '').toString();
    final avatarUrl = (m['avatarUrl'] ?? '').toString();
    final vehiclePhotoUrl = (m['vehiclePhotoUrl'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white,
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 48, color: Colors.grey)
                  : null,
            ),
          ),
          const SizedBox(height: 16),

          const _SectionTitle(title: 'ข้อมูลส่วนตัว'),
          const SizedBox(height: 8),

          _ReadonlyField(
            icon: Icons.badge_outlined,
            hint: 'name',
            value: _displayName.isEmpty ? '-' : _displayName,
          ),

          const SizedBox(height: 10),
          _ReadonlyField(
            icon: Icons.phone_outlined,
            hint: 'phoneNumber',
            value: phoneNumber.isNotEmpty
                ? phoneNumber
                : (SessionStore.phoneId ?? '-'),
          ),
         
          const SizedBox(height: 12),

          _LogoutButton(onPressed: widget.onLogout),
          const SizedBox(height: 20),

          const _SectionTitle(title: 'ข้อมูลรถ'),
          const SizedBox(height: 8),
          _ReadonlyField(
            icon: Icons.two_wheeler_outlined,
            hint: 'เลขทะเบียนรถ',
            value: plateNumber.isEmpty ? '-' : plateNumber,
          ),
          const SizedBox(height: 12),

          if (vehiclePhotoUrl.isNotEmpty) ...[
            const _SectionTitle(title: 'รูปรถ'),
            const SizedBox(height: 8),
            _ImageCard(url: vehiclePhotoUrl),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFFFD8700),
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    );
  }
}

class _ReadonlyField extends StatelessWidget {
  const _ReadonlyField({
    required this.icon,
    required this.hint,
    required this.value,
  });

  final IconData icon;
  final String hint;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextField(
      readOnly: true,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      controller: TextEditingController(text: value),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDDDDDD)),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.network(url, fit: BoxFit.cover),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFE9E9),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: onPressed,
          icon: const Icon(Icons.logout),
          label: const Text('logout',
              style: TextStyle(fontWeight: FontWeight.w700)),
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
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองดึงใหม่'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE53935),
                      foregroundColor: Colors.white),
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('ออกจากระบบ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
