import { useEffect, useState } from "react";

export function useWeather() {
  const [raining, setRaining] = useState(false);

  useEffect(() => {
    let alive = true;

    const fetchWeather = async () => {
      try {
        const res = await fetch("http://localhost:8000/weather");
        const data = await res.json();

        if (alive) {
          setRaining(data.rain === 1);
        }
      } catch (err) {
        console.error("Weather fetch failed", err);
      }
    };

    // ⏱️ initial fetch
    fetchWeather();

    // 🔁 poll every 3 seconds (same spirit as spots)
    const interval = setInterval(fetchWeather, 3000);

    return () => {
      alive = false;
      clearInterval(interval);
    };
  }, []);

  return raining;
}
