import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/detail_shipments.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class HomeRider extends StatefulWidget {
  const HomeRider({Key? key}) : super(key: key);

  @override
  State<HomeRider> createState() => _HomeRiderState();
}

class _HomeRiderState extends State<HomeRider> {
  static const _orange = Color(0xFFFD8700);
  static const _bg = Color(0xFFF8F6F2);

  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

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
    final m = snap.data() ?? {};
    return (m['address_text'] ?? m['detail'] ?? '').toString();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _riderStream() {
    final id = _riderId;
    if (id.isEmpty) {
      return const Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance.collection('riders').doc(id).snapshots();
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _shipmentsStream() {
    return FirebaseFirestore.instance
        .collection('shipments')
        .orderBy('created_at', descending: true)
        .limit(80)
        .snapshots()
        .map((s) => s.docs);
  }

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
        if (current.isNotEmpty)
          throw Exception('คุณมีงานที่กำลังทำอยู่ (#$current)');

        final shipSnap = await tx.get(shipRef);
        if (!shipSnap.exists) throw Exception('งานถูกลบแล้ว');
        final m = shipSnap.data() as Map<String, dynamic>;
        final s = m['status'];
        final status = (s is int) ? s : int.tryParse('$s') ?? 0;
        if (status != 1) throw Exception('งานนี้ถูกคนอื่นรับไปแล้ว');

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

      Get.snackbar('สำเร็จ', 'รับงานเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('รับงานไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  Future<void> completeOrCancel(String shipmentId,
      {required bool complete}) async {
    final riderId = _riderId;
    if (riderId.isEmpty) return;

    final fs = FirebaseFirestore.instance;
    final riderRef = fs.collection('riders').doc(riderId);
    final shipRef = fs.collection('shipments').doc(shipmentId);

    try {
      await fs.runTransaction((tx) async {
        final riderSnap = await tx.get(riderRef);
        final riderData = riderSnap.data() as Map<String, dynamic>? ?? {};
        final current = (riderData['current_shipment_id'] ?? '').toString();
        if (current != shipmentId)
          throw Exception('ไม่มีสิทธิ์หรือไม่มีงานนี้ในมือ');

        tx.update(riderRef, {
          'current_shipment_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        tx.update(shipRef, {
          'status': complete ? 3 : 1,
          if (!complete) 'rider_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });

      Get.snackbar(
          'อัปเดตสำเร็จ', complete ? 'ปิดงานเรียบร้อย' : 'คืนงานเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('อัปเดตงานไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: customAppBar(),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _riderStream(),
        builder: (context, riderSnap) {
          final riderData =
              riderSnap.data?.data() as Map<String, dynamic>? ?? {};
          final currentId = (riderData['current_shipment_id'] ?? '').toString();
          final hasCurrent = currentId.isNotEmpty;

          return Column(
            children: [
              Expanded(
                child: hasCurrent
                    ? const Center(
                        child: Text(
                            'กรุณาปิด/คืนงานที่ทำอยู่ก่อน แล้วจึงรับงานใหม่'),
                      )
                    : StreamBuilder<
                        List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                        stream: _shipmentsStream(),
                        builder: (context, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'เกิดข้อผิดพลาด: ${snap.error}\n\n'
                                'ถ้าเป็น failed-precondition ให้ลบ where/orderBy ที่ไม่จำเป็นเพื่อลดการต้องใช้ index',
                              ),
                            );
                          }

                          final docs = (snap.data ?? []).where((d) {
                            final m = d.data();
                            final s = m['status'];
                            final status =
                                (s is int) ? s : int.tryParse('$s') ?? 0;
                            return status == 1; // งานว่างเท่านั้น
                          }).toList();

                          if (docs.isEmpty) {
                            return const Center(
                                child: Text('ยังไม่มีงานที่ว่าง'));
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final Map<String, dynamic> m = docs[i].data();

                              final id = (m['id'] ?? docs[i].id).toString();
                              final itemName =
                                  (m['item_name'] ?? m['itemName'] ?? '-')
                                      .toString();
                              final itemDesc = (m['item_description'] ??
                                      m['itemDescription'] ??
                                      '')
                                  .toString();
                              final photoUrl =
                                  (m['last_photo_url'] ?? m['photo_url'] ?? '')
                                      .toString();

                              final sender =
                                  _asMap(m['sender_snapshot'] ?? m['sender']);
                              final receiver = _asMap(
                                  m['receiver_snapshot'] ?? m['receiver']);
                              final deliverySnap =
                                  _asMap(m['delivery_address_snapshot'] ?? {});

                              final sName = (sender['name'] ?? '').toString();
                              final sPhone = (sender['phone'] ??
                                      sender['phoneNumber'] ??
                                      '')
                                  .toString();
                              final sPickup = _asMap(sender['pickup_address']);
                              final String sAddressImmediate =
                                  (sPickup['detail'] ??
                                          sPickup['address_text'] ??
                                          _asMap(sender['address'])[
                                              'address_text'] ??
                                          '')
                                      .toString();
                              final sPickupId = (sender['pickup_address_id'] ??
                                      m['pickup_address_id'] ??
                                      '')
                                  .toString();

                              final rName = (receiver['name'] ?? '').toString();
                              final rPhone = (receiver['phone'] ??
                                      receiver['phoneNumber'] ??
                                      '')
                                  .toString();
                              final String rAddressImmediate =
                                  (deliverySnap['detail'] ??
                                          deliverySnap['address_text'] ??
                                          _asMap(receiver['address'])[
                                              'address_text'] ??
                                          '')
                                      .toString();
                              final rAddrId = (receiver['address_id'] ??
                                      m['delivery_address_id'] ??
                                      '')
                                  .toString();

                              return _JobCard(
                                brand: 'Delivery WarpSong',
                                photoUrl: photoUrl,
                                itemName: itemName,
                                itemDesc: itemDesc,
                                senderName: sName,
                                senderPhone: sPhone,
                                senderAddressWidget: _AddressText(
                                  immediateText: sAddressImmediate,
                                  addressIdForFallback: sPickupId,
                                  loadById: _loadAddressTextById,
                                ),
                                receiverName: rName,
                                receiverPhone: rPhone,
                                receiverAddressWidget: _AddressText(
                                  immediateText: rAddressImmediate,
                                  addressIdForFallback: rAddrId,
                                  loadById: _loadAddressTextById,
                                ),
                                canAccept: true,
                                onAccept: () => _accept(id),

                                // 👉 นำทางทำที่นี่ (parent) เพราะมี id/m อยู่
                                onDetail: () {
                                  Get.to(
                                    () => const DetailShipments(),
                                    arguments: {
                                      'shipment_id': id,
                                      'snapshot': Map<String, dynamic>.from(m),
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------- Widgets ----------------

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

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.brand,
    required this.photoUrl,
    required this.itemName,
    required this.itemDesc,
    required this.senderName,
    required this.senderPhone,
    required this.senderAddressWidget,
    required this.receiverName,
    required this.receiverPhone,
    required this.receiverAddressWidget,
    required this.onAccept,
    required this.onDetail, // <- รับเป็น callback
    required this.canAccept,
    this.acceptDisabledReason,
  });

  final String brand;
  final String photoUrl;
  final String itemName;
  final String itemDesc;

  final String senderName;
  final String senderPhone;
  final Widget senderAddressWidget;

  final String receiverName;
  final String receiverPhone;
  final Widget receiverAddressWidget;

  final VoidCallback onAccept;
  final VoidCallback onDetail; // <- แค่เรียก ไม่ต้องรู้จัก id/m

  final bool canAccept;
  final String? acceptDisabledReason;

  static const _orange = Color(0xFFFD8700);
  static const _orangeSoft = Color(0xFFFFF0D8);

  @override
  Widget build(BuildContext context) {
    const radius = 16.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _orange, width: 2),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x14323232),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 28,
                  width: 28,
                  decoration: BoxDecoration(
                    color: _orangeSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: _orange, size: 18),
                ),
                const SizedBox(width: 8),
                Text(
                  brand,
                  style: const TextStyle(
                    color: _orange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoUrl.isEmpty
                      ? Container(
                          height: 64,
                          width: 64,
                          color: const Color(0xFFEFEFEF),
                          child: const Icon(Icons.image_not_supported),
                        )
                      : Image.network(
                          photoUrl,
                          height: 64,
                          width: 64,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.black87,
                      height: 1.25,
                      fontSize: 13.5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          itemName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        if (itemDesc.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            itemDesc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                        const SizedBox(height: 10),
                        const _SectionLabel(
                          icon: Icons.place,
                          text: 'รับที่:',
                          color: _orange,
                        ),
                        _NamePhoneLine(name: senderName, phone: senderPhone),
                        Padding(
                          padding: const EdgeInsets.only(left: 22),
                          child: senderAddressWidget,
                        ),
                        const SizedBox(height: 8),
                        const _SectionLabel(
                          icon: Icons.local_shipping_outlined,
                          text: 'ส่งที่:',
                          color: _orange,
                        ),
                        _NamePhoneLine(
                            name: receiverName, phone: receiverPhone),
                        Padding(
                          padding: const EdgeInsets.only(left: 22),
                          child: receiverAddressWidget,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: canAccept
                          ? onAccept
                          : () {
                              if ((acceptDisabledReason ?? '').isNotEmpty) {
                                Get.snackbar(
                                  'รับงานไม่ได้',
                                  acceptDisabledReason!,
                                  snackPosition: SnackPosition.BOTTOM,
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            canAccept ? _orange : const Color(0xFFCCCCCC),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      child: Text(canAccept ? 'รับงาน' : 'มีงานค้างอยู่'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed:
                          onDetail, // <- แค่เรียก callback ที่ parent ส่งมา
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _orange,
                        side: const BorderSide(color: _orange, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      child: const Text('รายละเอียด'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _NamePhoneLine extends StatelessWidget {
  const _NamePhoneLine({required this.name, required this.phone});
  final String name;
  final String phone;

  @override
  Widget build(BuildContext context) {
    final phonePart = (phone.isNotEmpty ? ' · $phone' : '');
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: Colors.black87,
            height: 1.25,
            fontSize: 13.5,
          ),
          children: [
            TextSpan(
              text: name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: phonePart),
          ],
        ),
      ),
    );
  }
}
