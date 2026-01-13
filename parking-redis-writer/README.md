# Parking Redis Writer

Service Node.js qui consomme les événements Kafka des parkings et met à jour l'état en temps réel dans Redis.

## Rôle dans l'architecture

Ce service fait le pont entre le flux d'événements Kafka et la base de données Redis qui stocke l'état actuel des places de parking.

```
Topics Kafka (parking.nice_sophia.A/B/C, rain.global)
    ↓ Consommation
Parking-Redis-Writer
    ↓ Écriture
Redis (états des places en temps réel)
```

## Fonctionnalités

### 1. Gestion des événements de parking

Consomme les messages des topics Kafka et met à jour Redis:

**Topics écoutés:**
- `parking.nice_sophia.A`
- `parking.nice_sophia.B`
- `parking.nice_sophia.C`

**Structure du message:**
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

**Actions Redis:**
- Met à jour le hash `spot:{slot_id}` avec le nouveau statut
- Gère le set `parking:{parking_id}:free` (ajoute si libre, retire si occupé)

### 2. Gestion de la météo

Consomme les événements météo et stocke l'état de la pluie:

**Topic écouté:**
- `rain.global`

**Structure du message:**
```json
{
  "sensor_id": "WEATHER_SENSOR_01",
  "rain_pct": 35
}
```

**Action Redis:**
- Met à jour la clé `weather:rain` avec 0 (pas de pluie) ou 1 (pluie)
- Seuil: 20% (si rain_pct >= 20, alors pluie = 1)

## Structure Redis

### Hash: `spot:{slot_id}`

Contient toutes les informations d'une place:

```redis
HGETALL spot:A-12
1) "parking_id"
2) "A"
3) "status"
4) "0"           # 0=libre, 1=occupé, 2=réservé
5) "type"
6) "NORMAL"      # NORMAL, COVERED, PMR, EV
7) "battery_mv"
8) "3500"
9) "sent_at"
10) "2026-01-13T10:00:00Z"
11) "received_at"
12) "2026-01-13T10:00:01Z"
```

### Set: `parking:{parking_id}:free`

Ensemble des places libres d'un parking:

```redis
SMEMBERS parking:A:free
1) "A-1"
2) "A-5"
3) "A-12"
...
```

### Key: `weather:rain`

État de la pluie (0 ou 1):

```redis
GET weather:rain
"1"
```

## Configuration

Variables d'environnement (configurées dans docker-compose.yml):

| Variable | Description | Défaut |
|----------|-------------|--------|
| `KAFKA_BROKERS` | Liste des brokers Kafka | `kafka:9092` |
| `KAFKA_GROUP_ID` | Consumer group ID | `parking-redis-writer` |
| `REDIS_HOST` | Hôte Redis | `redis` |
| `REDIS_PORT` | Port Redis | `6379` |

## Installation locale

### Prérequis

- Node.js 20+
- Accès à Kafka et Redis

### Installation

```bash
cd parking-redis-writer
npm install
```

### Configuration

```bash
export KAFKA_BROKERS=localhost:9092
export REDIS_HOST=localhost
export REDIS_PORT=6379
```

### Démarrage

```bash
npm start
```

## Avec Docker

Le service est inclus dans le `docker-compose.yml` principal:

```bash
# Démarrer uniquement ce service (avec dépendances)
docker-compose up -d parking-redis-writer

# Voir les logs
docker-compose logs -f parking-redis-writer
```

## Logs

Le service affiche des logs pour chaque message traité:

```
Redis updated: topic=parking.nice_sophia.A parking_id=nice_sophia.A short=A slot_id=A-12 status=0
Redis updated: weather:rain=1 (rain_pct=35, sensor_id=WEATHER_SENSOR_01)
```

## Test

### 1. Publier un événement via MQTT (via le bridge)

```bash
docker-compose exec mosquitto mosquitto_pub \
  -t 'parking/nice_sophia.A/status' \
  -m '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false,"battery_mv":3500,"sent_at":"2026-01-13T10:00:00Z"}'
```

### 2. Vérifier dans Redis

```bash
# Vérifier la place A-12
docker-compose exec redis redis-cli HGETALL spot:A-12

# Vérifier les places libres du parking A
docker-compose exec redis redis-cli SMEMBERS parking:A:free
```

### 3. Produire directement dans Kafka

```bash
# Produire un message de test
echo '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false}' | \
  docker-compose exec -T kafka kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic parking.nice_sophia.A
```

### 4. Tester la météo

```bash
# Publier un événement pluie
echo '{"sensor_id":"WEATHER_01","rain_pct":50}' | \
  docker-compose exec -T kafka kafka-console-producer \
  --bootstrap-server localhost:9092 \
  --topic rain.global

# Vérifier dans Redis
docker-compose exec redis redis-cli GET weather:rain
# Devrait retourner: "1"
```

## Dépendances

```json
{
  "kafkajs": "^2.2.4",
  "ioredis": "^5.4.1"
}
```

## Gestion des erreurs

- **Message JSON invalide**: Ignoré avec log d'erreur
- **Champs requis manquants**: Message ignoré avec warning
- **Erreur Redis**: Log d'erreur, le service continue
- **Perte de connexion Kafka**: Reconnexion automatique avec retry exponentiel

## Performance

- **Auto-commit**: Activé pour de meilleures performances
- **Traitement asynchrone**: Chaque message est traité de manière non-bloquante
- **Retry policy**: Reconnexion automatique avec backoff exponentiel (max 30s)

## Monitoring

### Via les logs

```bash
docker-compose logs -f parking-redis-writer
```

### Via Kafka UI

- URL: http://localhost:8080
- Consumer Group: `parking-redis-writer`
- Voir le lag et les offsets

### Via Redis Insight

- URL: http://localhost:8001
- Explorer les clés mises à jour en temps réel

## Troubleshooting

### Le service ne démarre pas

```bash
# Vérifier les logs
docker-compose logs parking-redis-writer

# Vérifier que Kafka et Redis sont démarrés
docker-compose ps kafka redis
```

### Les messages ne sont pas consommés

```bash
# Vérifier les topics
docker-compose exec kafka kafka-topics --list --bootstrap-server localhost:9092

# Vérifier le consumer group
docker-compose exec kafka kafka-consumer-groups \
  --bootstrap-server localhost:9092 \
  --describe --group parking-redis-writer
```

### Redis n'est pas mis à jour

```bash
# Vérifier la connexion Redis
docker-compose exec parking-redis-writer sh -c "nc -zv redis 6379"

# Vérifier les logs du service
docker-compose logs -f parking-redis-writer
```

## Architecture technique

### Consumer Group

Le service utilise un consumer group Kafka pour:
- Permettre le scaling horizontal (plusieurs instances)
- Garantir le traitement de chaque message une seule fois
- Gérer automatiquement la répartition des partitions

### Stratégie de traitement

1. **Réception du message** depuis Kafka
2. **Parsing JSON** avec validation
3. **Extraction du parking_id court** (A, B, ou C)
4. **Mise à jour atomique Redis**:
   - Modification du hash `spot:{slot_id}`
   - Mise à jour du set `parking:{parking_id}:free`
5. **Commit automatique** de l'offset

### Gestion de l'état

Le service est **stateless**: toutes les données sont dans Redis, ce qui permet:
- Redémarrage sans perte de données
- Scaling horizontal simple
- Résilience aux pannes

## Intégration

### Services en amont

- **MQTT-Kafka Bridge**: Produit les messages dans Kafka
- **ESP32**: Source originale des données

### Services en aval

- **Reservation API**: Lit l'état depuis Redis
- **Controle-Reservation**: Lit l'état depuis Redis
- **Application Web/Mobile**: Via l'API Reservation

## Licence

Projet OptiPark - Polytech Nice Sophia SI5
