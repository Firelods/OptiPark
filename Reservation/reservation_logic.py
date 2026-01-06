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
    key = f"spot:{spot_id}"
    return r.hgetall(key)


# ============================================================
# 2) UTILITY — Reserve a spot (update Redis)
# ============================================================
def reserve_spot(spot_id, rfid):
    key = f"spot:{spot_id}"
    r.hset(key, mapping={
        "status": 2,  # reserved
        "rfid": rfid
    })


# ============================================================
# 3) DISTANCE (kept for compatibility but NOT used for sorting)
# ============================================================
def distance_spot_block(spot_id, block_id):
    s = SPOTS[spot_id]
    b = BLOCKS[block_id]
    return math.sqrt((s["x"] - b["x"])**2 + (s["y"] - b["y"])**2)


# ============================================================
# 4) FIND BEST SPOT (new logic)
# ============================================================
def find_best_spot(block_id, rfid):
    """
    New behavior:
    - Select only the spots in the same parking as the block
    - Sort by X DESC (closest first)
    - Pick the first free spot
    """
    block = BLOCKS[block_id]
    parking_id = block["parking_id"]

    # Filter spots by parking & sort by X DESC
    candidate_spots = sorted(
        [s for s in SPOTS.values() if s["parking_id"] == parking_id],
        key=lambda s: s["x"],
        reverse=True
    )

    for spot in candidate_spots:
        spot_id = spot["id"]
        redis_state = get_spot_state(spot_id)

        status = int(redis_state.get("status") or 0)  # SAFE

        if status == 0:  # free
            reserve_spot(spot_id, rfid)
            return {
                "spot_id": spot_id,
                "parking_id": spot["parking_id"],
                "x": spot["x"],
                "y": spot["y"],
                "distance": distance_spot_block(spot_id, block_id)
            }

    return {"error": "NO_SPOT_AVAILABLE"}


# ============================================================
# 5) GET ALL SPOTS (safe int parsing)
# ============================================================
def get_all_spots():
    spots = {}

    for spot_id, spot_data in SPOTS.items():
        redis_state = get_spot_state(spot_id)

        status = int(redis_state.get("status") or 0)
        battery = int(redis_state.get("battery") or 0)

        spots[spot_id] = {
            "status": status,
            "rfid": redis_state.get("rfid", ""),
            "battery": battery,
            "x": spot_data["x"],
            "y": spot_data["y"],
            "parking_id": redis_state.get("parking_id", spot_data["parking_id"]),
        }

    return spots

# ============================================================
# CANCEL A RESERVATION (set status back to FREE)
# ============================================================
def cancel_reservation(spot_id):
    """
    Reset the spot in Redis after a user cancels:
    - status = 0 (free)
    - rfid = "" (clear any tag)
    """
    key = f"spot:{spot_id}"
    r.hset(key, mapping={
        "status": 0,
        "rfid": ""
    })
