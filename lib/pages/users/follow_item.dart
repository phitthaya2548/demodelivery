// lib/pages/follow_item.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
// ถ้ามีโมเดล Shipment ของโปรเจกต์คุณ ใช้ได้ (ไม่จำเป็นต่อไฟล์นี้)
// import 'package:deliverydomo/models/shipment.dart';

class FollowItem extends StatefulWidget {
  final String shipmentId;
  const FollowItem({Key? key, required this.shipmentId}) : super(key: key);

  @override
  State<FollowItem> createState() => _FollowItemState();
}

class _FollowItemState extends State<FollowItem> {
  // ===== THEME =====
  static const _orange = Color(0xFFFD8700);
  static const _orangeLight = Color(0xFFFFE6C7);
  static const _green = Color(0xFF16A34A);
  static const _grayCard = Color(0xFFF7F7F7);

  // ปรับรายชื่อคอลเลกชันที่อาจเก็บข้อมูลไรเดอร์ได้ตามโปรเจกต์คุณ
  static const List<String> _riderCandidateCollections = [
    'riders',
    'drivers',
    'users',
  ];

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('shipments').doc(widget.shipmentId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2EF),
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Delivery WarpSong'),
        centerTitle: false,
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_orange, _orangeLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _doc.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('ไม่พบคำสั่งนี้'));
          }

          final m = snap.data!.data()!;

          // ====== STATUS ======
          final status = _parseStatus(m['status']); // 1..4

          // ====== RIDER ======
          final riderSnap = _asMap(m['rider_snapshot']);
          final riderObj = _asMap(m['rider']); // บางระบบใช้ 'rider'
          final riderId = (m['riderId'] ??
                  m['rider_id'] ??
                  riderObj['id'] ??
                  riderObj['uid'] ??
                  riderObj['userId'] ??
                  riderSnap['id'] ??
                  riderSnap['uid'] ??
                  riderSnap['userId'] ??
                  '')
              .toString();

          // ====== SENDER / RECEIVER ======
          final sender = _asMap(m['sender_snapshot']);
          final receiver = _asMap(m['receiver_snapshot']);

          // ====== ADDRESS ======
          final pickup = _normalizeAddress(_asMap(sender['pickup_address']));
          final delivery = _normalizeAddress(
            _asMap(m['delivery_address_snapshot']).isNotEmpty
                ? _asMap(m['delivery_address_snapshot'])
                : _asMap(receiver['address']),
          );

          // ====== MAP URL (optional) ======
          final mapUrl = (m['route_map_url'] ?? '').toString().trim();

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Column(
              children: [
                // การ์ดไรเดอร์ (โหลดจาก snapshot ก่อน ถ้าไม่พอค่อยไป fetch)
                _RiderHeader(
                  riderSnapshot: riderSnap.isNotEmpty ? riderSnap : riderObj,
                  riderId: riderId,
                  candidateCollections: _riderCandidateCollections,
                ),

                const SizedBox(height: 10),

                // แผนที่/เส้นทาง
                _mapCard(mapUrl: mapUrl),

                const SizedBox(height: 10),

                // ผู้ส่ง (โชว์ชื่อ/โทร/ที่อยู่ + รูปโปรไฟล์)
                _partyCard(
                  title: 'ผู้ส่ง',
                  name: _pickName(sender),
                  phone: _pickPhone(sender),
                  addressLine: pickup.detail.isNotEmpty ? pickup.detail : '-',
                  avatarUrl: _pickPhoto(sender),
                ),

                const SizedBox(height: 10),

                // ผู้รับ (โชว์ชื่อ/โทร/ที่อยู่ + รูปโปรไฟล์)
                _partyCard(
                  title: 'ผู้รับ',
                  name: _pickName(receiver),
                  phone: _pickPhone(receiver),
                  addressLine:
                      delivery.detail.isNotEmpty ? delivery.detail : '-',
                  avatarUrl: _pickPhoto(receiver),
                ),

                const SizedBox(height: 10),

                // สถานะการส่ง
                _statusSection(status),

                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'ย้อนกลับ',
                    style: TextStyle(
                      color: _orange,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  // ===== Helpers =====

  int _parseStatus(dynamic v) {
    if (v is int) return v.clamp(1, 4);
    return (int.tryParse('$v') ?? 1).clamp(1, 4);
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  // ดึงชื่อจากหลายคีย์ที่อาจใช้ใน snapshot
  String _pickName(Map<String, dynamic> m) {
    final cands = [
      'display_name',
      'name',
      'fullname',
      'full_name',
      'first_last',
      'username',
    ];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '-';
  }

  // ดึงเบอร์โทรจากหลายคีย์
  String _pickPhone(Map<String, dynamic> m) {
    final cands = ['phone', 'phone_number', 'mobile', 'tel'];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '-';
  }

  // ดึงรูปจากหลายคีย์
  String _pickPhoto(Map<String, dynamic> m) {
    final cands = [
      'photo_url',
      'avatar',
      'avatar_url',
      'profile_url',
      'image_url',
      'photo'
    ];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  _Addr _normalizeAddress(Map<String, dynamic> m) {
    final detail =
        (m['detail_normalized'] ?? m['address_text'] ?? m['detail'] ?? '')
            .toString()
            .trim();
    final phone = (m['phone'] ?? '').toString().trim();

    // รองรับ GeoPoint และ Map
    String latlng = '';
    final loc = m['location'] ?? m['geopoint'] ?? m['geo'] ?? m['location_geo'];
    if (loc is GeoPoint) {
      latlng =
          '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
    } else if (loc is Map) {
      final lat = loc['latitude'] ?? loc['_latitude'] ?? loc['lat'];
      final lng = loc['longitude'] ?? loc['_longitude'] ?? loc['lng'];
      if (lat is num && lng is num) {
        latlng =
            '${lat.toDouble().toStringAsFixed(4)}, ${lng.toDouble().toStringAsFixed(4)}';
      }
    }
    return _Addr(detail: detail, phone: phone, latLng: latlng);
  }

  // ===== Widgets =====

  Widget _mapCard({required String mapUrl}) {
    return _card(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: mapUrl.isNotEmpty
              ? Image.network(
                  mapUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _mapPlaceholder(),
                )
              : _mapPlaceholder(),
        ),
      ),
    );
  }

  Widget _mapPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: _orange.withOpacity(.5), width: 2),
        color: Colors.white,
      ),
      child: const Center(
        child: Icon(Icons.map_outlined, size: 56, color: _orange),
      ),
    );
  }

  Widget _partyCard({
    required String title,
    required String name,
    required String phone,
    required String addressLine,
    required String avatarUrl,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // หัวข้อ
          Row(
            children: [
              Icon(
                title == 'ผู้ส่ง'
                    ? Icons.upload_rounded
                    : Icons.download_rounded,
                color: Colors.black45,
              ),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Colors.black87)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(avatarUrl, radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _iconLine(Icons.person_outline, name),
                    _iconLine(Icons.call, phone),
                    const SizedBox(height: 6),
                    _iconLine(Icons.location_on_outlined, addressLine),
                    const SizedBox(height: 6),
                    const Divider(color: Color(0xFFE6CDA9), thickness: 2),
                  ],
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusSection(int status) {
    final labels = const [
      'รอไรเดอร์รับสินค้า',
      'ไรเดอร์รับงาน (กำลังมารับ)',
      'ไรเดอร์รับสินค้าแล้ว (กำลังไปส่ง)',
      'ไรเดอร์นำส่งสินค้าแล้ว',
    ];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _sectionTitle('สถานะการส่ง'),
          const SizedBox(height: 8),
          for (int i = 0; i < labels.length; i++)
            _statusRow(
              labels[i],
              done: status >= i + 1,
              isCurrent: status == i + 1,
            ),
        ],
      ),
    );
  }

  Widget _statusRow(String text,
      {required bool done, required bool isCurrent}) {
    final icon = done ? Icons.check_circle : Icons.radio_button_unchecked;
    final icColor = done ? _green : Colors.black26;
    final txColor = done ? Colors.black87 : Colors.black45;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: icColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: txColor,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (isCurrent) const Icon(Icons.check, color: _green, size: 16),
        ],
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _orange, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text.isEmpty ? '-' : text,
              style: const TextStyle(height: 1.25)),
        )
      ],
    );
  }

  Widget _avatar(String url, {double radius = 20}) {
    final has = url.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFEDEDED),
      backgroundImage: has ? NetworkImage(url) : null,
      child: has ? null : const Icon(Icons.person, color: Colors.black26),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _grayCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

class _sectionTitle extends StatelessWidget {
  const _sectionTitle(this.text, {Key? key}) : super(key: key);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.radio_button_checked,
            color: _FollowItemState._orange, size: 16),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w900, color: Colors.black87)),
      ],
    );
  }
}

// Simple data holder
class _Addr {
  final String detail;
  final String phone;
  final String latLng;
  _Addr({required this.detail, required this.phone, required this.latLng});
}

/// ===== Rider Header (auto fetch if snapshot incomplete, with logs) =====
class _RiderHeader extends StatelessWidget {
  const _RiderHeader({
    Key? key,
    required this.riderSnapshot,
    required this.riderId,
    required this.candidateCollections,
  }) : super(key: key);

  final Map<String, dynamic> riderSnapshot;
  final String riderId;
  final List<String> candidateCollections;

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, v) => MapEntry(k.toString(), v));
    return <String, dynamic>{};
  }

  String _pickName(Map<String, dynamic> m) {
    final cands = [
      'display_name',
      'name',
      'fullname',
      'full_name',
      'username',
      'first_last',
    ];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickPhone(Map<String, dynamic> m) {
    final cands = ['phone', 'phone_number', 'mobile', 'tel'];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  String _pickPhoto(Map<String, dynamic> m) {
    final cands = [
      'photo_url',
      'avatar',
      'avatar_url',
      'profile_url',
      'image_url',
      'photo'
    ];
    for (final k in cands) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    final profile = _asMap(m['profile']);
    for (final k in cands) {
      final v = (profile[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  Future<Map<String, dynamic>?> _fetchById(String id) async {
    final fs = FirebaseFirestore.instance;
    for (final col in candidateCollections) {
      try {
        final doc = await fs.collection(col).doc(id).get();
        if (doc.exists) {
          debugPrint('[FOLLOW_RIDER] found riderId=$id in "$col"');
          return doc.data();
        } else {
          debugPrint('[FOLLOW_RIDER] not in "$col": $id');
        }
      } catch (e) {
        debugPrint('[FOLLOW_RIDER] error reading "$col/$id": $e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchByPhone(String phone) async {
    if (phone.isEmpty) return null;
    final fs = FirebaseFirestore.instance;
    for (final col in candidateCollections) {
      try {
        final qs = await fs
            .collection(col)
            .where('phone', isEqualTo: phone)
            .limit(1)
            .get();
        if (qs.docs.isNotEmpty) {
          debugPrint(
              '[FOLLOW_RIDER] found phone=$phone in "$col" → ${qs.docs.first.id}');
          return qs.docs.first.data();
        } else {
          debugPrint('[FOLLOW_RIDER] phone=$phone not in "$col"');
        }
      } catch (e) {
        debugPrint('[FOLLOW_RIDER] error query phone in "$col": $e');
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> _loadRider() async {
    // 1) ใช้ snapshot ก่อน
    final snap = riderSnapshot;
    final sName = _pickName(snap);
    final sPhone = _pickPhone(snap);
    final sPhoto = _pickPhoto(snap);
    final sPlate = (snap['plate'] ?? snap['car_plate'] ?? '').toString();

    if (sName.isNotEmpty ||
        sPhone.isNotEmpty ||
        sPhoto.isNotEmpty ||
        sPlate.isNotEmpty) {
      debugPrint('[FOLLOW_RIDER] using rider_snapshot (enough fields)');
      return {
        'name': sName,
        'phone': sPhone,
        'photo_url': sPhoto,
        'plate': sPlate,
      };
    }

    // 2) ถ้ามี riderId → ลองเปิดจากหลายคอลเลกชัน
    if (riderId.isNotEmpty) {
      final byId = await _fetchById(riderId);
      if (byId != null) {
        return {
          'name': _pickName(byId),
          'phone': _pickPhone(byId),
          'photo_url': _pickPhoto(byId),
          'plate': (byId['plate'] ?? byId['car_plate'] ?? '').toString(),
        };
      }
      debugPrint('[FOLLOW_RIDER] riderId=$riderId not found anywhere');
    }

    // 3) ถ้าไม่มี id แต่ snapshot มี phone → ลองค้นด้วยเบอร์
    if (sPhone.isNotEmpty) {
      final byPhone = await _fetchByPhone(sPhone);
      if (byPhone != null) {
        return {
          'name': _pickName(byPhone),
          'phone': _pickPhone(byPhone),
          'photo_url': _pickPhoto(byPhone),
          'plate': (byPhone['plate'] ?? byPhone['car_plate'] ?? '').toString(),
        };
      }
    }

    // 4) ไม่พบอะไรเลย → คืนค่า default
    debugPrint('[FOLLOW_RIDER] fallback to default rider');
    return {
      'name': 'คุณสมปอง รวดเร็ว',
      'phone': '',
      'photo_url': '',
      'plate': 'ฉฉ 5678',
    };
  }

  @override
  Widget build(BuildContext context) {
    // ถ้า snapshot มีพอแล้ว แสดงได้ทันที (ไม่ต้องรอ Future)
    final n0 = _pickName(riderSnapshot);
    final p0 = _pickPhone(riderSnapshot);
    final ph0 = _pickPhoto(riderSnapshot);
    final pl0 =
        (riderSnapshot['plate'] ?? riderSnapshot['car_plate'] ?? '').toString();
    final hasEnough =
        n0.isNotEmpty || p0.isNotEmpty || ph0.isNotEmpty || pl0.isNotEmpty;

    if (hasEnough) {
      return _RiderCard(
        name: n0.isEmpty ? 'คุณสมปอง รวดเร็ว' : n0,
        sub: 'เลขรถ ${pl0.isEmpty ? 'ฉฉ 5678' : pl0}',
        phone: p0,
        avatarUrl: ph0,
      );
    }

    // ต้องโหลดเพิ่ม (ด้วย fallback logic)
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadRider(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const _RiderCard.skeleton();
        }
        final data = s.data ?? const {};
        return _RiderCard(
          name: (data['name'] ?? 'คุณสมปอง รวดเร็ว').toString(),
          sub: 'เลขรถ ${(data['plate'] ?? 'ฉฉ 5678').toString()}',
          phone: (data['phone'] ?? '').toString(),
          avatarUrl: (data['photo_url'] ?? '').toString(),
        );
      },
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({
    Key? key,
    required this.name,
    required this.sub,
    required this.phone,
    required this.avatarUrl,
  }) : super(key: key);

  final String name;
  final String sub;
  final String phone;
  final String avatarUrl;

  const _RiderCard.skeleton({Key? key})
      : name = 'กำลังโหลดไรเดอร์…',
        sub = '',
        phone = '',
        avatarUrl = '',
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _FollowItemState._grayCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFFEDEDED),
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty
                  ? const Icon(Icons.person, color: Colors.black26)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 16)),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: const TextStyle(color: Colors.black54)),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone,
                          color: _FollowItemState._orange, size: 16),
                      const SizedBox(width: 6),
                      Text(phone.isEmpty ? '-' : phone,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
