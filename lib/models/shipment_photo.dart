// lib/models/shipment_photo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class ShipmentPhoto {
  final String id;
  final String url; // อาจเป็น http(s), gs:// หรือ storage path ตอนอ่านครั้งแรก
  final int status; // 1..4 หรือ 0 ถ้าไม่ระบุ
  final Timestamp? ts; // เวลาถ่าย/อัปโหลด (optional)
  // คุณมีฟิลด์อื่น ๆ ก็เพิ่มได้ เช่น takenBy, note ฯลฯ

  const ShipmentPhoto({
    required this.id,
    required this.url,
    required this.status,
    this.ts,
  });

  factory ShipmentPhoto.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data();
    final s = m['status'];
    return ShipmentPhoto(
      id: d.id,
      url: (m['url'] ??
              m['photo_url'] ??
              m['image_url'] ??
              m['downloadURL'] ??
              m['download_url'] ??
              m['path'] ??
              m['storage_path'] ??
              m['filePath'] ??
              '')
          .toString(),
      status: (s is int) ? s : (int.tryParse('$s') ?? 0),
      ts: m['ts'] is Timestamp ? m['ts'] as Timestamp : null,
    );
  }

  ShipmentPhoto copyWith({
    String? url,
    int? status,
    Timestamp? ts,
  }) {
    return ShipmentPhoto(
      id: id,
      url: url ?? this.url,
      status: status ?? this.status,
      ts: ts ?? this.ts,
    );
  }
}
