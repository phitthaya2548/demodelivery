import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ShipmentApi {
  ShipmentApi({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _st;
  DocumentReference<Map<String, dynamic>> _ref(String id) =>
      _fs.collection('shipments').doc(id);

  Future<Map<String, dynamic>?> getById(String id) async {
    final snap = await _ref(id).get();
    return snap.data();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchById(String id) {
    return _ref(id).snapshots();
  }

  Future<bool> exists(String id) async {
    final snap = await _ref(id).get();
    return snap.exists;
  }

  Future<ShipmentCreateResult> createDraft({
    required String senderId,
    required String receiverId,
    required String? pickupAddressId,
    required String? deliveryAddressId,
    required String itemName,
    String? itemDescription,
    required Map<String, dynamic> senderSnapshot,
    required Map<String, dynamic> receiverSnapshot,
    Map<String, dynamic>? deliveryAddressSnapshot,
    File? firstPhotoFile,
  }) {
    return _createShipment(
      status: 0,
      senderId: senderId,
      receiverId: receiverId,
      pickupAddressId: pickupAddressId,
      deliveryAddressId: deliveryAddressId,
      itemName: itemName,
      itemDescription: itemDescription,
      senderSnapshot: senderSnapshot,
      receiverSnapshot: receiverSnapshot,
      deliveryAddressSnapshot: deliveryAddressSnapshot,
      firstPhotoFile: firstPhotoFile,
    );
  }

  Future<ShipmentCreateResult> createConfirmed({
    required String senderId,
    required String receiverId,
    required String? pickupAddressId,
    required String? deliveryAddressId,
    required String itemName,
    String? itemDescription,
    required Map<String, dynamic> senderSnapshot,
    required Map<String, dynamic> receiverSnapshot,
    Map<String, dynamic>? deliveryAddressSnapshot,
    File? firstPhotoFile,
  }) {
    return _createShipment(
      status: 1,
      senderId: senderId,
      receiverId: receiverId,
      pickupAddressId: pickupAddressId,
      deliveryAddressId: deliveryAddressId,
      itemName: itemName,
      itemDescription: itemDescription,
      senderSnapshot: senderSnapshot,
      receiverSnapshot: receiverSnapshot,
      deliveryAddressSnapshot: deliveryAddressSnapshot,
      firstPhotoFile: firstPhotoFile,
    );
  }

  Future<String> uploadItemPhoto({
    required String shipmentId,
    required File file,
  }) async {
    final url = await _uploadItemPhoto(shipmentId: shipmentId, file: file);
    final docRef = _ref(shipmentId);

    // Update Firestore document with the new photo URL and timestamp
    await docRef.update({
      'last_photo_url': url,
      'last_photo_uploaded_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    // Return the updated URL of the image
    return url;
  }

  Future<int> countDrafts({required String senderId}) async {
    final q = await _fs
        .collection('shipments')
        .where('sender_id', isEqualTo: senderId)
        .where('status', isEqualTo: 0)
        .get();
    return q.docs.length;
  }

  Future<int> sendAllDrafts({required String senderId}) async {
    final q = await _fs
        .collection('shipments')
        .where('sender_id', isEqualTo: senderId)
        .where('status', isEqualTo: 0)
        .get();

    if (q.docs.isEmpty) return 0;

    final now = FieldValue.serverTimestamp();
    WriteBatch? batch;
    const chunk = 450; // Prevent exceeding limit (500 per batch)
    int updated = 0;

    for (int i = 0; i < q.docs.length; i++) {
      if (i % chunk == 0) {
        if (batch != null) {
          await batch.commit();
        }
        batch = _fs.batch();
      }
      batch!.update(q.docs[i].reference, {
        'status': 1,
        'updated_at': now,
      });
      updated++;
    }

    if (batch != null) {
      await batch.commit();
    }

    return updated;
  }

  Future<ShipmentCreateResult> _createShipment({
    required int status,
    required String senderId,
    required String receiverId,
    required String? pickupAddressId,
    required String? deliveryAddressId,
    required String itemName,
    String? itemDescription,
    required Map<String, dynamic> senderSnapshot,
    required Map<String, dynamic> receiverSnapshot,
    Map<String, dynamic>? deliveryAddressSnapshot,
    File? firstPhotoFile,
  }) async {
    final col = _fs.collection('shipments');
    final docRef = col.doc();
    final now = FieldValue.serverTimestamp();

    String? uploadedUrl;
    if (firstPhotoFile != null) {
      uploadedUrl =
          await _uploadItemPhoto(shipmentId: docRef.id, file: firstPhotoFile);
    }

    final payload = <String, dynamic>{
      'id': docRef.id,
      'status': status,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'pickup_address_id': pickupAddressId,
      'delivery_address_id': deliveryAddressId,
      'item_name': itemName,
      'item_description': itemDescription?.trim() ?? '',
      'created_at': now,
      'updated_at': now,
      'sender_snapshot': senderSnapshot,
      'receiver_snapshot': receiverSnapshot,
      'delivery_address_snapshot': deliveryAddressSnapshot,
      'last_photo_url': uploadedUrl ?? '',
      'last_photo_uploaded_at': uploadedUrl == null ? null : now,
    };

    await docRef.set(payload);

    return ShipmentCreateResult(
      id: docRef.id,
      lastPhotoUrl: uploadedUrl ?? '',
      isConfirmed: status == 1,
    );
  }

  Future<String> _uploadItemPhoto({
    required String shipmentId,
    required File file,
  }) async {
    final path =
        'shipments/$shipmentId/item_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _st.ref(path);
    final snap =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return snap.ref.getDownloadURL();
  }
}

class ShipmentCreateResult {
  final String id;
  final String lastPhotoUrl;
  final bool isConfirmed;
  ShipmentCreateResult({
    required this.id,
    required this.lastPhotoUrl,
    required this.isConfirmed,
  });
}
