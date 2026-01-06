import 'dart:async';

import 'package:application_mobile/screens/home_page.dart';
import 'package:application_mobile/screens/map_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/reservation_api.dart';

class QrPage extends StatefulWidget {
  final String fullName;
  final String classroom;
  final bool ev;
  final bool handicap;
  final String reservedPlace;
  final String reservationId;
  final bool arrivedMode;

  const QrPage({
    super.key,
    required this.fullName,
    required this.classroom,
    required this.ev,
    required this.handicap,
    required this.reservedPlace,
    required this.reservationId,
    this.arrivedMode = false,
  });

  @override
  State<QrPage> createState() => _QrPageState();
}

class _QrPageState extends State<QrPage> {
  Timer? timer;
  int secondsLeft = 0;
  bool _loading = true;

  late DocumentSnapshot _reservation;

  bool _arrivalDialogShown = false;

  // ---- Theme tokens (match your light, minimal, futuristic style)
  static const pageBg = Color(0xFFF6F8FB);
  static const cardBg = Colors.white;
  static const line = Color(0xFFE6EAF0);
  static const textMain = Color(0xFF0F172A);
  static const textSub = Color(0xFF64748B);
  static const teal = Color(0xFF0B7E86);
  static const tealDeep = Color(0xFF086E75);
  static const danger = Color(0xFFE11D48);

  @override
  void initState() {
    super.initState();
    _loadReservationAndStart();

    if (widget.arrivedMode && !_arrivalDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _arrivalDialogShown = true;
        _showArrivalConfirmation();
      });
    }
  }

  Future<void> _showArrivalConfirmation() async {
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Arrival Confirmation",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text("Have you reached the reserved place?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tealDeep),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _confirmReservation();
    }
  }

  // -------------------------------------------------------------
  Future<void> _confirmReservation() async {
    try {
      // ✅ Appel API → status = 1 dans Redis
      await ReservationAPI.confirmReservation(widget.reservedPlace);

      // ✅ Stop le compteur
      timer?.cancel();

      if (!mounted) return;

      // ✅ Retour vers Home (sans supprimer Firestore)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            fullName: widget.fullName,
            email: FirebaseAuth.instance.currentUser!.email ?? "",
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Confirmation failed")));
    }
  }

  // -------------------------------------------------------------
  Future<void> _loadReservationAndStart() async {
    try {
      _reservation = await FirebaseFirestore.instance
          .collection("reservations")
          .doc(widget.reservationId)
          .get();

      if (!_reservation.exists) {
        if (mounted) Navigator.pop(context);
        return;
      }

      _updateCountdown();
      timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _updateCountdown(),
      );

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("ERROR: $e");
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => HomePage(
              fullName: widget.fullName,
              email: FirebaseAuth.instance.currentUser!.email ?? "",
            ),
          ),
          (route) => false,
        );
      }
    }
  }

  // -------------------------------------------------------------
  void _updateCountdown() async {
    final expiry = (_reservation["expiresAt"] as Timestamp).toDate();
    final now = DateTime.now();

    secondsLeft = expiry.difference(now).inSeconds;
    if (secondsLeft < 0) secondsLeft = 0;

    if (mounted) setState(() {});

    if (secondsLeft == 0) {
      timer?.cancel();
      await _autoExpireReservation();
      if (mounted) Navigator.pop(context, true);
    }
  }

  // -------------------------------------------------------------
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  String fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return "${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}";
  }

  // -------------------------------------------------------------
  Future<void> _autoExpireReservation() async {
    await ReservationAPI.cancelReservation(widget.reservedPlace);

    await FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .delete();
  }

  Future<void> _cancelReservation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Cancel reservation",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          "Are you sure you want to cancel this reservation?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("No"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await ReservationAPI.cancelReservation(widget.reservedPlace);

    await FirebaseFirestore.instance
        .collection("reservations")
        .doc(widget.reservationId)
        .delete();

    timer?.cancel();

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          fullName: widget.fullName,
          email: FirebaseAuth.instance.currentUser!.email ?? "",
        ),
      ),
      (route) => false,
    );
  }

  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final qrData = "OPTIPARK:${widget.reservedPlace}:${widget.fullName}";
    final expired = secondsLeft <= 0;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, false);
        return false;
      },
      child: Scaffold(
        backgroundColor: pageBg,
        appBar: AppBar(
          backgroundColor: pageBg,
          elevation: 0,
          surfaceTintColor: pageBg,
          title: const Text(
            "QR Code",
            style: TextStyle(fontWeight: FontWeight.w800, color: textMain),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: textMain),
            onPressed: () => Navigator.pop(context, false),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Header card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
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
                          color: teal.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: teal.withOpacity(0.20)),
                        ),
                        child: const Icon(Icons.qr_code_2, color: tealDeep),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Hello, ${widget.fullName}",
                              style: const TextStyle(
                                color: textMain,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expired
                                  ? "Reservation expired"
                                  : "Cooldown: ${fmt(secondsLeft)}",
                              style: TextStyle(
                                color: expired ? danger : tealDeep,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: expired
                              ? danger.withOpacity(0.10)
                              : teal.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: expired
                                ? danger.withOpacity(0.25)
                                : teal.withOpacity(0.25),
                          ),
                        ),
                        child: Text(
                          expired ? "EXPIRED" : "ACTIVE",
                          style: TextStyle(
                            color: expired ? danger : tealDeep,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // QR card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 16,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: line),
                        ),
                        child: QrImageView(data: qrData, size: 220),
                      ),
                      const SizedBox(height: 14),

                      // Place label
                      const Text(
                        "Reserved place",
                        style: TextStyle(
                          color: textSub,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.reservedPlace,
                        style: const TextStyle(
                          color: textMain,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Info chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoChip(
                            icon: Icons.school_outlined,
                            label: "Classroom: ${widget.classroom}",
                          ),
                          _InfoChip(
                            icon: Icons.tune,
                            label: "EV",
                            enabled: widget.ev,
                          ),
                          _InfoChip(
                            icon: Icons.accessible_outlined,
                            label: "Handicap",
                            enabled: widget.handicap,
                          ),
                          if (!widget.ev && !widget.handicap)
                            const _InfoChip(
                              icon: Icons.do_not_disturb_alt_outlined,
                              label: "No options",
                              enabled: true,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Actions card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.map_outlined),
                          label: const Text(
                            "View Map",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: tealDeep,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MapPageScreen(
                                  fullName: widget.fullName,
                                  classroom: widget.classroom,
                                  ev: widget.ev,
                                  handicap: widget.handicap,
                                  viewOnly: true,
                                  reservationId: widget.reservationId,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textMain,
                            side: const BorderSide(color: line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            "Back",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: danger,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _cancelReservation,
                          child: const Text(
                            "Cancel Reservation",
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  static const line = Color(0xFFE6EAF0);
  static const teal = Color(0xFF0B7E86);
  static const tealDeep = Color(0xFF086E75);
  static const textMain = Color(0xFF0F172A);
  static const textSub = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final bg = enabled ? teal.withOpacity(0.08) : const Color(0xFFF1F5F9);
    final border = enabled ? teal.withOpacity(0.18) : line;
    final iconColor = enabled ? tealDeep : textSub;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: enabled ? textMain : textSub,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
