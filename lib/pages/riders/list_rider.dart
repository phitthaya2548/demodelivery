import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart'; // ใช้ SessionStore.userId / phoneId
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ListRider extends StatefulWidget {
  const ListRider({Key? key}) : super(key: key);

  @override
  State<ListRider> createState() => _ListRiderState();
}

class _ListRiderState extends State<ListRider> {
  static const _orange = Color(0xFFFD8700);
  static const _bg = Color(0xFFF8F6F2);

  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  // ======== PHOTO LOADER (NEW) ========
  final Map<String, String> _photoCache = {}; // key = uid|phone

  Future<String> _fetchUserPhotoByUid(String uid) async {
    if (uid.isEmpty) return '';
    final key = 'uid:$uid';
    if (_photoCache.containsKey(key)) return _photoCache[key]!;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (snap.exists) {
        final m = snap.data() ?? {};
        final url = (m['photoUrl'] ?? m['avatarUrl'] ?? m['avatar_url'] ?? '')
            .toString();
        _photoCache[key] = url;
        return url;
      }
    } catch (_) {}
    _photoCache[key] = '';
    return '';
  }

  Future<String> _fetchUserPhotoByPhone(String phone) async {
    if (phone.isEmpty) return '';
    final key = 'phone:$phone';
    if (_photoCache.containsKey(key)) return _photoCache[key]!;
    try {
      // map phone -> uid
      final map = await FirebaseFirestore.instance
          .collection('phone_to_uid')
          .doc(phone)
          .get();
      final uid = (map.data()?['uid'] ?? '').toString();
      if (uid.isNotEmpty) {
        final url = await _fetchUserPhotoByUid(uid);
        _photoCache[key] = url;
        return url;
      }
      // legacy: users/{phone}
      final legacy =
          await FirebaseFirestore.instance.collection('users').doc(phone).get();
      if (legacy.exists) {
        final m = legacy.data() ?? {};
        final url = (m['photoUrl'] ?? m['avatarUrl'] ?? m['avatar_url'] ?? '')
            .toString();
        _photoCache[key] = url;
        return url;
      }
    } catch (_) {}
    _photoCache[key] = '';
    return '';
  }

  // โหลดข้อความที่อยู่จาก addressuser/{id} เมื่อ snapshot ไม่มี detail
  Future<String> _loadAddressTextById(String id) async {
    if (id.isEmpty) return '';
    final snap = await FirebaseFirestore.instance
        .collection('addressuser')
        .doc(id)
        .get();
    if (!snap.exists) return '';
    final m = snap.data() ?? {};
    return (m['address_text'] ?? m['detail'] ?? '').toString();
  }

  // ---- stream ดูล็อกงานปัจจุบันของไรเดอร์
  Stream<DocumentSnapshot<Map<String, dynamic>>> _riderLockStream() {
    if (_riderId.isEmpty) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('riders')
        .doc(_riderId)
        .snapshots();
  }

  // stream งานทั้งหมดของเรา (ไว้กรองต่อในฝั่งแอป)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _mineStream() {
    final q = FirebaseFirestore.instance
        .collection('shipments')
        .where('rider_id', isEqualTo: _riderId)
        .limit(80);
    return q.snapshots().map((s) => s.docs);
  }

  // โหลด 1 งานตาม id (เมื่อมี current_shipment_id)
  Stream<DocumentSnapshot<Map<String, dynamic>>> _shipmentById(String id) {
    return FirebaseFirestore.instance
        .collection('shipments')
        .doc(id)
        .snapshots();
  }

  // อัปเดตสถานะด้วย transaction (กันชนกัน) + ตรวจล็อกให้ตรงกับงาน
  Future<void> _updateStatus(String shipmentId, int from, int to) async {
    final fs = FirebaseFirestore.instance;
    final riderRef = fs.collection('riders').doc(_riderId);
    final shipRef = fs.collection('shipments').doc(shipmentId);

    try {
      await fs.runTransaction((tx) async {
        final riderSnap = await tx.get(riderRef);
        final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
        final current = (riderData['current_shipment_id'] ?? '').toString();

        // ต้องล็อกตรงกับงานที่กำลังอัปเดตเท่านั้น
        if (current != shipmentId) {
          throw Exception('งานนี้ไม่ใช่งานที่ถูกล็อกอยู่ (#$current)');
        }

        final snap = await tx.get(shipRef);
        if (!snap.exists) throw Exception('เอกสารถูกลบแล้ว');

        final m = snap.data() as Map<String, dynamic>;
        final riderId = (m['rider_id'] ?? '').toString();
        final s = m['status'];
        final status = (s is int) ? s : int.tryParse('$s') ?? 0;

        if (riderId != _riderId) {
          throw Exception('งานนี้ไม่ใช่ของคุณ');
        }
        if (status != from) {
          throw Exception('สถานะเปลี่ยนไปแล้ว');
        }

        tx.update(shipRef, {
          'status': to,
          'updated_at': FieldValue.serverTimestamp(),
        });

        // ถ้าปิดงาน (to >= 4) ให้ปลดล็อกไรเดอร์
        if (to >= 4) {
          tx.update(riderRef, {
            'current_shipment_id': FieldValue.delete(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      });

      Get.snackbar('สำเร็จ', 'อัปเดตสถานะเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('อัปเดตไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar:  customAppBar(),
      body: (_riderId.isEmpty)
          ? const Center(child: Text('ยังไม่พบรหัสไรเดอร์ในเซสชัน'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _riderLockStream(),
              builder: (context, riderSnap) {
                final riderData = riderSnap.data?.data() ?? {};
                final currentId =
                    (riderData['current_shipment_id'] ?? '').toString();
                final hasCurrent = currentId.isNotEmpty;

                // ถ้ามี current -> แสดงเฉพาะ “งานเดียว” ตาม lock
                if (hasCurrent) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _shipmentById(currentId),
                    builder: (context, shipSnap) {
                      if (shipSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!shipSnap.hasData || !shipSnap.data!.exists) {
                        return const Center(
                            child: Text('ไม่พบงานที่ถูกล็อกไว้'));
                      }
                      final doc = shipSnap.data!;
                      final m = doc.data() as Map<String, dynamic>? ?? {};

                      final id = (m['id'] ?? doc.id).toString();
                      final itemName = (m['item_name'] ?? '-').toString();
                      final itemDesc = (m['item_description'] ?? '').toString();
                      final photoUrl = (m['last_photo_url'] ?? '').toString();

                      final s = m['status'];
                      final statusVal =
                          (s is int) ? s : int.tryParse('$s') ?? 0;

                      final sender = _asMap(m['sender_snapshot']);
                      final receiver = _asMap(m['receiver_snapshot']);
                      final deliverySnap =
                          _asMap(m['delivery_address_snapshot']);

                      final sName = (sender['name'] ?? '').toString();
                      final sPhone = (sender['phone'] ?? '').toString();
                      // immediate avatar (if any) from snapshot
                      final sImmediateAvatar = (sender['avatar_url'] ??
                              sender['photoUrl'] ??
                              sender['avatarUrl'] ??
                              sender['photo_url'] ??
                              '')
                          .toString();
                      final sPickup = _asMap(sender['pickup_address']);
                      String sAddressImmediate = (sPickup['detail'] ??
                              sPickup['address_text'] ??
                              _asMap(sender['address'])['address_text'] ??
                              '')
                          .toString();
                      final sPickupId = (sender['pickup_address_id'] ??
                              m['pickup_address_id'] ??
                              '')
                          .toString();
                      final sUid = (sender['user_id'] ?? '').toString();

                      final rName = (receiver['name'] ?? '').toString();
                      final rPhone = (receiver['phone'] ?? '').toString();
                      final rImmediateAvatar = (receiver['avatar_url'] ??
                              receiver['photoUrl'] ??
                              receiver['avatarUrl'] ??
                              receiver['photo_url'] ??
                              '')
                          .toString();
                      String rAddressImmediate = (deliverySnap['detail'] ??
                              deliverySnap['address_text'] ??
                              _asMap(receiver['address'])['address_text'] ??
                              '')
                          .toString();
                      final rAddrId = (receiver['address_id'] ??
                              m['delivery_address_id'] ??
                              '')
                          .toString();
                      final rUid = (receiver['user_id'] ?? '').toString();

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        children: [
                          _lockedBanner(currentId),
                          _ShipmentDetailCard(
                            brand: 'Delivery WarpSong',
                            itemName: itemName,
                            itemDesc: itemDesc,
                            photoUrl: photoUrl,
                            senderName: sName,
                            senderPhone: sPhone,
                            senderAvatar: _Avatar(
                              immediateUrl: sImmediateAvatar,
                              uid: sUid,
                              phone: sPhone,
                              loaderByUid: _fetchUserPhotoByUid,
                              loaderByPhone: _fetchUserPhotoByPhone,
                              radius: 20,
                            ),
                            senderAddressWidget: _AddressText(
                              immediateText: sAddressImmediate,
                              addressIdForFallback: sPickupId,
                              loadById: _loadAddressTextById,
                            ),
                            receiverName: rName,
                            receiverPhone: rPhone,
                            receiverAvatar: _Avatar(
                              immediateUrl: rImmediateAvatar,
                              uid: rUid,
                              phone: rPhone,
                              loaderByUid: _fetchUserPhotoByUid,
                              loaderByPhone: _fetchUserPhotoByPhone,
                              radius: 20,
                            ),
                            receiverAddressWidget: _AddressText(
                              immediateText: rAddressImmediate,
                              addressIdForFallback: rAddrId,
                              loadById: _loadAddressTextById,
                            ),
                            status: statusVal,
                            onTakeProofPhoto: () {
                              Get.snackbar('ถ่ายรูป', 'ฟีเจอร์กำลังพัฒนา',
                                  snackPosition: SnackPosition.BOTTOM);
                            },
                            onStepAction: () async {
                              if (statusVal == 2) {
                                await _updateStatus(id, 2, 3);
                              } else if (statusVal == 3) {
                                await _updateStatus(id, 3, 4);
                              } else if (statusVal >= 4) {
                                Get.snackbar('แจ้งเตือน', 'งานนี้ปิดจ๊อบแล้ว',
                                    snackPosition: SnackPosition.BOTTOM);
                              }
                            },
                          ),
                        ],
                      );
                    },
                  );
                }

                // ถ้าไม่มี current -> แสดงงานของเราเฉพาะที่ "กำลังทำ" (2/3)
                return StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: _mineStream(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('เกิดข้อผิดพลาด: ${snap.error}'),
                      );
                    }

                    final all = snap.data ?? [];
                    // กรองเฉพาะสถานะ 2/3 (ที่ยังทำอยู่)
                    final active = all.where((d) {
                      final s = d.data()['status'];
                      final st = (s is int) ? s : int.tryParse('$s') ?? 0;
                      return st == 2 || st == 3;
                    }).toList();

                    if (active.isEmpty) {
                      return const Center(child: Text('ยังไม่มีงานที่รับ'));
                    }

                    // ถ้ามีมากกว่า 1 งาน แสดงแถบเตือน (ข้อมูลผิดปกติ)
                    final hasAnomaly = active.length > 1;

                    // sort: updated_at -> created_at
                    active.sort((a, b) {
                      int ts(
                          DocumentSnapshot<Map<String, dynamic>> d, String k) {
                        final v = d.data()?[k];
                        if (v is Timestamp) return v.millisecondsSinceEpoch;
                        return 0;
                      }

                      final bu = ts(b, 'updated_at');
                      final au = ts(a, 'updated_at');
                      if (bu != au) return bu.compareTo(au);
                      final bc = ts(b, 'created_at');
                      final ac = ts(a, 'created_at');
                      return bc.compareTo(ac);
                    });

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      itemCount: active.length + (hasAnomaly ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (hasAnomaly && i == 0) {
                          return _warnBanner();
                        }

                        final doc = active[hasAnomaly ? i - 1 : i];
                        final m = doc.data();

                        final id = (m['id'] ?? doc.id).toString();
                        final itemName = (m['item_name'] ?? '-').toString();
                        final itemDesc =
                            (m['item_description'] ?? '').toString();
                        final photoUrl = (m['last_photo_url'] ?? '').toString();

                        final stRaw = m['status'];
                        final statusVal = (stRaw is int)
                            ? stRaw
                            : int.tryParse('$stRaw') ?? 0;

                        final sender = _asMap(m['sender_snapshot']);
                        final receiver = _asMap(m['receiver_snapshot']);
                        final deliverySnap =
                            _asMap(m['delivery_address_snapshot']);

                        final sName = (sender['name'] ?? '').toString();
                        final sPhone = (sender['phone'] ?? '').toString();
                        final sImmediateAvatar = (sender['avatar_url'] ??
                                sender['photoUrl'] ??
                                sender['avatarUrl'] ??
                                sender['photo_url'] ??
                                '')
                            .toString();
                        final sPickup = _asMap(sender['pickup_address']);
                        String sAddressImmediate = (sPickup['detail'] ??
                                sPickup['address_text'] ??
                                _asMap(sender['address'])['address_text'] ??
                                '')
                            .toString();
                        final sPickupId = (sender['pickup_address_id'] ??
                                m['pickup_address_id'] ??
                                '')
                            .toString();
                        final sUid = (sender['user_id'] ?? '').toString();

                        final rName = (receiver['name'] ?? '').toString();
                        final rPhone = (receiver['phone'] ?? '').toString();
                        final rImmediateAvatar = (receiver['avatar_url'] ??
                                receiver['photoUrl'] ??
                                receiver['avatarUrl'] ??
                                receiver['photo_url'] ??
                                '')
                            .toString();
                        String rAddressImmediate = (deliverySnap['detail'] ??
                                deliverySnap['address_text'] ??
                                _asMap(receiver['address'])['address_text'] ??
                                '')
                            .toString();
                        final rAddrId = (receiver['address_id'] ??
                                m['delivery_address_id'] ??
                                '')
                            .toString();
                        final rUid = (receiver['user_id'] ?? '').toString();

                        return _ShipmentDetailCard(
                          brand: 'Delivery WarpSong',
                          itemName: itemName,
                          itemDesc: itemDesc,
                          photoUrl: photoUrl,
                          senderName: sName,
                          senderPhone: sPhone,
                          senderAvatar: _Avatar(
                            immediateUrl: sImmediateAvatar,
                            uid: sUid,
                            phone: sPhone,
                            loaderByUid: _fetchUserPhotoByUid,
                            loaderByPhone: _fetchUserPhotoByPhone,
                            radius: 20,
                          ),
                          senderAddressWidget: _AddressText(
                            immediateText: sAddressImmediate,
                            addressIdForFallback: sPickupId,
                            loadById: _loadAddressTextById,
                          ),
                          receiverName: rName,
                          receiverPhone: rPhone,
                          receiverAvatar: _Avatar(
                            immediateUrl: rImmediateAvatar,
                            uid: rUid,
                            phone: rPhone,
                            loaderByUid: _fetchUserPhotoByUid,
                            loaderByPhone: _fetchUserPhotoByPhone,
                            radius: 20,
                          ),
                          receiverAddressWidget: _AddressText(
                            immediateText: rAddressImmediate,
                            addressIdForFallback: rAddrId,
                            loadById: _loadAddressTextById,
                          ),
                          status: statusVal,
                          onTakeProofPhoto: () {
                            Get.snackbar('ถ่ายรูป', 'ฟีเจอร์กำลังพัฒนา',
                                snackPosition: SnackPosition.BOTTOM);
                          },
                          onStepAction: () async {
                            if (statusVal == 2) {
                              await _updateStatus(id, 2, 3);
                            } else if (statusVal == 3) {
                              await _updateStatus(id, 3, 4);
                            } else if (statusVal >= 4) {
                              Get.snackbar('แจ้งเตือน', 'งานนี้ปิดจ๊อบแล้ว',
                                  snackPosition: SnackPosition.BOTTOM);
                            }
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _lockedBanner(String currentId) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0D8),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFD79A)),
        ),
        child: Text(
          'กำลังทำงานอยู่ (#$currentId) — ปิดงานก่อนจึงจะรับงานใหม่ได้',
          style: const TextStyle(
              color: Color(0xFF7A4D00), fontWeight: FontWeight.w700),
        ),
      );

  Widget _warnBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0F0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFB4B4)),
        ),
        child: const Text(
          'พบหลายงานที่สถานะกำลังทำอยู่ ทั้งที่ไม่มีล็อก — โปรดตรวจสอบข้อมูล หรือให้แอดมินคืนงาน/ปิดงานที่ไม่ถูกต้อง',
          style:
              TextStyle(color: Color(0xFF7A0000), fontWeight: FontWeight.w700),
        ),
      );
}

// ---------- Widgets ----------

class _Avatar extends StatelessWidget {
  const _Avatar({
    Key? key,
    required this.immediateUrl,
    required this.uid,
    required this.phone,
    required this.loaderByUid,
    required this.loaderByPhone,
    this.radius = 20,
  }) : super(key: key);

  final String immediateUrl;
  final String uid;
  final String phone;
  final Future<String> Function(String uid) loaderByUid;
  final Future<String> Function(String phone) loaderByPhone;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // ถ้ามี URL ใน snapshot ใช้ทันที
    if (immediateUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFFF2F2F2),
        backgroundImage: NetworkImage(immediateUrl),
      );
    }

    // มิฉะนั้นพยายามโหลดจาก users/{uid} หรือ map phone->uid
    Future<String> fut() async {
      if (uid.isNotEmpty) {
        final u = await loaderByUid(uid);
        if (u.isNotEmpty) return u;
      }
      if (phone.isNotEmpty) {
        final p = await loaderByPhone(phone);
        return p;
      }
      return '';
    }

    return FutureBuilder<String>(
      future: fut(),
      builder: (context, snap) {
        final url = (snap.data ?? '').toString();
        if (url.isNotEmpty) {
          return CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFF2F2F2),
            backgroundImage: NetworkImage(url),
          );
        }
        // loading/empty -> icon
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFF2F2F2),
          child: const Icon(Icons.person_outline, color: Colors.black45),
        );
      },
    );
  }
}

class _AddressText extends StatelessWidget {
  const _AddressText({
    Key? key,
    required this.immediateText,
    required this.addressIdForFallback,
    required this.loadById,
  }) : super(key: key);

  final String immediateText;
  final String addressIdForFallback;
  final Future<String> Function(String id) loadById;

  @override
  Widget build(BuildContext context) {
    if (immediateText.trim().isNotEmpty) {
      return Text(immediateText, maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    if (addressIdForFallback.isEmpty) {
      return const Text('-', maxLines: 2, overflow: TextOverflow.ellipsis);
    }
    return FutureBuilder<String>(
      future: loadById(addressIdForFallback),
      builder: (context, snap) {
        final txt = (snap.data ?? '').toString();
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('กำลังโหลดที่อยู่...',
              maxLines: 2, overflow: TextOverflow.ellipsis);
        }
        if (txt.isEmpty) {
          return const Text('-', maxLines: 2, overflow: TextOverflow.ellipsis);
        }
        return Text(txt, maxLines: 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}

class _ShipmentDetailCard extends StatelessWidget {
  const _ShipmentDetailCard({
    Key? key,
    required this.brand,
    required this.itemName,
    required this.itemDesc,
    required this.photoUrl,
    required this.senderName,
    required this.senderPhone,
    required this.senderAvatar, // ✅ เปลี่ยนเป็น Widget
    required this.senderAddressWidget,
    required this.receiverName,
    required this.receiverPhone,
    required this.receiverAvatar, // ✅ เปลี่ยนเป็น Widget
    required this.receiverAddressWidget,
    required this.status,
    required this.onTakeProofPhoto,
    required this.onStepAction,
  }) : super(key: key);

  final String brand;
  final String itemName;
  final String itemDesc;
  final String photoUrl;

  final String senderName;
  final String senderPhone;
  final Widget senderAvatar; // ✅
  final Widget senderAddressWidget;

  final String receiverName;
  final String receiverPhone;
  final Widget receiverAvatar; // ✅
  final Widget receiverAddressWidget;

  final int status;
  final VoidCallback onTakeProofPhoto;
  final VoidCallback onStepAction;

  static const _orange = Color(0xFFFD8700);
  static const _orangeLight = Color(0xFFFFF0D8);
  static const _green = Color(0xFF22C55E);

  String get _statusText {
    switch (status) {
      case 2:
        return 'ไรเดอร์รับงานแล้วและกำลังเดินทางไปรับ';
      case 3:
        return 'รับพัสดุแล้ว กำลังจัดส่ง';
      case 4:
        return 'จัดส่งเสร็จสิ้น';
      default:
        return 'สถานะไม่ทราบ';
    }
  }

  String get _primaryBtnText {
    switch (status) {
      case 2:
        return 'รับสินค้าแล้ว';
      case 3:
        return 'รับสินค้าปลายทางแล้ว';
      default:
        return 'ปิดงานแล้ว';
    }
  }

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _orange, width: 2),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x14323232),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  height: 28,
                  width: 28,
                  decoration: BoxDecoration(
                    color: _orangeLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: _orange, size: 18),
                ),
                const SizedBox(width: 8),
                Text(brand,
                    style: const TextStyle(
                        color: _orange, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),

            // รูปสินค้า + ชื่อ
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: photoUrl.isEmpty
                      ? Container(
                          height: 96,
                          width: 140,
                          color: const Color(0xFFEFEFEF),
                          child: const Icon(Icons.image, color: Colors.black26),
                        )
                      : Image.network(
                          photoUrl,
                          height: 96,
                          width: 140,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DefaultTextStyle(
                    style: const TextStyle(height: 1.25, color: Colors.black87),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('สินค้า: $itemName',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        if (itemDesc.isNotEmpty)
                          Text('รายละเอียด: $itemDesc',
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text('Delivery WarpSong',
                style: TextStyle(
                    color: _orange, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 10),

            _PersonRow(
              title: 'ผู้ส่ง',
              name: senderName,
              phone: senderPhone,
              avatar: senderAvatar, // ✅ ใช้ Avatar widget
              addressWidget: senderAddressWidget,
            ),
            const Divider(height: 22, color: Color(0xFFFFE4BD), thickness: 1),

            _PersonRow(
              title: 'ผู้รับ',
              name: receiverName,
              phone: receiverPhone,
              avatar: receiverAvatar, // ✅ ใช้ Avatar widget
              addressWidget: receiverAddressWidget,
            ),

            const SizedBox(height: 16),

            // กล่องสถานะ + ปุ่มถ่ายรูป
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFFFAF3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _orangeLight, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.camera_alt_outlined, color: _orange),
                        SizedBox(width: 8),
                        Text('ถ่ายรูปประกอบสถานะ',
                            style: TextStyle(
                                color: _orange, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _orangeLight, width: 1.2),
                          ),
                          child: Text(
                            _statusText,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Spacer(),
                        Text(
                            'ขั้นตอน ${status == 2 ? "2/4" : status == 3 ? "3/4" : "4/4"}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, color: _orange)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onTakeProofPhoto,
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _orangeLight, width: 1.5),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_a_photo_outlined,
                                size: 36, color: Colors.black54),
                            SizedBox(height: 6),
                            Text('แตะเพื่อถ่ายรูป',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (status >= 4) ? null : onStepAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (status >= 4) ? Colors.grey : _green,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
                child: Text(_primaryBtnText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    Key? key,
    required this.title,
    required this.name,
    required this.phone,
    required this.avatar, // ✅ new
    required this.addressWidget,
  }) : super(key: key);

  final String title;
  final String name;
  final String phone;
  final Widget avatar; // ✅
  final Widget addressWidget;

  static const _orange = Color(0xFFFD8700);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar, // ✅ ใช้ Avatar widget ที่โหลดรูปอัตโนมัติ
        const SizedBox(width: 12),
        Expanded(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87, height: 1.24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _orange, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('คุณ $name',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (phone.isNotEmpty)
                  Text('เบอร์: $phone',
                      style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 2),
                const Text('ที่อยู่',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                addressWidget,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
