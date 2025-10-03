import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/pages/users/follow_item.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// ===============================================
/// ListorderUser
/// - แท็บ "ส่งของ" / "รับของ"
/// - อ่านที่อยู่หลาย path (top-level + snapshot เก่า)
/// - รองรับ detail_normalized / address_text / detail
/// - รองรับ GeoPoint และ map {latitude,longitude}
/// - Fallback เป็นชื่อ/เบอร์ เมื่อไม่มีที่อยู่
/// - แสดง "ชื่อผู้รับ (พร้อมเบอร์)" เด่นด้านบนของการ์ด
/// - แสดง label + detail ของที่อยู่ทั้งฝั่งรับและส่ง
/// - มีโหมดดีบักโชว์ path ที่พบ
/// ===============================================
class ListorderUser extends StatefulWidget {
  const ListorderUser({Key? key}) : super(key: key);

  @override
  State<ListorderUser> createState() => _ListorderUserState();
}

class _ListorderUserState extends State<ListorderUser>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFF8F6F2);
  late final TabController _tab;

  String get _uid => (SessionStore.userId ?? '').toString();
  String get _phone => (SessionStore.phoneId ?? '').toString();
  String get _meAny => _uid.isNotEmpty ? _uid : _phone;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ============== Firestore Streams (ไม่ใช้ orderBy เพื่อไม่ต้องมี index) ==============
  Stream<QuerySnapshot<Map<String, dynamic>>> _mySendStream() {
    final me = _meAny;
    return FirebaseFirestore.instance
        .collection('shipments')
        .where('sender_id', isEqualTo: me)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myReceiveStream() {
    final col = FirebaseFirestore.instance.collection('shipments');
    if (_uid.isNotEmpty) {
      return col.where('receiver_id', isEqualTo: _uid).snapshots();
    }
    // ถ้าไม่มี uid ใช้เบอร์จาก receiver_snapshot.phone
    return col.where('receiver_snapshot.phone', isEqualTo: _phone).snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: customAppBar(),
      body: (_meAny.isEmpty)
          ? const Center(child: Text('ยังไม่พบรหัสผู้ใช้ในเซสชัน'))
          : Column(
              children: [
                // Tabs นอก AppBar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  child: _TopTabs(controller: _tab),
                ),
                const Divider(height: 1, color: Color(0xFFECECEC)),
                // เนื้อหาแท็บ
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _OrderList(stream: _mySendStream(), isSenderSide: true),
                      _OrderList(
                          stream: _myReceiveStream(), isSenderSide: false),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// =================== TOP TABS ===================

class _TopTabs extends StatelessWidget {
  const _TopTabs({Key? key, required this.controller}) : super(key: key);
  final TabController controller;

  static const _orange = Color(0xFFFD8700);

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: controller,
      isScrollable: true,
      indicatorColor: _orange,
      indicatorWeight: 3,
      labelColor: _orange,
      unselectedLabelColor: Colors.black54,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      tabs: const [
        Tab(text: 'ส่งของ'),
        Tab(text: 'รับของ'),
      ],
    );
  }
}

// =================== LIST ===================

class _OrderList extends StatelessWidget {
  const _OrderList({
    Key? key,
    required this.stream,
    required this.isSenderSide,
  }) : super(key: key);

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final bool isSenderSide;

  // เปิด/ปิดโหมดดีบัก: true จะแสดงคีย์ที่พบใต้การ์ด
  static const bool kShowDebug = false;

  int _parseStatus(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
    // 1=รอโอนย้ายสินค้า, 2=ไรเดอร์กำลังไปรับแล้ว, 3=ไรเดอร์รับงาน, 4=จัดส่งสำเร็จ
  }

  String _statusBadge(int s) {
    switch (s) {
      case 1:
        return 'รอโอนย้ายสินค้า';
      case 2:
        return 'ไรเดอร์กำลังไปรับแล้ว';
      case 3:
        return 'ไรเดอร์รับงาน';
      case 4:
        return 'จัดส่งสำเร็จ';
      default:
        return 'ไม่ทราบสถานะ';
    }
  }

  Color _badgeColor(int s) {
    switch (s) {
      case 2:
        return const Color(0xFF3B82F6);
      case 3:
        return const Color(0xFFF59E0B);
      case 4:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF9CA3AF);
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  /// อ่าน label รองรับหลาย key
  String _readLabel(dynamic node) {
    final m = _asMap(node);
    final label =
        (m['label'] ?? m['name'] ?? m['name_address'] ?? '').toString().trim();
    return label;
  }

  /// อ่าน detail แบบรองรับหลาย key และมี fallback
  String _readDetail(dynamic node) {
    final m = _asMap(node);
    final detail =
        (m['detail_normalized'] ?? m['address_text'] ?? m['detail'] ?? '')
            .toString()
            .trim();
    if (detail.isNotEmpty) return detail;

    final label = _readLabel(node);
    final phone = (m['phone'] ?? '').toString().trim();
    final alt = [label, phone].where((e) => e.isNotEmpty).join(' • ');
    if (alt.isNotEmpty) return alt;

    return 'ยังไม่มีรายละเอียดที่อยู่';
  }

  String _fmtLoc(dynamic node) {
    // รองรับ GeoPoint / Map {latitude,longitude} / {_latitude,_longitude}
    if (node is GeoPoint) {
      return '${node.latitude.toStringAsFixed(4)}, ${node.longitude.toStringAsFixed(4)}';
    }
    final m = _asMap(node);
    final lat = m['latitude'] ?? m['_latitude'];
    final lng = m['longitude'] ?? m['_longitude'];
    if (lat is num && lng is num) {
      return '${lat.toDouble().toStringAsFixed(4)}, ${lng.toDouble().toStringAsFixed(4)}';
    }
    return '';
  }

  String _fmtTime(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      final y = d.year.toString().padLeft(4, '0');
      final mo = d.month.toString().padLeft(2, '0');
      final da = d.day.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$y-$mo-$da $hh:$mm';
    }
    return '-';
  }

  /// คืนค่าที่อยู่ + label + ชื่อ/เบอร์ผู้รับ + debug
  ({
    String pickupLabel,
    String pickupText,
    String pickupLatLng,
    String deliveryLabel,
    String deliveryText,
    String deliveryLatLng,
    String receiverName,
    String receiverPhone,
    String debugNote
  }) _extractAddresses(Map<String, dynamic> m) {
    String _label(dynamic node) {
      final a = _asMap(node);
      return (a['label'] ?? a['name'] ?? a['name_address'] ?? '')
          .toString()
          .trim();
    }

    String _detail(dynamic node) => _readDetail(node);
    String _loc(dynamic node) => _fmtLoc(node);
    // ---------- PICKUP ----------
    String pText = '';
    String pLL = '';
    String pLabel = '';

    final topPickup = _asMap(m['pickup_address']);
    if (topPickup.isNotEmpty) {
      pText = _detail(topPickup);
      pLabel = _label(topPickup);
      pLL = _loc(topPickup['location']);
    }
    if (pText.isEmpty) {
      final ss = _asMap(m['sender_snapshot']);
      final spa = _asMap(ss['pickup_address']);
      if (spa.isNotEmpty) {
        pText = _detail(spa);
        if (pLabel.isEmpty) pLabel = _label(spa);
        if (pLL.isEmpty) pLL = _loc(spa['location']);
      }
    }
    if (pText.isEmpty) {
      final ss = _asMap(m['sender_snapshot']);
      final sName = (ss['name'] ?? '').toString();
      final sPhone = (ss['phone'] ?? '').toString();
      pText = [sName, sPhone].where((e) => e.isNotEmpty).join(' • ');
    }
    // >>> บังคับมีข้อความเสมอ (อย่างน้อยเป็นพิกัด)
    if (pText.trim().isEmpty && pLL.isNotEmpty) pText = 'พิกัด: $pLL';
    if (pLabel.trim().isEmpty) pLabel = 'จุดรับของ';

    // ---------- DELIVERY ----------
    String dText = '';
    String dLL = '';
    String dLabel = '';
    String rName = '';
    String rPhone = '';

    final das = _asMap(m['delivery_address_snapshot']);
    if (das.isNotEmpty) {
      dText = _detail(das);
      dLabel = _label(das);
      dLL = _loc(das['location']);
    }
    final rs = _asMap(m['receiver_snapshot']);
    if (dText.isEmpty) {
      final ra = _asMap(rs['address']);
      if (ra.isNotEmpty) {
        dText = _detail(ra);
        if (dLabel.isEmpty) dLabel = _label(ra);
        if (dLL.isEmpty) dLL = _loc(ra['location']);
      }
    }
    rName = (rs['name'] ?? '').toString();
    rPhone = (rs['phone'] ?? '').toString();
    if (dText.isEmpty)
      dText = [rName, rPhone].where((e) => e.isNotEmpty).join(' • ');
    // >>> บังคับมีข้อความเสมอ
    if (dText.trim().isEmpty && dLL.isNotEmpty) dText = 'พิกัด: $dLL';
    if (dLabel.trim().isEmpty) dLabel = 'ปลายทาง';

    // ---------- Debug ----------
    final dbg = StringBuffer();
    dbg.writeln('DEBUG KEYS FOUND:');
    if (topPickup.isNotEmpty) dbg.writeln('- pickup_address ✓');
    if (_asMap(_asMap(m['sender_snapshot'])['pickup_address']).isNotEmpty) {
      dbg.writeln('- sender_snapshot.pickup_address ✓');
    }
    if (das.isNotEmpty) dbg.writeln('- delivery_address_snapshot ✓');
    if (_asMap(_asMap(m['receiver_snapshot'])['address']).isNotEmpty) {
      dbg.writeln('- receiver_snapshot.address ✓');
    }

    return (
      pickupLabel: pLabel,
      pickupText: pText,
      pickupLatLng: pLL,
      deliveryLabel: dLabel,
      deliveryText: dText,
      deliveryLatLng: dLL,
      receiverName: rName,
      receiverPhone: rPhone,
      debugNote: dbg.toString().trim()
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'มีข้อผิดพลาดจาก Firestore:\n${snap.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        // ====== จัดเรียงฝั่ง client ตาม updated_at (ใหม่->เก่า) ======
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
            (snap.data?.docs ?? [])
              ..sort((a, b) {
                int ts(DocumentSnapshot<Map<String, dynamic>> d, String k) {
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

        if (docs.isEmpty) {
          return Center(
            child: Text(
              isSenderSide
                  ? 'ยังไม่มีคำสั่งที่คุณส่ง'
                  : 'ยังไม่มีคำสั่งที่คุณรับ',
              style: const TextStyle(color: Colors.black54),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();

            final itemName = (m['item_name'] ?? '-').toString();
            final photoUrl = (m['last_photo_url'] ?? '').toString();
            final st = _parseStatus(m['status']);
            final updatedAt = m['updated_at'];
            final createdAt = m['created_at'];

            final x = _extractAddresses(m);

            return _OrderCard(
                brand: 'Delivery WarpSong',
                docId: d.id,
                itemName: itemName,
                pickupLabel: x.pickupLabel,
                pickupText: x.pickupText,
                pickupLatLng: x.pickupLatLng,
                deliveryLabel: x.deliveryLabel,
                deliveryText: x.deliveryText,
                deliveryLatLng: x.deliveryLatLng,
                receiverName: x.receiverName,
                receiverPhone: x.receiverPhone,
                badgeText: _statusBadge(st),
                badgeColor: _badgeColor(st),
                photoUrl: photoUrl,
                updatedText:
                    'อัปเดต: ${_fmtTime(updatedAt)} • สร้าง: ${_fmtTime(createdAt)}',
                debugNote: kShowDebug ? x.debugNote : null,
                onFollow: () {
                  // ใช้ GetX
                  Get.to(() => FollowItem(shipmentId: d.id));
                });
          },
        );
      },
    );
  }
}

// =================== CARD ===================

// =================== CARD (layout แบบภาพตัวอย่าง) ===================

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    Key? key,
    required this.brand,
    required this.docId, // ยังรับไว้เผื่อใช้ในอนาคต (ไม่แสดงใน UI นี้)
    required this.itemName,
    required this.pickupLabel, // ไม่ใช้ใน layout นี้ แต่คงพารามิเตอร์ไว้ให้คอมไพล์ผ่าน
    required this.pickupText, // "
    required this.pickupLatLng, // "
    required this.deliveryLabel, // ไม่ใช้ (เราโชว์เฉพาะข้อความ address)
    required this.deliveryText,
    required this.deliveryLatLng,
    required this.receiverName, // ไม่ใช้ในบรรทัด แต่คงพารามิเตอร์ไว้
    required this.receiverPhone, // "
    required this.badgeText,
    required this.badgeColor,
    required this.photoUrl,
    required this.updatedText, // ไม่แสดงใน layout นี้
    required this.onFollow,
    this.debugNote,
  }) : super(key: key);

  final String brand;
  final String docId;
  final String itemName;

  final String pickupLabel;
  final String pickupText;
  final String pickupLatLng;

  final String deliveryLabel;
  final String deliveryText;
  final String deliveryLatLng;

  final String receiverName;
  final String receiverPhone;

  final String badgeText;
  final Color badgeColor;
  final String photoUrl;
  final String updatedText;
  final VoidCallback onFollow;
  final String? debugNote;

  static const _orange = Color(0xFFFD8700);
  static const _orangeBorder = Color(0xFFFFC58B);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _orangeBorder, width: 1.6),
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: brand + status badge
            Row(
              children: [
                Container(
                  height: 28,
                  width: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1D6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: _orange, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    brand,
                    style: const TextStyle(
                      color: _orange,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(.12),
                    border: Border.all(color: badgeColor, width: 1.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Body: left image, right texts
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // image placeholder
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 64,
                    width: 64,
                    color: const Color(0xFFEFEFEF),
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.image, color: Colors.black26)
                        : Image.network(photoUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                // right column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ชื่อสินค้า หนา
                      Text(
                        itemName.isEmpty ? '-' : itemName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // ผู้รับ: <address>
                      Text(
                        'ผู้รับ: ${deliveryText.isEmpty ? "-" : deliveryText}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // พิกัด
                      if (deliveryLatLng.isNotEmpty)
                        Text(
                          'พิกัด: $deliveryLatLng',
                          style: const TextStyle(
                            color: Colors.black54,
                            height: 1.2,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // Debug (ถ้าเปิด)
            if (debugNote != null && debugNote!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                debugNote!,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF6B7280), height: 1.2),
              ),
            ],

            const SizedBox(height: 12),

            // Follow button
            SizedBox(
              height: 42,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                child: const Text('ติดตาม'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
