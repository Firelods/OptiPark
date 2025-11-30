from flask import Flask, request, jsonify
from flask_cors import CORS
from reservation_logic import find_best_spot

app = Flask(__name__)

# Enable CORS for all origins (or restrict to your web app)
CORS(app, resources={r"/*": {"origins": "*"}})

@app.post("/reserve")
def reserve():
    data = request.json
    block_id = data["block_id"]
    rfid = data["rfid_tag"]

    result = find_best_spot(block_id, rfid)
    return jsonify(result)

@app.get("/get-spots")
def get_spots():
    # you need to return all spot data here
    from reservation_logic import get_all_spots
    return jsonify({"spots": get_all_spots()})

@app.get("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
