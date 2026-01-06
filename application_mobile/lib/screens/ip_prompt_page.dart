import 'package:application_mobile/screens/login_page.dart';
import 'package:flutter/material.dart';
import '../services/ip_config.dart';

class IpPromptPage extends StatefulWidget {
  const IpPromptPage({super.key});

  @override
  State<IpPromptPage> createState() => _IpPromptPageState();
}

class _IpPromptPageState extends State<IpPromptPage> {
  final controller = TextEditingController();
  String? error;

  Future<void> _save() async {
    final ip = controller.text.trim();

    if (ip.isEmpty || !ip.contains(".")) {
      setState(() => error = "Enter a valid IP address");
      return;
    }

    await IpConfig.saveIp(ip);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginPage(), // or HomePage if already logged in
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🎨 Light futuristic palette (logo-aligned)
    const bg = Color(0xFFF4F7FA);
    const primary = Color(0xFF4ED6C1);
    const accent = Color(0xFF2BB7A6);
    const textMain = Color(0xFF0B3C3A);
    const textSub = Color(0xFF6E8A92);
    const fieldBg = Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              // 🔷 Logo
              Image.asset("assets/icon/app_icon.png", width: 90),

              const SizedBox(height: 28),

              const Text(
                "Backend Configuration",
                style: TextStyle(
                  color: textMain,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Enter the backend IP address to continue",
                textAlign: TextAlign.center,
                style: TextStyle(color: textSub, fontSize: 14),
              ),

              const SizedBox(height: 36),

              // 🔷 Input
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: textMain),
                decoration: InputDecoration(
                  labelText: "IP Address",
                  labelStyle: const TextStyle(color: textSub),
                  errorText: error,
                  filled: true,
                  fillColor: fieldBg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: primary.withOpacity(0.35)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: accent, width: 1.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // 🔷 Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Save & Continue",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
