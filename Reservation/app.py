from flask import Flask, request, jsonify
from reservation_logic import find_best_spot

app = Flask(__name__)

@app.post("/reserve")
def reserve():
    data = request.json
    block_id = data["block_id"]
    rfid = data["rfid_tag"]

    result = find_best_spot(block_id, rfid)
    return jsonify(result)

@app.get("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
