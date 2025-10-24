import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

class ThaiGeocoder {
  ThaiGeocoder({this.googleApiKey});
  final String? googleApiKey;

  Future<({double? lat, double? lng})> geocode(String address) async {
    Future<({double? lat, double? lng})> _system(String q) async {
      try {
        final list = await locationFromAddress(q, localeIdentifier: 'th_TH');
        if (list.isNotEmpty) {
          final loc = list.first;
          return (lat: loc.latitude, lng: loc.longitude);
        }
      } catch (e) {
        debugPrint('[geo] system geocode error: $e');
      }
      return (lat: null, lng: null);
    }

    final tries = <String>[
      address,
      '$address ประเทศไทย',
      '$address, ประเทศไทย',
      '$address, Thailand',
    ];
    for (final t in tries) {
      final r = await _system(t);
      if (r.lat != null) return r;
    }

    if (googleApiKey != null && googleApiKey!.isNotEmpty) {
      final url = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': address,
        'region': 'th',
        'language': 'th',
        'key': googleApiKey!,
      });

      try {
        final res = await http.get(url);
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final status = (data['status'] as String?) ?? 'UNKNOWN';
          if (status == 'OK') {
            final results = (data['results'] as List);
            if (results.isNotEmpty) {
              final loc = results.first['geometry']['location'];
              final lat = (loc['lat'] as num).toDouble();
              final lng = (loc['lng'] as num).toDouble();
              return (lat: lat, lng: lng);
            }
          } else {
            debugPrint(
                '[geo] google status=$status msg=${data['error_message']}');
          }
        } else {
          debugPrint('[geo] http=${res.statusCode} body=${res.body}');
        }
      } catch (e) {
        debugPrint('[geo] google geocode error: $e');
      }
    }

    return (lat: null, lng: null);
  }
}
