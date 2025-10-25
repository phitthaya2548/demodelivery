import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/pages/users/follow_item.dart';
import 'package:deliverydomo/services/firebase_reueries.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ListorderUser extends StatefulWidget {
  const ListorderUser({Key? key}) : super(key: key);

  @override
  State<ListorderUser> createState() => _ListorderUserState();
}

class _ListorderUserState extends State<ListorderUser>
    with SingleTickerProviderStateMixin {
  static const _primaryOrange = Color(0xFFFD8700);
  static const _lightOrange = Color(0xFFFFB84D);

  late final TabController _tab;
  final FirebaseShipmentsApi _api = FirebaseShipmentsApi();

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

  Stream<QuerySnapshot<Map<String, dynamic>>> _mySendStream() {
    return _api.watchSent(_meAny);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myReceiveStream() {
    return _api.watchReceived(uid: _uid, phone: _phone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryOrange, _lightOrange],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _primaryOrange.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: customAppBar(),
        ),
      ),
      body: (_meAny.isEmpty)
          ? Center(
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.person_off_outlined,
                        size: 48,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ยังไม่พบรหัสผู้ใช้',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'กรุณาเข้าสู่ระบบก่อนใช้งาน',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                const SizedBox(height: kToolbarHeight + 8),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: _TopTabs(controller: _tab),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _OrderList(
                        stream: _mySendStream(),
                        isSenderSide: true,
                        api: _api,
                      ),
                      _OrderList(
                        stream: _myReceiveStream(),
                        isSenderSide: false,
                        api: _api,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TopTabs extends StatelessWidget {
  const _TopTabs({Key? key, required this.controller}) : super(key: key);
  final TabController controller;

  static const _orange = Color(0xFFFD8700);
  static const _lightOrange = Color(0xFFFFB84D);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 4, top: 50),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [_orange, _lightOrange],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _orange.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(width: 8),
                Text('ส่งของ'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(width: 8),
                Text('รับของ'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  const _OrderList({
    Key? key,
    required this.stream,
    required this.isSenderSide,
    required this.api,
  }) : super(key: key);

  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final bool isSenderSide;
  final FirebaseShipmentsApi api;

  int _parseStatus(dynamic v) {
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }

  String _statusBadge(int s) {
    switch (s) {
      case 1:
        return 'รอไรเดอร์มารับ';
      case 2:
        return 'กำลังมารับ';
      case 3:
        return 'กำลังไปส่ง';
      case 4:
        return 'ส่งสำเร็จ';
      default:
        return 'ไม่ทราบสถานะ';
    }
  }

  Color _badgeColor(int s) {
    switch (s) {
      case 1:
        return const Color(0xFF9CA3AF);
      case 2:
        return const Color(0xFF3B82F6);
      case 3:
        return const Color(0xFFF59E0B);
      case 4:
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _statusIcon(int s) {
    switch (s) {
      case 1:
        return Icons.hourglass_empty;
      case 2:
        return Icons.directions_bike;
      case 3:
        return Icons.local_shipping;
      case 4:
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  String _readDetail(dynamic node) {
    final m = _asMap(node);
    final detail =
        (m['detail_normalized'] ?? m['detail'] ?? '').toString().trim();
    if (detail.isNotEmpty) return detail;

    final label = (m['label'] ?? '').toString().trim();
    final phone = (m['phone'] ?? '').toString().trim();
    final alt = [label, phone].where((e) => e.isNotEmpty).join(' • ');
    if (alt.isNotEmpty) return alt;

    return 'ยังไม่มีรายละเอียดที่อยู่';
  }

  String _fmtLoc(dynamic node) {
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
      final now = DateTime.now();
      final diff = now.difference(d);

      if (diff.inMinutes < 1) return 'เมื่อสักครู่';
      if (diff.inHours < 1) return '${diff.inMinutes} นาทีที่แล้ว';
      if (diff.inDays < 1) return '${diff.inHours} ชั่วโมงที่แล้ว';
      if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';

      final y = d.year.toString().padLeft(4, '0');
      final mo = d.month.toString().padLeft(2, '0');
      final da = d.day.toString().padLeft(2, '0');
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$da/$mo/$y $hh:$mm';
    }
    return '-';
  }

  ({
    String pickupLabel,
    String pickupText,
    String pickupLatLng,
    String deliveryLabel,
    String deliveryText,
    String deliveryLatLng,
    String receiverName,
    String receiverPhone,
  }) _extractAddresses(Map<String, dynamic> m) {
    String _label(dynamic node) {
      final a = _asMap(node);
      return (a['label'] ?? '').toString().trim();
    }

    String _detail(dynamic node) => _readDetail(node);
    String _loc(dynamic node) => _fmtLoc(node);

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
    if (pText.trim().isEmpty && pLL.isNotEmpty) pText = 'พิกัด: $pLL';
    if (pLabel.trim().isEmpty) pLabel = 'จุดรับของ';

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
    if (dText.isEmpty) {
      dText = [rName, rPhone].where((e) => e.isNotEmpty).join(' • ');
    }
    if (dText.trim().isEmpty && dLL.isNotEmpty) dText = 'พิกัด: $dLL';
    if (dLabel.trim().isEmpty) dLabel = 'ปลายทาง';

    return (
      pickupLabel: pLabel,
      pickupText: pText,
      pickupLatLng: pLL,
      deliveryLabel: dLabel,
      deliveryText: dText,
      deliveryLatLng: dLL,
      receiverName: rName,
      receiverPhone: rPhone
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFFFD8700),
                  ),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 16),
                Text(
                  'กำลังโหลดรายการ...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.red.shade200, width: 1),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade700, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'เกิดข้อผิดพลาด',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snap.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.red.shade800,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

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
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isSenderSide
                          ? Icons.inventory_2_outlined
                          : Icons.inbox_outlined,
                      size: 64,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    isSenderSide
                        ? 'ยังไม่มีรายการส่งของ'
                        : 'ยังไม่มีรายการรับของ',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSenderSide
                        ? 'เมื่อคุณส่งของจะแสดงที่นี่'
                        : 'เมื่อมีคนส่งของให้คุณจะแสดงที่นี่',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (_, i) {
            final d = docs[i];
            final m = d.data();

            final itemName = (m['item_name'] ?? '-').toString();
            final itemDesc = (m['item_description'] ?? '').toString().trim();
            final photoUrl =
                (m['last_photo_url'] ?? m['photo_url'] ?? m['image_url'] ?? '')
                    .toString();

            final st = _parseStatus(m['status']);
            final updatedAt = m['updated_at'];

            final x = _extractAddresses(m);

            return FutureBuilder<RiderResolved>(
              future: api.resolveRiderForShipmentMap(m),
              builder: (context, rSnap) {
                final rider = rSnap.data;

                return Dismissible(
                  key: ValueKey(d.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.red.shade400,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    final st = _parseStatus(m['status']);
                    if (st != 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('ลบได้เฉพาะงานที่ส่งสำเร็จเท่านั้น')),
                      );
                      return false;
                    }
                    return await Get.dialog<bool>(
                          Dialog(
                            insetPadding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 24),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Header
                                Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 20, 20, 14),
                                  decoration: const BoxDecoration(
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFFFD8700),
                                        Color(0xFFFFB84D)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  child: Row(
                                    children: const [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: Colors.white,
                                        child: Icon(Icons.delete,
                                            color: Color(0xFFFD8700)),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'ลบรายการนี้?',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                            letterSpacing: .3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Padding(
                                  padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                                  child: Text(
                                    'คุณต้องการลบงานที่ส่งเสร็จแล้วใช่ไหม',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          onPressed: () =>
                                              Get.back(result: false),
                                          child: const Text('ยกเลิก',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () => Get.back(result: true),
                                          child: Ink(
                                            height: 44,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFFFD8700),
                                                  Color(0xFFFFB84D)
                                                ],
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x33FD8700),
                                                  blurRadius: 10,
                                                  offset: Offset(0, 6),
                                                ),
                                              ],
                                            ),
                                            child: const Center(
                                              child: Text(
                                                'ลบ',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: .2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          barrierDismissible: false,
                        ) ??
                        false;
                  },
                  onDismissed: (_) async {
                    try {
                      await api.deleteShipmentIfCompleted(d.id);
                      // หรือถ้าใช้ soft delete:
                      // await api.softDeleteShipmentIfCompleted(d.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ลบรายการแล้ว')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('ลบไม่สำเร็จ: $e')),
                      );
                    }
                  },
                  child: _OrderCard(
                    brand: 'Delivery WarpSong',
                    itemName: itemName,
                    pickupLabel: x.pickupLabel,
                    pickupText: x.pickupText,
                    pickupLatLng: x.pickupLatLng,
                    deliveryLabel: x.deliveryLabel,
                    deliveryText: x.deliveryText,
                    deliveryLatLng: x.deliveryLatLng,
                    receiverName: x.receiverName,
                    receiverPhone: x.receiverPhone,
                    riderName: rider?.name ?? '',
                    riderPhone: rider?.phone ?? '',
                    riderPlate: rider?.plateNumber ?? '',
                    itemDes: itemDesc,
                    statusIcon: _statusIcon(st),
                    badgeText: _statusBadge(st),
                    badgeColor: _badgeColor(st),
                    photoUrl: photoUrl,
                    updatedText: _fmtTime(updatedAt),
                    onFollow: () => Get.to(
                      () => FollowItem(
                        shipmentId: d.id,
                        initialTabIndex:
                            isSenderSide ? 0 : 1, // 0=ส่งของ, 1=รับของ
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(
      {Key? key,
      required this.brand,
      required this.itemName,
      required this.pickupLabel,
      required this.pickupText,
      required this.pickupLatLng,
      required this.deliveryLabel,
      required this.deliveryText,
      required this.deliveryLatLng,
      required this.receiverName,
      required this.receiverPhone,
      required this.riderName,
      required this.riderPhone,
      required this.riderPlate,
      required this.statusIcon,
      required this.badgeText,
      required this.badgeColor,
      required this.photoUrl,
      required this.updatedText,
      required this.onFollow,
      required this.itemDes})
      : super(key: key);

  final String brand;
  final String itemName;
  final String pickupLabel;
  final String pickupText;
  final String pickupLatLng;
  final String deliveryLabel;
  final String deliveryText;
  final String deliveryLatLng;
  final String receiverName;
  final String receiverPhone;
  final String riderName;
  final String riderPhone;
  final String riderPlate;
  final IconData statusIcon;
  final String badgeText;
  final Color badgeColor;
  final String photoUrl;
  final String updatedText;
  final VoidCallback onFollow;
  final String itemDes;
  static const _orange = Color(0xFFFD8700);
  static const _lightOrange = Color(0xFFFFB84D);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _orange.withOpacity(0.1),
                  _lightOrange.withOpacity(0.05)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_orange, _lightOrange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.local_shipping,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        brand,
                        style: const TextStyle(
                          color: _orange,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        updatedText,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        badgeText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item with image
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: photoUrl.isEmpty
                            ? Container(
                                color: Colors.grey.shade100,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: Colors.grey.shade400,
                                  size: 32,
                                ),
                              )
                            : Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade100,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFFD8700),
                                      Color(0xFFFFB84D)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x33FD8700),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.inventory_2_rounded,
                                    size: 16, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  itemName.isEmpty
                                      ? 'ไม่ระบุชื่อสินค้า'
                                      : itemName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: Colors.black87,
                                    height: 1.25,
                                    letterSpacing: .2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (itemDes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF5E8),
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: const Color(0xFFFFE3C2)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.description_outlined,
                                      size: 16, color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      itemDes,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.35,
                                        color: Colors.grey.shade800,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  ],
                ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color.fromARGB(255, 243, 248, 244),
                        Colors.teal.shade50,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.green.shade200,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade600,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            deliveryLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.green.shade800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        deliveryText.isEmpty ? 'ไม่ระบุที่อยู่' : deliveryText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (deliveryLatLng.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.pin_drop,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              deliveryLatLng,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                if (riderName.isNotEmpty ||
                    riderPhone.isNotEmpty ||
                    riderPlate.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _orange.withOpacity(0.08),
                          _lightOrange.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _orange.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_orange, _lightOrange],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _orange.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.delivery_dining,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (riderName.isNotEmpty)
                                Text(
                                  riderName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),
                              if (riderPhone.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      size: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      riderPhone,
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (riderPlate.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ทะเบียน: $riderPlate',
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_orange, _lightOrange],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withOpacity(0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onFollow,
                      borderRadius: BorderRadius.circular(14),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.my_location,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Text(
                              'ติดตามพัสดุ',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
