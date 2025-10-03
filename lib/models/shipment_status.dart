enum ShipmentStatus { waiting, accepted, delivering, delivered }

extension ShipmentStatusX on ShipmentStatus {
  String get code => switch (this) {
    ShipmentStatus.waiting    => '1',
    ShipmentStatus.accepted   => '2',
    ShipmentStatus.delivering => '3',
    ShipmentStatus.delivered  => '4',
  };

  static ShipmentStatus fromCode(String code) => switch (code) {
    '1' => ShipmentStatus.waiting,
    '2' => ShipmentStatus.accepted,
    '3' => ShipmentStatus.delivering,
    '4' => ShipmentStatus.delivered,
    _   => ShipmentStatus.waiting,
  };
}
