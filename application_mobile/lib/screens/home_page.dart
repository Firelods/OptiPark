import 'dart:async';

import 'package:application_mobile/screens/map_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/arrival_notifications.dart';
import '../services/auth_service.dart';
import '../services/fcm_service.dart';
import '../services/reservation_api.dart';
import 'qr_page.dart';

class HomePage extends StatefulWidget {
  final String fullName;
  final String email;

  const HomePage({super.key, required this.fullName, required this.email});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with RouteAware {
  //final classroom = TextEditingController();
  String? selectedBlock; // A or B
  bool ev = false;
  bool handicap = false;

  DocumentSnapshot? activeReservation;
  Timer? timer;
  int secondsLeft = 0;

  bool _expiredHandled = false; // ⭐ NEW — prevent double deletion

  // draggable bubble position
  double bubbleX = 20;
  double bubbleY = 500;

  StreamSubscription<DocumentSnapshot>? arrivedListener;

  String departureMode = "live";

  final Map<String, LatLng> hardcodedDepartures = {
    "Antibes": LatLng(43.58028728033885, 7.126025653325961),
    "Biot": LatLng(43.62741762070003, 7.097777049870632),
    "Cagne sur mer": LatLng(43.663202958024996, 7.15781312048672),
    "Cannes": LatLng(43.55408448412185, 7.019062041171009),
    "Mougains": LatLng(43.60276754754512, 7.007287196449653),
    "Nice": LatLng(43.70970941427251, 7.257549445772798),
    "Saint Philippe": LatLng(43.618637960538216, 7.070699546185013),
    "Valbonne": LatLng(43.641490028056815, 7.007594282969608),
    "Vallauris": LatLng(43.57712558926858, 7.056655732522315),
  };

  Future<void> _handleArrival(DocumentSnapshot doc) async {
    // Annuler le listener pour éviter les appels multiples
    arrivedListener?.cancel();
    arrivedListener = null;

    // Effacer la réservation active pour revenir à la page d'accueil
    if (mounted) {
      setState(() {
        activeReservation = null;
        secondsLeft = 0;
        _expiredHandled = false;
      });
    }

    // Afficher un message de confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ Arrivée confirmée ! Vous pouvez faire une nouvelle réservation.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _listenForArrival() {
    arrivedListener?.cancel();

    if (activeReservation == null) return;

    arrivedListener = FirebaseFirestore.instance
        .collection("reservations")
        .doc(activeReservation!.id)
        .snapshots()
        .listen((doc) async {
          if (!doc.exists) return;

          final data = doc.data() as Map<String, dynamic>;

          if (data["arrived"] == true) {
            await _handleArrival(doc);
          }
        });
  }

  @override
  void initState() {
    super.initState();

    // Initialiser FCM
    FcmService.initialize();

    Future.delayed(const Duration(milliseconds: 500), () {
      _checkReservation();
    });

    timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );

    arrivalNotificationCallback = (reservationId) async {
      final doc = await FirebaseFirestore.instance
          .collection("reservations")
          .doc(reservationId)
          .get();

      if (!doc.exists) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrPage(
            fullName: widget.fullName,
            classroom: doc["classroom"],
            ev: doc["ev"],
            handicap: doc["handicap"],
            reservedPlace: doc["reservedPlace"],
            reservationId: reservationId,
            arrivedMode: true,
          ),
        ),
      );
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkReservation();
    });
  }

  @override
  void didPopNext() {
    super.didPopNext();
    _checkReservation();
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    timer?.cancel();
    arrivedListener?.cancel();
    super.dispose();
  }

  // -----------------------------------------------------------
  Future<DocumentSnapshot?> _getActiveReservation() async {
    final user = FirebaseAuth.instance.currentUser!;
    final now = DateTime.now();

    final query = await FirebaseFirestore.instance
        .collection("reservations")
        .where("userId", isEqualTo: user.uid)
        .where("expiresAt", isGreaterThan: Timestamp.fromDate(now))
        .orderBy("expiresAt")
        .limit(1)
        .get();

    return query.docs.isEmpty ? null : query.docs.first;
  }

  Future<void> _checkReservation() async {
    activeReservation = await _getActiveReservation();
    _expiredHandled = false;
    _updateCountdown();

    arrivedListener?.cancel();
    _listenForArrival(); // ✅ ADD THIS LINE

    if (mounted) setState(() {});
  }

  // -----------------------------------------------------------
  void _updateCountdown() async {
    if (activeReservation == null) {
      secondsLeft = 0;
      if (mounted) setState(() {});
      return;
    }

    final expiry = (activeReservation!["expiresAt"] as Timestamp).toDate();
    final now = DateTime.now();

    secondsLeft = expiry.difference(now).inSeconds;

    // -------------------------------------------------------
    // ⭐ NEW FIX: When expired → update Firestore + backend
    // -------------------------------------------------------
    if (secondsLeft <= 0 && !_expiredHandled) {
      _expiredHandled = true;

      final place = activeReservation!["reservedPlace"];
      final docId = activeReservation!.id;

      // Tell backend to free the spot
      await ReservationAPI.cancelReservation(place);

      // Remove reservation doc from Firestore
      await FirebaseFirestore.instance
          .collection("reservations")
          .doc(docId)
          .delete();

      // Clear UI state
      activeReservation = null;
      secondsLeft = 0;

      if (mounted) setState(() {});
      return;
    }

    if (secondsLeft <= 0) {
      secondsLeft = 0;
      activeReservation = null;
    }

    if (mounted) setState(() {});
  }

  // -----------------------------------------------------------

  Future<void> reserve() async {
    if (activeReservation != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You already have an active reservation."),
        ),
      );
      return;
    }

    if (selectedBlock == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Choose your Block")));
      return;
    }

    LatLng? forcedDeparture;

    if (departureMode != "live") {
      forcedDeparture = hardcodedDepartures[departureMode];
    }

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MapPageScreen(
          fullName: widget.fullName,
          classroom: selectedBlock!,
          ev: ev,
          handicap: handicap,
          forcedDeparture: forcedDeparture,
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  String _formatTime(int seconds) {
    if (seconds <= 0) return "00:00";
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return "${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  // ------------------ UI THEME (light, minimal, futuristic) ------------------
  static const _pageBg = Color(0xFFF6F8FB);
  static const _cardBg = Colors.white;
  static const _border = Color(0xFFE5EAF0);
  static const _textMain = Color(0xFF0F172A);
  static const _textSub = Color(0xFF64748B);
  static const _primary = Color(0xFF4ED6C1); // close to logo palette
  static const _primaryDeep = Color(0xFF18B7A2);
  static const _chipBg = Color(0xFFF1FBF9);

  Theme _dropdownTheme(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        // background of the popup menu
        canvasColor: _cardBg,
        // remove strong dividers if any appear
        dividerColor: Colors.transparent,
        // subtle highlight when selecting
        focusColor: _chipBg,
        hoverColor: _chipBg,
      ),
      child: child,
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    String? hintText,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(color: _textSub, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _primaryDeep, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  // -----------------------------------------------------------
  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 16,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(Icons.person_outline, color: _primaryDeep),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Welcome back,",
                        style: TextStyle(
                          color: _textSub,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textMain,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Main form card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _dropdownTheme(
                    DropdownButtonFormField<String>(
                      initialValue: selectedBlock,
                      dropdownColor: _cardBg,
                      borderRadius: BorderRadius.circular(18),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _textSub,
                      ),
                      style: const TextStyle(
                        color: _textMain,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      decoration: _fieldDecoration(
                        label: "Select Block",
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: "A", child: Text("Block A")),
                        DropdownMenuItem(value: "B", child: Text("Block B")),
                      ],
                      onChanged: (value) {
                        setState(() => selectedBlock = value);
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  _dropdownTheme(
                    DropdownButtonFormField<String>(
                      initialValue: departureMode,
                      dropdownColor: _cardBg,
                      borderRadius: BorderRadius.circular(18),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _textSub,
                      ),
                      style: const TextStyle(
                        color: _textMain,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      decoration: _fieldDecoration(
                        label: "Departure",
                        prefixIcon: const Icon(Icons.route_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: "live",
                          child: Text("My Live Location"),
                        ),
                        DropdownMenuItem(
                          value: "Antibes",
                          child: Text("Antibes"),
                        ),
                        DropdownMenuItem(value: "Biot", child: Text("Biot")),
                        DropdownMenuItem(
                          value: "Cagne sur mer",
                          child: Text("Cagne sur mer"),
                        ),
                        DropdownMenuItem(
                          value: "Cannes",
                          child: Text("Cannes"),
                        ),
                        DropdownMenuItem(
                          value: "Mougains",
                          child: Text("Mougains"),
                        ),
                        DropdownMenuItem(value: "Nice", child: Text("Nice")),
                        DropdownMenuItem(
                          value: "Saint Philippe",
                          child: Text("Saint Philippe"),
                        ),
                        DropdownMenuItem(
                          value: "Valbonne",
                          child: Text("Valbonne"),
                        ),
                        DropdownMenuItem(
                          value: "Vallauris",
                          child: Text("Vallauris"),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => departureMode = value!),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Options card (modern toggles)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Options",
                          style: TextStyle(
                            color: _textMain,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: ev ? _chipBg : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _border),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: ev,
                                      onChanged: (v) => setState(() => ev = v!),
                                      activeColor: _primaryDeep,
                                    ),
                                    const Text(
                                      "EV",
                                      style: TextStyle(
                                        color: _textMain,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: handicap ? _chipBg : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: _border),
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: handicap,
                                      onChanged: (v) =>
                                          setState(() => handicap = v!),
                                      activeColor: _primaryDeep,
                                    ),
                                    const Text(
                                      "Handicap",
                                      style: TextStyle(
                                        color: _textMain,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Primary action button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: reserve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: const Color(0xFF0B0F14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "Reserve",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------------------------------------
  Widget _buildDraggableBubble() {
    // keep same logic, only restyle visuals to match the new theme
    return Positioned(
      left: bubbleX,
      top: bubbleY,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final screen = MediaQuery.of(context).size;

            bubbleX += details.delta.dx;
            bubbleY += details.delta.dy;

            const bubbleWidth = 150.0;
            const bubbleHeight = 55.0;

            final maxY = screen.height - bubbleHeight - 145.0;

            bubbleX = bubbleX
                .clamp(6.0, screen.width - bubbleWidth + 40.0)
                .toDouble();
            bubbleY = bubbleY.clamp(0.0, maxY).toDouble();
          });
        },
        onTap: () async {
          if (activeReservation == null) return;

          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => QrPage(
                fullName: widget.fullName,
                classroom: activeReservation!["classroom"],
                ev: activeReservation!["ev"],
                handicap: activeReservation!["handicap"],
                reservedPlace: activeReservation!["reservedPlace"],
                reservationId: activeReservation!.id,
              ),
            ),
          );

          // ✅ If QR cancelled → clear bubble instantly
          if (result == true) {
            activeReservation = null;
            secondsLeft = 0;
            if (mounted) setState(() {});
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 14,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _chipBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: const Icon(Icons.timer_outlined, color: _primaryDeep),
              ),
              const SizedBox(width: 10),
              Text(
                _formatTime(secondsLeft),
                style: const TextStyle(
                  color: _textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _pageBg,
        appBar: AppBar(
          backgroundColor: _pageBg,
          elevation: 0,
          surfaceTintColor: _pageBg,
          title: const Text(
            "Home",
            style: TextStyle(
              color: _textMain,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: _textMain),
              onPressed: () async {
                await AuthService.logout();
                if (!mounted) return;
                Navigator.pushReplacementNamed(context, "/");
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            _buildMainContent(),
            if (activeReservation != null) _buildDraggableBubble(),
          ],
        ),
      ),
    );
  }
}
