# OptiPark - Infrastructure Kafka pour Smart Parking

## Vue d'ensemble

OptiPark est une infrastructure événementielle basée sur Apache Kafka pour gérer les données de parkings intelligents. Le système collecte et traite les événements provenant de capteurs magnétiques installés sur les places de parking.

## Architecture

```
Capteurs Magnétiques → Kafka Topics → Schema Registry
                              ↓
                         Kafka UI (Monitoring)
```

### Services Docker

| Service | Port | Description |
|---------|------|-------------|
| Zookeeper | 2181 | Coordination du cluster Kafka |
| Kafka | 9092 | Broker de messages |
| Schema Registry | 8081 | Validation des schémas JSON |
| Kafka UI | 8080 | Interface web de monitoring |

---

## Configuration

### [topics.yaml](topics.yaml)

Définition déclarative des topics Kafka.

```yaml
topics:
  - name: parking.nice_sophia.p1.magnetic.raw
    partitions: 3
    replicationFactor: 1
```

| Topic | Partitions | Réplication | Usage |
|-------|-----------|-------------|-------|
| `parking.nice_sophia.p1.magnetic.raw` | 3 | 1 | Événements parking P1 |
| `parking.nice_sophia.p2.magnetic.raw` | 3 | 1 | Événements parking P2 |
| `parking.nice_sophia.p3.magnetic.raw` | 3 | 1 | Événements parking P3 |
| `parking-state` | 1 | 1 | État agrégé |

**Convention de nommage :** `parking.<location>.<parking_id>.magnetic.raw`

---

### [schemas/magnetic-raw-event.json](schemas/magnetic-raw-event.json)

Schéma JSON pour les événements de capteurs magnétiques.

| Champ | Type | Obligatoire | Description |
|-------|------|-------------|-------------|
| `message_id` | UUID | ✓ | Identifiant unique |
| `parking_id` | String | ✓ | Identifiant du parking |
| `slot_id` | String | ✓ | Numéro de la place |
| `sensor_id` | String | ✓ | Identifiant du capteur |
| `gateway_id` | String | ✓ | Gateway LoRaWAN/Sigfox |
| `event_type` | Enum | ✓ | `STATE_CHANGED`, `HEARTBEAT`, `BATTERY_LOW` |
| `occupied` | Boolean | ✓ | État d'occupation |
| `sent_at` | DateTime | ✓ | Timestamp ISO 8601 |
| `raw_magnetic` | Number | - | Valeur brute du champ magnétique |
| `battery_mv` | Integer | - | Batterie (millivolts) |
| `rssi_dbm` | Integer | - | Signal radio |
| `fw_version` | String | - | Version du firmware |

**Exemple :**

```json
{
  "message_id": "550e8400-e29b-41d4-a716-446655440000",
  "parking_id": "nice_sophia_p1",
  "slot_id": "A-042",
  "sensor_id": "MAG-7F3A",
  "gateway_id": "GW-SOPHIA-01",
  "event_type": "STATE_CHANGED",
  "occupied": true,
  "raw_magnetic": 245.7,
  "battery_mv": 3200,
  "rssi_dbm": -87,
  "fw_version": "2.4.1",
  "sent_at": "2025-11-18T16:42:33Z"
}
```

---

## Utilisation

### Démarrage

```bash
docker-compose up -d
docker-compose logs -f
```

### Interfaces

| Service | URL |
|---------|-----|
| Kafka UI | http://localhost:8080 |
| Schema Registry | http://localhost:8081 |
## Licence

À définir

## Contributeurs

Projet OptiPark - Polytech Nice Sophia SI5
