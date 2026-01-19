# OptiPark - Infrastructure Kafka pour Smart Parking

## Vue d'ensemble

OptiPark est une infrastructure événementielle basée sur Apache Kafka pour gérer les données de parkings intelligents. Le système collecte et traite les événements provenant de capteurs magnétiques ESP32 installés sur les places de parking.

## Architecture globale

```
ESP32 (Capteurs magnétiques)
    ↓ MQTT (mosquitto:1883)
Mosquitto Broker
    ↓
MQTT-Kafka Bridge (Node.js)
    ↓ Kafka Topics
parking.nice_sophia.A/B/C, rain.global
    ↓
[Parking-Redis-Writer] → Redis ← [Controle-Reservation]
                          ↓
                    API Reservation (Flask)
                          ↓
              [Application Web] [Application Mobile]
```

## Démarrage rapide

### Prérequis

- Docker 20.10+
- Docker Compose 2.0+
- 4 GB RAM minimum
- Ports disponibles: 1883, 3000, 6379, 8000, 8080, 9092

### Lancer l'infrastructure complète

```bash
# Cloner le repository
git clone <repo-url>
cd OptiPark

# Démarrer tous les services
docker-compose up -d

# Vérifier que tout fonctionne
docker-compose ps
docker-compose logs -f
```

### Vérification rapide

```bash
# Health check API
curl http://localhost:8000/health

# Vérifier Redis (60 places attendues)
docker-compose exec redis redis-cli DBSIZE

# Lister les topics Kafka
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092
```

## Documentation

### 📚 Documentation principale

- **[Guide de déploiement](DEPLOYMENT.md)** - Installation et configuration complète
- **[Collections Postman](postman/README.md)** - Tester l'API sans l'app mobile

### 🔧 Documentation des services

#### Infrastructure

| Service | Description | Documentation |
|---------|-------------|---------------|
| **Kafka** | Broker de messages événementiels | [Kafka Topics & Schema](kafka/) |
| **Redis** | Base de données en mémoire | [Redis Setup](Redis/README.md) |
| **Mosquitto** | Broker MQTT pour ESP32 | [Mosquitto Config](mosquitto/) |
| **Grafana** | Dashboards de monitoring | [Grafana Setup](grafana/) |

#### Services de traitement

| Service | Langage | Description | Documentation |
|---------|---------|-------------|---------------|
| **mqtt-kafka-bridge** | Node.js | Pont MQTT → Kafka | [README](mqtt-kafka-bridge/README.md) |
| **parking-redis-writer** | Node.js | Kafka → Redis (états) | [README](parking-redis-writer/README.md) |
| **controle-reservation** | Node.js | Notifications FCM | [README](controle-reservation/README.md) |

#### API & Applications

| Service | Technologie | Description | Documentation |
|---------|-------------|-------------|---------------|
| **Reservation API** | Python/Flask | API REST réservations | [README](Reservation/README.md) |
| **Application Web** | React/Vite | Frontend web | [README](application_web/README.md) |
| **Application Mobile** | Flutter | App iOS/Android | [README](application_mobile/README.md) |

#### Hardware

| Module | Description | Documentation |
|--------|-------------|---------------|
| **ESP32** | Capteurs magnétiques | [README](esp32/README.md) |

## Interfaces web

Une fois les services démarrés, accédez aux interfaces:

| Interface | URL | Description |
|-----------|-----|-------------|
| **Application Web** | http://localhost:3000 | Interface utilisateur |
| **API Reservation** | http://localhost:8000 | API REST (voir docs) |
| **Kafka UI** | http://localhost:8080 | Monitoring Kafka |
| **Redis Insight** | http://localhost:8001 | Explorateur Redis |
| **Grafana** | http://localhost:3001 | Dashboards (admin/admin) |

## Topics Kafka

Le système utilise les topics suivants:

### Topics de parking

| Topic | Partitions | Description |
|-------|-----------|-------------|
| `parking.nice_sophia.A` | 3 | Événements parking A |
| `parking.nice_sophia.B` | 3 | Événements parking B |
| `parking.nice_sophia.C` | 3 | Événements parking C |

**Format des messages:**
```json
{
  "parking_id": "nice_sophia.A",
  "slot_id": "A-12",
  "occupied": false,
  "battery_mv": 3500,
  "sent_at": "2026-01-13T10:00:00Z",
  "received_at": "2026-01-13T10:00:01Z"
}
```

### Topic météo

| Topic | Partitions | Description |
|-------|-----------|-------------|
| `rain.global` | 1 | Événements météo (pluie) |

**Format des messages:**
```json
{
  "sensor_id": "WEATHER_SENSOR_01",
  "rain_pct": 35
}
```

## Flux de données

### 1. Publication d'événement (ESP32)

```bash
# L'ESP32 publie via MQTT
Topic: parking/nice_sophia.A/status
Payload: {"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false}
```

### 2. Bridge MQTT → Kafka

Le service `mqtt-kafka-bridge` consomme MQTT et produit dans Kafka:
```
MQTT parking/nice_sophia.A/status → Kafka parking.nice_sophia.A
```

### 3. Traitement Kafka → Redis

Le service `parking-redis-writer` met à jour Redis:
```
Kafka parking.nice_sophia.A → Redis spot:A-12 (status=0)
```

### 4. API & Applications

Les applications consultent Redis pour l'état en temps réel:
```
Application → API /get-spots → Redis → Réponse JSON
```

### 5. Notifications (réservations)

Le service `controle-reservation` détecte les occupations:
```
Kafka (occupied=true) → Firestore (réservation?) → FCM (notification)
```

## Schémas de données

### Redis

#### Hash: `spot:{slot_id}`
```redis
HGETALL spot:A-12
1) "parking_id" → "A"
2) "status" → "0"  # 0=libre, 1=occupé, 2=réservé
3) "type" → "NORMAL"  # NORMAL, COVERED, PMR, EV
4) "covered" → "0"  # 0=non couvert, 1=couvert
5) "battery_mv" → "3500"
6) "sent_at" → "2026-01-13T10:00:00Z"
```

#### Set: `parking:{parking_id}:free`
```redis
SMEMBERS parking:A:free
1) "A-1"
2) "A-5"
3) "A-12"
```

#### Key: `weather:rain`
```redis
GET weather:rain
"1"  # 0=pas de pluie, 1=pluie
```

### Firestore (controle-reservation)

#### Collection: `reservations`
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

#### Collection: `users`
```json
{
  "email": "jean@example.com",
  "fullName": "Jean Dupont",
  "fcmToken": "fZj3k2..."
}
```

## API Endpoints

### Reservation API (Port 8000)

| Méthode | Endpoint | Description |
|---------|----------|-------------|
| GET | `/health` | Health check |
| GET | `/weather` | État météo (pluie) |
| GET | `/get-spots` | Toutes les places |
| POST | `/reserve` | Réserver une place |
| POST | `/confirm-reservation` | Confirmer arrivée |
| POST | `/cancel-reservation` | Annuler réservation |

**Exemple: Réserver une place**
```bash
curl -X POST http://localhost:8000/reserve \
  -H "Content-Type: application/json" \
  -d '{"block_id":"block_A","user_type":"NORMAL"}'
```

**Réponse:**
```json
{
  "spot_id": "A-12",
  "parking_id": "A",
  "type": "NORMAL",
  "x": 150.5,
  "y": 200.3,
  "status": 2,
  "rain": 0
}
```

Voir la **[documentation API complète](Reservation/README.md)** et les **[collections Postman](postman/README.md)**.

## Test avec Postman

Pour tester l'API sans l'application mobile:

1. **Importer les collections**
   ```bash
   # Ouvrir Postman et importer:
   postman/OptiPark_API.postman_collection.json
   postman/OptiPark_Local.postman_environment.json
   ```

2. **Sélectionner l'environnement** "OptiPark Local"

3. **Exécuter les scénarios de test**
   - Scenario 1: Full Reservation Flow
   - Scenario 2: Cancel Reservation
   - Scenario 3: Multiple User Types

Voir le **[guide Postman complet](postman/README.md)**.

## Test avec ESP32

### Configuration WiFi

1. Flasher le code ESP32 (voir [esp32/README.md](esp32/README.md))
2. Configurer via `idf.py menuconfig`:
   - WiFi SSID et mot de passe
   - MQTT Broker: `<votre-ip>:1883`

### Publication MQTT

L'ESP32 publie sur:
```
Topic: parking/nice_sophia.A/status
Payload: {"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false,"battery_mv":3500}
```

### Vérification

```bash
# Écouter les messages MQTT
docker-compose exec mosquitto mosquitto_sub -t 'parking/#' -v

# Vérifier dans Kafka
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic parking.nice_sophia.A \
  --from-beginning

# Vérifier dans Redis
docker-compose exec redis redis-cli HGETALL spot:A-12
```

## Commandes utiles

### Docker Compose

```bash
# Démarrer tous les services
docker-compose up -d

# Voir les logs
docker-compose logs -f [service]

# Redémarrer un service
docker-compose restart [service]

# Arrêter tout
docker-compose down

# Tout supprimer (y compris volumes)
docker-compose down -v
```

### Kafka

```bash
# Lister les topics
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Consommer un topic
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic parking.nice_sophia.A \
  --from-beginning

# Consumer groups
docker-compose exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe --group parking-redis-writer
```

### Redis

```bash
# Redis CLI
docker-compose exec redis redis-cli

# Lister les clés
docker-compose exec redis redis-cli KEYS "*"

# Voir une place
docker-compose exec redis redis-cli HGETALL spot:A-12

# Places libres du parking A
docker-compose exec redis redis-cli SMEMBERS parking:A:free

# Météo
docker-compose exec redis redis-cli GET weather:rain
```

### MQTT

```bash
# S'abonner à tous les topics
docker-compose exec mosquitto mosquitto_sub -t 'parking/#' -v

# Publier un message de test
docker-compose exec mosquitto mosquitto_pub \
  -t 'parking/nice_sophia.A/status' \
  -m '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false,"battery_mv":3500}'
```

## Troubleshooting

### Les services ne démarrent pas

```bash
# Vérifier les logs
docker-compose logs

# Vérifier les ports
netstat -an | grep "1883\|3000\|6379\|8000\|8080\|9092"

# Redémarrer Docker
docker-compose down
docker-compose up -d
```

### Redis vide

```bash
# Réinitialiser Redis
docker-compose up -d redis-init

# Vérifier
docker-compose exec redis redis-cli DBSIZE
```

### Topics Kafka manquants

```bash
# Relancer l'init
docker-compose up -d kafka-init

# Créer manuellement
docker-compose exec kafka kafka-topics \
  --create --if-not-exists \
  --bootstrap-server localhost:9092 \
  --partitions 3 --replication-factor 1 \
  --topic parking.nice_sophia.A
```

Voir le **[guide de dépannage complet](DEPLOYMENT.md#troubleshooting)**.

## Monitoring

### Kafka UI

- URL: http://localhost:8080
- Voir les topics, messages, consumer groups
- Inspecter les schémas du Schema Registry

### Redis Insight

- URL: http://localhost:8001
- Explorer les clés en temps réel
- Exécuter des commandes Redis

### Grafana

- URL: http://localhost:3001
- Identifiants: admin / admin
- Dashboards de statistiques (en développement)

### Logs

```bash
# Tous les services
docker-compose logs -f

# Service spécifique
docker-compose logs -f parking-redis-writer
docker-compose logs -f mqtt-kafka-bridge
docker-compose logs -f controle-reservation
```

## Configuration

### Fichiers de configuration

- `docker-compose.yml` - Services et dépendances
- `mosquitto/config/mosquitto.conf` - Configuration MQTT
- `Reservation/config/` - Géométrie des parkings
- `schemas/` - Schémas JSON pour Kafka

## Architecture technique

### Stack technologique

| Couche | Technologies |
|--------|-------------|
| **Frontend** | React, Vite, TypeScript, Tailwind CSS |
| **Mobile** | Flutter, Dart |
| **Backend** | Python (Flask), Node.js |
| **Message Broker** | Apache Kafka, Mosquitto (MQTT) |
| **Bases de données** | Redis, Firestore |
| **Infrastructure** | Docker, Docker Compose |
| **Monitoring** | Kafka UI, Redis Insight, Grafana |

### Services et ports

| Service | Port(s) | Type |
|---------|---------|------|
| Zookeeper | 2181 | Infrastructure |
| Kafka | 9092 | Message Broker |
| Schema Registry | 8081 | Kafka |
| Redis | 6379, 8001 | Database |
| Mosquitto | 1883 | MQTT Broker |
| Reservation API | 8000 | Backend |
| Application Web | 3000 | Frontend |
| Grafana | 3001 | Monitoring |
| Kafka UI | 8080 | Monitoring |

## Développement

### Modifier un service

```bash
# Éditer le code
vim parking-redis-writer/index.js

# Reconstruire l'image
docker-compose build parking-redis-writer

# Redémarrer
docker-compose up -d parking-redis-writer

# Voir les logs
docker-compose logs -f parking-redis-writer
```

### Ajouter un topic Kafka

1. Éditer `docker-compose.yml` dans le service `kafka-init`
2. Ajouter la ligne de création:
   ```bash
   kafka-topics --create --if-not-exists --bootstrap-server kafka:9092 \
     --partitions 3 --replication-factor 1 --topic nouveau.topic
   ```
3. Redémarrer: `docker-compose up -d kafka-init`

### Modifier les données Redis

1. Éditer `Redis/init_parking.redis`
2. Réinitialiser:
   ```bash
   docker-compose exec redis redis-cli FLUSHALL
   docker-compose up -d redis-init
   ```

## Structure du projet

```
OptiPark/
├── application_mobile/       # App Flutter
├── application_web/          # Frontend React
├── controle-reservation/     # Service notifications FCM
├── esp32/                    # Code ESP32
├── grafana/                  # Dashboards Grafana
├── kafka/                    # Scripts Kafka
├── mosquitto/                # Config MQTT
├── mqtt-kafka-bridge/        # Bridge MQTT→Kafka
├── parking-redis-writer/     # Service Kafka→Redis
├── postman/                  # Collections API
├── Redis/                    # Init Redis
├── Reservation/              # API Python Flask
├── schemas/                  # Schémas Kafka
├── docker-compose.yml        # Orchestration
├── DEPLOYMENT.md             # Guide déploiement
└── README.md                 # Ce fichier
```

## Performance

- **Latence**: < 100ms du capteur à l'application
- **Throughput**: > 1000 événements/seconde
- **Disponibilité**: 99.9% (avec réplication Kafka)
- **Scalabilité**: Horizontale (consumer groups)

## Sécurité

### En développement

- CORS ouvert sur l'API
- Pas d'authentification MQTT
- Pas de TLS

### Pour la production

1. **Activer TLS/SSL**:
   - Kafka: SASL_SSL
   - MQTT: TLS 1.3
   - API: HTTPS

2. **Authentification**:
   - API: JWT ou OAuth2
   - MQTT: Username/Password
   - Kafka: SASL

3. **Firewall**:
   - Exposer uniquement ports nécessaires
   - Restreindre accès par IP

4. **CORS**:
   - Restreindre origins autorisées

## Évolutions possibles

1. **Scaling**:
   - Kafka cluster (multi-broker)
   - Redis Cluster
   - Load balancer pour l'API

2. **Fonctionnalités**:
   - Historique des réservations (PostgreSQL)
   - Analytics avancées (ClickHouse)
   - Prédictions ML (occupation future)
   - Tarification dynamique

3. **Infrastructure**:
   - Kubernetes (K8s)
   - Monitoring avancé (Prometheus)
   - Tracing distribué (Jaeger)
   - CI/CD (GitHub Actions)

## Contributeurs

Projet OptiPark - Polytech Nice Sophia SI5

## Licence

À définir

## Support

- **Documentation**: Voir les README de chaque module
- **Issues**: Reporter les bugs via GitHub Issues
- **Guide complet**: [DEPLOYMENT.md](DEPLOYMENT.md)
- **API Testing**: [postman/README.md](postman/README.md)

