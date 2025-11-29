import redis

r = redis.Redis(
    host="localhost",
    port=6379,
    decode_responses=True
)

def get_spot_state(spot_id):
    return r.hgetall(f"spot:{spot_id}")

def reserve_spot(spot_id, rfid):
    r.hset(f"spot:{spot_id}", mapping={
        "status": 2,
        "rfid": rfid
    })
    r.set(f"rfid:{rfid}", spot_id)
