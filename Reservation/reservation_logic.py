import json
import math
import redis

# --------------------------
# Redis connection
# --------------------------
r = redis.Redis(
    host="redis",   # local run
    port=6379,
    decode_responses=True
)

# Spot status codes
FREE = 0
OCCUPIED = 1
RESERVED = 2
BLOCKED = 3


# --------------------------
# Load static geometry (blocks & spots)
# --------------------------
with open("config/blocks.json") as f:
    BLOCKS = {b["id"]: b for b in json.load(f)["blocks"]}

with open("config/spots.json") as f:
    SPOTS = {s["id"]: s for s in json.load(f)["spots"]}

with open("config/access_points.json") as f:
    ACCESS_POINTS = json.load(f)


# ============================================================
# 1) UTILITY — Read spot state from Redis
# ============================================================
def get_spot_state(spot_id):
    key = f"spot:{spot_id}"
    return r.hgetall(key)


# ============================================================
# 3) DISTANCE 
# ============================================================
def distance_spot_access(spot_id, parking_id):
    spot = SPOTS[spot_id]
    access = ACCESS_POINTS[parking_id]

    dx = spot["x"] - access["x"]
    dy = spot["y"] - access["y"]

    return math.sqrt(dx*dx + dy*dy)

# ============================================================
# 4) FIND BEST SPOT (final logic)
# ============================================================
def find_best_spot(block_id, user_type="NORMAL"):
    user_type = user_type.upper()

    block = BLOCKS.get(block_id)
    if not block:
        return {"error": "INVALID_BLOCK"}

    parking_id = block["parking_id"]

    PRIORITY = {
        "NORMAL": ["NORMAL", "EV", "PMR"],
        "EV": ["EV", "NORMAL", "PMR"],
        "PMR": ["PMR", "NORMAL", "EV"],
    }

    priority_order = PRIORITY.get(user_type)
    if not priority_order:
        return {"error": "INVALID_USER_TYPE"}

    raining = is_raining()

    for wanted_type in priority_order:
        candidates = []

        for spot in SPOTS.values():
            if spot["parking_id"] != parking_id:
                continue

            attrs = get_spot_attributes(spot["id"])

            # must be FREE
            if attrs["status"] != FREE:
                continue

            # must match current priority type
            if attrs["type"] != wanted_type:
                continue

            dist = distance_spot_access(spot["id"], parking_id)

            candidates.append({
                "spot": spot,
                "distance": dist,
                "covered": attrs["covered"]
            })

        if not candidates:
            continue

        # 🌧️ weather rule applies ONLY inside same type
        if raining:
            candidates.sort(
                key=lambda c: (-c["covered"], c["distance"])
            )
        else:
            candidates.sort(
                key=lambda c: c["distance"]
            )

        chosen = candidates[0]["spot"]

        reserve_spot(chosen["id"])

        return {
            "spot_id": chosen["id"],
            "parking_id": chosen["parking_id"],
            "type": wanted_type,
            "x": chosen["x"],
            "y": chosen["y"],
            "status": RESERVED,
            "rain": int(raining)
        }

    return {"error": "NO_SPOT_AVAILABLE"}

# ============================================================
# 2) UTILITY — Reserve a spot (update Redis)
# ============================================================
def reserve_spot(spot_id):
    r.hset(f"spot:{spot_id}", "status", RESERVED)
# ============================================================
# 5) GET ALL SPOTS (safe int parsing)
# ============================================================
def get_all_spots():
    spots = {}

    for spot_id, spot_data in SPOTS.items():
        redis_state = get_spot_state(spot_id)

        spots[spot_id] = {
            "status": int(redis_state.get("status", 0)),
            "type": redis_state.get("type", spot_data.get("type")),
            "parking_id": redis_state.get("parking_id", spot_data["parking_id"]),
            "x": spot_data["x"],
            "y": spot_data["y"],
        }

    return spots

# ============================================================
# CANCEL A RESERVATION (set status back to FREE)
# ============================================================
def cancel_reservation(spot_id):
    r.hset(f"spot:{spot_id}", "status", FREE)


# ============================================================
# CONFIRM A RESERVATION (set status to OCCUPIED)
# ============================================================
def confirm_reservation(spot_id):
    r.hset(f"spot:{spot_id}", "status", OCCUPIED)


def get_spot_attributes(spot_id):
    state = r.hgetall(f"spot:{spot_id}")
    spot_cfg = SPOTS[spot_id]

    return {
        "status": int(state.get("status") or 0),
        "type": state.get("type", spot_cfg["type"]).upper(),
        "covered": int(state.get("covered") or 0)
    }

def is_raining():
    return int(r.get("weather:rain") or 0) == 1
