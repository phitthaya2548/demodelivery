import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/app_colors.dart';
import 'package:deliverydomo/models/shipment_models.dart';
import 'package:deliverydomo/pages/riders/widgets/appbar.dart';
import 'package:deliverydomo/pages/sesstion.dart';
import 'package:deliverydomo/services/firebase_reueries_rider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

class ListRider extends StatefulWidget {
  const ListRider({Key? key}) : super(key: key);

  @override
  State<ListRider> createState() => _ListRiderState();
}

class _ListRiderState extends State<ListRider> {
  String get _riderId =>
      (SessionStore.userId ?? SessionStore.phoneId ?? '').toString();

  final _picker = ImagePicker();
  final _repo = FirebaseRiderRepository();

  File? _pendingProofPreviewFile;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _riderLockStream() {
    if (_riderId.isEmpty) {
      return Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();
    }
    return _repo.watchRider(_riderId);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _mineStream() {
    return FirebaseFirestore.instance
        .collection('shipments')
        .where('rider_id', isEqualTo: _riderId)
        .where('status', whereIn: [2, 3])
        .snapshots()
        .map((qs) => qs.docs);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _shipmentById(String id) =>
      _repo.watchShipment(id);

  Future<String> _loadAddressTextById(String id) =>
      _repo.loadAddressTextById(id);

  Stream<String> _watchAvatarByUid(String uid) =>
      _repo.watchUserAvatarByUid(uid);
  Stream<String> _watchAvatarByPhone(String phone) =>
      _repo.watchUserAvatarByPhone(phone);

  Future<void> _pickProofPhoto({
    required String shipmentId,
    required int currentStatus,
  }) async {
    if (kIsWeb) {
      Get.snackbar(
        'ยังไม่รองรับเว็บ',
        'อัปโหลดไฟล์จากเว็บยังไม่ได้ในเวอร์ชันนี้',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายรูปด้วยกล้อง'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากเครื่อง'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );

    if (source == null) return;

    final x = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (x == null) return;

    final file = File(x.path);

    setState(() => _pendingProofPreviewFile = file);

    Get.snackbar(
      'เตรียมรูปไว้แล้ว',
      'รูปยังไม่ถูกส่งขึ้นระบบ จนกว่าจะกด "อัปเดตสถานะ"',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _updateStatusOnlyOrWithPending({
    required String shipmentId,
    required int fromStatus,
    required int toStatus,
  }) async {
    try {
      await _repo.updateShipmentStatus(
        riderId: _riderId,
        shipmentId: shipmentId,
        fromStatus: fromStatus,
        toStatus: toStatus,
        proofFile: _pendingProofPreviewFile,
      );

      setState(() => _pendingProofPreviewFile = null);

      Get.snackbar('สำเร็จ', 'อัปเดตสถานะเรียบร้อย',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('อัปเดตไม่สำเร็จ', '$e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red[400],
          colorText: Colors.white);
    }
  }

  VoidCallback _onUpdateStatus(String shipmentId, int statusVal) {
    return () async {
      if (statusVal == 2) {
        await _updateStatusOnlyOrWithPending(
            shipmentId: shipmentId, fromStatus: 2, toStatus: 3);
      } else if (statusVal == 3) {
        await _updateStatusOnlyOrWithPending(
            shipmentId: shipmentId, fromStatus: 3, toStatus: 4);
      } else {
        Get.snackbar('แจ้งเตือน', 'งานนี้ปิดจ๊อบแล้ว',
            snackPosition: SnackPosition.BOTTOM);
      }
    };
  }

  Widget _buildShipmentCard(ShipmentVM vm) {
    return _ShipmentDetailCard(
      brand: 'Delivery WarpSong',
      itemName: vm.itemName,
      itemDesc: vm.itemDesc,
      photoUrl: vm.photoUrl,
      senderName: vm.sender.name,
      senderPhone: vm.sender.phone,
      senderAvatar: _Avatar(
        immediateUrl: vm.sender.immediateAvatar,
        uid: vm.sender.uid,
        phone: vm.sender.phone,
        // เปลี่ยนเป็น watcher สองตัวนี้
        watchByUid: _watchAvatarByUid,
        watchByPhone: _watchAvatarByPhone,
        radius: 24,
      ),
      senderAddressWidget: _AddressText(
        immediateText: vm.sender.addressImmediate,
        addressIdForFallback: vm.sender.addressIdFallback,
        loadById: _loadAddressTextById,
      ),
      receiverName: vm.receiver.name,
      receiverPhone: vm.receiver.phone,
      receiverAvatar: _Avatar(
        immediateUrl: vm.receiver.immediateAvatar,
        uid: vm.receiver.uid,
        phone: vm.receiver.phone,
        watchByUid: _watchAvatarByUid,
        watchByPhone: _watchAvatarByPhone,
        radius: 24,
      ),
      receiverAddressWidget: _AddressText(
        immediateText: vm.receiver.addressImmediate,
        addressIdForFallback: vm.receiver.addressIdFallback,
        loadById: _loadAddressTextById,
      ),
      status: vm.status,
      pendingPreviewFile: _pendingProofPreviewFile,
      onPickProofPhoto: () =>
          _pickProofPhoto(shipmentId: vm.id, currentStatus: vm.status),
      onUpdateStatus: _onUpdateStatus(vm.id, vm.status),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F7F5),
      appBar: customAppBar(),
      body: (_riderId.isEmpty)
          ? const Center(child: Text('ยังไม่พบรหัสไรเดอร์ในเซสชัน'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _riderLockStream(),
              builder: (context, riderSnap) {
                final riderData = riderSnap.data?.data() ?? {};
                final currentId =
                    (riderData['current_shipment_id'] ?? '').toString();
                final hasCurrent = currentId.isNotEmpty;

                if (hasCurrent) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _shipmentById(currentId),
                    builder: (context, shipSnap) {
                      if (shipSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!shipSnap.hasData || !shipSnap.data!.exists) {
                        return const Center(
                            child: Text('ไม่พบงานที่ถูกล็อกไว้'));
                      }

                      final vm = ShipmentVM.fromDoc(shipSnap.data!);

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                        children: [
                          _LockedBanner(currentId: currentId),
                          const SizedBox(height: 12),
                          _buildShipmentCard(vm),
                        ],
                      );
                    },
                  );
                }

                return StreamBuilder<
                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: _mineStream(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('เกิดข้อผิดพลาด: ${snap.error}'),
                      );
                    }

                    final active = (snap.data ?? []);
                    if (active.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            const Text(
                              'ไม่มีงาน',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'รอการมอบหมายงานใหม่',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    active.sort((a, b) {
                      int ts(
                          DocumentSnapshot<Map<String, dynamic>> d, String k) {
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

                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
                      itemCount: active.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final vm = ShipmentVM.fromDoc(active[i]);
                        return _buildShipmentCard(vm);
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}

class _LockedBanner extends StatelessWidget {
  const _LockedBanner({required this.currentId});

  final String currentId;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.orange.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock_outlined, color: AppColors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'งานที่ล็อกไว้',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.orange,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#$currentId',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.info_outline, color: Colors.black26, size: 18),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    Key? key,
    required this.immediateUrl,
    required this.uid,
    required this.phone,
    required this.watchByUid,
    required this.watchByPhone,
    this.radius = 20,
  }) : super(key: key);

  final String immediateUrl;
  final String uid;
  final String phone;
  final Stream<String> Function(String uid) watchByUid;
  final Stream<String> Function(String phone) watchByPhone;
  final double radius;

  Stream<String> _chooseStream() {
    if (uid.isNotEmpty) return watchByUid(uid);
    if (phone.isNotEmpty) return watchByPhone(phone);
    // ถ้าไม่มีทั้ง uid/phone ก็ส่งสตรีมว่าง
    return const Stream<String>.empty();
  }

  @override
  Widget build(BuildContext context) {
    // ถ้ามี URL จาก snapshot ติดมาก่อน ใช้เป็น initialData ให้ UI แสดงก่อน
    final initial = immediateUrl;

    return StreamBuilder<String>(
      stream: _chooseStream(),
      initialData: initial,
      builder: (context, snap) {
        final url = (snap.data ?? '').trim();
        final hasUrl = url.isNotEmpty;

        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                spreadRadius: 1,
              )
            ],
          ),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFF5F5F5),
            backgroundImage: hasUrl ? NetworkImage(url) : null,
            child: hasUrl
                ? null
                : const Icon(Icons.person_outline,
                    color: Colors.black45, size: 24),
          ),
        );
      },
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
      return Text(
        immediateText,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
          height: 1.4,
        ),
      );
    }
    if (addressIdForFallback.isEmpty) {
      return const Text('-',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.black54, fontSize: 12));
    }
    return FutureBuilder<String>(
      future: loadById(addressIdForFallback),
      builder: (context, snap) {
        final txt = (snap.data ?? '').toString();
        if (snap.connectionState == ConnectionState.waiting) {
          return const Text('กำลังโหลด...',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.black45, fontSize: 12));
        }
        if (txt.isEmpty) {
          return const Text('-',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.black54, fontSize: 12));
        }
        return Text(txt,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
              height: 1.4,
            ));
      },
    );
  }
}

class _ShipmentDetailCard extends StatelessWidget {
  const _ShipmentDetailCard({
    Key? key,
    required this.brand,
    required this.itemName,
    required this.itemDesc,
    required this.photoUrl,
    required this.senderName,
    required this.senderPhone,
    required this.senderAvatar,
    required this.senderAddressWidget,
    required this.receiverName,
    required this.receiverPhone,
    required this.receiverAvatar,
    required this.receiverAddressWidget,
    required this.status,
    required this.pendingPreviewFile,
    required this.onPickProofPhoto,
    required this.onUpdateStatus,
  }) : super(key: key);

  final String brand;
  final String itemName;
  final String itemDesc;
  final String photoUrl;
  final String senderName;
  final String senderPhone;
  final Widget senderAvatar;
  final Widget senderAddressWidget;
  final String receiverName;
  final String receiverPhone;
  final Widget receiverAvatar;
  final Widget receiverAddressWidget;
  final int status;
  final File? pendingPreviewFile;
  final VoidCallback onPickProofPhoto;
  final VoidCallback onUpdateStatus;

  String get _statusText {
    switch (status) {
      case 2:
        return 'ไรเดอร์รับงานแล้วและกำลังเดินทางไปรับ';
      case 3:
        return 'รับพัสดุแล้ว กำลังจัดส่ง';
      case 4:
        return 'จัดส่งเสร็จสิ้น';
      default:
        return 'สถานะไม่ทราบ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeaderSection(brand: brand),
            const SizedBox(height: 16),
            _ItemSection(
              photoUrl: photoUrl,
              itemName: itemName,
              itemDesc: itemDesc,
            ),
            const SizedBox(height: 16),
            _PersonSection(
              title: 'ผู้ส่ง',
              name: senderName,
              phone: senderPhone,
              avatar: senderAvatar,
              addressWidget: senderAddressWidget,
            ),
            const Divider(height: 20, color: Color(0xFFEEEEEE), thickness: 1),
            _PersonSection(
              title: 'ผู้รับ',
              name: receiverName,
              phone: receiverPhone,
              avatar: receiverAvatar,
              addressWidget: receiverAddressWidget,
            ),
            const SizedBox(height: 16),
            _ProofSection(
              status: status,
              statusText: _statusText,
              pendingPreviewFile: pendingPreviewFile,
              onPickProofPhoto: onPickProofPhoto,
            ),
            const SizedBox(height: 16),
            _UpdateButton(
              status: status,
              onPressed: onUpdateStatus,
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
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                brand,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.orange,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'รายละเอียดรายการสินค้า',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _ItemSection extends StatelessWidget {
  const _ItemSection({
    required this.photoUrl,
    required this.itemName,
    required this.itemDesc,
  });

  final String photoUrl;
  final String itemName;
  final String itemDesc;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE4C7), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: photoUrl.isEmpty
                  ? Container(
                      color: Colors.grey.shade200,
                      child:
                          const Icon(Icons.image, color: Colors.grey, size: 48),
                    )
                  : Image.network(photoUrl, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 12),
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
            const SizedBox(height: 6),
            Text(
              itemDesc,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _PersonSection extends StatelessWidget {
  const _PersonSection({
    required this.title,
    required this.name,
    required this.phone,
    required this.avatar,
    required this.addressWidget,
  });

  final String title;
  final String name;
  final String phone;
  final Widget avatar;
  final Widget addressWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'คุณ $name',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              addressWidget,
            ],
          ),
        ),
      ],
    );
  }
}

class _ProofSection extends StatelessWidget {
  const _ProofSection({
    required this.status,
    required this.statusText,
    required this.pendingPreviewFile,
    required this.onPickProofPhoto,
  });

  final int status;
  final String statusText;
  final File? pendingPreviewFile;
  final VoidCallback onPickProofPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE4C7), width: 1),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.camera_alt_outlined,
                  color: AppColors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ถ่ายรูปประกอบสถานะ',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: AppColors.orange,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${status.clamp(1, 4)}/4',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    color: AppColors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onPickProofPhoto,
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFE4C7), width: 1.5),
              ),
              child: pendingPreviewFile == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_a_photo_outlined,
                            size: 40, color: AppColors.orange),
                        SizedBox(height: 8),
                        Text(
                          'แตะเพื่อถ่าย/เลือกรูป',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        pendingPreviewFile!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  const _UpdateButton({
    required this.status,
    required this.onPressed,
  });

  final int status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isDisabled = status >= 4;
    final buttonText = status == 2
        ? 'รับสินค้าแล้ว (อัปเดตเป็น 3/4)'
        : status == 3
            ? 'ส่งสำเร็จ (อัปเดตเป็น 4/4)'
            : 'ปิดงานแล้ว';

    return SizedBox(
      height: 50,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDisabled ? Colors.grey.shade300 : AppColors.green,
          foregroundColor: isDisabled ? Colors.grey.shade600 : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        child: Text(buttonText),
      ),
    );
  }
}
