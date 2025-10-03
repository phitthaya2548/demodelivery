import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:deliverydomo/models/user_profile.dart';

class UserRepo {
  final _col = FirebaseFirestore.instance.collection('users');

  Future<bool> exists(String phoneDocId) async =>
      (await _col.doc(phoneDocId).get()).exists;

  Future<void> create(UserProfile u) async => _col.doc(u.id).set({
        ...u.toJson(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

  Future<void> updatePhoto(String phoneDocId, String url) async =>
      _col.doc(phoneDocId).update({
        'photoUrl': url,
        'updated_at': FieldValue.serverTimestamp(),
      });

  Future<UserProfile?> getByPhone(String phoneDocId) async {
    final d = await _col.doc(phoneDocId).get();
    if (!d.exists) return null;
    return UserProfile.fromJson(d.id, d.data()!);
  }
}
