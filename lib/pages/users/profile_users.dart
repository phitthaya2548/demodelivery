import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/login.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/pages/users/address_user.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ProfileUser extends StatelessWidget {
  const ProfileUser({Key? key}) : super(key: key);

  /// หา uid โดยลองหลายทาง เพื่อรองรับทั้งสคีมาใหม่/เก่า
  Future<String?> _resolveUidSmart() async {
    final fs = FirebaseFirestore.instance;

    // 1) จาก session
    final ssUid = SessionStore.userId;
    if (ssUid != null && ssUid.isNotEmpty) {
      final ok = await fs.collection('users').doc(ssUid).get();
      if (ok.exists) return ssUid;
    }

    // 2) จาก mapping phone_to_uid
    final phone = SessionStore.phoneId;
    if (phone != null && phone.isNotEmpty) {
      final map = await fs.collection('phone_to_uid').doc(phone).get();
      final uidFromMap = (map.data()?['uid'] ?? '').toString();
      if (uidFromMap.isNotEmpty) {
        final ok = await fs.collection('users').doc(uidFromMap).get();
        if (ok.exists) return uidFromMap;
      }

      // 3) query users ด้วย phone
      final q = await fs
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      // 4) fallback เอกสารเก่า users/{phone}
      final legacy = await fs.collection('users').doc(phone).get();
      if (legacy.exists) return phone;
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFD8700);
    const bg = Color(0xFFFFF5E8);

    return FutureBuilder<String?>(
      future: _resolveUidSmart(),
      builder: (context, uidSnap) {
        if (uidSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final uid = uidSnap.data ?? '';
        if (uid.isEmpty) {
          return const Scaffold(
            body: Center(
                child: Text('ยังไม่ได้ล็อกอิน หรือหา uid ของผู้ใช้ไม่เจอ')),
          );
        }

        final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: const Text(
              'Delivery WarpSong',
              style: TextStyle(color: orange, fontWeight: FontWeight.w700),
            ),
          ),
          body: SafeArea(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: userDoc.snapshots(),
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
                final name =
                    (data['name'] ?? data['fullname'] ?? '').toString();
                final phone =
                    (data['phone'] ?? SessionStore.phoneId ?? '').toString();
                final avatarUrl =
                    (data['avatarUrl'] ?? data['photoUrl'] ?? '').toString();

                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: Colors.white,
                        backgroundImage: avatarUrl.isNotEmpty
                            ? NetworkImage(avatarUrl)
                            : null,
                        child: avatarUrl.isEmpty
                            ? const Icon(Icons.person,
                                size: 48, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(height: 16),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'ข้อมูลส่วนตัว',
                          style: TextStyle(
                            color: orange,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      _ReadonlyTile(
                        icon: Icons.badge_outlined,
                        label: 'name',
                        value: name.isEmpty ? '-' : name,
                      ),
                      const SizedBox(height: 8),
                      _ReadonlyTile(
                        icon: Icons.phone_outlined,
                        label: 'phone number',
                        value: phone.isEmpty ? '-' : phone,
                      ),
                      const SizedBox(height: 16),

                      _LogoutButton(
                        onPressed: () async {
                          await SessionStore.clearAll();
                          Get.offAll(() => const LoginPage());
                        },
                      ),

                      const SizedBox(height: 20),

                      Row(
                        children: [
                          const Text(
                            'ที่อยู่',
                            style: TextStyle(
                              color: orange,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => Get.to(() => const AddressUser()),
                            icon: const Icon(Icons.add_location_alt_outlined),
                            label: const Text('เพิ่มที่อยู่'),
                            style:
                                TextButton.styleFrom(foregroundColor: orange),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // ⬇️ ใช้ addressuser (คอลเลกชันราก) แทน subcollection เดิม
                      _AddressList(uid: uid),
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

class _ReadonlyTile extends StatelessWidget {
  const _ReadonlyTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 12, height: 1.0)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          onPressed: onPressed,
          icon: const Icon(Icons.logout),
          label: const Text(
            'logout',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// รายการที่อยู่แบบย่อ — อ่านจากคอลเลกชันราก `addressuser`
class _AddressList extends StatelessWidget {
  const _AddressList({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('addressuser')
        .where('userId', isEqualTo: uid);
    // ไม่ใช้ orderBy หลายอัน เพื่อเลี่ยง composite index — เราจะ sort ฝั่ง client

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _EmptyCard(
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return _EmptyCard(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
        }

        var docs = snapshot.data?.docs.toList() ?? [];
        if (docs.isEmpty) {
          return const _EmptyCard(
            child: Text('ยังไม่มีที่อยู่ — กด “เพิ่มที่อยู่” เพื่อบันทึก'),
          );
        }

        // ดัน “หลัก” มาก่อน แล้วค่อยตาม created_at ล่าสุด
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
          children: show.map((d) {
            final m = d.data();
            final label = (m['label'] ?? m['name'] ?? 'ที่อยู่').toString();
            final detail = (m['detail'] ?? m['address_text'] ?? '').toString();
            final phone = (m['phone'] ?? '').toString();
            final isDefault = (m['is_default'] ?? false) == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                title: Row(
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1D6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'หลัก',
                          style: TextStyle(
                            color: Color(0xFFFD8700),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$detail ${phone.isNotEmpty ? '\n$phone' : ''}',
                    style: const TextStyle(height: 1.3),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Get.to(() => const AddressUser()),
              ),
            );
          }).toList(),
        );
      },
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
