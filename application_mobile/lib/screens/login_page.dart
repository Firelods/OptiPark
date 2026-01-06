import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool hidePwd = true;
  String? error;
  bool loading = false;

  void doLogin() async {
    setState(() {
      error = null;
      loading = true;
    });

    try {
      final user = await AuthService.login(
        email.text.trim(),
        password.text.trim(),
      );

      if (user == null) {
        setState(() {
          error = "Invalid login credentials.";
          loading = false;
        });
        return;
      }

      String extractNameFromEmail(String email) {
        final username = email.split('@').first;
        final parts = username.split('.');

        final capitalized = parts.map((p) {
          if (p.isEmpty) return "";
          final clean = p.replaceAll(RegExp(r'[^a-zA-Z]'), "");
          if (clean.isEmpty) return "";
          return clean[0].toUpperCase() + clean.substring(1).toLowerCase();
        }).toList();

        return capitalized.join(" ").trim();
      }

      final uid = user.uid;
      final fcmToken = await FirebaseMessaging.instance.getToken();

      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "fullName": extractNameFromEmail(user.email ?? email.text.trim()),
        "email": user.email ?? email.text.trim(),
        "fcmToken": fcmToken,
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            fullName: user.displayName ?? "User",
            email: user.email ?? "",
          ),
        ),
      );
    } catch (_) {
      setState(() => error = "Invalid login credentials.");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // tuned to resemble the screenshot (light page, teal accents, card, separators)
    const pageBg = Color(0xFFF4F4F4);
    const teal = Color(0xFF007Fa5);
    const tealDeep = Color(0xFF007Fa5);
    const hint = Color(0xFF6B7280);
    const textMain = Color(0xFF111827);
    const cardBg = Color(0xFFF7F7EA);

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Column(
                      children: [
                        Image.asset("assets/icon/logo.png", width: 220),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // ───────────────────────── MAIN OUTER CARD
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1A000000),
                          blurRadius: 18,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // main card (service)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 14,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // left “colored rectangles” replacement: logo in dark square
                              Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2F3B45),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Image.asset(
                                    "assets/icon/icone.png",
                                    width: 72,
                                    height: 72,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      "You will log in to the\nservice:",
                                      style: TextStyle(
                                        color: textMain,
                                        fontSize: 14,
                                        height: 1.2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      "OptiPark",
                                      style: TextStyle(
                                        color: textMain,
                                        fontSize: 26,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // “Enter Username & Password” line
                        Row(
                          children: const [
                            Icon(Icons.shield_outlined, color: textMain),
                            SizedBox(width: 10),
                            Text(
                              "Enter Username & Password",
                              style: TextStyle(
                                color: textMain,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // username field (teal outline like sample)
                        const Padding(
                          padding: EdgeInsets.only(left: 6, bottom: 6),
                          child: Text(
                            "Username:",
                            style: TextStyle(
                              color: teal,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: teal, width: 2),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextField(
                                controller: email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // password label (gray like sample)
                        const Padding(
                          padding: EdgeInsets.only(left: 6, bottom: 6),
                          child: Text(
                            "Password:",
                            style: TextStyle(
                              color: hint,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        // password box + teal eye block (very close to screenshot)
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFD1D5DB)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: TextField(
                                    controller: password,
                                    obscureText: hidePwd,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 76,
                                height: double.infinity,
                                child: Material(
                                  color: teal,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(6),
                                    bottomRight: Radius.circular(6),
                                  ),
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => hidePwd = !hidePwd),
                                    child: Icon(
                                      hidePwd
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        // LOGIN button (small left button like sample)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 130,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: loading ? null : doLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tealDeep,
                                foregroundColor: Colors.white,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "LOGIN",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // divider line
                        Container(height: 1, color: const Color(0xFFD9D9D9)),

                        const SizedBox(height: 14),

                        // “Forgot your password?” + bullets like the screenshot
                        const Text(
                          "Forgot your password?",
                          style: TextStyle(
                            color: textMain,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 10),

                        _BulletLink(
                          text: "You are a student",
                          color: tealDeep,
                          onTap: () {},
                        ),
                        const SizedBox(height: 8),
                        _BulletLink(
                          text: "You are staff member",
                          color: tealDeep,
                          onTap: () {},
                        ),

                        const SizedBox(height: 16),

                        const Text(
                          "For security reasons, please log out and\n"
                          "exit your web browser when you are\n"
                          "done accessing services that require\n"
                          "authentication!",
                          style: TextStyle(
                            color: textMain,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),

                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulletLink extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onTap;

  const _BulletLink({
    required this.text,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 6),
        const Text("•  ", style: TextStyle(fontSize: 18)),
        GestureDetector(
          onTap: onTap,
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 16,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
