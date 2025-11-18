#!/bin/bash
set -e  # Arrêt en cas d'erreur

BOOTSTRAP="kafka:9092"

echo "⏳ Waiting for Kafka to be ready..."

# Healthcheck Kafka avec timeout
MAX_RETRIES=30
RETRY_COUNT=0
until kafka-topics --bootstrap-server $BOOTSTRAP --list >/dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT+1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Kafka failed to start after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "   Attempt $RETRY_COUNT/$MAX_RETRIES..."
  sleep 2
done

echo "✅ Kafka is ready"

# Installer yq pour parser le YAML correctement
echo "⏳ Installing yq..."
wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod +x /usr/local/bin/yq

# Lire les topics depuis le YAML avec yq
TOPIC_COUNT=$(yq eval '.topics | length' /topics.yaml)

for i in $(seq 0 $((TOPIC_COUNT - 1))); do
  TOPIC_NAME=$(yq eval ".topics[$i].name" /topics.yaml)
  PARTITIONS=$(yq eval ".topics[$i].partitions" /topics.yaml)
  REPLICATION=$(yq eval ".topics[$i].replicationFactor" /topics.yaml)

  echo "➡️ Creating topic: $TOPIC_NAME (partitions=$PARTITIONS, replication=$REPLICATION)"

  if kafka-topics --create --if-not-exists \
    --bootstrap-server $BOOTSTRAP \
    --partitions $PARTITIONS \
    --replication-factor $REPLICATION \
    --topic "$TOPIC_NAME" 2>&1; then
    echo "   ✅ Topic $TOPIC_NAME ready"
  else
    echo "   ❌ Failed to create topic $TOPIC_NAME"
    exit 1
  fi
done

echo "🎉 All $TOPIC_COUNT topics initialized successfully"
sleep infinity
