#!/bin/sh
set -e  # Arrêt en cas d'erreur

echo "⏳ Installing dependencies..."
apk add --no-cache curl jq wget > /dev/null 2>&1

SCHEMA_REGISTRY_URL="http://schema-registry:8081"

echo "⏳ Waiting for Schema Registry..."
MAX_RETRIES=30
RETRY_COUNT=0

until curl -s "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Schema Registry failed to start after $MAX_RETRIES attempts"
    exit 1
  fi
  echo "   Attempt $RETRY_COUNT/$MAX_RETRIES..."
  sleep 2
done

echo "✅ Schema Registry is ready"

# Compter les schémas
SCHEMA_COUNT=$(ls -1 /schemas/*.json 2>/dev/null | wc -l)

if [ "$SCHEMA_COUNT" -eq 0 ]; then
  echo "⚠️  No schemas found in /schemas/"
  sleep infinity
  exit 0
fi

echo "📋 Found $SCHEMA_COUNT schema(s) to register"

for f in /schemas/*.json; do
  subject="$(basename "$f" .json)-value"

  echo "➡️ Registering schema for subject: $subject"

  # Valider que le fichier est du JSON valide
  if ! jq empty "$f" 2>/dev/null; then
    echo "   ❌ Invalid JSON in $f"
    exit 1
  fi

  raw_schema=$(cat "$f")
  escaped_schema=$(printf '%s' "$raw_schema" | jq -Rs .)

  # Envoyer la requête et capturer le code HTTP
  response=$(curl -s -w "\n%{http_code}" -X POST \
    "$SCHEMA_REGISTRY_URL/subjects/$subject/versions" \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    --data "{\"schemaType\": \"JSON\", \"schema\": $escaped_schema}")

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    schema_id=$(echo "$body" | jq -r '.id' 2>/dev/null || echo "unknown")
    echo "   ✅ Schema registered successfully (id=$schema_id)"
  else
    echo "   ❌ Failed to register $subject (HTTP $http_code)"
    echo "   Response: $body"
    exit 1
  fi
done

echo "🎉 All $SCHEMA_COUNT schemas registered successfully"
sleep infinity
