#!/bin/sh

set -eu

# Minimal, ASCII-only init script for Redis
# - Normalizes CRLF line endings
# - Joins lines that end with a backslash
# - Ignores comment lines that start with '#'
# - Executes each Redis command line using redis-cli

echo "Initializing Redis with /scripts/init_parking.redis"

if [ ! -f /scripts/init_parking.redis ]; then
  echo "Error: /scripts/init_parking.redis not found" >&2
  exit 1
fi

# Normalize CRLF -> LF into a temp file
tr -d '\r' < /scripts/init_parking.redis > /tmp/init_parking_unix.redis

# Wait for Redis to be available
until redis-cli -h redis ping > /dev/null 2>&1; do
  echo "Waiting for Redis..."
  sleep 1
done

echo "Redis is ready, processing commands..."

# Use awk to remove comments, join backslash continuation lines and drop empty lines
awk '
  { sub(/\r$/, ""); }
  /^#/ { next }
  {
    line = $0
    while (line ~ /\\$/) {
      sub(/\\$/, "")
      if (getline nextline <= 0) break
      sub(/\r$/, "", nextline)
      line = line nextline
    }
    if (line ~ /\S/) print line
  }' /tmp/init_parking_unix.redis > /tmp/redis_commands.txt

# Execute each command
while IFS= read -r line; do
  echo "Executing: $line"
  if ! echo "$line" | redis-cli -h redis >/dev/null 2>&1; then
    echo "Error executing: $line" >&2
  fi
done < /tmp/redis_commands.txt

# Cleanup
rm -f /tmp/init_parking_unix.redis /tmp/redis_commands.txt

echo "Initialization complete. Keys count: $(redis-cli -h redis DBSIZE)"
