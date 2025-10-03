import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final _ref = FirebaseStorage.instance.ref();

  Future<String?> uploadUserAvatar({
    required String phoneDocId,
    required File file,
  }) async {
    final dest = _ref.child('users/$phoneDocId/profile.jpg');
    await dest.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return await dest.getDownloadURL();
  }
}
