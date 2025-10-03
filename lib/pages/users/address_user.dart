import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/user_address.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // SessionStore (userId / phoneId)
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

class AddressUser extends StatefulWidget {
  const AddressUser({Key? key}) : super(key: key);

  @override
  State<AddressUser> createState() => _AddressUserState();
}

class _AddressUserState extends State<AddressUser> {
  // ===== Resolve UID แบบอัจฉริยะ =====
  Future<String?> _resolveUidSmart() async {
    final fs = FirebaseFirestore.instance;

    // 1) จาก session (userId)
    final ssUid = SessionStore.userId;
    if (ssUid != null && ssUid.isNotEmpty) {
      final ok = await fs.collection('users').doc(ssUid).get();
      if (ok.exists) return ssUid;
    }

    // 2) จาก mapping phone_to_uid
    final phone = SessionStore.phoneId;
    if (phone != null && phone.isNotEmpty) {
      final map = await fs.collection('phone_to_uid').doc(phone).get();
      final mapped = (map.data()?['uid'] ?? '').toString();
      if (mapped.isNotEmpty) {
        final ok = await fs.collection('users').doc(mapped).get();
        if (ok.exists) return mapped;
      }

      // 3) ค้น users ที่ field phone = เบอร์
      final q = await fs
          .collection('users')
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) return q.docs.first.id;

      // 4) legacy: users/{phone}
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
            body: Center(child: Text('ยังไม่ได้ล็อกอิน หรือหา UID ไม่เจอ')),
          );
        }

        // อ่านคอลเลกชันราก addressuser ของผู้ใช้คนนี้
        final q = FirebaseFirestore.instance
            .collection('addressuser')
            .where('userId', isEqualTo: uid);

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            title: const Text(
              'ที่อยู่ของฉัน',
              style: TextStyle(color: orange, fontWeight: FontWeight.w800),
            ),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
              }

              var docs = snap.data?.docs.toList() ?? [];
              if (docs.isEmpty) return const _EmptyHint();

              // เรียง “ที่อยู่หลัก” มาก่อน -> created_at ใหม่ก่อน
              docs.sort((a, b) {
                final da = ((a.data()['is_default'] ?? false) == true) ? 0 : 1;
                final db = ((b.data()['is_default'] ?? false) == true) ? 0 : 1;
                if (da != db) return da.compareTo(db);
                final ta = a.data()['created_at'];
                final tb = b.data()['created_at'];
                final ai = (ta is Timestamp) ? ta.millisecondsSinceEpoch : 0;
                final bi = (tb is Timestamp) ? tb.millisecondsSinceEpoch : 0;
                return bi.compareTo(ai);
              });

              // map -> model ตามลำดับที่ sort แล้ว
              final items = docs.map((d) {
                final m = d.data();
                return UserAddress.fromJson(d.id, m,
                    userId: (m['userId'] ?? uid) as String);
              }).toList();

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final a = items[i];
                  return Container(
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      title: Row(
                        children: [
                          Text(a.nameLabel,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          if (a.isDefault) ...[
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
                                  color: orange,
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
                          a.addressText,
                          style: const TextStyle(height: 1.3),
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'default') {
                            await _setDefaultAddress(uid, a.id);
                          } else if (v == 'delete') {
                            await _deleteAddress(a.id);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'default',
                              child: Text('ตั้งเป็นที่อยู่หลัก')),
                          PopupMenuItem(
                              value: 'delete', child: Text('ลบที่อยู่นี้')),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => _openAddAddressSheet(uid),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('เพิ่มที่อยู่'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddAddressSheet(String uid) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF5E8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddAddressSheet(uid: uid),
    );
  }

  Future<void> _setDefaultAddress(String uid, String addressId) async {
    final fs = FirebaseFirestore.instance;
    final col = fs.collection('addressuser');
    final batch = fs.batch();

    final all = await col.where('userId', isEqualTo: uid).get();
    for (final d in all.docs) {
      batch.update(d.reference, {'is_default': d.id == addressId});
    }
    await batch.commit();

    Get.snackbar('สำเร็จ', 'ตั้งที่อยู่หลักเรียบร้อย',
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> _deleteAddress(String addressId) async {
    await FirebaseFirestore.instance
        .collection('addressuser')
        .doc(addressId)
        .delete();
    Get.snackbar('สำเร็จ', 'ลบที่อยู่นี้แล้ว',
        snackPosition: SnackPosition.BOTTOM);
  }
}

// ---------- Empty hint ----------
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ที่อยู่ของฉัน',
            style: TextStyle(
              color: Color(0xFFFD8700),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.location_off_outlined),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'ยังไม่มีที่อยู่ — กด “เพิ่มที่อยู่” เพื่อบันทึก')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- Bottom sheet: add address ----------
class _AddAddressSheet extends StatefulWidget {
  const _AddAddressSheet({required this.uid, Key? key}) : super(key: key);
  final String uid;

  @override
  State<_AddAddressSheet> createState() => _AddAddressSheetState();
}

class _AddAddressSheetState extends State<_AddAddressSheet> {
  final _label = TextEditingController();
  final _detail = TextEditingController();
  final _phone = TextEditingController();
  bool _isDefault = false;
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _detail.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFD8700);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 5,
            width: 44,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Text('เพิ่มที่อยู่',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration:
                _deco('ชื่อกำกับ (เช่น บ้าน, ที่ทำงาน)', Icons.label_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _detail,
            minLines: 3,
            maxLines: 5,
            decoration: _deco(
                'ที่อยู่ (ตำบล อำเภอ จังหวัด ประเทศไทย)', Icons.home_outlined),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: _deco('เบอร์โทร', Icons.phone_outlined),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('ตั้งที่อยู่หลัก'),
              const Spacer(),
              Switch(
                value: _isDefault,
                activeColor: const Color(0xFFFD8700),
                onChanged: (v) => setState(() => _isDefault = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFD8700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('เพิ่มที่อยู่',
                      style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey),
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  // geocode ไทย + ลองหลายรูปแบบ + Fallback Google Geocoding API
  Future<({double? lat, double? lng})> _tryGeocode(String address) async {
    Future<({double? lat, double? lng})> _goSystem(String q) async {
      try {
        final list = await locationFromAddress(q, localeIdentifier: 'th_TH');
        if (list.isNotEmpty) {
          final loc = list.first;
          return (lat: loc.latitude, lng: loc.longitude);
        }
      } catch (e) {
        // ระบบเครื่องหาไม่ได้/ไม่รองรับ
        debugPrint('[geo] system geocode error: $e');
      }
      return (lat: null, lng: null);
    }

    // 1) พยายามด้วย system geocoder หลายรูปแบบ
    final tries = <String>[
      address,
      '$address ประเทศไทย',
      '$address, ประเทศไทย',
      '$address, Thailand',
    ];
    for (final t in tries) {
      final r = await _goSystem(t);
      if (r.lat != null) return r;
    }

    // 2) FALLBACK: Google Geocoding REST
    const googleApiKey = 'YOUR_GOOGLE_API_KEY'; // TODO: ใส่คีย์จริงของคุณ
    final url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': address,
      'region': 'th', // bias ประเทศไทย
      'language': 'th',
      'key': googleApiKey,
    });

    try {
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final status = (data['status'] as String?) ?? 'UNKNOWN';
        if (status == 'OK') {
          final results = (data['results'] as List);
          if (results.isNotEmpty) {
            final loc = results.first['geometry']['location'];
            final lat = (loc['lat'] as num).toDouble();
            final lng = (loc['lng'] as num).toDouble();
            return (lat: lat, lng: lng);
          }
        } else {
          debugPrint(
              '[geo] google status=$status msg=${data['error_message']}');
        }
      } else {
        debugPrint('[geo] google http=${res.statusCode} body=${res.body}');
      }
    } catch (e) {
      debugPrint('[geo] google geocode error: $e');
    }

    // 3) ไม่พบจริง ๆ
    return (lat: null, lng: null);
  }

  Future<void> _save() async {
    final nameLabel = _label.text.trim();
    final addressText = _detail.text.trim();
    final phone = _phone.text.trim();

    if (nameLabel.isEmpty || addressText.isEmpty) {
      Get.snackbar('กรอกไม่ครบ', 'กรุณากรอกชื่อกำกับและที่อยู่',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    setState(() => _saving = true);
    final fs = FirebaseFirestore.instance;
    final col = fs.collection('addressuser');

    try {
      final now = FieldValue.serverTimestamp();
      final pos = await _tryGeocode(addressText);

      if (pos.lat == null || pos.lng == null) {
        debugPrint('[geo] not found for address="$addressText"');
      }

      // ใช้ model แล้วแปลง JSON ตาม schema
      final model = UserAddress(
        id: '_new_',
        userId: widget.uid,
        nameLabel: nameLabel,
        addressText: addressText,
        lat: pos.lat,
        lng: pos.lng,
        isDefault: false,
      );

      final payload = model.toJson()
        ..addAll({
          'userId': widget.uid,
          'created_at': now,
          'updated_at': now,
          'phone': phone,
          if (pos.lat != null && pos.lng != null) ...{
            'lat': pos.lat,
            'lng': pos.lng,
            'geopoint': GeoPoint(pos.lat!, pos.lng!),
          },
        });

      final ref = await col.add(payload);

      // ตั้งค่า default ถ้าติ๊ก
      if (_isDefault) {
        final batch = fs.batch();
        final all = await col.where('userId', isEqualTo: widget.uid).get();
        for (final d in all.docs) {
          batch.update(d.reference, {'is_default': d.id == ref.id});
        }
        await batch.commit();
      }

      if (pos.lat == null) {
        Get.snackbar('บันทึกแล้ว (ไม่มีพิกัด)',
            'หาแผนที่จากที่อยู่ไม่เจอ — ลองพิมพ์ละเอียดขึ้น เช่น อำเภอ จังหวัด ประเทศ',
            snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('สำเร็จ', 'เพิ่มที่อยู่เรียบร้อย',
            snackPosition: SnackPosition.BOTTOM);
      }

      Get.back();
    } catch (e) {
      Get.snackbar('ผิดพลาด', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
