from flask import Flask, request, jsonify
from flask_cors import CORS
from reservation_logic import find_best_spot
from reservation_logic import (
    cancel_reservation as cancel_reservation_logic,
    get_all_spots
)
from reservation_logic import confirm_reservation
from reservation_logic import is_raining


app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# ============================================================
# RESERVE ENDPOINT
# ============================================================
@app.post("/reserve")
def reserve():
    data = request.get_json(force=True)

    block_id = data.get("block_id")
    user_type = data.get("user_type", "NORMAL")

    if not block_id:
        return jsonify({"error": "block_id missing"}), 400

    result = find_best_spot(block_id, user_type)
    return jsonify(result)

# ============================================================
# GET ALL SPOTS
# ============================================================
@app.get("/get-spots")
def get_spots():
    return jsonify({"spots": get_all_spots()})

# ============================================================
# CANCEL RESERVATION ENDPOINT
# ============================================================
@app.post("/cancel-reservation")
def cancel_reservation_api():
    data = request.get_json()
    spot_id = data.get("spot_id")

    if not spot_id:
        return jsonify({"error": "spot_id missing"}), 400

    cancel_reservation_logic(spot_id)
    return jsonify({"success": True}), 200

# ============================================================
# WEATHER ENDPOINT
# ============================================================
@app.get("/weather")
def get_weather():
    return {
        "rain": 1 if is_raining() else 0
    }

# ============================================================
# CONFIRM RESERVATION ENDPOINT
# ============================================================
@app.post("/confirm-reservation")
def confirm_reservation_api():
    data = request.get_json()
    spot_id = data.get("spot_id")

    if not spot_id:
        return jsonify({"error": "spot_id missing"}), 400

    confirm_reservation(spot_id)

    return jsonify({"success": True}), 200


# ============================================================
# HEALTH CHECK
# ============================================================
@app.get("/health")
def health():
    return {"status": "ok"}


# ============================================================
# START SERVER
# ============================================================
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)


