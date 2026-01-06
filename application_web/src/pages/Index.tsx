import { useState, useEffect, Suspense } from "react";
import Campus3D from "@/components/Campus3D";
import { MapPin, Loader2 } from "lucide-react";

/* ===============================
   LIVE DATA FETCH FROM PYTHON API
   =============================== */

async function fetchSpots() {
  try {
    const res = await fetch("http://localhost:8000/get-spots", {
      method: "GET",
      headers: { "Content-Type": "application/json" },
    });

    if (!res.ok) throw new Error("Backend error");

    const data = await res.json();
    return data.spots || {};
  } catch (err) {
    console.error("Error fetching spots:", err);
    return {};
  }
}

const Index = () => {
  // initial state replaced by dynamic later
  const [parkingA, setParkingA] = useState({ total: 4, occupied: 0 });
  const [parkingB, setParkingB] = useState({ total: 4, occupied: 0 });

  /* ===========================
     Fetch parking data on load
     =========================== */
  useEffect(() => {
    async function load() {
      const spots = await fetchSpots();

      // Count spots for each parking
      const aKeys = Object.keys(spots).filter((k) =>
        k.startsWith("A-")
      );
      const bKeys = Object.keys(spots).filter((k) =>
        k.startsWith("B-")
      );

      const aOccupied = aKeys.filter((k) => spots[k].status !== 0).length;
      const bOccupied = bKeys.filter((k) => spots[k].status !== 0).length;

      setParkingA({ total: aKeys.length, occupied: aOccupied });
      setParkingB({ total: bKeys.length, occupied: bOccupied });
    }

    load();
    const interval = setInterval(load, 3000); // auto-refresh every 3 seconds
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="min-h-screen bg-background flex flex-col">
      {/* Header */}
      <header className="bg-card border-b border-border shadow-sm">
        <div className="container mx-auto px-6 py-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-primary rounded-lg flex items-center justify-center">
              <MapPin className="w-6 h-6 text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-foreground">OptiPark</h1>
              <p className="text-sm text-muted-foreground">
                Campus Parking Management
              </p>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 container mx-auto px-6 py-8">
        <div className="mb-8">
          <h2 className="text-3xl font-bold text-foreground mb-2">
            Vue d'ensemble du campus
          </h2>
          <p className="text-muted-foreground">
            Visualisation en temps réel de l'occupation des parkings
          </p>
        </div>

        {/* Vue 3D du Campus */}
        <div className="mb-8">
          <Suspense
            fallback={
              <div className="w-full h-[600px] rounded-2xl border-2 border-border flex items-center justify-center bg-card">
                <div className="text-center">
                  <Loader2 className="w-12 h-12 animate-spin text-primary mx-auto mb-4" />
                  <p className="text-muted-foreground">Chargement de la vue 3D...</p>
                </div>
              </div>
            }
          >
            <Campus3D
              parkingAOccupied={parkingA.occupied}
              parkingATotal={parkingA.total}
              parkingBOccupied={parkingB.occupied}
              parkingBTotal={parkingB.total}
            />
          </Suspense>

          <p className="text-center text-sm text-muted-foreground mt-4">
            🖱️ Cliquez et faites glisser pour tourner • Molette pour zoomer • Clic droit pour déplacer
          </p>
        </div>

        {/* Control Panel */}
        <div className="bg-card rounded-xl border border-border shadow-lg p-6">
          <h3 className="text-xl font-bold text-foreground mb-4">
            Panneau de contrôle
          </h3>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <span className="text-sm font-medium text-foreground">
                  Parking A - Places occupées
                </span>
                <span className="text-sm font-bold text-primary">
                  {parkingA.occupied}/{parkingA.total}
                </span>
              </div>
            </div>

            <div className="space-y-2">
              <div className="flex justify-between items-center">
                <span className="text-sm font-medium text-foreground">
                  Parking B - Places occupées
                </span>
                <span className="text-sm font-bold text-primary">
                  {parkingB.occupied}/{parkingB.total}
                </span>
              </div>
            </div>
          </div>

          {/* Legend */}
          <div className="mt-6 pt-6 border-t border-border">
            <h4 className="text-sm font-semibold text-foreground mb-3">Légende</h4>
            <div className="flex flex-wrap gap-4">
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-parking-available" />
                <span className="text-xs text-muted-foreground">
                  Disponible (&lt;70%)
                </span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-parking-warning" />
                <span className="text-xs text-muted-foreground">
                  Presque plein (70–89%)
                </span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-parking-full" />
                <span className="text-xs text-muted-foreground">
                  Complet (≥90%)
                </span>
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="bg-card border-t border-border mt-auto">
        <div className="container mx-auto px-6 py-4">
          <p className="text-center text-sm text-muted-foreground">
            OptiPark – Visualization Demo
          </p>
        </div>
      </footer>
    </div>
  );
};

export default Index;
