# Controle Reservation

Service Node.js qui détecte l'occupation d'une place réservée et envoie une notification push à l'utilisateur pour confirmer sa présence.

## Rôle dans l'architecture

Ce service surveille les événements d'occupation des places et déclenche des notifications push (FCM) aux utilisateurs ayant réservé.

```
Topics Kafka (parking.nice_sophia.A/B/C)
    ↓ Détection: occupied=true
Controle-Reservation
    ↓ Requête Firestore (réservations actives)
    ↓ Récupération FCM token
    ↓ Envoi notification push
Application Mobile (Firebase Cloud Messaging)
```

## Fonctionnalités

### 1. Détection d'occupation

Écoute les événements Kafka et détecte quand une place devient occupée:

**Topics écoutés:**
- `parking.nice_sophia.A`
- `parking.nice_sophia.B`
- `parking.nice_sophia.C`

**Déclencheur:**
```json
{
  "parking_id": "nice_sophia.A",
  "slot_id": "A-12",
  "occupied": true,
  "sent_at": "2026-01-13T10:00:00Z"
}
```

Le service ne réagit que si `occupied === true`.

### 2. Vérification de réservation

Interroge Firestore pour trouver une réservation active sur cette place:

**Collection Firestore**: `reservations`

**Requête:**
```javascript
firestore
  .collection("reservations")
  .where("reservedPlace", "==", slot_id)
  .where("expiresAt", ">", Date.now())
  .get()
```

**Document attendu:**
```json
{
  "userId": "user123",
  "fullName": "Jean Dupont",
  "email": "jean@example.com",
  "reservedPlace": "A-12",
  "parkingId": "A",
  "expiresAt": "2026-01-13T11:00:00Z",
  "createdAt": "2026-01-13T09:30:00Z"
}
```

### 3. Récupération du token FCM

Récupère le token Firebase Cloud Messaging de l'utilisateur:

**Collection Firestore**: `users`

**Document:**
```json
{
  "userId": "user123",
  "email": "jean@example.com",
  "fcmToken": "fZj3k2...",
  "fullName": "Jean Dupont"
}
```

### 4. Envoi de notification push

Envoie une notification FCM à l'utilisateur:

**Payload:**
```json
{
  "notification": {
    "title": "Confirmez votre stationnement",
    "body": "La place A-12 que vous avez réservée a été détectée comme occupée. Est-ce vous ?"
  },
  "data": {
    "action": "VERIFY_OCCUPATION",
    "placeId": "A-12",
    "parkingId": "nice_sophia.A",
    "userId": "user123"
  },
  "token": "fZj3k2..."
}
```

L'utilisateur peut alors:
- Confirmer que c'est lui → Libération de la réservation
- Ignorer → Timeout automatique ou annulation

## Configuration

### Variables d'environnement

| Variable | Description | Défaut |
|----------|-------------|--------|
| `KAFKA_BROKERS` | Liste des brokers Kafka | `kafka:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `controle-reservation` |
| `REDIS_HOST` | Hôte Redis | `redis` |
| `REDIS_PORT` | Port Redis | `6379` |
| `FIREBASE_CREDENTIALS` | Chemin vers serviceAccount.json | `/firebase/serviceAccount.json` |
| `FIREBASE_CREDENTIALS_JSON` | JSON credentials (base64 ou string) | - |

### Configuration Firebase

#### Option 1: Fichier serviceAccount.json (Recommandé pour Docker)

1. Téléchargez le fichier depuis la console Firebase
2. Placez-le dans `controle-reservation/firebase/serviceAccount.json`

Structure du fichier:
```json
{
  "type": "service_account",
  "project_id": "optipark-xxxxx",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "firebase-adminsdk-xxx@optipark.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

#### Option 2: Variable d'environnement

```bash
# Base64 encodé
export FIREBASE_CREDENTIALS_JSON=$(cat serviceAccount.json | base64)

# Ou JSON string direct
export FIREBASE_CREDENTIALS_JSON='{"type":"service_account",...}'
```

## Installation locale

### Prérequis

- Node.js 20+
- Compte Firebase avec Firestore et FCM activés
- Accès à Kafka et Redis

### Installation

```bash
cd controle-reservation
npm install
```

### Configuration

```bash
export KAFKA_BROKERS=localhost:9092
export REDIS_HOST=localhost
export REDIS_PORT=6379
export FIREBASE_CREDENTIALS=./firebase/serviceAccount.json
```

### Démarrage

```bash
npm start
```

## Avec Docker

Le service est inclus dans le `docker-compose.yml` principal:

```yaml
controle-reservation:
  build: ./controle-reservation
  depends_on:
    kafka:
      condition: service_healthy
    redis:
      condition: service_healthy
  environment:
    KAFKA_BROKERS: kafka:9092
    REDIS_HOST: redis
    FIREBASE_CREDENTIALS: /firebase/serviceAccount.json
  volumes:
    - ./controle-reservation/firebase:/firebase:ro
```

```bash
# Démarrer le service
docker-compose up -d controle-reservation

# Voir les logs
docker-compose logs -f controle-reservation
```

## Logs

Le service affiche des logs détaillés pour chaque étape:

```
🔥 RAW=1 détecté sur la place A-12
🎯 Réservation valide trouvée → Jean Dupont (jean@example.com)
📨 Notification envoyée à Jean Dupont (jean@example.com)
```

Ou en cas de problème:
```
⚠ Aucune réservation valide trouvée pour A-12
⚠ Utilisateur user123 introuvable dans Firestore
⚠ Aucun token FCM pour user user123
```

## Test

### 1. Créer une réservation dans Firestore

Via la console Firebase ou un script:

```javascript
// Collection: reservations
{
  "userId": "test_user",
  "fullName": "Test User",
  "email": "test@example.com",
  "reservedPlace": "A-12",
  "parkingId": "A",
  "expiresAt": new Date(Date.now() + 3600000), // +1h
  "createdAt": new Date()
}

// Collection: users
{
  "fcmToken": "YOUR_FCM_TOKEN_FROM_APP"
}
```

### 2. Simuler une occupation

```bash
# Publier via MQTT
docker-compose exec mosquitto mosquitto_pub \
  -t 'parking/nice_sophia.A/status' \
  -m '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":true,"sent_at":"2026-01-13T10:00:00Z"}'
```

### 3. Vérifier les logs

```bash
docker-compose logs -f controle-reservation
```

Vous devriez voir:
```
🔥 RAW=1 détecté sur la place A-12
🎯 Réservation valide trouvée → Test User (test@example.com)
📨 Notification envoyée à Test User (test@example.com)
```

### 4. Vérifier sur l'app mobile

La notification devrait apparaître sur l'application mobile avec:
- Titre: "Confirmez votre stationnement"
- Message: "La place A-12 que vous avez réservée a été détectée comme occupée. Est-ce vous ?"

## Dépendances

```json
{
  "firebase-admin": "^12.0.0",
  "ioredis": "^5.3.2",
  "kafkajs": "^2.2.4"
}
```

## Structure Firestore

### Collection: `reservations`

Documents des réservations actives:

```
reservations/
  {reservationId}/
    userId: string
    fullName: string
    email: string
    reservedPlace: string (ex: "A-12")
    parkingId: string (ex: "A")
    expiresAt: timestamp
    createdAt: timestamp
```

### Collection: `users`

Documents des utilisateurs:

```
users/
  {userId}/
    email: string
    fullName: string
    fcmToken: string
    createdAt: timestamp
```

## Gestion des erreurs

### Pas de réservation trouvée

Si aucune réservation active n'est trouvée pour la place:
```
⚠ Aucune réservation valide trouvée pour A-12
```

**Causes possibles:**
- Place non réservée
- Réservation expirée
- Mauvais slot_id

### Utilisateur introuvable

```
⚠ Utilisateur user123 introuvable dans Firestore
```

**Solution:** Vérifier que le document existe dans `users/{userId}`

### Pas de token FCM

```
⚠ Aucun token FCM pour user user123
```

**Solution:** L'utilisateur doit se connecter à l'app mobile qui enregistrera son token

### Erreur FCM

```
Erreur FCM: Error: Registration token is invalid
```

**Solutions:**
- Token expiré → L'utilisateur doit relancer l'app
- Token révoqué → L'utilisateur doit se reconnecter
- Token invalide → Vérifier le format

## Reconnexion automatique

Le service implémente une stratégie de reconnexion robuste:

```javascript
retry: {
  initialRetryTime: 300,
  retries: 10,
  maxRetryTime: 30000,
  multiplier: 2
}
```

- Première tentative: 300ms
- Deuxième: 600ms
- Troisième: 1200ms
- ...
- Maximum: 30s
- Total: 10 tentatives

## Performance

- **Traitement asynchrone**: Ne bloque pas la consommation Kafka
- **Requêtes Firestore optimisées**: Index sur `reservedPlace` et `expiresAt`
- **Pas de polling**: Notification instantanée via FCM

## Monitoring

### Via les logs

```bash
docker-compose logs -f controle-reservation
```

### Via Kafka UI

- URL: http://localhost:8080
- Consumer Group: `controle-reservation`
- Voir le lag et les offsets

### Via Firebase Console

- Logs des envois FCM
- Statistiques de livraison
- Erreurs de tokens

## Troubleshooting

### Le service ne démarre pas

```bash
# Vérifier les credentials Firebase
docker-compose exec controle-reservation ls -la /firebase/

# Vérifier les logs d'erreur
docker-compose logs controle-reservation
```

### Les notifications ne sont pas envoyées

1. **Vérifier la réservation dans Firestore**:
   - Le document existe ?
   - `expiresAt` est dans le futur ?
   - `reservedPlace` correspond au `slot_id` ?

2. **Vérifier le token FCM**:
   - Le document user existe ?
   - Le champ `fcmToken` est présent ?
   - Le token n'est pas expiré ?

3. **Vérifier les logs**:
   ```bash
   docker-compose logs -f controle-reservation
   ```

### Erreur: "Firebase credentials not configured"

```bash
# Vérifier le volume Docker
docker-compose exec controle-reservation cat /firebase/serviceAccount.json

# Ou reconstruire l'image
docker-compose build controle-reservation
docker-compose up -d controle-reservation
```

## Architecture technique

### Consumer Group

- **Group ID**: `controle-reservation`
- **Stratégie**: Consommation parallèle des 3 topics
- **Commit**: Automatique après traitement

### Workflow

1. **Message Kafka reçu** (`occupied: true`)
2. **Query Firestore** (réservation active)
3. **Si trouvée**: Query Firestore (token FCM)
4. **Si token présent**: Envoi FCM
5. **Commit offset** Kafka

### Idempotence

Le service n'est pas idempotent: chaque message `occupied: true` déclenchera une notification si les conditions sont remplies.

**Recommandation**: Implémenter un cache/debounce si nécessaire pour éviter les notifications en double.

## Intégration

### Services en amont

- **Parking-Redis-Writer**: Met à jour Redis
- **MQTT-Kafka Bridge**: Produit les événements
- **ESP32**: Source des données

### Services externes

- **Firebase Firestore**: Base de données
- **Firebase Cloud Messaging**: Notifications push

### Services en aval

- **Application Mobile**: Reçoit les notifications

## Évolutions possibles

1. **Debouncing**: Éviter les notifications multiples
2. **Timeout automatique**: Annuler si pas de confirmation après X minutes
3. **Statistiques**: Tracker les taux de confirmation
4. **Multi-tenancy**: Support de plusieurs projets Firebase
5. **Webhooks**: Alternative à FCM pour les apps web

## Licence

Projet OptiPark - Polytech Nice Sophia SI5
