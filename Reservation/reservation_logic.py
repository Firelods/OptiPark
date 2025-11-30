import json
import math
import redis

# --------------------------
# Redis connection
# --------------------------
r = redis.Redis(host="localhost", port=6379, decode_responses=True)

# --------------------------
# Load static geometry (blocks & spots)
# --------------------------
with open("config/blocks.json") as f:
    BLOCKS = {b["id"]: b for b in json.load(f)["blocks"]}

with open("config/spots.json") as f:
    SPOTS = {s["id"]: s for s in json.load(f)["spots"]}


# ============================================================
# 1) UTILITY — Read spot state from Redis
# ============================================================
def get_spot_state(spot_id):
    """
    Reads live info from Redis:
    - status
    - rfid
    - battery
    - parking_id (should already be in Redis)
    """
    key = f"spot:{spot_id}"
    return r.hgetall(key)


# ============================================================
# 2) UTILITY — Reserve a spot (update Redis)
# ============================================================
def reserve_spot(spot_id, rfid):
    """
    Update Redis:
    status = 2 (reserved)
    rfid = tag used
    """
    key = f"spot:{spot_id}"
    r.hset(key, mapping={
        "status": 2,
        "rfid": rfid
    })


# ============================================================
# 3) DISTANCE CALCULATION
# ============================================================
def distance_spot_block(spot_id, block_id):
    s = SPOTS[spot_id]     # static coordinates
    b = BLOCKS[block_id]   # static block position
    return math.sqrt((s["x"] - b["x"])**2 + (s["y"] - b["y"])**2)


# ============================================================
# 4) FIND BEST SPOT (reservation logic)
# ============================================================
def find_best_spot(block_id, rfid):
    """
    Steps:
    1) Sort spots by distance to block
    2) Check Redis state for each spot
    3) Select the first free one
    4) Reserve it (update Redis)
    """
    sorted_spots = sorted(
        SPOTS.values(),
        key=lambda s: distance_spot_block(s["id"], block_id)
    )

    for spot in sorted_spots:
        spot_id = spot["id"]
        redis_state = get_spot_state(spot_id)

        status = int(redis_state.get("status", 0))  # default = free

        if status == 0:  # FREE
            reserve_spot(spot_id, rfid)
            return {
                "spot_id": spot_id,
                "parking_id": spot["parking_id"],
                "x": spot["x"],
                "y": spot["y"],
                "distance": distance_spot_block(spot_id, block_id)
            }

    return { "error": "NO_SPOT_AVAILABLE" }


# ============================================================
# 5) GET ALL SPOTS (for /get-spots)
# ============================================================
def get_all_spots():
    """
    Returns the complete list of spots with:
    - static coordinates (from JSON)
    - live Redis state
    """
    spots = {}

    for spot_id, spot_data in SPOTS.items():

        redis_state = get_spot_state(spot_id)
        status = int(redis_state.get("status", 0))
        rfid = redis_state.get("rfid", "")
        battery = int(redis_state.get("battery", 0))
        parking = redis_state.get("parking_id", spot_data["parking_id"])

        spots[spot_id] = {
            "status": status,
            "rfid": rfid,
            "battery": battery,
            "x": spot_data["x"],
            "y": spot_data["y"],
            "parking_id": parking
        }

    return spots
