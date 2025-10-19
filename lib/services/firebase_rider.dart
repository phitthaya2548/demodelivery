// lib/data/firebase_rider_api.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseRiderApi {
  FirebaseRiderApi({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _st;

  /// เช็คเบอร์ซ้ำจาก riders/{uid} โดยการค้นหาจากฟิลด์ phoneNumber
  Future<bool> phoneExists(String phone) async {
    final doc = await _fs
        .collection('riders')
        .where('phoneNumber', isEqualTo: phone)
        .get();
    return doc.docs.isNotEmpty;
  }

  Future<String> _upload({
    required String path,
    required File file,
    String contentType = 'image/jpeg',
  }) async {
    final ref = _st.ref(path);
    final snap =
        await ref.putFile(file, SettableMetadata(contentType: contentType));
    return snap.ref.getDownloadURL();
  }

  /// สร้างไรเดอร์ใหม่ (เก็บเฉพาะใน riders/{uid})
  Future<CreateRiderResult> createRider({
    required String phone,
    required String name,
    required String passwordHash,
    required String plateNumber,
    required File avatarFile, // บังคับมี (ตาม UI)
    File? vehicleFile, // อาจไม่มี
  }) async {
    // กันซ้ำรอบแรกก่อนอัปโหลดรูป
    if (await phoneExists(phone)) {
      throw const FirebaseRiderApiError('PHONE_TAKEN');
    }

    // gen uid จากคอลเลกชัน riders เพื่อใช้เป็น doc id และ path ไฟล์
    final uid = _fs.collection('riders').doc().id;
    final ts = DateTime.now().millisecondsSinceEpoch;

    // อัปโหลดภาพ (ผูก path กับ uid)
    final avatarUrl = await _upload(
      path: 'riders/$uid/avatar_$ts.jpg',
      file: avatarFile,
    );

    String? vehicleUrl;
    if (vehicleFile != null) {
      vehicleUrl = await _upload(
        path: 'riders/$uid/vehicle_$ts.jpg',
        file: vehicleFile,
      );
    }

    final ridersRef = _fs.collection('riders').doc(uid);
    final now = FieldValue.serverTimestamp();

    
    await _fs.runTransaction((tx) async {
     
      tx.set(ridersRef, {
        'id': uid,
        'name': name,
        'phoneNumber': phone,
        'passwordHash': passwordHash,
        'plateNumber': plateNumber,
        'avatarUrl': avatarUrl,
        'vehiclePhotoUrl': vehicleUrl,
        'createdAt': now,
        'updatedAt': now,
      });
    });

    return CreateRiderResult(
      uid: uid,
      avatarUrl: avatarUrl,
      vehicleUrl: vehicleUrl,
    );
  }
}

class CreateRiderResult {
  final String uid;
  final String? avatarUrl;
  final String? vehicleUrl;
  const CreateRiderResult({
    required this.uid,
    this.avatarUrl,
    this.vehicleUrl,
  });
}

class FirebaseRiderApiError implements Exception {
  final String code;
  const FirebaseRiderApiError(this.code);
  @override
  String toString() => code;
}
