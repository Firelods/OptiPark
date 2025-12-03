const { Kafka } = require("kafkajs");
const Redis = require("ioredis");
const admin = require("firebase-admin");

// -----------------------------------------------------------
// CONFIG
// -----------------------------------------------------------
const KAFKA_BROKERS = process.env.KAFKA_BROKERS || "kafka:9092";
const KAFKA_GROUP_ID = process.env.KAFKA_GROUP_ID || "reservation-control";
const REDIS_HOST = process.env.REDIS_HOST || "redis";
const REDIS_PORT = parseInt(process.env.REDIS_PORT || "6379", 10);

const FIREBASE_CREDENTIALS = process.env.FIREBASE_CREDENTIALS || "/firebase/serviceAccount.json";
const RESERVATIONS_COLLECTION = "reservations";

const RAW_TOPICS = [
  "parking.nice_sophia.A",
  "parking.nice_sophia.B",
  "parking.nice_sophia.C",
];

// -----------------------------------------------------------
// INITIALISATION FIREBASE
// -----------------------------------------------------------
admin.initializeApp({
  credential: admin.credential.cert(require(FIREBASE_CREDENTIALS)),
});

const firestore = admin.firestore();

// -----------------------------------------------------------
// CLIENTS
// -----------------------------------------------------------
const kafka = new Kafka({
  clientId: "reservation-control",
  brokers: KAFKA_BROKERS.split(","),
});

const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  lazyConnect: true,
});

// -----------------------------------------------------------
// MAIN
// -----------------------------------------------------------
async function run() {
  await redis.connect();
  console.log("Redis connected.");

  const consumer = kafka.consumer({ groupId: KAFKA_GROUP_ID });
  await consumer.connect();
  await consumer.subscribe({ topics: RAW_TOPICS });

  console.log("ReservationControl Firestore POC started.");

  await consumer.run({
    eachMessage: async ({ topic, message }) => {
      let event;

      try {
        event = JSON.parse(message.value.toString());
      } catch {
        console.error("Invalid JSON:", message.value.toString());
        return;
      }

      const { parking_id, slot_id, occupied } = event;

      // Nous ne traitons que les "occupied = true"
      if (!occupied) return;

      console.log(`🔥 RAW=1 détecté sur la place ${slot_id}`);

      // 1) Requête Firestore : trouver la réservation active
      const now = Date.now();
      const snapshot = await firestore
        .collection(RESERVATIONS_COLLECTION)
        .where("reservedPlace", "==", slot_id)
        .where("expiresAt", ">", new Date(now))
        .get();

      if (snapshot.empty) {
        console.warn(`⚠ Aucune réservation valide trouvée pour ${slot_id}`);
        return;
      }

      // Normalement une seule réservation active
      const doc = snapshot.docs[0];
      const reservation = doc.data();

      const { userId, fullName, email } = reservation;

      console.log(`🎯 Réservation valide trouvée → ${fullName} (${email})`);

      // 2) Récupérer le token FCM
      const token = await redis.get(`user:${userId}:fcmToken`);

      if (!token) {
        console.warn(`⚠ Aucun token FCM pour user ${userId}`);
        return;
      }

      // 3) Envoi direct de la notification FCM
      const payload = {
        notification: {
          title: "Confirmez votre stationnement",
          body: `La place ${slot_id} que vous avez réservée a été détectée comme occupée. Est-ce vous ?`,
        },
        data: {
          action: "VERIFY_OCCUPATION",
          placeId: slot_id,
          parkingId: parking_id,
          userId: userId,
        },
        token,
      };

      try {
        await admin.messaging().send(payload);
        console.log(`📨 Notification envoyée à ${fullName} (${email})`);
      } catch (err) {
        console.error("Erreur FCM:", err);
      }
    },
  });
}

run().catch((err) => {
  console.error("Fatal ReservationControl:", err);
  process.exit(1);
});
