import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/shipment_photo.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_reueries.dart';
import 'package:deliverydomo/services/rider_location.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class FollowItem extends StatefulWidget {
  final String shipmentId;
  const FollowItem({Key? key, required this.shipmentId}) : super(key: key);

  @override
  State<FollowItem> createState() => _FollowItemState();
}

class _FollowItemState extends State<FollowItem>
    with SingleTickerProviderStateMixin {
  static const _primaryOrange = Color(0xFFFD8700);
  static const _lightOrange = Color(0xFFFFB84D);
  static const _paleOrange = Color(0xFFFFF4E6);
  static const _deepGreen = Color(0xFF16A34A);
  static const _lightGreen = Color(0xFF4ADE80);
  static const _cardBg = Color(0xFFFFFFFF);
  static const _bgGray = Color(0xFFF8FAFC);

  final _repo = FirebaseShipmentsApi();
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  late RiderLocationSender riderLocationSender;
  late AnimationController _animController;

  double latSender = 0.0;
  double lngSender = 0.0;
  double latReceiver = 0.0;
  double lngReceiver = 0.0;
  String currentRiderId = '';
  GoogleMapController? _mapController;

  List<LatLng> points = [];

  @override
  void initState() {
    super.initState();
    riderLocationSender = RiderLocationSender();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Stream<String> watchUserAvatar({String? uid, String? phone}) async* {
    final u = (uid ?? '').trim();
    if (u.isNotEmpty) {
      yield* _fs.collection('users').doc(u).snapshots().map((d) {
        final m = d.data() ?? {};
        final v = (m['photoUrl'] ?? '').toString().trim();
        return v.startsWith('http') ? v : '';
      });
      return;
    }

    final p = (phone ?? '').trim();
    if (p.isNotEmpty) {
      yield* _fs
          .collection('users')
          .where('phone', isEqualTo: p)
          .limit(1)
          .snapshots()
          .map((qs) {
        if (qs.docs.isEmpty) return '';
        final m = qs.docs.first.data();
        final v = (m['photoUrl'] ?? '').toString().trim();
        return v.startsWith('http') ? v : '';
      });
      return;
    }

    yield '';
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _shipmentStream =>
      _repo.watchShipment(widget.shipmentId);

  Stream<List<ShipmentPhoto>> get _photosStream =>
      _repo.watchShipmentPhotos(widget.shipmentId);

  Stream<List<Map<String, dynamic>>> get _allShipmentsStream {
    final auth = SessionStore.getAuth();
    final userId = (auth?.userId ?? '').trim();
    if (userId.isEmpty) return Stream.value(const []);
    return riderLocationSender.watchShipmentsForUser(userId);
  }

  Future<Map<String, dynamic>> _getOSRM(LatLng a, LatLng b) async {
    final coords = '${a.longitude},${a.latitude};${b.longitude},${b.latitude}';
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$coords',
      {
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
      },
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw Exception('OSRM ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    debugPrint('OSRM Response: $data');

    final routes = (data['routes'] as List);
    if (routes.isEmpty) {
      debugPrint('No routes found');
      return {'points': <LatLng>[], 'duration': 0.0, 'distance': 0.0};
    }
    final route = routes.first as Map;
    final coordsList = ((route['geometry'] as Map)['coordinates'] as List);
    final points = <LatLng>[
      for (final c in coordsList)
        LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
    ];
    return {
      'points': points,
      'duration': (route['duration'] as num?)?.toDouble() ?? 0.0,
      'distance': (route['distance'] as num?)?.toDouble() ?? 0.0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            color: _primaryOrange,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Delivery WarpSong',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
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
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _shipmentStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryOrange),
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'กำลังโหลดข้อมูล...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: _errorWidget('โหลดข้อมูลไม่สำเร็จ: ${snap.error}'),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(child: _errorWidget('ไม่พบคำสั่งนี้'));
          }

          final m = snap.data!.data()!;
          final status = _parseStatus(m['status']);

          final riderSnapRaw = m['rider_snapshot'];
          final riderObjRaw = m['rider'];
          final Map<String, dynamic> riderSnap =
              (riderSnapRaw is Map<String, dynamic>) ? riderSnapRaw : {};
          final Map<String, dynamic> riderObj =
              (riderObjRaw is Map<String, dynamic>) ? riderObjRaw : {};

          final riderId = (m['rider_id'] ?? '').toString();

          final sender = (m['sender_snapshot'] ?? {}) as Map;
          final senderDetail = sender['pickup_address'] ?? {};
          final senderuid = (sender['uid'] ?? '').toString();
          final senderPhone = (sender['phone'] ?? '').toString();
          final senderAddressDetail =
              (senderDetail['detail_normalized'] ?? '').toString();

          final receiver = (m['receiver_snapshot'] ?? {}) as Map;
          final receiveruid = (receiver['uid'] ?? '').toString();
          final receiverPhone = (receiver['phone'] ?? '').toString();

          final delivery = (m['delivery_address_snapshot'] ?? {}) as Map;
          final detail_delivery =
              (delivery['detail_normalized'] ?? '').toString();

          final addressSender = senderDetail['location'];
          final addressReceiver = delivery['location'];

          latSender = addressSender.latitude;
          lngSender = addressSender.longitude;

          latReceiver = addressReceiver.latitude;
          lngReceiver = addressReceiver.longitude;

          return FadeTransition(
            opacity: _animController,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 24),
              child: Column(
                children: [
                  StreamBuilder<Map<String, dynamic>?>(
                    stream: riderLocationSender
                        .getShipmentLocation(widget.shipmentId),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _shimmerCard(height: 120);
                      }
                      if (snapshot.hasError) {
                        return _errorWidget('Error: ${snapshot.error}');
                      }
                      if (!snapshot.hasData || snapshot.data == null) {
                        return _infoCard(
                          icon: Icons.info_outline,
                          message: 'ไม่พบข้อมูลตำแหน่งไรเดอร์',
                        );
                      }

                      final riderLocation = snapshot.data;
                      if (riderLocation == null || riderLocation.isEmpty) {
                        return _infoCard(
                          icon: Icons.location_off,
                          message: 'ไม่มีข้อมูลตำแหน่งไรเดอร์',
                        );
                      }

                      final riderLat = riderLocation['lat'];
                      final riderLng = riderLocation['lng'];

                      return Column(
                        children: [
                          // Rider Header
                          if (status >= 2)
                            _RiderHeader(
                              riderSnapshot:
                                  riderSnap.isNotEmpty ? riderSnap : riderObj,
                              riderId: riderId,
                              repo: _repo,
                            )
                          else
                            const _RiderHeader(
                              riderSnapshot: {},
                              riderId: '-',
                              repo: null, // not used in this branch
                            ),
                          const SizedBox(height: 16),

                          // Map Card
                          if (status < 4)
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: _allShipmentsStream,
                              builder: (context, shipmentsSnap) {
                                final shipments = shipmentsSnap.data ?? [];

                                return FutureBuilder<Map<String, dynamic>>(
                                  future: _getOSRM(
                                    LatLng(riderLat, riderLng),
                                    LatLng(latSender, lngSender),
                                  ),
                                  builder: (context, osrmSnap) {
                                    final osrmPoints =
                                        osrmSnap.data?['points'] ?? <LatLng>[];
                                    return _mapCard(
                                      riderLat: riderLat,
                                      riderLng: riderLng,
                                      senderLat: latSender,
                                      senderLng: lngSender,
                                      receiverLat: latReceiver,
                                      receiverLng: lngReceiver,
                                      points: osrmPoints,
                                      shipments: shipments,
                                    );
                                  },
                                );
                              },
                            ),
                          const SizedBox(height: 16),

                          _partyCardFromUserDoc(
                            uid: senderuid,
                            phone: senderPhone,
                            title: 'ผู้ส่ง',
                            name: (sender['name'] ?? '').toString(),
                            addressLine: senderAddressDetail,
                            gradientColors: [
                              Colors.red.shade50,
                              Colors.orange.shade50
                            ],
                            fallbackPhotoUrl:
                                (sender['photoUrl'] ?? '').toString(),
                          ),
                          const SizedBox(height: 16),

                          // Receiver (real-time + phone fallback)
                          _partyCardFromUserDoc(
                            uid: receiveruid,
                            phone: receiverPhone,
                            title: 'ผู้รับ',
                            name: (receiver['name'] ?? '').toString(),
                            addressLine: detail_delivery,
                            gradientColors: [
                              Colors.green.shade50,
                              Colors.teal.shade50
                            ],
                            fallbackPhotoUrl: (receiver['photoUrl'] ??
                                    receiver['photo_url'] ??
                                    '')
                                .toString(),
                          ),
                          const SizedBox(height: 16),

                          // Status Section
                          _statusSection(status),
                          const SizedBox(height: 16),

                          // Photos Section
                          StreamBuilder<List<ShipmentPhoto>>(
                            stream: _photosStream,
                            builder: (context, ps) {
                              if (ps.connectionState ==
                                  ConnectionState.waiting) {
                                return _shimmerCard(height: 100);
                              }
                              if (ps.hasError) {
                                return _errorWidget(
                                    'โหลดรูปไม่สำเร็จ: ${ps.error}');
                              }
                              final photos = ps.data ?? const <ShipmentPhoto>[];
                              if (photos.isEmpty) {
                                return _infoCard(
                                  icon: Icons.photo_library_outlined,
                                  message: 'ยังไม่มีรูปจากไรเดอร์',
                                );
                              }

                              final byStatus = <int, List<ShipmentPhoto>>{};
                              for (final p in photos) {
                                byStatus.putIfAbsent(p.status, () => []).add(p);
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if ((byStatus[1] ?? []).isNotEmpty) ...[
                                    _photoGroupHeader('รูปตอนรับสินค้า',
                                        Colors.yellow.shade700),
                                    _photoGrid(byStatus[1]!),
                                    const SizedBox(height: 16),
                                  ],
                                  if ((byStatus[2] ?? []).isNotEmpty) ...[
                                    _photoGroupHeader('รูประหว่างเดินทาง',
                                        Colors.orange.shade700),
                                    _photoGrid(byStatus[2]!),
                                    const SizedBox(height: 16),
                                  ],
                                  if ((byStatus[3] ?? []).isNotEmpty) ...[
                                    _photoGroupHeader(
                                        'รูปกำลังไปส่ง', Colors.blue.shade700),
                                    _photoGrid(byStatus[3]!),
                                    const SizedBox(height: 16),
                                  ],
                                  if ((byStatus[4] ?? []).isNotEmpty) ...[
                                    _photoGroupHeader('รูปส่งสินค้าแล้ว',
                                        Colors.green.shade700),
                                    _photoGrid(byStatus[4]!),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),

                          // Back Button
                          _modernButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'ย้อนกลับ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  int _parseStatus(dynamic v) {
    if (v is int) return v.clamp(1, 4);
    return (int.tryParse('$v') ?? 1).clamp(1, 4);
  }

  Widget _mapCard({
    required double riderLat,
    required double riderLng,
    required double senderLat,
    required double senderLng,
    required double receiverLat,
    required double receiverLng,
    required List<LatLng> points,
    required List<Map<String, dynamic>> shipments,
    String? currentShipmentId,
    bool myLocationEnabled = true,
  }) {
    final markers = <Marker>{};
    final circles = <Circle>{};
    final allPositions = <LatLng>[];

    final senderPos = LatLng(senderLat, senderLng);
    final receiverPos = LatLng(receiverLat, receiverLng);
    allPositions
      ..add(senderPos)
      ..add(receiverPos);

    markers.add(Marker(
      markerId: const MarkerId('sender_marker'),
      position: senderPos,
      infoWindow: const InfoWindow(title: 'ผู้ส่ง'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
    ));
    markers.add(Marker(
      markerId: const MarkerId('receiver_marker'),
      position: receiverPos,
      infoWindow: const InfoWindow(title: 'ผู้รับ'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ));

    circles.add(Circle(
      circleId: const CircleId('sender_circle'),
      center: senderPos,
      radius: 50,
      strokeWidth: 2,
      strokeColor: Colors.redAccent.withOpacity(.7),
      fillColor: Colors.redAccent.withOpacity(.2),
    ));
    circles.add(Circle(
      circleId: const CircleId('receiver_circle'),
      center: receiverPos,
      radius: 50,
      strokeWidth: 2,
      strokeColor: Colors.green.withOpacity(.7),
      fillColor: Colors.green.withOpacity(.2),
    ));

    final primaryPos = LatLng(riderLat, riderLng);
    allPositions.add(primaryPos);
    markers.add(Marker(
      markerId: const MarkerId('primary_rider_marker'),
      position: primaryPos,
      infoWindow: const InfoWindow(title: 'ไรเดอร์หลัก'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
    ));

    for (final s in shipments) {
      final rl = s['rider_location'];
      if (rl is! Map) continue;

      final lat = (rl['lat'] as num?)?.toDouble();
      final lng = (rl['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      // กันซ้ำ: ไม่วางหมุดของ shipment ปัจจุบัน (คือไรเดอร์หลัก)
      final sid = (s['id'] ?? '').toString();
      if (currentShipmentId != null && sid == currentShipmentId) continue;

      // (ออปชันกันพิกัดซ้อน) ถ้าพิกัดตรงกับหลักเกินไปก็ข้าม
      const eps = 1e-6;
      if ((lat - riderLat).abs() < eps && (lng - riderLng).abs() < eps)
        continue;

      final pos = LatLng(lat, lng);
      allPositions.add(pos);

      final riderTitle = (s['rider_name'] ?? s['rider_id'] ?? '').toString();

      final status = int.tryParse('${s['status'] ?? ''}') ?? 0;
      final hue = _hueForStatus(status);

      markers.add(Marker(
        markerId: MarkerId('rider_marker_${sid.isEmpty ? riderTitle : sid}'),
        position: pos,
        infoWindow: InfoWindow(
          title: 'ไรเดอร์ $riderTitle',
          snippet: 'สถานะ: ${s['status'] ?? '-'}',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
      ));
    }

    final initialTarget = allPositions.isNotEmpty
        ? allPositions.first
        : LatLng(
            (riderLat + senderLat + receiverLat) / 3,
            (riderLng + senderLng + receiverLng) / 3,
          );

    Future<void> fitAll() async {
      if (_mapController == null) return;
      if (allPositions.length == 1) {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(allPositions.first, 15),
        );
        return;
      }
      final bounds = _boundsFrom(allPositions);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 60),
      );
    }

    return Container(
      width: double.infinity,
      height: 380,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: initialTarget,
                zoom: 13,
              ),
              markers: markers,
              circles: circles,
              polylines: {
                if (points.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: points,
                    color: const Color.fromARGB(255, 55, 182, 255),
                    width: 5,
                  ),
              },
              myLocationEnabled: myLocationEnabled,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              onMapCreated: (c) async {
                _mapController = c;
                WidgetsBinding.instance.addPostFrameCallback((_) => fitAll());
              },
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.my_location, color: _primaryOrange),
                  tooltip: 'แสดงทุกหมุด',
                  onPressed: fitAll,
                ),
              ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _LegendDot(color: Colors.red, label: 'ผู้ส่ง'),
                    SizedBox(width: 12),
                    _LegendDot(color: Colors.green, label: 'ผู้รับ'),
                    SizedBox(width: 12),
                    _LegendDot(color: Colors.lightBlue, label: 'ไรเดอร์'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LatLngBounds _boundsFrom(List<LatLng> list) {
    assert(list.isNotEmpty);
    double minLat = list.first.latitude, maxLat = list.first.latitude;
    double minLng = list.first.longitude, maxLng = list.first.longitude;
    for (final p in list) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  double _hueForStatus(int status) {
    switch (status) {
      case 1:
        return BitmapDescriptor.hueYellow;
      case 2:
        return BitmapDescriptor.hueOrange;
      case 3:
        return BitmapDescriptor.hueBlue;
      case 4:
        return BitmapDescriptor.hueGreen;
      default:
        return BitmapDescriptor.hueBlue;
    }
  }

  /// ห่อการ์ด: ดูรูปแบบเรียลไทม์ + fallback
  Widget _partyCardFromUserDoc({
    required String uid,
    required String phone,
    required String title,
    required String name,
    required String addressLine,
    required List<Color> gradientColors,
    required String fallbackPhotoUrl,
  }) {
    return StreamBuilder<String>(
      stream: watchUserAvatar(uid: uid, phone: phone),
      builder: (context, s) {
        final url = (s.data ?? fallbackPhotoUrl).toString();
        return _partyCard(
          title: title,
          name: name,
          phone: phone,
          addressLine: addressLine,
          avatarUrl: url,
          gradientColors: gradientColors,
        );
      },
    );
  }

  Widget _partyCard({
    required String title,
    required String name,
    required String phone,
    required String addressLine,
    required String avatarUrl,
    required List<Color> gradientColors,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(100),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _avatar(avatarUrl, radius: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow(Icons.person, name, Colors.blue.shade600),
                          const SizedBox(height: 12),
                          _infoRow(Icons.phone, phone, Colors.green.shade600),
                          const SizedBox(height: 12),
                          _infoRow(Icons.location_on, addressLine,
                              Colors.red.shade600),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text.isEmpty ? '-' : text,
            style: const TextStyle(
              height: 1.4,
              fontSize: 14,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusSection(int status) {
    final items = [
      _StatusItem(
        icon: Icons.hourglass_empty,
        label: 'รอไรเดอร์รับสินค้า',
        color: Colors.grey,
      ),
      _StatusItem(
        icon: Icons.directions_bike,
        label: 'ไรเดอร์รับงาน (กำลังมารับ)',
        color: Colors.orange,
      ),
      _StatusItem(
        icon: Icons.local_shipping,
        label: 'ไรเดอร์รับสินค้าแล้ว (กำลังไปส่ง)',
        color: Colors.blue,
      ),
      _StatusItem(
        icon: Icons.check_circle,
        label: 'ไรเดอร์นำส่งสินค้าแล้ว',
        color: _deepGreen,
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_primaryOrange, _lightOrange],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.location_searching,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'สถานะการส่ง',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            for (int i = 0; i < items.length; i++) ...[
              _statusRow(
                item: items[i],
                done: status >= i + 1,
                isCurrent: status == i + 1,
                isLast: i == items.length - 1,
              ),
              if (i < items.length - 1) const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow({
    required _StatusItem item,
    required bool done,
    required bool isCurrent,
    required bool isLast,
  }) {
    return Row(
      children: [
        Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: done ? item.color : Colors.grey.shade200,
                shape: BoxShape.circle,
                boxShadow: done
                    ? [
                        BoxShadow(
                          color: item.color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                done ? Icons.check : item.icon,
                color: done ? Colors.white : Colors.grey.shade400,
                size: 20,
              ),
            ),
            if (!isLast)
              Container(
                width: 3,
                height: 50,
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color:
                      done ? item.color.withOpacity(0.5) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color:
                  isCurrent ? item.color.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isCurrent
                  ? Border.all(color: item.color.withOpacity(0.3), width: 1.5)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: done ? Colors.black87 : Colors.grey.shade500,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: item.color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'ขั้นตอนปัจจุบัน',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _photoGroupHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.photo_camera,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoGrid(List<ShipmentPhoto> photos) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: photos.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (_, i) {
          final url = photos[i].url;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: (url.isEmpty)
                  ? Container(
                      color: Colors.grey.shade100,
                      child: Icon(Icons.image, color: Colors.grey.shade400),
                    )
                  : Image.network(
                      url,
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
          );
        },
      ),
    );
  }

  Widget _avatar(String url, {double radius = 20}) {
    final has = url.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey.shade100,
      backgroundImage: has ? NetworkImage(url) : null,
      child: has
          ? null
          : Icon(Icons.person, color: Colors.grey.shade400, size: radius),
    );
  }

  Widget _modernButton({
    required VoidCallback onPressed,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primaryOrange, _lightOrange],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _primaryOrange.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: DefaultTextStyle(
              style: const TextStyle(color: Colors.white),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorWidget(String message) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blue.shade700, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerCard({required double height}) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_primaryOrange),
          strokeWidth: 3,
        ),
      ),
    );
  }
}

class _StatusItem {
  final IconData icon;
  final String label;
  final Color color;

  _StatusItem({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _RiderHeader extends StatelessWidget {
  const _RiderHeader({
    Key? key,
    required this.riderSnapshot,
    required this.riderId,
    required this.repo,
  }) : super(key: key);

  final Map<String, dynamic> riderSnapshot;
  final String riderId;
  final FirebaseShipmentsApi? repo;

  @override
  Widget build(BuildContext context) {
    final n0 = (riderSnapshot['name'] ?? '').toString();
    final p0 = (riderSnapshot['phone'] ?? '').toString();
    final ph0 = (riderSnapshot['photoUrl'] ?? riderSnapshot['photo_url'] ?? '')
        .toString();

    final hasEnoughSnapshot =
        riderId.isEmpty && (n0.isNotEmpty || p0.isNotEmpty || ph0.isNotEmpty);

    if (hasEnoughSnapshot) {
      return _RiderCard(
        name: n0.isEmpty ? 'ไรเดอร์' : n0,
        sub: '',
        phone: p0,
        avatarUrl: ph0,
      );
    }

    if (riderId.isNotEmpty && repo != null) {
      return FutureBuilder<RiderResolved?>(
        future: repo!.resolveRiderById(riderId),
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const _RiderCard.skeleton();
          }
          final r = s.data;
          if (r == null) {
            return _RiderCard(
              name: n0.isEmpty ? 'ไรเดอร์' : n0,
              sub: '',
              phone: p0,
              avatarUrl: ph0,
            );
          }
          final avatar = (r.avatarUrl.isNotEmpty ? r.avatarUrl : ph0);
          return _RiderCard(
            name: r.name.isEmpty ? 'ไรเดอร์' : r.name,
            sub: r.plateNumber.isEmpty ? '' : 'เลขรถ ${r.plateNumber}',
            phone: r.phone,
            avatarUrl: avatar,
          );
        },
      );
    }

    return const _RiderCard.skeleton();
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
        gradient: LinearGradient(
          colors: [
            const Color.fromARGB(255, 255, 244, 234).withOpacity(0.05),
            _FollowItemState._paleOrange,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _FollowItemState._primaryOrange.withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _FollowItemState._primaryOrange.withOpacity(0.15),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _FollowItemState._primaryOrange.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 32,
                backgroundColor: Colors.white,
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? const Icon(
                        Icons.person,
                        color: _FollowItemState._primaryOrange,
                        size: 32,
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.delivery_dining,
                        color: _FollowItemState._primaryOrange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: Colors.black87,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _FollowItemState._primaryOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        sub,
                        style: TextStyle(
                          color: _FollowItemState._primaryOrange,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.phone,
                          color: _FollowItemState._deepGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          phone.isEmpty ? '-' : phone,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
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
