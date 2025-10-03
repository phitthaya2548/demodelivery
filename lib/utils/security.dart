import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';



String hashPassword(String password, String salt) {
  final bytes = utf8.encode('$salt::$password');
  return sha256.convert(bytes).toString();
}
