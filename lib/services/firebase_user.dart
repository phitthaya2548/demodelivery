// lib/data/firebase_user_api.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseUserApi {
  FirebaseUserApi({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _fs = firestore ?? FirebaseFirestore.instance,
        _st = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _fs;
  final FirebaseStorage _st;

  Future<bool> phoneExists(String phone) async {
    final q = await _fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<String?> _uploadAvatar(String uid, File file) async {
    final ref = _st
        .ref('users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final task = await ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return task.ref.getDownloadURL();
  }

  /// สร้าง user ใหม่ลงที่ users/{uid} โดยตรง
  /// - ไม่สร้าง mapping ใน phone_to_uid
  /// - ถ้าเบอร์ซ้ำ โยน FirebaseUserApiError('PHONE_TAKEN')
  Future<CreateUserResult> createUser({
    required String phone,
    required String name,
    required String passwordHash,
    File? avatarFile,
  }) async {
    // กันซ้ำจาก users โดยตรง
    if (await phoneExists(phone)) {
      throw const FirebaseUserApiError('PHONE_TAKEN');
    }

    // gen uid (doc id)
    final uid = _fs.collection('users').doc().id;

    // อัปโหลดรูป (ถ้ามี)
    String? photoUrl;
    if (avatarFile != null) {
      photoUrl = await _uploadAvatar(uid, avatarFile);
    }

    final usersRef = _fs.collection('users').doc(uid);
    final now = FieldValue.serverTimestamp();

    // บันทึก users/{uid}
    await usersRef.set({
      'id': uid,
      'phone': phone,
      'name': name,
      'photoUrl': photoUrl,
      'passwordHash': passwordHash,
      'createdAt': now,
      'updatedAt': now,
    });

    return CreateUserResult(uid: uid, photoUrl: photoUrl);
  }

  /// (ออปชัน) ดึงผู้ใช้ด้วยเบอร์โดยตรง
  Future<Map<String, dynamic>?> getUserByPhone(String phone) async {
    final q = await _fs
        .collection('users')
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    final d = q.docs.first;
    return {'id': d.id, ...d.data()};
  }
}

class CreateUserResult {
  final String uid;
  final String? photoUrl;
  const CreateUserResult({required this.uid, this.photoUrl});
}

class FirebaseUserApiError implements Exception {
  final String code;
  const FirebaseUserApiError(this.code);
  @override
  String toString() => code;
}
