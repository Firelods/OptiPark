# mqtt-kafka-bridge

Simple Node.js bridge that subscribes to `parking/+/status` and produces messages into Kafka topics named `parking.<parking_id>` (so the `parking-redis-writer` consumes them).

Usage:
1. Build and start with `docker compose up -d` from the repo root (services: `mosquitto`, `mqtt-kafka-bridge`, etc.).
2. Bridge reads env vars (see `docker-compose.yml`):
   - `MQTT_URL` (default `mqtt://mosquitto:1883`)
   - `KAFKA_BROKERS` (default `kafka:9092`)
   - `KAFKA_TOPIC` (fallback default `parking.events` — used only if `parking_id` cannot be inferred)

MQTT topic and payload (for ESP32) — recommended format
- MQTT topic pattern: `parking/<parking_id>/status`
  - Example: `parking/nice_sophia.A/status`
- Payload (JSON):
  {
    "parking_id": "nice_sophia.A",
    "slot_id": "A-12",
    "occupied": false,
    "battery_mv": 3000,
    "sent_at": "2026-01-08T18:00:00Z"
  }

How it maps:
- The bridge will parse JSON payload and, if `parking_id` exists, publish the message to Kafka topic `parking.<parking_id>` (e.g., `parking.nice_sophia.A`).
- If payload is not JSON, the bridge falls back to extracting the `parking_id` from the MQTT topic level (the second level after `parking/`), e.g., `parking/nice_sophia.A/status` → produces to `parking.nice_sophia.A`.

Test publish (from host inside the mosquitto container — recommended):

```bash
# Publish a sample event (occupied=false will trigger Redis update)
docker compose exec mosquitto mosquitto_pub -t 'parking/nice_sophia.A/status' -m '{"parking_id":"nice_sophia.A","slot_id":"A-12","occupied":false,"battery_mv":3500,"sent_at":"2026-01-08T18:00:00Z"}'
```

Verify Kafka message:

```bash
docker compose exec kafka kafka-console-consumer --bootstrap-server localhost:9092 --topic parking.nice_sophia.A --from-beginning --max-messages 1
```

Verify Redis update (parking-redis-writer behavior):
- parking set: `parking:<parking_id>:spots` (should contain `slot_id`)
- spot hash: `spot:<slot_id>` contains fields: `parking_id`, `status` (0=free, 1=occupied), optional `battery_mv`, `sent_at`, `received_at`

Examples:

```bash
# Check set membership
docker compose exec redis redis-cli SMEMBERS parking:nice_sophia.A:spots

# Check spot hash
docker compose exec redis redis-cli HGETALL spot:A-12
```

Notes:
- The `parking-redis-writer` ignores events when `occupied === true` (it logs that occupied places are not updated to Redis). To test Redis writes, publish with `"occupied": false`.
- To reduce a KafkaJS warning, the environment variable `KAFKAJS_NO_PARTITIONER_WARNING=1` is set in the compose file for the bridge.
