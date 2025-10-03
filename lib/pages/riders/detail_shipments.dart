// lib/pages/riders/detail_shipments.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DetailShipments extends StatefulWidget {
  const DetailShipments({Key? key}) : super(key: key);

  @override
  State<DetailShipments> createState() => _DetailShipmentsState();
}

class _DetailShipmentsState extends State<DetailShipments> {
  static const _orange = Color(0xFFFD8700);
  static const _bg = Color(0xFFF8F6F2);

  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

  // ===== Utils =====
  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  Future<String> _loadAddressTextById(String id) async {
    if (id.isEmpty) return '';
    final snap = await FirebaseFirestore.instance
        .collection('addressuser')
        .doc(id)
        .get();
    if (!snap.exists) return '';
    final m = (snap.data() ?? {}) as Map<String, dynamic>;
    return (m['address_text'] ?? m['detail'] ?? '').toString();
  }

  // ดึง URL รูปจาก map แบบ recursive: หาคีย์ที่มีคำว่า photo/avatar/image/picture/pic/url
  String _pickPhotoUrl(Map<String, dynamic> m) {
    String? found;

    bool looksLikeUrl(dynamic v) {
      if (v is! String) return false;
      final s = v.trim();
      return s.startsWith('https://') || s.startsWith('http://');
    }

    void walk(dynamic node) {
      if (found != null) return;
      if (node is Map) {
        for (final entry in node.entries) {
          final k = entry.key.toString().toLowerCase();
          final v = entry.value;

          if (looksLikeUrl(v)) {
            if (k.contains('photo') ||
                k.contains('avatar') ||
                k.contains('image') ||
                k.contains('picture') ||
                k.contains('pic') ||
                k == 'url' ||
                k.contains('profile')) {
              found = v.toString().trim();
              return;
            }
          }

          if (v is Map || v is List) walk(v);
        }
      } else if (node is List) {
        for (final e in node) {
          if (found != null) return;
          walk(e);
        }
      }
    }

    walk(m);
    return found ?? '';
  }

  // สร้างตัวอักษรย่อจากชื่อ (รองรับไทย/อังกฤษ) ถ้าว่าง ใช้ "คุณ"
  String _initials(String name) {
    var n = name.trim();
    if (n.isEmpty) n = 'คุณ';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'ค';
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return (parts.first.characters.take(1).toString() +
        parts.last.characters.take(1).toString());
  }

  // ===== Transactions =====
  Future<void> _accept(String shipmentId) async {
    final riderId = _riderId;
    if (riderId.isEmpty) {
      Get.snackbar('รับงานไม่ได้', 'ยังไม่พบรหัสไรเดอร์ในเซสชัน',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final fs = FirebaseFirestore.instance;
    final riderRef = fs.collection('riders').doc(riderId);
    final shipRef = fs.collection('shipments').doc(shipmentId);

    try {
      await fs.runTransaction((tx) async {
        final riderSnap = await tx.get(riderRef);
        final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
        final current = (riderData['current_shipment_id'] ?? '').toString();
        if (current.isNotEmpty) {
          throw Exception('คุณมีงานที่กำลังทำอยู่ (#$current)');
        }

        final shipSnap = await tx.get(shipRef);
        if (!shipSnap.exists) {
          throw Exception('งานถูกลบแล้ว');
        }
        final m = shipSnap.data() as Map<String, dynamic>;
        final s = m['status'];
        final status = (s is int) ? s : int.tryParse('$s') ?? 0;
        if (status != 1) {
          throw Exception('งานนี้ถูกคนอื่นรับไปแล้ว');
        }

        tx.set(
          riderRef,
          {
            'current_shipment_id': shipmentId,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        tx.update(shipRef, {
          'status': 2,
          'rider_id': riderId,
          'updated_at': FieldValue.serverTimestamp(),
        });
      });

      Get.back(); // ปิดหน้ารายละเอียด
      Get.snackbar('สำเร็จ', 'รับงานเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('รับงานไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    // รับ argument จาก Get
    final args = (Get.arguments ?? {}) as Map?;
    final shipmentId = (args?['shipment_id'] ?? args?['id'] ?? '').toString();
    final initialSnapshot =
        (args?['snapshot'] ?? const <String, dynamic>{}) as Map?;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _orange,
        title: const Text('รายละเอียด'),
        elevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
      ),
      body: shipmentId.isEmpty
          ? const Center(child: Text('ไม่พบรหัสงาน'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('shipments')
                  .doc(shipmentId)
                  .snapshots(),
              builder: (context, snap) {
                // ใช้ข้อมูลเริ่มต้นก่อน ถ้า stream ยังมาไม่ถึง
                final data = (snap.data?.data() ??
                        (initialSnapshot ?? <String, dynamic>{}))
                    as Map<String, dynamic>;

                if (!snap.hasData && (data.isEmpty)) {
                  return const Center(child: CircularProgressIndicator());
                }

                // ---- สกัดฟิลด์หลัก ----
                final brand = 'Delivery WarpSong';
                final photoUrl =
                    (data['last_photo_url'] ?? data['photo_url'] ?? '')
                        .toString();
                final itemName =
                    (data['item_name'] ?? data['itemName'] ?? '-').toString();
                final itemDesc =
                    (data['item_description'] ?? data['itemDescription'] ?? '')
                        .toString();
                final statusRaw = data['status'];
                final status = (statusRaw is int)
                    ? statusRaw
                    : int.tryParse('$statusRaw') ?? 0;

                // sender / receiver & snapshot
                final sender =
                    _asMap(data['sender_snapshot'] ?? data['sender']);
                final receiver =
                    _asMap(data['receiver_snapshot'] ?? data['receiver']);
                final deliverySnap =
                    _asMap(data['delivery_address_snapshot'] ?? {});
                final pickupSnap = _asMap(sender['pickup_address']);

                // sender
                final sName = (sender['name'] ?? '').toString();
                final sPhone =
                    (sender['phone'] ?? sender['phoneNumber'] ?? '').toString();
                final sPickupId = (sender['pickup_address_id'] ??
                        data['pickup_address_id'] ??
                        '')
                    .toString();
                final sAddressImmediate = (pickupSnap['detail'] ??
                        pickupSnap['address_text'] ??
                        _asMap(sender['address'])['address_text'] ??
                        '')
                    .toString();
                final sAvatarUrl = _pickPhotoUrl(sender);

                // receiver
                final rName = (receiver['name'] ?? '').toString();
                final rPhone =
                    (receiver['phone'] ?? receiver['phoneNumber'] ?? '')
                        .toString();
                final rAddrId = (receiver['address_id'] ??
                        data['delivery_address_id'] ??
                        '')
                    .toString();
                final rAddressImmediate = (deliverySnap['detail'] ??
                        deliverySnap['address_text'] ??
                        _asMap(receiver['address'])['address_text'] ??
                        '')
                    .toString();
                final rAvatarUrl = _pickPhotoUrl(receiver);

                final canAccept = status == 1; // งานว่างเท่านั้น

                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  child: Column(
                    children: [
                      // การ์ดรายละเอียด
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: _orange, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                alignment: Alignment.centerLeft,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6.0),
                                child: const Text(
                                  'รายละเอียดรายการสินค้า',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              AspectRatio(
                                aspectRatio: 16 / 9,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: photoUrl.isEmpty
                                      ? Container(
                                          color: const Color(0xFFEFEFEF),
                                          child: const Icon(
                                            Icons.image,
                                            size: 48,
                                            color: Colors.black26,
                                          ),
                                        )
                                      : Image.network(
                                          photoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            color: const Color(0xFFEFEFEF),
                                            child: const Icon(
                                              Icons.broken_image_outlined,
                                              size: 48,
                                              color: Colors.black26,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                brand,
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // ผู้ส่ง
                              _PersonBlock(
                                title: 'ผู้ส่ง',
                                name: sName,
                                phone: sPhone,
                                addressWidget: _AddressText(
                                  immediateText: sAddressImmediate,
                                  addressIdForFallback: sPickupId,
                                  loadById: _loadAddressTextById,
                                ),
                                avatarUrl: sAvatarUrl,
                                initials: _initials(sName),
                              ),
                              const Divider(height: 20),

                              // ผู้รับ
                              _PersonBlock(
                                title: 'ผู้รับ',
                                name: rName,
                                phone: rPhone,
                                addressWidget: _AddressText(
                                  immediateText: rAddressImmediate,
                                  addressIdForFallback: rAddrId,
                                  loadById: _loadAddressTextById,
                                ),
                                avatarUrl: rAvatarUrl,
                                initials: _initials(rName),
                              ),

                              const SizedBox(height: 8),
                              if (itemName.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('สินค้า: $itemName',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                              ],
                              if (itemDesc.isNotEmpty)
                                Text('รายละเอียด: $itemDesc'),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // ปุ่ม “รับงาน” + “กลับ”
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton(
                                onPressed: canAccept
                                    ? () => _accept(shipmentId)
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _orange,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      const Color(0xFFCCCCCC),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                child: const Text('รับงาน'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 42,
                              child: OutlinedButton(
                                onPressed: () => Get.back(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _orange,
                                  side: const BorderSide(
                                      color: _orange, width: 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                child: const Text('กลับ'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ===== Sub-widgets =====

class _PersonBlock extends StatelessWidget {
  const _PersonBlock({
    required this.title,
    required this.name,
    required this.phone,
    required this.addressWidget,
    required this.avatarUrl,
    required this.initials,
  });

  final String title;
  final String name;
  final String phone;
  final Widget addressWidget;

  // รูปโปรไฟล์ (ถ้าไม่มีจะโชว์ตัวอักษรย่อ)
  final String avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Avatar
        Container(
          margin: const EdgeInsets.only(top: 2),
          height: 44,
          width: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          child: ClipOval(
            child: hasAvatar
                ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        _InitialsAvatar(initials: initials),
                  )
                : _InitialsAvatar(initials: initials),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.black87, height: 1.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.black54)),
                const SizedBox(height: 2),
                Text(
                  name.isEmpty ? '-' : name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (phone.isNotEmpty)
                  Text('โทร: $phone',
                      style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ที่อยู่: ',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Expanded(child: addressWidget),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFECECEC),
      alignment: Alignment.center,
      child: Text(
        (initials.isEmpty ? '–' : initials),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 16,
          color: Colors.black54,
        ),
      ),
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('กำลังโหลดที่อยู่...',
              maxLines: 2, overflow: TextOverflow.ellipsis);
        }
        final txt = (snap.data ?? '').toString();
        return Text(txt.isEmpty ? '-' : txt,
            maxLines: 2, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
