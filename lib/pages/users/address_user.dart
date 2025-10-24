
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/user_address.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_address_repository.dart';
import 'package:deliverydomo/services/th_geocoder.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AddressUser extends StatefulWidget {
  const AddressUser({Key? key}) : super(key: key);

  @override
  State<AddressUser> createState() => _AddressUserState();
}

class _AddressUserState extends State<AddressUser> {
  late final AddressRepository _repo;
  late final ThaiGeocoder _geocoder;

  @override
  void initState() {
    super.initState();
    _repo = AddressRepository();
  }

  Future<String?> _resolveUid() => _repo.resolveUidSmart(
        sessionUserId: SessionStore.userId,
        sessionPhone: SessionStore.phoneId,
      );

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFD8700);
    const bg = Color(0xFFFFF5E8);

    return FutureBuilder<String?>(
      future: _resolveUid(),
      builder: (context, uidSnap) {
        if (uidSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final uid = uidSnap.data ?? '';
        if (uid.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('ยังไม่ได้ล็อกอิน หรือหา UID ไม่เจอ')),
          );
        }

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
            stream: _repo.streamAddresses(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
              }

              var docs = snap.data?.docs.toList() ?? [];
              if (docs.isEmpty) return const _EmptyHint();

              
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
                        child: Text(a.addressText,
                            style: const TextStyle(height: 1.3)),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'default') {
                            await _repo.setDefaultAddress(uid, a.id);
                            Get.snackbar('สำเร็จ', 'ตั้งที่อยู่หลักเรียบร้อย',
                                snackPosition: SnackPosition.BOTTOM);
                          } else if (v == 'delete') {
                            await _repo.deleteAddress(a.id);
                            Get.snackbar('สำเร็จ', 'ลบที่อยู่นี้แล้ว',
                                snackPosition: SnackPosition.BOTTOM);
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
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddAddressSheet(String uid) async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFFF5E8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddAddressSheet(
        uid: uid,
        repo: _repo,
        geocoder: _geocoder,
      ),
    );

    
    if (result is Map && result['added'] == true) {
      final hasLat = result['latFound'] == true;
      Get.snackbar(
        'สำเร็จ',
        hasLat
            ? 'เพิ่มที่อยู่เรียบร้อย'
            : 'บันทึกแล้ว (ไม่มีพิกัด) — ลองใส่ที่อยู่ละเอียดขึ้นในครั้งถัดไป',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}


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
  const _AddAddressSheet({
    required this.uid,
    required this.repo,
    required this.geocoder,
    Key? key,
  }) : super(key: key);

  final String uid;
  final AddressRepository repo;
  final ThaiGeocoder geocoder;

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

    try {
      final pos = await widget.geocoder.geocode(addressText);

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
          'phone': phone,
          if (pos.lat != null && pos.lng != null) ...{
            'lat': pos.lat,
            'lng': pos.lng,
            'geopoint': GeoPoint(pos.lat!, pos.lng!),
          },
        });

      await widget.repo.addAddress(
        uid: widget.uid,
        payload: payload,
        setDefault: _isDefault,
      );

      
      if (!mounted) return;
      Navigator.of(context).pop({
        'added': true,
        'latFound': pos.lat != null,
      });
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
