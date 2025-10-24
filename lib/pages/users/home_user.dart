import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_shipment.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// ✅ เพิ่ม import แผนที่
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

class HomeUser extends StatefulWidget {
  const HomeUser({Key? key}) : super(key: key);

  @override
  State<HomeUser> createState() => _HomeUserState();
}

class _HomeUserState extends State<HomeUser> {
  // THEME
  static const _orange = Color(0xFFFD8700);
  static const _orangeSoft = Color(0xFFFFE4BD);
  static const _bg = Color(0xFFF8F6F2);
  static const _pillBg = Color(0xFFFFF5E6);

  // Controllers (สินค้า)
  final _phoneCtrl = TextEditingController(); // ค้นหาผู้รับ
  final _itemNameCtrl = TextEditingController();
  final _itemNoteCtrl = TextEditingController();

  // Shipment API
  final _shipApi = ShipmentApi();

  // Runtime: ผู้รับ
  bool _searching = false;
  bool _creating = false;
  bool _addingToCart = false;
  bool _sendingAll = false;
  String? _uid;
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _addresses = [];
  String? _addressIdSelected;

  // รูปสินค้า
  File? _photoFile;

  // ที่อยู่ผู้ส่ง (pickup)
  Map<String, dynamic>? _senderPickupAddress;

  // Draft count
  int _cartCount = 0;

  // ===== Google Map state =====
  GoogleMapController? _mapCtrl;
  final Set<Marker> _markers = {};
  LatLng? _pickupLatLng; // ผู้ส่ง
  LatLng? _dropLatLng; // ผู้รับหลัก

  // ---------- Helpers ----------
  String _normalizePhone(String s) => s.replaceAll(RegExp(r'\D'), '');

  void _toast(String msg, {bool success = false}) {
    Get.showSnackbar(GetSnackBar(
      margin: const EdgeInsets.all(12),
      borderRadius: 12,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor:
          success ? const Color(0xFF22c55e) : const Color(0xFFef4444),
      messageText: Text(msg, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 2),
    ));
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  GeoPoint? _geo(dynamic lat, dynamic lng) {
    final la = _toDouble(lat), lo = _toDouble(lng);
    if (la == null || lo == null) return null;
    return GeoPoint(la, lo);
  }

  LatLng? _toLatLngFromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final loc = m['location'];
    if (loc is GeoPoint) return LatLng(loc.latitude, loc.longitude);
    final lat = m['lat'] ?? m['latitude'];
    final lng = m['lng'] ?? m['longitude'];
    final gp = _geo(lat, lng);
    return gp == null ? null : LatLng(gp.latitude, gp.longitude);
  }

  // ===== Address & Profile Helpers =====

  Map<String, dynamic> _normalizeAddressMap(Map<String, dynamic>? raw) {
    final m = (raw ?? {});
    final detail =
        (m['detail_normalized'] ?? m['address_text'] ?? m['detail'] ?? '')
            .toString()
            .trim();
    final label = (m['label'] ?? m['name'] ?? m['name_address'] ?? 'ที่อยู่')
        .toString()
        .trim();
    final phone = (m['phone'] ?? '').toString().trim();

    GeoPoint? location;
    final loc = m['location'];
    if (loc is GeoPoint) {
      location = loc;
    } else {
      final lat = m['lat'] ?? m['latitude'];
      final lng = m['lng'] ?? m['longitude'];
      location = _geo(lat, lng);
    }

    final normalizedText =
        detail.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    return {
      'label': label,
      'detail': (m['detail'] ?? '').toString(),
      'detail_normalized': normalizedText,
      if (phone.isNotEmpty) 'phone': phone,
      if (location != null) 'location': location,
    };
  }

  Future<Map<String, dynamic>?> _loadUserProfileSafe(String? uidOrPhone) async {
    if (uidOrPhone == null || uidOrPhone.isEmpty) return null;
    final fs = FirebaseFirestore.instance;

    final doc = await fs.collection('users').doc(uidOrPhone).get();
    if (doc.exists) return doc.data();

    final legacy = await fs.collection('users').doc(uidOrPhone).get();
    return legacy.data();
  }

  String _pickPhotoUrl(Map<String, dynamic>? user) {
    if (user == null) return '';
    final avatarUrl = (user['avatarUrl'] ?? '').toString();
    if (avatarUrl.isNotEmpty) return avatarUrl;
    final photoUrl = (user['photoUrl'] ?? '').toString();
    if (photoUrl.isNotEmpty) return photoUrl;
    return '';
  }

  // ======= ค้นหา/โหลดข้อมูล =======

  Future<String?> _resolveUidByPhone(String phone) async {
    final fs = FirebaseFirestore.instance;

    // mapping phone→uid
    final map = await fs.collection('phone_to_uid').doc(phone).get();
    final mapped = (map.data()?['uid'] ?? '').toString();
    if (mapped.isNotEmpty) return mapped;

    // users query
    final q = await fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first.id;

    // legacy docId = phone
    final legacy = await fs.collection('users').doc(phone).get();
    if (legacy.exists) return phone;

    return null;
  }

  Future<Map<String, dynamic>?> _loadUserProfile(String uid) async {
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return snap.data();
  }

  /// โหลดที่อยู่ของผู้ใช้ และคืนค่ามาเฉพาะ "ที่อยู่หลัก" เท่านั้น (ถ้าไม่มีคืน [])
  Future<List<Map<String, dynamic>>> _loadAddressesForUid(
      String uid, String phone) async {
    final fs = FirebaseFirestore.instance;

    final sub =
        await fs.collection('users').doc(uid).collection('addresses').get();
    List<Map<String, dynamic>> list = [];
    if (sub.docs.isNotEmpty) {
      list = sub.docs.map((d) {
        final m = d.data();
        return {
          'id': d.id,
          'label': (m['label'] ?? m['name'] ?? 'ที่อยู่').toString(),
          'detail': (m['detail'] ?? m['address_text'] ?? '').toString(),
          'phone': (m['phone'] ?? '').toString(),
          'is_default': (m['is_default'] ?? false) == true,
          'created_at': m['created_at'],
          ...m,
        };
      }).toList();
    } else {
      final top = await fs
          .collection('addressuser')
          .where('userId', isEqualTo: uid)
          .get();
      final top2 = top.docs.isEmpty
          ? await fs
              .collection('addressuser')
              .where('userId', isEqualTo: phone)
              .get()
          : null;

      list = (top.docs.isNotEmpty ? top.docs : (top2?.docs ?? [])).map((d) {
        final m = d.data();
        return {
          'id': d.id,
          'label': (m['name'] ?? m['label'] ?? m['name_address'] ?? 'ที่อยู่')
              .toString(),
          'detail': (m['address_text'] ?? m['detail'] ?? '').toString(),
          'phone': (m['phone'] ?? '').toString(),
          'is_default': (m['is_default'] ?? false) == true,
          'created_at': m['created_at'],
          ...m,
        };
      }).toList();
    }

    // default → ใหม่สุด
    list.sort((a, b) {
      final da = a['is_default'] == true ? 0 : 1;
      final db = b['is_default'] == true ? 0 : 1;
      if (da != db) return da.compareTo(db);
      final ta = a['created_at'];
      final tb = b['created_at'];
      final ai = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
      final bi = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
      return bi.compareTo(ai);
    });

    if (list.isEmpty) return [];
    final mainAddr = list.first;
    return [mainAddr];
  }

  Future<void> _searchByPhone() async {
    final phone = _normalizePhone(_phoneCtrl.text);
    if (phone.isEmpty) {
      _toast('กรุณากรอกเบอร์โทร');
      return;
    }

    setState(() {
      _searching = true;
      _uid = null;
      _user = null;
      _addresses = [];
      _addressIdSelected = null;
      // ไม่ล้าง _senderPickupAddress เพื่อให้ UI ยังเห็นค่าปัจจุบันระหว่างโหลด
    });

    try {
      final uid = await _resolveUidByPhone(phone);
      if (uid == null) {
        _toast('ไม่พบผู้ใช้จากเบอร์นี้');
        return;
      }

      final profile = await _loadUserProfile(uid);
      final addresses = await _loadAddressesForUid(uid, phone);
      final senderPickup =
          await _getSenderDefaultAddress(); // โหลดที่อยู่ผู้ส่งด้วย

      final String? defaultId =
          addresses.isNotEmpty ? addresses.first['id'] as String : null;

      setState(() {
        _uid = uid;
        _user = profile ?? {'name': '-', 'phone': phone};
        _addresses = addresses;
        _addressIdSelected = defaultId;
        _senderPickupAddress = senderPickup; // โชว์ทันที
      });

      // ✅ อัปเดตแผนที่หลังได้ข้อมูล
      _refreshMiniMap();

      if (addresses.isEmpty) _toast('ผู้รับยังไม่มีที่อยู่');
    } catch (e) {
      _toast('ค้นหาล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // เลือกรูปสินค้า
  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              height: 5,
              width: 44,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูป'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากคลัง'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (src == null) return;

    final x = await ImagePicker()
        .pickImage(source: src, imageQuality: 85, maxWidth: 1600);
    if (x != null) setState(() => _photoFile = File(x.path));
  }

  Future<Map<String, dynamic>?> _getSenderDefaultAddress() async {
    final fs = FirebaseFirestore.instance;
    final uid = SessionStore.userId ?? '';
    final phone = SessionStore.phoneId ?? '';
    if (uid.isEmpty && phone.isEmpty) return null;

    final byUid = await fs
        .collection('addressuser')
        .where('userId', isEqualTo: uid)
        .get();
    QuerySnapshot<Map<String, dynamic>>? byPhone;
    if (byUid.docs.isEmpty && phone.isNotEmpty) {
      byPhone = await fs
          .collection('addressuser')
          .where('userId', isEqualTo: phone)
          .get();
    }

    final docs =
        byUid.docs.isNotEmpty ? byUid.docs.toList() : (byPhone?.docs ?? []);
    if (docs.isEmpty) return null;

    docs.sort((a, b) {
      final da = ((a.data()['is_default'] ?? false) == true) ? 0 : 1;
      final db = ((b.data()['is_default'] ?? false) == true) ? 0 : 1;
      if (da != db) return da.compareTo(db);
      final ta = a.data()['created_at'];
      final tb = b.data()['created_at'];
      final ai = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
      final bi = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
      return bi.compareTo(ai);
    });

    final d = docs.first;
    final m = d.data();

    return {
      'id': d.id,
      ..._normalizeAddressMap(m),
      'is_default': (m['is_default'] ?? false) == true,
      'created_at': m['created_at'],
    };
  }

  // ====== Mini-map helpers ======
  void _refreshMiniMap() {
    // pickup
    _pickupLatLng = _toLatLngFromMap(_senderPickupAddress);

    // receiver main
    LatLng? receiver;
    if (_addressIdSelected != null) {
      final a = _addresses.firstWhere(
        (x) => x['id'] == _addressIdSelected,
        orElse: () => {},
      );
      if (a.isNotEmpty) {
        receiver = _toLatLngFromMap(_normalizeAddressMap(a));
      }
    }
    _dropLatLng = receiver;

    // markers
    final newMarkers = <Marker>{};
    if (_pickupLatLng != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLatLng!,
          infoWindow: const InfoWindow(title: 'รับของ (ผู้ส่ง)'),
        ),
      );
    }
    if (_dropLatLng != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: _dropLatLng!,
          infoWindow: const InfoWindow(title: 'ส่งของ (ผู้รับ)'),
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });

    // fit bounds เมื่อ controller พร้อม และมีอย่างน้อย 1 จุด
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_mapCtrl == null) return;
      if (_pickupLatLng == null && _dropLatLng == null) return;

      if (_pickupLatLng != null && _dropLatLng != null) {
        final sw = LatLng(
          _pickupLatLng!.latitude <= _dropLatLng!.latitude
              ? _pickupLatLng!.latitude
              : _dropLatLng!.latitude,
          _pickupLatLng!.longitude <= _dropLatLng!.longitude
              ? _pickupLatLng!.longitude
              : _dropLatLng!.longitude,
        );
        final ne = LatLng(
          _pickupLatLng!.latitude >= _dropLatLng!.latitude
              ? _pickupLatLng!.latitude
              : _dropLatLng!.latitude,
          _pickupLatLng!.longitude >= _dropLatLng!.longitude
              ? _pickupLatLng!.longitude
              : _dropLatLng!.longitude,
        );
        final bounds = LatLngBounds(southwest: sw, northeast: ne);
        try {
          await _mapCtrl!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 60),
          );
        } catch (_) {
          // บางครั้งต้องรอให้แผนที่เรนเดอร์ก่อน
          await Future.delayed(const Duration(milliseconds: 200));
          await _mapCtrl!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 60),
          );
        }
      } else {
        final only = _pickupLatLng ?? _dropLatLng!;
        await _mapCtrl!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: only, zoom: 15),
          ),
        );
      }
    });
  }

  // ============== สร้างคำสั่งเดี่ยวแบบยืนยัน (status=1) ==============
  Future<void> _createShipment() async {
    if (_uid == null) {
      _toast('กรุณาค้นหาผู้รับก่อน');
      return;
    }
    if (_addressIdSelected == null) {
      _toast('กรุณาเลือกที่อยู่ผู้รับ');
      return;
    }
    final itemName = _itemNameCtrl.text.trim();
    if (itemName.isEmpty) {
      _toast('กรอกชื่อสินค้า');
      return;
    }

    final senderId = SessionStore.userId ?? SessionStore.phoneId ?? '';
    if (senderId.isEmpty) {
      _toast('ไม่พบข้อมูลผู้ส่ง (session ว่าง)');
      return;
    }

    setState(() => _creating = true);

    try {
      final senderProfile = await _loadUserProfileSafe(
          SessionStore.userId ?? SessionStore.phoneId);
      final senderPhotoUrl = _pickPhotoUrl(senderProfile);

      final receiverProfile = await _loadUserProfileSafe(_uid);
      final receiverPhotoUrl = _pickPhotoUrl(receiverProfile);

      final senderPickup =
          _senderPickupAddress ?? await _getSenderDefaultAddress();
      final senderPickupNorm = _normalizeAddressMap(senderPickup);

      Map<String, dynamic>? receiverAddr;
      if (_addressIdSelected != null) {
        receiverAddr = _addresses.firstWhere(
          (a) => a['id'] == _addressIdSelected,
          orElse: () => {},
        );
      }
      final receiverAddrNorm =
          receiverAddr == null ? null : _normalizeAddressMap(receiverAddr);

      await _shipApi.createConfirmed(
        senderId: senderId,
        receiverId: _uid!,
        pickupAddressId: senderPickup?['id'],
        deliveryAddressId: _addressIdSelected,
        itemName: itemName,
        itemDescription: _itemNoteCtrl.text,
        senderSnapshot: {
          'user_id': senderId,
          'name': (SessionStore.fullname ?? '').toString(),
          'phone': (SessionStore.phoneId ?? '').toString(),
          'photo_url': senderPhotoUrl,
          'pickup_address_id': senderPickup?['id'],
          'pickup_address': senderPickupNorm,
        },
        receiverSnapshot: {
          'user_id': _uid,
          'name': (_user?['name'] ?? _user?['fullname'] ?? '').toString(),
          'phone': (_user?['phone'] ?? '').toString(),
          'photo_url': receiverPhotoUrl,
          'address_id': _addressIdSelected,
        },
        deliveryAddressSnapshot: receiverAddrNorm,
        firstPhotoFile: _photoFile,
      );

      _toast('สร้างคำสั่งสำเร็จ', success: true);

      setState(() {
        _itemNameCtrl.clear();
        _itemNoteCtrl.clear();
        _photoFile = null;
      });

      await _refreshCartCount();
    } catch (e) {
      _toast('สร้างคำสั่งล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ============== เพิ่มเป็น Draft (status=0) ==============
  Future<void> _addToCart() async {
    if (_uid == null) return _toast('กรุณาค้นหาผู้รับก่อน');
    if (_addressIdSelected == null) {
      _toast('ยังไม่มีที่อยู่หลักของผู้รับ');
      return;
    }
    final name = _itemNameCtrl.text.trim();
    if (name.isEmpty) return _toast('กรอกชื่อสินค้า');

    final ownerId =
        (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (ownerId.isEmpty) return _toast('ไม่พบ session ของผู้ส่ง');

    if (_addingToCart) return;
    setState(() => _addingToCart = true);

    try {
      final senderProfile = await _loadUserProfileSafe(
          SessionStore.userId ?? SessionStore.phoneId);
      final senderPhotoUrl = _pickPhotoUrl(senderProfile);

      final receiverProfile = await _loadUserProfileSafe(_uid);
      final receiverPhotoUrl = _pickPhotoUrl(receiverProfile);

      final senderPickup =
          _senderPickupAddress ?? await _getSenderDefaultAddress();
      final senderPickupNorm = _normalizeAddressMap(senderPickup);

      final receiverAddr = _addresses.firstWhere(
        (a) => a['id'] == _addressIdSelected,
        orElse: () => {},
      );
      final receiverAddrNorm = _normalizeAddressMap(receiverAddr);

      await _shipApi.createDraft(
        senderId: ownerId,
        receiverId: _uid!,
        pickupAddressId: senderPickup?['id'],
        deliveryAddressId: _addressIdSelected,
        itemName: name,
        itemDescription: _itemNoteCtrl.text,
        senderSnapshot: {
          'user_id': ownerId,
          'name': (SessionStore.fullname ?? '').toString(),
          'phone': (SessionStore.phoneId ?? '').toString(),
          'photo_url': senderPhotoUrl,
          'pickup_address_id': senderPickup?['id'],
          'pickup_address': senderPickupNorm,
        },
        receiverSnapshot: {
          'user_id': _uid,
          'name': (_user?['name'] ?? _user?['fullname'] ?? '').toString(),
          'phone': (_user?['phone'] ?? '').toString(),
          'photo_url': receiverPhotoUrl,
          'address_id': _addressIdSelected,
        },
        deliveryAddressSnapshot: receiverAddrNorm,
        firstPhotoFile: _photoFile,
      );

      _toast('เพิ่มเป็นรายการสินค้าแล้ว', success: true);

      setState(() {
        _itemNameCtrl.clear();
        _itemNoteCtrl.clear();
        _photoFile = null;
      });

      await _refreshCartCount();
    } catch (e) {
      _toast('เพิ่มร่างล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }

  /// “ส่งทั้งหมด” → ยืนยัน draft ทั้งหมด (status 0 → 1)
  Future<void> _sendAllFromCart() async {
    final ownerId =
        (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (ownerId.isEmpty) {
      _toast('ไม่พบ session ของผู้ส่ง');
      return;
    }

    setState(() => _sendingAll = true);

    try {
      final updated = await _shipApi.sendAllDrafts(senderId: ownerId);

      if (updated == 0) {
        _toast('ไม่มีรายการร่างที่รอส่ง');
      } else {
        _toast('ยืนยันส่งทั้งหมดสำเร็จ ($updated รายการ)', success: true);
      }

      await _refreshCartCount();
    } catch (e) {
      _toast('ส่งทั้งหมดล้มเหลว: $e');
    } finally {
      if (mounted) setState(() => _sendingAll = false);
    }
  }

  // ===== ลบร่างเดี่ยว (UI) =====
  Future<void> _deleteDraft(String shipmentId) async {
    final ownerId =
        (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (ownerId.isEmpty) {
      _toast('ไม่พบ session ของผู้ส่ง');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบรายการร่าง'),
        content: const Text('ต้องการลบรายการร่างนี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final done = await _shipApi.deleteIfDraft(
        shipmentId: shipmentId,
        ownerId: ownerId,
      );
      if (done) {
        _toast('ลบรายการร่างแล้ว', success: true);
        await _refreshCartCount();
      } else {
        _toast('ลบไม่ได้: ไม่ใช่ของคุณหรือไม่อยู่สถานะร่าง');
      }
    } catch (e) {
      _toast('ลบล้มเหลว: $e');
    }
  }

  // ===== Draft counter =====
  Future<void> _refreshCartCount() async {
    final ownerId =
        (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (ownerId.isEmpty) {
      if (mounted) setState(() => _cartCount = 0);
      return;
    }
    final n = await _shipApi.countDrafts(senderId: ownerId);
    if (mounted) setState(() => _cartCount = n);
  }

  // ===== lifecycle =====
  @override
  void initState() {
    super.initState();
    _warmupSenderPickup();
    _refreshCartCount();
  }

  Future<void> _warmupSenderPickup() async {
    try {
      final m = await _getSenderDefaultAddress();
      if (mounted) setState(() => _senderPickupAddress = m);
      // มีที่อยู่ผู้ส่งแล้ว ลองรีเฟรชแผนที่
      _refreshMiniMap();
    } catch (_) {}
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _itemNameCtrl.dispose();
    _itemNoteCtrl.dispose();
    _mapCtrl?.dispose();
    super.dispose();
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: customAppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              child: Column(
                children: [
                  _sectionChip(icon: Icons.local_shipping, text: 'ส่งสินค้า'),
                  const SizedBox(height: 10),
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _labelRow('ค้นหาผู้รับสินค้า',
                            icon: Icons.call_outlined),
                        const SizedBox(height: 8),
                        _searchBox(),
                        const SizedBox(height: 12),
                        _divider(),
                        const SizedBox(height: 12),
                        _labelRow('สินค้า', icon: Icons.inventory_2_outlined),
                        const SizedBox(height: 8),
                        _input(_itemNameCtrl, hint: 'ชื่อสินค้า *'),
                        const SizedBox(height: 8),
                        _input(_itemNoteCtrl,
                            hint: 'รายละเอียดสินค้า (ถ้ามี)', maxLines: 3),
                        const SizedBox(height: 12),
                        _photoPickerBlock(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  _sectionChip(
                      icon: Icons.store_mall_directory_outlined,
                      text: 'ที่อยู่ผู้ส่ง (จุดรับ)'),
                  const SizedBox(height: 10),
                  _senderPickupAddress == null
                      ? _emptyCard(
                          'ยังไม่พบที่อยู่รับของของผู้ส่ง — โปรดเพิ่มที่อยู่ในโปรไฟล์ (เมนู Address) หรือกำหนดค่าเริ่มต้น')
                      : _pickupCard(_senderPickupAddress!),

                  const SizedBox(height: 14),

                  _sectionChip(
                      icon: Icons.person_outline, text: 'ข้อมูลผู้รับ'),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _uid == null
                        ? _emptyCard(
                            'กรอกเบอร์แล้วกดไอคอนแว่นขยายเพื่อค้นหาผู้รับ',
                          )
                        : Column(
                            key: const ValueKey('receiver'),
                            children: [
                              _receiverCard(_user, _uid!),
                              const SizedBox(height: 10),
                              if (_addressIdSelected == null)
                                _emptyCard(
                                    'ยังไม่มีที่อยู่หลัก — ให้ผู้รับเพิ่มในโปรไฟล์')
                              else
                                _receiverAddressSummary(),
                              const SizedBox(height: 10),

                              // ✅ แผนที่จำลอง
                              _miniMapCard(),
                            ],
                          ),
                  ),

                  const SizedBox(height: 16),

                  _primaryButton(
                    icon: _creating
                        ? Icons.hourglass_bottom
                        : Icons.play_arrow_rounded,
                    text: _creating
                        ? 'กำลังสร้างคำสั่ง...'
                        : 'สร้างคำสั่งส่งสินค้ารายการเดียว',
                    onPressed: _creating ? () {} : _createShipment,
                  ),
                  const SizedBox(height: 10),
                  _secondaryButton(
                    icon: _addingToCart
                        ? Icons.hourglass_empty
                        : Icons.add_shopping_cart_outlined,
                    text: _addingToCart
                        ? 'กำลังเพิ่มเป็นร่าง...'
                        : 'เพิ่มรายการในงาน',
                    onPressed: _addingToCart ? () {} : _addToCart,
                  ),

                  const SizedBox(height: 18),

                  // แถบ "คิวร่าง" + ปุ่มยืนยันทั้งหมด
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _orangeSoft.withOpacity(.9), width: 1),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 10,
                          offset: Offset(0, 6),
                          color: Color(0x12000000),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.pending_actions_outlined,
                            color: _orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'งานรอยืนยัน: $_cartCount รายการ',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.black87),
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: (_cartCount == 0 || _sendingAll)
                                ? null
                                : _sendAllFromCart,
                            icon: _sendingAll
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.check_circle_outline),
                            label: Text(_sendingAll
                                ? 'กำลังยืนยัน...'
                                : 'ยืนยันทั้งหมด'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _cartCount == 0 ? Colors.grey : _orange,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  _sectionChip(
                      icon: Icons.list_alt_outlined,
                      text: 'รายการสินค้าของฉัน'),
                  const SizedBox(height: 10),
                  _draftListCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip({required IconData icon, required String text}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _orange,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Color(0x30FD8700), blurRadius: 8, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Material(
      elevation: 3,
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      shadowColor: Colors.black.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        width: double.infinity,
        color: Colors.grey.shade200,
      );

  Widget _labelRow(String text, {required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: _orange, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }

  Widget _searchBox() {
    return TextField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        hintText: 'ค้นหาเบอร์',
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.phone_outlined),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_phoneCtrl.text.isNotEmpty)
              IconButton(
                tooltip: 'ล้าง',
                onPressed: () {
                  _phoneCtrl.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              onPressed: _searching ? null : _searchByPhone,
              icon: _searching
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
            ),
          ],
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _orange, width: 2),
        ),
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _searchByPhone(),
    );
  }

  Widget _input(TextEditingController c, {String? hint, int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _orange, width: 2),
        ),
      ),
    );
  }

  Widget _photoPickerBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.photo_camera_outlined, color: _orange, size: 20),
            SizedBox(width: 6),
            Text('แนบรูปสินค้า *',
                style: TextStyle(fontWeight: FontWeight.w700)),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'รูปแสดงให้ไรเดอร์ดู',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: _orange),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _photoPicker(),
      ],
    );
  }

  Widget _photoPicker() {
    return InkWell(
      onTap: _pickPhoto,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        height: 160,
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _orangeSoft, width: 1.4),
        ),
        child: _photoFile == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 40, color: Colors.black54),
                    SizedBox(height: 6),
                    Text('แตะเพื่อเพิ่มรูป',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.file(
                  _photoFile!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
      ),
    );
  }

  Widget _emptyCard(String text) {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF1D6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.info_outline, color: _orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiverCard(Map<String, dynamic>? user, String uid) {
    final name = (user?['name'] ?? '-').toString();
    final phone = (user?['phone'] ?? '-').toString();

    final avatarUrl =
        (user?['avatarUrl'] ?? user?['photoUrl'] ?? '').toString();

    return _card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFF1F1F1),
            backgroundImage:
                avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(phone, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickupCard(Map<String, dynamic> a) {
    final label = (a['label']).toString();
    final detail = (a['detail_normalized']).toString();
    final phone = (a['phone'] ?? '').toString();

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.storefront_outlined, color: _orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(height: 1.3)),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(phone, style: const TextStyle(color: Colors.grey)),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiverAddressSummary() {
    final a = _addresses.firstWhere(
      (x) => x['id'] == _addressIdSelected,
      orElse: () => {},
    );
    if (a.isEmpty) return const SizedBox.shrink();

    final norm = _normalizeAddressMap(a);
    final label = (norm['label']).toString();
    final detail = (norm['detail_normalized']).toString();
    final phone = (norm['phone']).toString();

    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_on_outlined, color: _orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _pillBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _orangeSoft, width: 1.2),
                  ),
                  child: const Text('ที่อยู่ผู้รับ (หลัก)',
                      style: TextStyle(
                          color: _orange, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 8),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(detail, style: const TextStyle(height: 1.3)),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(phone, style: const TextStyle(color: Colors.grey)),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Mini-map card
  Widget _miniMapCard() {
    final hasAnyPoint = _pickupLatLng != null || _dropLatLng != null;

    return _card(
      child: SizedBox(
        height: 220,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hasAnyPoint
              ? GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _pickupLatLng ??
                        _dropLatLng ??
                        const LatLng(13.7563, 100.5018), // BKK fallback
                    zoom: 13,
                  ),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  markers: _markers,
                  onMapCreated: (c) {
                    _mapCtrl = c;
                    // ฟิตกล้องครั้งแรก
                    _refreshMiniMap();
                  },
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.map_outlined, size: 40, color: Colors.black45),
                      SizedBox(height: 6),
                      Text('ยังไม่มีพิกัดให้แสดง',
                          style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _primaryButton(
      {required IconData icon,
      required String text,
      required VoidCallback onPressed}) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: ElevatedButton.styleFrom(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _secondaryButton(
      {required IconData icon,
      required String text,
      required VoidCallback onPressed}) {
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: _orange),
        label: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _orange, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _orange, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          backgroundColor: Colors.white,
        ),
      ),
    );
  }

  // ===== รายการร่างของฉัน =====
  Widget _draftListCard() {
    final ownerId =
        (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();
    if (ownerId.isEmpty) {
      return _emptyCard('ยังไม่ได้ล็อกอินผู้ส่ง');
    }

    return _card(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _shipApi.watchDrafts(senderId: ownerId, limit: 100),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Text('ยังไม่มีรายการร่าง');
          }

          final docs = snap.data!.docs;

          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => Divider(color: Colors.grey.shade200),
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final id = d.id;
              final itemName = (m['item_name'] ?? '—').toString();
              final receiver =
                  ((m['receiver_snapshot']?['name']) ?? '—').toString();
              final lastUrl = (m['last_photo_url'] ?? '').toString();

              final subtitleParts = <String>[];
              if (receiver.isNotEmpty) subtitleParts.add('ผู้รับ: $receiver');
              final subtitle = subtitleParts.join(' • ');

              final tile = ListTile(
                contentPadding: EdgeInsets.zero,
                leading: (lastUrl.isEmpty)
                    ? const CircleAvatar(child: Icon(Icons.inventory_2))
                    : CircleAvatar(
                        backgroundImage: NetworkImage(lastUrl),
                      ),
                title: Text(
                  'ชื่อสินค้า $itemName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(subtitle,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'ลบรายการร่างนี้',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteDraft(id),
                ),
              );

              // รองรับปาดเพื่อลบ
              return Dismissible(
                key: ValueKey('draft_$id'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (_) async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('ลบรายการร่าง'),
                      content: const Text('ต้องการลบรายการร่างนี้หรือไม่?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('ยกเลิก')),
                        ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('ลบ')),
                      ],
                    ),
                  );
                  return ok == true;
                },
                onDismissed: (_) => _deleteDraft(id),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}
