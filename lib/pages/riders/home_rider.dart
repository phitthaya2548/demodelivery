// lib/pages/riders/home_rider.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/detail_shipments.dart';
import 'package:deliverydomo/pages/riders/map_rider.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/riders/widgets/bottom.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_rider_showworl.dart';
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

  final _api = FirebaseRiderApi();

  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  Future<void> _accept(String shipmentId) async {
  final riderId = _riderId;
  if (riderId.isEmpty) {
    Get.snackbar('รับงานไม่ได้', 'ยังไม่พบรหัสไรเดอร์ในเซสชัน',
        snackPosition: SnackPosition.BOTTOM);
    return;
  }
  try {
    await _api.acceptShipment(riderId: riderId, shipmentId: shipmentId);

    
    Get.offAll(() => const BottomRider(initialIndex: 2));

    Get.snackbar('สำเร็จ', 'รับงานเรียบร้อย',
        snackPosition: SnackPosition.BOTTOM);
  } catch (e) {
    Get.snackbar('รับงานไม่สำเร็จ', '$e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red[400],
        colorText: Colors.white);
  }
}


  Future<void> _completeOrCancel(String shipmentId,
      {required bool complete}) async {
    final riderId = _riderId;
    if (riderId.isEmpty) return;
    try {
      await _api.completeOrCancel(
        riderId: riderId,
        shipmentId: shipmentId,
        complete: complete,
      );
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
        stream: _api.watchRider(_riderId),
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
                        stream: _api.watchOpenShipments(limit: 80),
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

                          final docs = [...(snap.data ?? [])]..sort((a, b) {
                              int ts(DocumentSnapshot<Map<String, dynamic>> d,
                                  String k) {
                                final v = d.data()?[k];
                                if (v is Timestamp) {
                                  return v.millisecondsSinceEpoch;
                                }
                                return 0;
                              }

                              final bc = ts(b, 'created_at');
                              final ac = ts(a, 'created_at');
                              return bc.compareTo(ac);
                            });

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

                              // -------- keys ที่ตรงกับ payload ล่าสุด --------
                              final itemName =
                                  (m['item_name'] ?? '-').toString();
                              final itemDesc = m['item_description'].toString();

                              final photoUrl = m['last_photo_url'].toString();

                              // snapshots
                              final sender = m['sender_snapshot'];
                              final receiver = m['receiver_snapshot'];

                              // CHANGED: delivery address ใช้ delivery_address_snapshot (มี detail_normalized)
                              final deliverySnap =
                                  m['delivery_address_snapshot'];

                              // sender
                              final sName = (sender['name'] ?? '').toString();
                              final sPhone = sender['phone'].toString();

                              final sPickup = sender['pickup_address'];
                              final String sAddressImmediate =
                                  sPickup['detail_normalized'].toString();

                              final sPickupId =
                                  sender['pickup_address_id'].toString();

                              // receiver
                              final rName = (receiver['name'] ?? '').toString();
                              final rPhone = receiver['phone'].toString();

                              final String rAddressImmediate =
                                  deliverySnap['detail_normalized'].toString();

                              // CHANGED: ใช้ receiver_snapshot.address_id ก่อน แล้วค่อย delivery_address_id บน shipment
                              final rAddrId = receiver['address_id'].toString();

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
                                  loadById: _api.addressTextById,
                                ),
                                receiverName: rName,
                                receiverPhone: rPhone,
                                receiverAddressWidget: _AddressText(
                                  immediateText: rAddressImmediate,
                                  addressIdForFallback: rAddrId,
                                  loadById: _api.addressTextById,
                                ),
                                // ตรงนี้ไม่ต้อง disable เพราะทั้งหน้า list จะถูกซ่อนไปตอนมี current อยู่แล้ว
                                canAccept: true,
                                onAccept: () => _accept(id),

                                // เปิดหน้า details พร้อม id + snapshot
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
    required this.onDetail,
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
  final VoidCallback onDetail;

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
                      onPressed: onDetail,
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
