import 'package:shared_preferences/shared_preferences.dart';

class IpConfig {
  static const _key = "backend_ip";

  static Future<void> saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, ip);
  }

  static Future<String?> getIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<bool> hasIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }
}
