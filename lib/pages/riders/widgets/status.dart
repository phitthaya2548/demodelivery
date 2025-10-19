import 'package:flutter/foundation.dart';

@immutable
class StatusTransition {
  final int from;
  final int to;
  const StatusTransition(this.from, this.to);
}

enum ShipmentStatus {
  waiting(1), // [1] รอไรเดอร์มารับสินค้า
  accepted(2), // [2] ไรเดอร์รับงาน (กำลังไปรับ)
  picked(3), // [3] รับสินค้าแล้ว กำลังไปส่ง
  delivered(4), // [4] ส่งสำเร็จ
  unknown(0);

  final int code;
  const ShipmentStatus(this.code);

  static ShipmentStatus fromInt(int? v) {
    if (v == null) return ShipmentStatus.unknown;
    return ShipmentStatus.values.firstWhere(
      (e) => e.code == v,
      orElse: () => ShipmentStatus.unknown,
    );
  }
}

extension ShipmentStatusX on ShipmentStatus {
  String get labelTH {
    switch (this) {
      case ShipmentStatus.waiting:
        return 'รอไรเดอร์มารับสินค้า';
      case ShipmentStatus.accepted:
        return 'ไรเดอร์รับงานแล้วและกำลังไปรับ';
      case ShipmentStatus.picked:
        return 'รับพัสดุแล้ว กำลังจัดส่ง';
      case ShipmentStatus.delivered:
        return 'จัดส่งเสร็จสิ้น';
      case ShipmentStatus.unknown:
        return 'สถานะไม่ทราบ';
    }
  }

  /// กติกาการไล่สถานะแบบเชิงธุรกิจ
  StatusTransition? nextTransition() {
    switch (this) {
      case ShipmentStatus.accepted:
        return const StatusTransition(2, 3);
      case ShipmentStatus.picked:
        return const StatusTransition(3, 4);
      default:
        return null;
    }
  }

  bool get isTerminal => this == ShipmentStatus.delivered;
}
