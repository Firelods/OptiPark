import 'dart:async';
import 'dart:convert';

import 'package:application_mobile/screens/home_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../services/reservation_api.dart';
import 'qr_page.dart';

class MapPageScreen extends StatefulWidget {
  final String fullName;
  final String classroom;
  final bool ev;
  final bool handicap;
  final bool viewOnly;
  final String? reservationId;
  final LatLng? forcedDeparture;

  const MapPageScreen({
    super.key,
    required this.fullName,
    required this.classroom,
    required this.ev,
    required this.handicap,
    this.viewOnly = false,
    this.reservationId,
    this.forcedDeparture,
  });

  @override
  State<MapPageScreen> createState() => _MapPageScreenState();
}

class _MapPageScreenState extends State<MapPageScreen> {
  final mapController = MapController();

  bool followUser = true;
  StreamSubscription<Position>? positionStream;

  LatLng? userPos;
  List<LatLng> routePoints = [];
  double? etaMinutes;
  int? finalEta; // rounded +15 minutes
  bool loading = false;

  final dest = const LatLng(
    43.61547830858652,
    7.071821115345416,
  ); //Location in Nice

  // Reservation tracking
  Timer? countdownTimer;
  int secondsLeft = 0;
  String? reservationId;
  String? reservedPlace;

  // Bubble position
  double bubbleX = 20;
  double bubbleY = 500;

  // ---------------- THEME TOKENS (match IP/Home light futuristic) ----------------
  static const pageBg = Color(0xFFF7FAFC);
  static const cardBg = Colors.white;
  static const line = Color(0x1F0B7E86);

  static const teal = Color(0xFF0B7E86);
  static const tealDeep = Color(0xFF086E75);

  static const textMain = Color(0xFF0B1220);
  static const textSub = Color(0xFF64748B);

  static const shadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 10)),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  // --------------------------------------------------------------
  Future<void> _init() async {
    await _getUserLocation();
    if (userPos != null) {
      await _getRoute();
    }
  }

  // --------------------------------------------------------------
  Future<void> _getUserLocation() async {
    if (widget.forcedDeparture != null) {
      userPos = widget.forcedDeparture;
      setState(() {});
      return;
    }

    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    final pos = await Geolocator.getCurrentPosition();
    userPos = LatLng(pos.latitude, pos.longitude);
    setState(() {});

    positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
          ),
        ).listen((Position newPos) {
          userPos = LatLng(newPos.latitude, newPos.longitude);

          if (followUser) {
            mapController.move(userPos!, mapController.camera.zoom);
          }

          setState(() {});
        });
  }

  // --------------------------------------------------------------
  Future<void> _getRoute() async {
    if (userPos == null) return;

    setState(() => loading = true);

    final url =
        "https://router.project-osrm.org/route/v1/driving/"
        "${userPos!.longitude},${userPos!.latitude};"
        "${dest.longitude},${dest.latitude}"
        "?overview=full&geometries=geojson";

    final res = await http.get(Uri.parse(url));
    final data = jsonDecode(res.body);

    final route = data["routes"][0];
    final durationSeconds = route["duration"];
    etaMinutes = durationSeconds / 60;

    finalEta = etaMinutes!.ceil() + 15;

    final coords = route["geometry"]["coordinates"] as List;
    routePoints = coords
        .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
        .toList();

    loading = false;
    setState(() {});

    // When ETA ready → create reservation
    if (!widget.viewOnly) {
      await _createReservation();
    }
  }

  // --------------------------------------------------------------
  Future<void> _createReservation() async {
    if (reservationId != null) return;
    if (finalEta == null) return;

    final user = FirebaseAuth.instance.currentUser!;
    final now = DateTime.now();

    // ✅ 0) Guard: user already has an active reservation → reuse it
    final existing = await FirebaseFirestore.instance
        .collection("reservations")
        .where("userId", isEqualTo: user.uid)
        .where("expiresAt", isGreaterThan: Timestamp.fromDate(now))
        .orderBy("expiresAt")
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;

      reservationId = doc.id;
      reservedPlace = doc["reservedPlace"];

      final expiry = (doc["expiresAt"] as Timestamp).toDate();
      secondsLeft = expiry.difference(now).inSeconds;
      if (secondsLeft < 0) secondsLeft = 0;

      _startCountdown();
      if (mounted) setState(() {});
      return;
    }

    // ✅ 1) No active reservation → create a new one
    final expiresAt = now.add(Duration(minutes: finalEta!));

    // 1) backend logic (redis)
    final rfid = "RFID-${now.millisecondsSinceEpoch}";
    final backend = await ReservationAPI.reserveSpot(
      block: widget.classroom,
      rfid: rfid,
      ev: widget.ev,
      handicap: widget.handicap,
    );

    if (backend.containsKey("error")) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No spot available")));
      return;
    }

    reservedPlace = backend["spot_id"];

    // 2) Firestore
    final docRef = await FirebaseFirestore.instance
        .collection("reservations")
        .add({
          "userId": user.uid,
          "fullName": widget.fullName,
          "email": user.email,
          "classroom": widget.classroom,
          "ev": widget.ev,
          "handicap": widget.handicap,
          "reservedPlace": reservedPlace,
          "timestamp": Timestamp.fromDate(now),
          "expiresAt": Timestamp.fromDate(expiresAt),
          "qrData": "OPTIPARK:$reservedPlace:${widget.fullName}",
          "arrived": false,
        });

    reservationId = docRef.id;

    // 3) Start countdown
    secondsLeft = finalEta! * 60;
    _startCountdown();
  }

  // --------------------------------------------------------------
  void _startCountdown() {
    countdownTimer?.cancel();

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (secondsLeft <= 0) {
        secondsLeft = 0;
        setState(() {});
        await _expireReservation();
        return;
      }

      setState(() {
        secondsLeft--;
      });
    });
  }

  // --------------------------------------------------------------
  Future<void> _expireReservation() async {
    countdownTimer?.cancel();

    if (reservedPlace != null) {
      await ReservationAPI.cancelReservation(reservedPlace!);
    }

    if (reservationId != null) {
      await FirebaseFirestore.instance
          .collection("reservations")
          .doc(reservationId)
          .delete();
    }

    if (mounted) Navigator.pop(context, true);
  }

  // --------------------------------------------------------------
  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return "${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  // --------------------------------------------------------------
  @override
  void dispose() {
    countdownTimer?.cancel();
    positionStream?.cancel();
    super.dispose();
  }

  // ---------------- UI helpers (new styling only) ----------------
  Widget _glassButton({
    required IconData icon,
    required VoidCallback onTap,
    required String heroTag,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: cardBg.withOpacity(0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: line),
              boxShadow: shadow,
            ),
            child: Icon(icon, color: tealDeep),
          ),
        ),
      ),
    );
  }

  Widget _topStatusCard() {
    return Positioned(
      top: 12,
      left: 14,
      right: 14,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cardBg.withOpacity(0.94),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: line),
            boxShadow: shadow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: teal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.route, color: tealDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Route to parking",
                      style: TextStyle(
                        color: textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.viewOnly
                          ? "View mode"
                          : (finalEta == null
                                ? "Computing ETA…"
                                : "ETA: ~$finalEta min"),
                      style: const TextStyle(
                        color: textSub,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------
  Widget _buildBubble() {
    if (reservationId == null) return const SizedBox();

    return Positioned(
      left: bubbleX,
      top: bubbleY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final screen = MediaQuery.of(context).size;

            bubbleX += details.delta.dx;
            bubbleY += details.delta.dy;

            const bw = 172.0;
            const bh = 58.0;

            final maxY = screen.height - bh - 145;

            bubbleX = bubbleX.clamp(8.0, screen.width - bw - 8.0);
            bubbleY = bubbleY.clamp(0.0, maxY);
          });
        },
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QrPage(
                fullName: widget.fullName,
                classroom: widget.classroom,
                ev: widget.ev,
                handicap: widget.handicap,
                reservedPlace: reservedPlace!,
                reservationId: reservationId!,
              ),
            ),
          );

          if (result == true && mounted) {
            Navigator.pop(context, true); // return to HOME
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cardBg.withOpacity(0.94),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: line),
            boxShadow: shadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: teal.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(Icons.timer, color: tealDeep, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                _fmt(secondsLeft),
                style: const TextStyle(
                  color: textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        if (widget.viewOnly) {
          Navigator.pop(context);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeWrapper()),
            (route) => false,
          );
        }
      },
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          surfaceTintColor: pageBg,
          title: const Text(
            "Route to Parking",
            style: TextStyle(
              color: textMain,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          iconTheme: const IconThemeData(color: textMain),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (widget.viewOnly) {
                Navigator.pop(context);
              } else {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeWrapper()),
                  (route) => false,
                );
              }
            },
          ),
        ),
        body: userPos == null
            ? const Center(
                child: Text(
                  "Waiting for location…",
                  style: TextStyle(color: textSub, fontWeight: FontWeight.w600),
                ),
              )
            : Stack(
                children: [
                  // Map
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    child: FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: userPos!,
                        initialZoom: 14,
                        onPointerDown: (tapPosition, point) {
                          followUser = false;
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              "https://api.maptiler.com/maps/hybrid/{z}/{x}/{y}.png?key=8zdQ3OeFHCVbTGaUN6Vh",
                          userAgentPackageName: 'com.example.app',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: userPos!,
                              width: 46,
                              height: 46,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned(
                                    top: 5,
                                    // white background circle
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  // person pin
                                  const Icon(
                                    Icons.person_pin_circle,
                                    size: 44,
                                    color: Color(0xFF0B7E86), // tealDeep
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: dest,
                              width: 44,
                              height: 44,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: cardBg.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: line),
                                  boxShadow: shadow,
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  size: 30,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (routePoints.isNotEmpty)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: routePoints,
                                strokeWidth: 5,
                                color: tealDeep.withOpacity(0.90),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // top status card
                  _topStatusCard(),

                  // right controls (glass)
                  Positioned(
                    right: 12,
                    bottom: 126,
                    child: Column(
                      children: [
                        _glassButton(
                          heroTag: "zoomIn",
                          icon: Icons.add,
                          onTap: () {
                            mapController.move(
                              mapController.camera.center,
                              mapController.camera.zoom + 1,
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _glassButton(
                          heroTag: "zoomOut",
                          icon: Icons.remove,
                          onTap: () {
                            mapController.move(
                              mapController.camera.center,
                              mapController.camera.zoom - 1,
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        _glassButton(
                          heroTag: "recenter",
                          icon: Icons.my_location,
                          onTap: () {
                            if (userPos != null) {
                              followUser = true;
                              mapController.move(
                                userPos!,
                                mapController.camera.zoom,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // timer bubble
                  _buildBubble(),
                ],
              ),
      ),
    );
  }
}
