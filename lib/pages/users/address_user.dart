import 'dart:async'; // Added for Completer, though Geolocator already imports it

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/user_address.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_address_repository.dart';
import 'package:deliverydomo/services/th_geocoder.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
// --- Imports for Map Selection ---
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Removed duplicate geolocator and get imports

class AddressUser extends StatefulWidget {
  const AddressUser({Key? key}) : super(key: key);

  @override
  State<AddressUser> createState() => _AddressUserState();
}

class _AddressUserState extends State<AddressUser> {
  late final AddressRepository _repo;
  late final ThaiGeocoder _geocoder; // เพิ่มการประกาศ `_geocoder`

  @override
  void initState() {
    super.initState();
    _repo = AddressRepository();
    _geocoder = ThaiGeocoder(); // การตั้งค่าของ _geocoder
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

  // --- State for Map Selection ---
  LatLng? _selectedLocation;
  // -----------------------------

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
          // --- Add "Select from Map" Button ---
          TextButton.icon(
            icon: const Icon(Icons.map_outlined, color: Color(0xFFFD8700)),
            label: const Text('เลือกจากแผนที่',
                style: TextStyle(color: Color(0xFFFD8700))),
            onPressed: _saving ? null : _selectFromMap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ------------------------------------
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

  // --- Logic for Map Selection ---
  Future<void> _selectFromMap() async {
    // 1. Check/request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        Get.snackbar('ไม่อนุญาต', 'กรุณาเปิดสิทธิ์การเข้าถึงตำแหน่ง',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      Get.snackbar(
          'ไม่อนุญาต', 'คุณปิดสิทธิ์การเข้าถึงตำแหน่งถาวร กรุณาไปที่การตั้งค่า',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // 2. Get current location to center the map
    Position? currentLocation;
    try {
      currentLocation = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
    } catch (e) {
      // Could fail if location services are off
      debugPrint('Error getting location: $e');
    }

    // 3. Navigate to MapSelectionPage
    if (!mounted) return;
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MapSelectionPage(
          initialLocation: currentLocation != null
              ? LatLng(currentLocation.latitude, currentLocation.longitude)
              : const LatLng(13.7563, 100.5018), // Default to Bangkok
        ),
      ),
    );

    // 4. Handle result
    if (result is Map<String, dynamic>) {
      final LatLng location = result['location'];
      final String address = result['address'];

      setState(() {
        _selectedLocation = location;
        _detail.text = address;
      });
    }
  }

  // --- MODIFIED Save Function ---
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
      // --- New Logic ---
      double? lat;
      double? lng;

      if (_selectedLocation != null) {
        // Location was picked from map
        lat = _selectedLocation!.latitude;
        lng = _selectedLocation!.longitude;
      } else {
        // Location was typed, use geocoder
        final pos = await widget.geocoder.geocode(addressText);
        lat = pos.lat;
        lng = pos.lng;
      }
      // --- End of New Logic ---

      final model = UserAddress(
        id: '_new_',
        userId: widget.uid,
        nameLabel: nameLabel,
        addressText: addressText,
        lat: lat, // Use the resolved lat
        lng: lng, // Use the resolved lng
        isDefault: false,
      );

      final payload = model.toJson()
        ..addAll({
          'phone': phone,
          if (lat != null && lng != null) ...{
            // Check resolved lat/lng
            'lat': lat,
            'lng': lng,
            'geopoint': GeoPoint(lat, lng),
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
        'latFound': lat != null, // Use resolved lat
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

// ---------- NEW: Map Selection Page ----------

class MapSelectionPage extends StatefulWidget {
  const MapSelectionPage({Key? key, required this.initialLocation})
      : super(key: key);
  final LatLng initialLocation;

  @override
  State<MapSelectionPage> createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {
  final Completer<GoogleMapController> _controller = Completer();
  late LatLng _selectedLocation;
  late final Set<Marker> _markers;
  bool _isConfirming = false;

  // --- 1. New State Variables ---
  String _currentAddressText = 'กำลังค้นหาที่อยู่...';
  bool _isGeocoding = false;
  // ------------------------------

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.initialLocation;
    _markers = {
      Marker(
        markerId: const MarkerId('selected_location'),
        position: _selectedLocation,
        draggable: true,
        onDragEnd: (newPosition) {
          setState(() {
            _selectedLocation = newPosition;
          });
          // --- 3. Call update function on Drag End ---
          _updateAddressFromLocation(newPosition);
        },
      ),
    };
    // --- 3. Call update function on Init ---
    _updateAddressFromLocation(_selectedLocation);
  }

  void _onMapTapped(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _markers.clear();
      _markers.add(
        Marker(
          markerId: const MarkerId('selected_location'),
          position: _selectedLocation,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() => _selectedLocation = newPosition);
            // --- 3. Call update function on Drag End (for new marker) ---
            _updateAddressFromLocation(newPosition);
          },
        ),
      );
    });
    // --- 3. Call update function on Map Tap ---
    _updateAddressFromLocation(location);
  }

  // --- 2. New Function to Handle Geocoding ---
  Future<void> _updateAddressFromLocation(LatLng location) async {
    if (_isGeocoding) return; // Prevent multiple simultaneous requests

    setState(() {
      _isGeocoding = true;
      _currentAddressText = 'กำลังค้นหาที่อยู่...';
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
        localeIdentifier: 'th_TH', // Request Thai locale
      );

      String address = 'ไม่พบที่อยู่';
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        // --- [START] REVISED THAI ADDRESS CONSTRUCTION ---
        // We build the address manually to avoid repetition

        // 1. Name/POI
        String namePart = p.name ?? ''; // e.g., "หอพักพรทิพย์"

        // 2. Street number and street name
        String streetNumberPart = p.subThoroughfare ?? ''; // e.g., "928 1"
        String streetNamePart =
            p.thoroughfare ?? ''; // e.g., "Tha Khon Yang" (ถนน)

        // Combine street parts
        String streetFullPart = '$streetNumberPart $streetNamePart'.trim();

        // 3. Admin levels
        String subLocalityPart =
            p.subLocality ?? ''; // e.g., "Tha Khon Yang" (ตำบล)
        String localityPart =
            p.locality ?? ''; // e.g., "Amphoe Kantharawichai" (อำเภอ)
        String adminAreaPart = p.administrativeArea ??
            ''; // e.g., "Chang Wat Maha Sarakham" (จังหวัด)
        String postalCodePart = p.postalCode ?? ''; // e.g., "44150"

        // 4. Combine all parts, checking for duplicates
        List<String> parts = [namePart];

        if (streetFullPart.isNotEmpty && streetFullPart != namePart) {
          parts.add(streetFullPart);
        }

        // If street name is different from subLocality, add subLocality
        if (subLocalityPart.isNotEmpty && subLocalityPart != streetNamePart) {
          parts.add(subLocalityPart);
        }

        parts.add(localityPart);
        parts.add(adminAreaPart);
        parts.add(postalCodePart);

        address = parts.where((s) => s.isNotEmpty).join(', ');
        // --- [END] REVISED THAI ADDRESS CONSTRUCTION ---
      }

      if (mounted) {
        setState(() {
          _currentAddressText = address;
        });
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      if (mounted) {
        setState(() {
          _currentAddressText = 'ไม่สามารถค้นหาที่อยู่จากพิกัดได้';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }
  // ------------------------------------------

  // --- 5. Simplified _confirmSelection ---
  Future<void> _confirmSelection() async {
    setState(() => _isConfirming = true);

    // No need to geocode here, just pop the state
    if (mounted) {
      Navigator.of(context).pop({
        'location': _selectedLocation,
        'address': _currentAddressText, // Pop the current address text
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกตำแหน่งบนแผนที่'),
        backgroundColor: const Color(0xFFFFF5E8),
        foregroundColor: const Color(0xFFFD8700),
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 16,
            ),
            onMapCreated: (GoogleMapController controller) {
              if (!_controller.isCompleted) {
                _controller.complete(controller);
              }
            },
            markers: _markers,
            onTap: _onMapTapped,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            // --- [MODIFIED] ---
            zoomControlsEnabled: true, // เปิดปุ่มซูม
            // --------------------
          ),
          // --- 4. Add Address Display ---
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFFFD8700), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentAddressText,
                        style: const TextStyle(fontSize: 14, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ------------------------------
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: SizedBox(
              height: 50,
              child: FloatingActionButton.extended(
                // Disable button while geocoding or confirming
                onPressed:
                    (_isConfirming || _isGeocoding) ? null : _confirmSelection,
                label: _isConfirming
                    ? const CircularProgressIndicator(color: Colors.white)
                    : (_isGeocoding // Show loading text if geocoding
                        ? const Text(
                            'กำลังค้นหา...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          )
                        : const Text('ยืนยันตำแหน่งนี้',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16))),
                icon: (_isConfirming || _isGeocoding) // Hide icon when loading
                    ? null
                    : const Icon(Icons.check, color: Colors.white),
                backgroundColor: const Color(0xFFFD8700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
