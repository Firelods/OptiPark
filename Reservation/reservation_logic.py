import json, math
from redis_client import get_spot_state, reserve_spot

with open("config/blocks.json") as f:
    BLOCKS = {b["id"]: b for b in json.load(f)["blocks"]}

with open("config/spots.json") as f:
    SPOTS = {s["id"]: s for s in json.load(f)["spots"]}

def distance_spot_block(spot_id, block_id):
    s = SPOTS[spot_id]
    b = BLOCKS[block_id]
    return math.sqrt((s["x"] - b["x"])**2 + (s["y"] - b["y"])**2)

def find_best_spot(block_id, rfid):
    # sort spots by distance
    sorted_spots = sorted(
        SPOTS.values(),
        key=lambda s: distance_spot_block(s["id"], block_id)
    )

    # find the first spot that is free
    for spot in sorted_spots:
        state = get_spot_state(spot["id"])
        status = int(state.get("status", 0))   

        if status == 0:
            reserve_spot(spot["id"], rfid)
            return {
                "spot_id": spot["id"],
                "parking_id": spot["parking_id"],
                "x": spot["x"],
                "y": spot["y"],
                "distance": distance_spot_block(spot["id"], block_id)
            }

    return { "error": "NO_SPOT_AVAILABLE" }
