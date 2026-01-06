import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ip_config.dart';

class ReservationAPI {
  static Future<String> _baseUrl() async {
    final ip = await IpConfig.getIp();
    if (ip == null || ip.isEmpty) {
      throw Exception("Backend IP not configured");
    }
    return "http://$ip:8000";
  }

  // ============================================================
  // RESERVE SPOT
  // ============================================================
  static Future<Map<String, dynamic>> reserveSpot({
    required String block,
    required String rfid,
    required bool ev,
    required bool handicap,
  }) async {
    final baseUrl = await _baseUrl();
    final url = Uri.parse("$baseUrl/reserve");

    final body = {
      "block_id": block,
      "rfid_tag": rfid,
      "ev": ev,
      "handicap": handicap,
    };

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Reservation failed (${response.statusCode})");
    }
  }

  // ============================================================
  // CANCEL RESERVATION
  // ============================================================
  static Future<bool> cancelReservation(String spotId) async {
    final baseUrl = await _baseUrl();
    final url = Uri.parse("$baseUrl/cancel-reservation");

    final body = {"spot_id": spotId};

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception("Cancel failed (${response.statusCode})");
    }
  }
}
