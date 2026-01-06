/**
 * Fetch parking spots directly from your Python backend.
 * No Supabase Edge Function. No Deno. No server middleware.
 */

export async function getParkingSpots() {
  const PYTHON_API_URL = "http://localhost:8000/get-spots";

  try {
    console.log("Fetching parking spots from:", PYTHON_API_URL);

    const response = await fetch(PYTHON_API_URL, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`Backend responded ${response.status}`);
    }

    const data = await response.json();
    console.log("Parking spots received:", data);

    return data;
  } catch (error) {
    console.error("Error fetching parking spots:", error);
    return {
      error: true,
      spots: {},
      message:
        error instanceof Error ? error.message : "Unknown fetch error",
    };
  }
}
