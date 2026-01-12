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
  // RESERVE SPOT (updated to backend contract: block_id + user_type)
  // ============================================================
  static Future<Map<String, dynamic>> reserveSpot({
    required String block,
    required bool ev,
    required bool handicap,
  }) async {
    final baseUrl = await _baseUrl();
    final url = Uri.parse("$baseUrl/reserve");

    final String userType = handicap ? "PMR" : (ev ? "EV" : "NORMAL");

    final body = {"block_id": block, "user_type": userType};

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      // Helpful error surface (backend may return {"error": "..."} )
      final msg = response.body.isNotEmpty ? response.body : "No body";
      throw Exception("Reservation failed (${response.statusCode}): $msg");
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

  // ============================================================
  // CONFIRM RESERVATION
  // ============================================================
  static Future<bool> confirmReservation(String spotId) async {
    final baseUrl = await _baseUrl();
    final url = Uri.parse("$baseUrl/confirm-reservation");

    final body = {"spot_id": spotId};

    final response = await http.post(
      url,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception("Confirm failed (${response.statusCode})");
    }
  }
}
