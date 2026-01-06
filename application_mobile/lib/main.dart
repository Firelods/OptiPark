import 'package:application_mobile/screens/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'services/arrival_notifications.dart';
import 'screens/login_page.dart';

import 'services/ip_config.dart';
import 'screens/ip_prompt_page.dart';

final RouteObserver<ModalRoute> routeObserver = RouteObserver<ModalRoute>();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// ✅ BACKGROUND FCM HANDLER (REQUIRED)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔵 FCM BACKGROUND: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await initArrivalNotifications();

  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Reservation App",
      navigatorKey: navigatorKey,
      navigatorObservers: [routeObserver],
      theme: ThemeData(useMaterial3: true, primarySwatch: Colors.blue),

      home: FutureBuilder<bool>(
        future: IpConfig.hasIp(),
        builder: (context, ipSnapshot) {
          if (!ipSnapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 🔴 IP NOT SET → SHOW PROMPT
          if (!ipSnapshot.data!) {
            return const IpPromptPage();
          }

          // 🟢 IP SET → NORMAL APP FLOW
          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final user = snapshot.data!;

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection("users")
                      .doc(user.uid)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                      FirebaseFirestore.instance
                          .collection("users")
                          .doc(user.uid)
                          .set({
                            "fullName": user.displayName ?? "User",
                            "email": user.email ?? "",
                          }, SetOptions(merge: true));

                      return HomePage(
                        fullName: user.displayName ?? "User",
                        email: user.email ?? "",
                      );
                    }

                    final data =
                        userSnapshot.data!.data() as Map<String, dynamic>?;

                    return HomePage(
                      fullName: data?["fullName"] ?? "User",
                      email: data?["email"] ?? "",
                    );
                  },
                );
              }

              return const LoginPage();
            },
          );
        },
      ),
    );
  }
}
