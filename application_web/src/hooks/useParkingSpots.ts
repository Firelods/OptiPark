import { useEffect, useState } from "react";

interface Spot {
  id: string;
  status: string;        
  parking_id?: string;
  x?: number;
  y?: number;
  battery?: number;
  rfid?: string;
}

type SpotsMap = Record<string, Spot>;

export function useParkingSpots() {
  const [spots, setSpots] = useState<SpotsMap>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  async function load() {
    try {
      const res = await fetch("http://localhost:8000/get-spots", {
        method: "GET",
        headers: { "Content-Type": "application/json" },
      });

      if (!res.ok) {
        throw new Error(`Backend returned ${res.status}`);
      }

      const data = await res.json();
      const rawSpots = data.spots || {};

      const normalized: SpotsMap = {};

      Object.entries(rawSpots).forEach(([id, value]) => {
        const v: any = value;
        const statusNum = Number(v.status ?? 0);
        const occupied = statusNum === 1 || statusNum === 3 || statusNum === 4;
        const reserved = statusNum === 2;

        normalized[id] = {
          id,
          status: String(statusNum),   // always "0", "1", "2", ...
          parking_id: v.parking_id,
          x: v.x,
          y: v.y,
          battery: v.battery,
          rfid: v.rfid,
        };
      });

      setSpots(normalized);
      setError(null);
    } catch (e: any) {
      console.error("Failed to load spots", e);
      setError(e.message || "Unknown error");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
    const id = setInterval(load, 3000); // refresh every 3s
    return () => clearInterval(id);
  }, []);

  return { spots, loading, error };
}
