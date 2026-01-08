# Kafka Connect (MQTT Source)

This folder contains an example connector config `mqtt-source-connector.json` that will create an MQTT Source connector to read from Mosquitto and write to Kafka topic `parking.events`.

To create the connector after the stack is up:

```bash
curl -X POST -H "Content-Type: application/json" --data @kafka-connect/mqtt-source-connector.json http://localhost:8083/connectors
```

If you used a Kafka Connect image that does not include the MQTT connector plugin, you can either:
- Use an image that bundles the MQTT connector (note: I attempted `streamthoughts/kafka-connect-mqtt` but that image could not be pulled), or
- Build a custom Kafka Connect image that installs the MQTT connector plugin at build time and exposes the Connect REST API. Example approaches:
  - Build-from-base: extend `confluentinc/cp-kafka-connect` and install the MQTT connector via `confluent-hub` or by downloading the plugin jar into the plugin path during image build.
  - Manual install: download the connector plugin and place it under `kafka-connect/plugins/` on the host, then mount `./kafka-connect/plugins:/usr/share/java` (or the plugin path) into a standard Connect image.

If you want, I can implement a `Dockerfile` that installs the connector automatically (recommended). Which do you prefer?
