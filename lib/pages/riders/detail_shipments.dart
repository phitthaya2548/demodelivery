import 'dart:async';

import 'package:deliverydomo/pages/riders/map_rider.dart';
import 'package:deliverydomo/pages/riders/widgets/bottom.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_rider_showworl.dart';
import 'package:deliverydomo/services/firebase_shipment_detail_rider.dart';
import 'package:deliverydomo/services/rider_location.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DetailShipments extends StatefulWidget {
  const DetailShipments({Key? key}) : super(key: key);

  @override
  State<DetailShipments> createState() => _DetailShipmentsState();
}

class _DetailShipmentsState extends State<DetailShipments>
    with TickerProviderStateMixin {
  static const _orange = Color(0xFFFD8700);
  static const _green = Color(0xFF16A34A);
  static const _bg = Color(0xFFF8F7F5);

  final _shipmentApi = ShipmentDetailApi();
  final _riderApi = FirebaseRiderApi();
  final _locationService = RiderLocationSender();

  late AnimationController _scaleController;
  late GoogleMapController _mapController;

  LatLng? _riderLocation;
  StreamSubscription<Map<String, dynamic>?>? _locationSubscription;

  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _subscribeToRiderLocation();
  }

  void _subscribeToRiderLocation() {
    final riderId = _riderId;
    if (riderId.isEmpty) return;

    _locationSubscription = _locationService
        .getShipmentLocationForRider(riderId)
        .listen((locationData) {
      if (locationData != null && mounted) {
        final lat = locationData['lat'] as num?;
        final lng = locationData['lng'] as num?;

        if (lat != null && lng != null) {
          setState(() {
            _riderLocation = LatLng(lat.toDouble(), lng.toDouble());
          });
        }
      }
    }, onError: (e) {
      print('Error loading rider location: $e');
    });
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  String _initials(String name) {
    var n = name.trim();
    if (n.isEmpty) n = 'คุณ';
    final parts = n.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'ค';
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return (parts.first.characters.take(1).toString() +
        parts.last.characters.take(1).toString());
  }

  Future<void> _accept(String shipmentId) async {
    final riderId = _riderId;
    if (riderId.isEmpty) {
      Get.snackbar('รับงานไม่ได้', 'ยังไม่พบรหัสไรเดอร์ในเซสชัน',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    try {
      await _riderApi.acceptShipment(
        riderId: riderId,
        shipmentId: shipmentId,
      );
      Get.back();
      Get.snackbar('สำเร็จ', 'รับงานเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
      Get.offAll(() => const BottomRider(initialIndex: 2));
    } catch (e) {
      Get.snackbar('รับงานไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = (Get.arguments ?? {}) as Map?;
    final shipmentId = (args?['shipment_id'] ?? args?['id'] ?? '').toString();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
              )
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: _orange, size: 20),
            onPressed: () => Get.back(),
          ),
        ),
        title: const Text(
          'รายละเอียดงาน',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 20,
            color: Colors.orange,
          ),
        ),
        centerTitle: false,
      ),
      body: shipmentId.isEmpty
          ? const Center(child: Text('ไม่พบรหัสงาน'))
          : StreamBuilder<ShipmentDetail?>(
              stream: _shipmentApi.watchShipmentDetail(shipmentId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final d = snap.data;
                if (d == null) {
                  return const Center(child: Text('ไม่พบข้อมูลงานนี้'));
                }

                const brand = 'Delivery WarpSong';
                final photoUrl = d.photoUrl;
                final itemName = d.itemName;
                final itemDesc = d.itemDesc;
                final canAccept = d.status == 1;

                final s = d.sender;
                final r = d.receiver;

                final LatLng senderLatLng =
                    LatLng(s.address.geo?.lat ?? 0, s.address.geo?.lng ?? 0);
                final LatLng receiverLatLng =
                    LatLng(r.address.geo?.lat ?? 0, r.address.geo?.lng ?? 0);

                return LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ScaleTransition(
                                scale: Tween<double>(begin: 0.95, end: 1.0)
                                    .animate(_scaleController),
                                child: _DetailCard(
                                  brand: brand,
                                  photoUrl: photoUrl,
                                  itemName: itemName,
                                  itemDesc: itemDesc,
                                  sender: s,
                                  receiver: r,
                                  getInitials: _initials,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Spacer(),
                              SizedBox(
                                height: 370,
                                child: GoogleMap(
                                  onMapCreated:
                                      (GoogleMapController controller) {
                                    _mapController = controller;
                                  },
                                  initialCameraPosition: CameraPosition(
                                    target:
                                        senderLatLng, // ตั้งค่าเริ่มต้นที่ตำแหน่งผู้ส่ง
                                    zoom: 14,
                                  ),
                                  markers: {
                                    Marker(
                                      markerId: MarkerId('sender'),
                                      position: senderLatLng,
                                      infoWindow: InfoWindow(title: 'ผู้ส่ง'),
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
                                        BitmapDescriptor.hueGreen,
                                      ),
                                    ),
                                    Marker(
                                      markerId: MarkerId('receiver'),
                                      position: receiverLatLng,
                                      infoWindow: InfoWindow(title: 'ผู้รับ'),
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
                                        BitmapDescriptor.hueRed,
                                      ),
                                    ),
                                    if (_riderLocation != null)
                                      Marker(
                                        markerId: MarkerId('rider'),
                                        position: _riderLocation!,
                                        infoWindow:
                                            InfoWindow(title: 'ตำแหน่งของคุณ'),
                                        icon: BitmapDescriptor
                                            .defaultMarkerWithHue(
                                          BitmapDescriptor.hueOrange,
                                        ),
                                      ),
                                  },
                                  zoomControlsEnabled: true,
                                  scrollGesturesEnabled: true,
                                  zoomGesturesEnabled: true,
                                  myLocationButtonEnabled: true,
                                  myLocationEnabled: true,
                                  mapToolbarEnabled: true,
                                  mapType: MapType.normal,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _ActionButtons(
                                canAccept: canAccept,
                                onAccept: () => _accept(d.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.brand,
    required this.photoUrl,
    required this.itemName,
    required this.itemDesc,
    required this.sender,
    required this.receiver,
    required this.getInitials,
  });

  final String brand;
  final String photoUrl;
  final String itemName;
  final String itemDesc;
  final dynamic sender;
  final dynamic receiver;
  final String Function(String) getInitials;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFD8700).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderSection(brand: brand),
            const SizedBox(height: 18),
            _ImageSection(photoUrl: photoUrl),
            const SizedBox(height: 18),
            _ItemInfoSection(
              itemName: itemName,
              itemDesc: itemDesc,
            ),
            const SizedBox(height: 20),
            _PersonSection(
              title: 'ผู้ส่ง',
              icon: Icons.person_outline,
              name: sender.name,
              phone: sender.phone,
              address: sender.address.text,
              avatarUrl: sender.avatarUrl,
              initials: getInitials(sender.name),
            ),
            const SizedBox(height: 20),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey.withOpacity(0.2),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _PersonSection(
              title: 'ผู้รับ',
              icon: Icons.location_on_outlined,
              name: receiver.name,
              phone: receiver.phone,
              address: receiver.address.text,
              avatarUrl: receiver.avatarUrl,
              initials: getInitials(receiver.name),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.brand});

  final String brand;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFFD8700),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                brand,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFD8700),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'รายละเอียดรายการสินค้า',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _ImageSection extends StatelessWidget {
  const _ImageSection({required this.photoUrl});

  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: photoUrl.isEmpty
              ? Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image, size: 56, color: Colors.grey),
                )
              : Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image_outlined,
                        size: 56, color: Colors.grey),
                  ),
                ),
        ),
      ),
    );
  }
}

class _ItemInfoSection extends StatelessWidget {
  const _ItemInfoSection({
    required this.itemName,
    required this.itemDesc,
  });

  final String itemName;
  final String itemDesc;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF9F3),
            const Color(0xFFFFFBF5),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE4C7), width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_bag_outlined,
                  color: const Color(0xFFFD8700), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'สินค้า',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.black54,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (itemName.isNotEmpty)
            Text(
              itemName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (itemDesc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              itemDesc,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.icon,
    required this.label,
    required this.isActive,
  });

  final IconData icon;
  final String label;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF9F3) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? const Color(0xFFFFE4C7) : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? const Color(0xFFFD8700) : Colors.grey.shade400,
            size: 20,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isActive ? const Color(0xFFFD8700) : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonSection extends StatelessWidget {
  const _PersonSection({
    required this.title,
    required this.icon,
    required this.name,
    required this.phone,
    required this.address,
    required this.avatarUrl,
    required this.initials,
  });

  final String title;
  final IconData icon;
  final String name;
  final String phone;
  final String address;
  final String avatarUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFD8700).withOpacity(0.15),
                blurRadius: 10,
                spreadRadius: 2,
              )
            ],
          ),
          child: ClipOval(
            child: SizedBox(
              height: 52,
              width: 52,
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
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: const Color(0xFFFD8700), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Color(0xFFFD8700),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                name.isEmpty ? '-' : name,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.phone_outlined, color: Colors.black38, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        phone,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined,
                      color: Colors.black38, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address.isEmpty ? '-' : address,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFF5E8),
            const Color(0xFFFFE9D0),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        (initials.isEmpty ? '–' : initials),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 18,
          color: Color(0xFFFD8700),
        ),
      ),
    );
  }
}

class _ActionButtons extends StatefulWidget {
  const _ActionButtons({
    required this.canAccept,
    required this.onAccept,
  });

  final bool canAccept;
  final VoidCallback onAccept;

  @override
  State<_ActionButtons> createState() => _ActionButtonsState();
}

class _ActionButtonsState extends State<_ActionButtons> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: widget.canAccept ? widget.onAccept : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.canAccept
                    ? const Color(0xFFFD8700)
                    : Colors.grey.shade300,
                foregroundColor:
                    widget.canAccept ? Colors.white : Colors.grey.shade600,
                elevation: _isHovered && widget.canAccept ? 8 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 20,
                      color: widget.canAccept
                          ? Colors.white
                          : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    widget.canAccept ? 'รับงาน' : 'งานนี้ยังไม่พร้อม',
                    style: const TextStyle(letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () => Get.back(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFD8700),
              side: const BorderSide(
                color: Color(0xFFFD8700),
                width: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: const Color(0xFFFD8700)),
                const SizedBox(width: 8),
                const Text('กลับ'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
