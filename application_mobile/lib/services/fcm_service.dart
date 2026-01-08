import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import 'ip_config.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  // Set pour tracker les notifications déjà traitées et éviter les doublons
  static final Set<String> _processedNotifications = {};

  /// Initialise FCM et demande les permissions
  static Future<void> initialize() async {
    // Demander la permission pour les notifications
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ FCM: Permission accordée');

      // Récupérer le token FCM
      String? token = await _messaging.getToken();
      if (token != null) {
        print('📱 FCM Token: $token');
        await _saveFcmTokenToServer(token);
      }

      // Écouter les changements de token
      _messaging.onTokenRefresh.listen(_saveFcmTokenToServer);

      // Gérer les notifications en foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Gérer les notifications quand l'app est en arrière-plan mais ouverte
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Gérer les notifications qui ont ouvert l'app depuis un état fermé
      RemoteMessage? initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } else {
      print('⚠️ FCM: Permission refusée');
    }
  }

  /// Sauvegarde le token FCM dans Firestore
  static Future<void> _saveFcmTokenToServer(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('⚠️ FCM: Utilisateur non connecté, impossible de sauvegarder le token');
        return;
      }

      // Sauvegarder le token dans Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ FCM Token sauvegardé dans Firestore');
    } catch (e) {
      print('❌ Erreur lors de la sauvegarde du token FCM: $e');
    }
  }

  /// Gère les notifications reçues en foreground
  static void _handleForegroundMessage(RemoteMessage message) {
    print('🔔 Notification reçue en foreground');
    print('Titre: ${message.notification?.title}');
    print('Corps: ${message.notification?.body}');
    print('Data: ${message.data}');

    if (message.data['action'] == 'VERIFY_OCCUPATION') {
      final placeId = message.data['placeId'] as String?;
      final parkingId = message.data['parkingId'] as String?;

      if (placeId != null && parkingId != null) {
        // Créer un ID unique pour cette notification
        final notificationId = '${placeId}_${parkingId}_${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}';

        // Vérifier si cette notification a déjà été traitée
        if (_processedNotifications.contains(notificationId)) {
          print('⚠️ Notification déjà traitée, ignorée');
          return;
        }

        // Marquer comme traitée
        _processedNotifications.add(notificationId);

        // Nettoyer les anciennes notifications (garder seulement les 10 dernières)
        if (_processedNotifications.length > 10) {
          _processedNotifications.remove(_processedNotifications.first);
        }

        final context = navigatorKey.currentContext;
        if (context != null) {
          showArrivalConfirmationDialog(context, placeId, parkingId);
        } else {
          print('⚠️ Context non disponible pour afficher le dialog');
        }
      }
    }
  }

  /// Gère le tap sur une notification
  static void _handleNotificationTap(RemoteMessage message) {
    print('👆 Notification tapée');
    print('Data: ${message.data}');

    if (message.data['action'] == 'VERIFY_OCCUPATION') {
      final placeId = message.data['placeId'] as String?;
      final parkingId = message.data['parkingId'] as String?;

      if (placeId != null && parkingId != null) {
        // Créer un ID unique pour cette notification
        final notificationId = '${placeId}_${parkingId}_${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}';

        // Vérifier si cette notification a déjà été traitée
        if (_processedNotifications.contains(notificationId)) {
          print('⚠️ Notification déjà traitée, ignorée');
          return;
        }

        // Marquer comme traitée
        _processedNotifications.add(notificationId);

        // Nettoyer les anciennes notifications (garder seulement les 10 dernières)
        if (_processedNotifications.length > 10) {
          _processedNotifications.remove(_processedNotifications.first);
        }

        final context = navigatorKey.currentContext;
        if (context != null) {
          showArrivalConfirmationDialog(context, placeId, parkingId);
        } else {
          print('⚠️ Context non disponible pour afficher le dialog');
        }
      }
    }
  }

  /// Affiche une dialog de confirmation d'arrivée
  static void showArrivalConfirmationDialog(
    BuildContext context,
    String placeId,
    String parkingId,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation d\'arrivée'),
        content: Text(
          'Êtes-vous bien arrivé sur la place $placeId ?',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _confirmArrival(context, placeId, false);
            },
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _confirmArrival(context, placeId, true);
            },
            child: const Text('Oui'),
          ),
        ],
      ),
    );
  }

  /// Confirme l'arrivée sur la place via l'API
  static Future<void> _confirmArrival(
    BuildContext context,
    String placeId,
    bool confirmed,
  ) async {
    try {
      final baseUrl = await IpConfig.getIp();
      if (baseUrl?.isEmpty ?? true) {
        _showSnackbar(context, 'URL de base non configurée');
        return;
      }

      if (confirmed) {
        // Appeler l'API pour confirmer la réservation
        final url = Uri.parse('http://$baseUrl:8000/confirm-reservation');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'spot_id': placeId}),
        );

        if (response.statusCode == 200) {
          // Supprimer la réservation de Firestore
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final snapshot = await FirebaseFirestore.instance
                .collection('reservations')
                .where('reservedPlace', isEqualTo: placeId)
                .where('userId', isEqualTo: user.uid)
                .where('expiresAt', isGreaterThan: DateTime.now())
                .limit(1)
                .get();

            if (snapshot.docs.isNotEmpty) {
              await snapshot.docs.first.reference.delete();
            }
          }

          _showSnackbar(context, '✅ Arrivée confirmée ! Réservation terminée.');

          // Retourner à la page d'accueil
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _showSnackbar(context, '⚠️ Erreur lors de la confirmation');
        }
      } else {
        // L'utilisateur n'est pas arrivé, on peut annuler la réservation
        final url = Uri.parse('http://$baseUrl:8000/cancel-reservation');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'spot_id': placeId}),
        );

        if (response.statusCode == 200) {
          _showSnackbar(context, 'Réservation annulée');

          // Retourner à la page d'accueil
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          _showSnackbar(context, '⚠️ Erreur lors de l\'annulation');
        }
      }
    } catch (e) {
      print('❌ Erreur lors de la confirmation: $e');
      _showSnackbar(context, '❌ Erreur de connexion');
    }
  }

  /// Affiche un snackbar
  static void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
