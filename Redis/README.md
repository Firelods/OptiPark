# Redis Initialization Guide for OptiPark

A simple guide explaining how to execute the `init.sh` script to reset and initialize the Redis database used by the OptiPark parking management system.

## Overview

This script:
- Clears the entire Redis database (`FLUSHALL`)
- Creates Parking A and Parking B
- Creates 20 parking spots for each parking
- Initializes every spot with:
  - `status = 0` FREE
  - `type = NORMAL | PMR | EV | COVERED`
  - `parking_id = A | B`
- Creates Redis indexes to support fast reservation logic:
  - Free spots per parking
  - Spot types (EV, PMR, COVERED, NORMAL)
This structure is designed for:
- Reservation logic
- Closest-spot calculation to a block
- Integration with the 3D campus visualization


## Requirements

Before running the script, ensure:
- Docker Desktop is installed and running
- The `redis-server` container is active
- The `init.sh` file is present inside the Redis volume

Check containers:

```bash
docker ps
```
Start them if needed:

```bash
docker compose up -d
```


## Run the Initialization Script
Execute:
```bash
docker exec -i redis-server redis-cli < init_parking.redis
```

## Redis Data Model

Each parking spot is stored as a Redis hash:

spot:{SPOT_ID}

Example:
spot:A-16

Fields:
- status → FREE | RESERVED | OCCUPIED | BLOCKED
- type → NORMAL | PMR | EV | COVERED
- parking_id → A | B

