#!/bin/sh

echo "=== RESET REDIS DATABASE ==="
redis-cli FLUSHALL

echo "=== CREATING PARKINGS A & B ==="

# --- Parking A ---
redis-cli HSET parking:A name "Parking A" description "Parking côté bloc A"
redis-cli SADD parking:A:spots A-1 A-2 A-3 A-4

# --- Places A ---
redis-cli HSET spot:A-1 parking_id A status 0 rfid ""
redis-cli HSET spot:A-2 parking_id A status 0 rfid ""
redis-cli HSET spot:A-3 parking_id A status 0 rfid ""
redis-cli HSET spot:A-4 parking_id A status 0 rfid ""

# --- Parking B ---
redis-cli HSET parking:B name "Parking B" description "Parking côté bloc B"
redis-cli SADD parking:B:spots B-1 B-2 B-3 B-4

# --- Places B ---
redis-cli HSET spot:B-1 parking_id B status 0 rfid ""
redis-cli HSET spot:B-2 parking_id B status 0 rfid ""
redis-cli HSET spot:B-3 parking_id B status 0 rfid ""
redis-cli HSET spot:B-4 parking_id B status 0 rfid ""

echo "=== INITIALIZATION DONE ==="
