# Redis Initialization Guide for OptiPark

A simple guide explaining how to execute the `init.sh` script to reset and initialize the Redis database used by the OptiPark parking management system.

## Overview

This script:
- Clears the entire Redis database (`FLUSHALL`)
- Creates Parking A and Parking B
- Creates 4 parking spots for each parking
- Initializes every spot with:
  - `status = 0` (free)
  - `rfid = ""` (no assigned user)
- Prepares Redis for the reservation service, mobile app, and automation logic



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
docker exec -it redis-server sh /data/init.sh
```

## Verify the Database
Open Redis CLI:
```bash
docker exec -it redis-server redis-cli
```
Check parking entries:
```bash
HGETALL parking:A
HGETALL parking:B
```
Check the list of spots:
```bash
SMEMBERS parking:A:spots
SMEMBERS parking:B:spots
```