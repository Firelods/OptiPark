import { Canvas } from "@react-three/fiber";
import { OrbitControls, PerspectiveCamera, Text } from "@react-three/drei";
import { useMemo } from "react";
import { useParkingSpots } from "@/hooks/useParkingSpots";
import { useTexture } from "@react-three/drei";
import { DoubleSide, SRGBColorSpace } from "three";
import Rain from "@/components/Rain";
import { useWeather } from "@/hooks/useWeather";

const PARKING_WIDTH = 7.2;
const PARKING_DEPTH = 6.2;
const PARKING_Y = 0.06;
const PARKING_Z = 2;


interface Campus3DProps {
  parkingAOccupied: number;
  parkingATotal: number;
  parkingBOccupied: number;
  parkingBTotal: number;
}

enum SpotType {
  NORMAL = "NORMAL",
  PMR = "PMR",
  EV = "EV",
}

const stableColors = [
  "#1e40af",
  "#dc2626",
  "#059669",
  "#ea580c",
  "#4f46e5",
  "#0891b2",
];
function colorForSpot(id: string) {
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = id.charCodeAt(i) + ((hash << 5) - hash);
  return stableColors[Math.abs(hash) % stableColors.length];
}


/* ===== PARKING A RULES (EXACT SPECIFICATION) ===== */

function classifyParkingASpot(index: number) {
  const row = Math.floor(index / 5);
  const col = index % 5;

  let covered = false;
  let type: SpotType = SpotType.NORMAL;

  // Row 0 fully covered
  if (row === 0) covered = true;

  // PMR: last two spots of row 0 and row 1
  if ((row === 0 || row === 1) && col >= 3) {
    type = SpotType.PMR;
  }

  // EV: A-16, A-17, A-18 (index 15,16,17)
  if (index === 15 || index === 16 || index === 17) {
    type = SpotType.EV;
  }

  return { covered, type };
}

/* ===== PARKING B RULES (EXACT SPECIFICATION) ===== */
function classifyParkingBSpot(index: number) {
  const row = Math.floor(index / 5);
  const col = index % 5;

  let covered = false;
  let type: SpotType = SpotType.NORMAL;

  // Covered row (same visual row as A)
  if (row === 0) covered = true;

  // PMR: B1 B2 B6 B7
  if ((row === 0 || row === 1) && col <= 1) {
    type = SpotType.PMR;
  }

  // EV: B18 B19 B20 (indexes 17,18,19)
  if (index === 17 || index === 18 || index === 19) {
    type = SpotType.EV;
  }

  return { covered, type };
}

// Composant pour une voiture 3D réaliste
const Car = ({ position, color, opacity = 1 }: { position: [number, number, number]; color: string;
  opacity?: number; }) => {
  return (
    <group position={position}>
      {/* Corps principal de la voiture */}
      <mesh position={[0, 0.15, 0]} castShadow>
        <boxGeometry args={[0.6, 0.25, 1]} />
        <meshStandardMaterial 
          color={color} 
          opacity={opacity}
          metalness={0.6}
          roughness={0.4}
        />
      </mesh>
      {/* Cabine avec vitres */}
      <mesh position={[0, 0.4, -0.1]} castShadow>
        <boxGeometry args={[0.5, 0.2, 0.5]} />
        <meshStandardMaterial 
          color={color}
          metalness={0.5}
          roughness={0.3}
        />
      </mesh>
      {/* Vitres avant */}
      <mesh position={[0, 0.4, 0.12]}>
        <boxGeometry args={[0.48, 0.18, 0.02]} />
        <meshStandardMaterial 
          color="#87CEEB" 
          transparent 
          opacity={0.3}
          metalness={0.9}
          roughness={0.1}
        />
      </mesh>
      {/* Phares avant */}
      <mesh position={[-0.2, 0.15, 0.51]}>
        <boxGeometry args={[0.1, 0.08, 0.02]} />
        <meshStandardMaterial color="#ffffcc" emissive="#ffff99" emissiveIntensity={0.5} />
      </mesh>
      <mesh position={[0.2, 0.15, 0.51]}>
        <boxGeometry args={[0.1, 0.08, 0.02]} />
        <meshStandardMaterial color="#ffffcc" emissive="#ffff99" emissiveIntensity={0.5} />
      </mesh>
      {/* Feux arrière */}
      <mesh position={[-0.2, 0.15, -0.51]}>
        <boxGeometry args={[0.08, 0.06, 0.02]} />
        <meshStandardMaterial color="#ff0000" emissive="#ff0000" emissiveIntensity={0.3} />
      </mesh>
      <mesh position={[0.2, 0.15, -0.51]}>
        <boxGeometry args={[0.08, 0.06, 0.02]} />
        <meshStandardMaterial color="#ff0000" emissive="#ff0000" emissiveIntensity={0.3} />
      </mesh>
      {/* Roues */}
      <mesh position={[-0.25, 0.08, 0.35]} rotation={[0, 0, Math.PI / 2]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.1, 16]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.8} />
      </mesh>
      <mesh position={[0.25, 0.08, 0.35]} rotation={[0, 0, Math.PI / 2]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.1, 16]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.8} />
      </mesh>
      <mesh position={[-0.25, 0.08, -0.35]} rotation={[0, 0, Math.PI / 2]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.1, 16]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.8} />
      </mesh>
      <mesh position={[0.25, 0.08, -0.35]} rotation={[0, 0, Math.PI / 2]} castShadow>
        <cylinderGeometry args={[0.08, 0.08, 0.1, 16]} />
        <meshStandardMaterial color="#1a1a1a" roughness={0.8} />
      </mesh>
    </group>
  );
};

// Composant pour une place de parking réaliste
const ParkingSpot = ({ 
  position,
  spotId,
  occupied,
  reserved = false,
  blocked = false,
  forbidden = false,
  spotType,
}: { 
  position: [number, number, number];
  spotId: string;
  occupied: boolean;
  reserved?: boolean;
  blocked?: boolean;
  forbidden?: boolean;
  spotType: SpotType;
}) => {

  const carColor = colorForSpot(spotId);

  const baseColor =
    spotType === SpotType.PMR
      ? "#2563eb"
      : spotType === SpotType.EV
      ? "#16a34a"
      : "#8a8a8a";

  // PMR texture
  const pmrTexture = useTexture("/textures/pmr.png");

  // 🔧 texture fixes (THIS is where it goes)
  pmrTexture.colorSpace = SRGBColorSpace;
  pmrTexture.flipY = false;
  pmrTexture.anisotropy = 16;

  const evTexture = useTexture("/textures/ev.png");
  evTexture.colorSpace = SRGBColorSpace;
  evTexture.flipY = false;

  return (
    <group position={position}>

      {/* Sol de la place */}
      <mesh position={[0, 0.045, 0]} receiveShadow>
        <boxGeometry args={[0.82, 0.02, 1.22]} />
        <meshStandardMaterial
          color={occupied ? "#505050" : baseColor}
          roughness={0.9}
        />
      </mesh>

      {/* Marquage blanc */}
      <mesh position={[0, 0.011, 0]}>
        <boxGeometry args={[0.8, 0.01, 1.2]} />
        <meshStandardMaterial color="#ffffff" transparent opacity={0.8} />
      </mesh>

      {/* Bordures */}
      <mesh position={[-0.4, 0.015, 0]}>
        <boxGeometry args={[0.04, 0.03, 1.2]} />
        <meshStandardMaterial color="#ffffff" />
      </mesh>
      <mesh position={[0.4, 0.015, 0]}>
        <boxGeometry args={[0.04, 0.03, 1.2]} />
        <meshStandardMaterial color="#ffffff" />
      </mesh>
      <mesh position={[0, 0.015, -0.6]}>
        <boxGeometry args={[0.8, 0.03, 0.04]} />
        <meshStandardMaterial color="#ffffff" />
      </mesh>

      {/* PMR ground sign (official image, fixed visibility) */}
      {spotType === SpotType.PMR && !occupied && (
        <group
          position={[0, 0.07, 0]}
          rotation={[-Math.PI / 2, 0, 0]}
        >
          {/* Blue background plate */}
          <mesh>
            <planeGeometry args={[0.62, 0.62]} />
            <meshStandardMaterial
              color="#2563eb"
              roughness={0.7}
              depthWrite={false}
            />
          </mesh>

          {/* White PMR icon */}
          <mesh position={[0, 0.001, 0]}
           rotation={[0, 0, Math.PI]} >
            <planeGeometry args={[0.55, 0.55]} />
            <meshStandardMaterial
              map={pmrTexture}
              transparent
              side={DoubleSide}
              depthWrite={false}
              toneMapped={false}
            />
          </mesh>
        </group>
      )}

        {/* EV ground sign (official image) */}
        {spotType === SpotType.EV && !occupied && (
          <group
            position={[0, 0.07, 0]}
            rotation={[-Math.PI / 2, 0, 0]}
          >
            {/* Green background plate */}
            <mesh>
              <planeGeometry args={[0.62, 0.62]} />
              <meshStandardMaterial
                color="#16a34a"
                roughness={0.7}
                depthWrite={false}
              />
            </mesh>

            {/* White EV icon */}
            <mesh
              position={[0, 0.001, 0]}
              rotation={[0, 0, Math.PI]}   // ✅ same fix as PMR
            >
              <planeGeometry args={[0.55, 0.55]} />
              <meshStandardMaterial
                map={evTexture}
                transparent
                side={DoubleSide}
                depthWrite={false}
                toneMapped={false}
              />
            </mesh>
          </group>
        )}


      {/* Reserved */}
      {reserved && !occupied && (
        <Text
          position={[0, 0.15, 0]}
          rotation={[-Math.PI / 2, 0, 0]}
          fontSize={0.22}
          color="#fbbf24"
          anchorX="center"
          anchorY="middle"
          outlineWidth={0.02}
          outlineColor="black"
        >
          RESERVED
        </Text>
      )}

      {/* Occupied */}
      {occupied && <Car position={[0, 0, 0]} color={carColor} />}

      {/* Blocked */}
      {blocked && !occupied && !reserved && !forbidden && (
        <Text
          position={[0, 0.15, 0]}
          rotation={[-Math.PI / 2, 0, 0]}
          fontSize={0.7}
          color="#dc2626"
        >
          X
        </Text>
      )}

      {/* Forbidden */}
      {forbidden && !occupied && !reserved && !blocked && (
        <group position={[0, 0.15, 0]} rotation={[-Math.PI / 2, 0, 0]}>
          <mesh>
            <ringGeometry args={[0.35, 0.45, 32]} />
            <meshStandardMaterial color="#dc2626" />
          </mesh>
          <mesh rotation={[0, 0, Math.PI / 4]}>
            <boxGeometry args={[0.7, 0.1, 0.1]} />
            <meshStandardMaterial color="#dc2626" />
          </mesh>
        </group>
      )}

    </group>
  );
};


const CoveredSpot = ({
  position,
  ...props
}: any) => (
  <group position={position}>

    {/* Spot itself */}
    <ParkingSpot {...props} position={[0, 0, 0]} />

    {/* Front-left pole */}
    <mesh position={[-0.4, 0.55, -0.6]} castShadow>
      <cylinderGeometry args={[0.05, 0.05, 1.5, 8]} />
      <meshStandardMaterial color="#4a5568" metalness={0.7} roughness={0.3} />
    </mesh>

    {/* Front-right pole */}
    <mesh position={[0.4, 0.55, -0.6]} castShadow>
      <cylinderGeometry args={[0.05, 0.05, 1.5, 8]} />
      <meshStandardMaterial color="#4a5568" metalness={0.7} roughness={0.3} />
    </mesh>

    {/* Back-left pole */}
    <mesh position={[-0.4, 0.55, 0.6]} castShadow>
      <cylinderGeometry args={[0.05, 0.05, 1.5, 8]} />
      <meshStandardMaterial color="#4a5568" metalness={0.7} roughness={0.3} />
    </mesh>

    {/* Back-right pole */}
    <mesh position={[0.4, 0.55, 0.6]} castShadow>
      <cylinderGeometry args={[0.05, 0.05, 1.5, 8]} />
      <meshStandardMaterial color="#4a5568" metalness={0.7} roughness={0.3} />
    </mesh>

    {/* Roof */}
    <mesh position={[0, 1.3, 0]} castShadow>
      <boxGeometry args={[0.9, 0.05, 1.3]} />
      <meshStandardMaterial color="#64748b" metalness={0.6} roughness={0.4} />
    </mesh>

  </group>
);



// Arbre
const Tree = ({ position }: { position: [number, number, number] }) => {
  return (
    <group position={position}>
      {/* Tronc */}
      <mesh position={[0, 0.5, 0]} castShadow>
        <cylinderGeometry args={[0.15, 0.2, 1, 8]} />
        <meshStandardMaterial color="#3d2817" roughness={0.9} />
      </mesh>
      {/* Feuillage - 3 sphères pour plus de réalisme */}
      <mesh position={[0, 1.3, 0]} castShadow>
        <sphereGeometry args={[0.6, 16, 16]} />
        <meshStandardMaterial color="#2d5016" roughness={0.8} />
      </mesh>
      <mesh position={[-0.2, 1.6, 0]} castShadow>
        <sphereGeometry args={[0.5, 16, 16]} />
        <meshStandardMaterial color="#3a6b1f" roughness={0.8} />
      </mesh>
      <mesh position={[0.2, 1.5, 0.2]} castShadow>
        <sphereGeometry args={[0.45, 16, 16]} />
        <meshStandardMaterial color="#2d5016" roughness={0.8} />
      </mesh>
    </group>
  );
};


// Parking complet
const Parking = ({
  position,
  rotation,
  name,
  spotIds,
  spotsData,
}: {
  position: [number, number, number];
  rotation: [number, number, number];
  name: string;
  spotIds: string[];
  spotsData: Record<string, { id: string; status: string }>;
}) => {

  /* ================= SPOTS COMPUTATION ================= */
  const spots = useMemo(() => {
    const cols = 5;

    return spotIds.map((spotId, index) => {
      const status = Number(spotsData[spotId]?.status ?? 0);

      const occupied  = status === 1;
      const reserved  = status === 2;
      const blocked   = status === 3;
      const forbidden = status === 4;

    const { covered, type } =
      name === "PARKING A"
        ? classifyParkingASpot(index)
        : classifyParkingBSpot(index);

      const row = Math.floor(index / cols);
      const col = index % cols;

      return {
        id: spotId,
        status,                 // 🔴 REQUIRED (was missing)
        pos: [
          col * 1.2 - (cols - 1) * 0.6,
          0,
          (row * 1.4) - 2.1,
        ] as [number, number, number],

        occupied,
        reserved,
        blocked,
        forbidden,
        covered,
        spotType: type,
      };
    });
  }, [spotIds, spotsData]);

  /* ================= PANEL LOGIC ================= */
  const freeCount = spots.filter(s => s.status === 0).length;
  const unavailableCount = spots.length - freeCount;
  const occupancyRate = (unavailableCount / spots.length) * 100;

  const statusColor =
    occupancyRate >= 90 ? "#ef4444" :
    occupancyRate >= 70 ? "#f59e0b" :
    "#22c55e";

  /* ================= RENDER ================= */
  return (
    <group position={position} rotation={rotation}>

      {/* Sol du parking */}
      <mesh position={[0, 0, 0]} receiveShadow>
        <boxGeometry args={[7.2, 0.1, 6.2]} />
        <meshStandardMaterial
          color="#2d3748"
          roughness={0.95}
          metalness={0.05}
        />
      </mesh>

      {/* Bordures – LOCAL to parking */}
      {/* Front border */}
      <mesh position={[0, PARKING_Y, -PARKING_DEPTH / 2]}>
        <boxGeometry args={[PARKING_WIDTH, 0.12, 0.2]} />
        <meshStandardMaterial color="#718096" />
      </mesh>

      {/* Back border */}
      <mesh position={[0, PARKING_Y, PARKING_DEPTH / 2]}>
        <boxGeometry args={[PARKING_WIDTH, 0.12, 0.2]} />
        <meshStandardMaterial color="#718096" />
      </mesh>

      {/* Left border */}
      <mesh position={[-PARKING_WIDTH / 2, PARKING_Y, 0]}>
        <boxGeometry args={[0.2, 0.12, PARKING_DEPTH]} />
        <meshStandardMaterial color="#718096" />
      </mesh>

      {/* Right border */}
      <mesh position={[PARKING_WIDTH / 2, PARKING_Y, 0]}>
        <boxGeometry args={[0.2, 0.12, PARKING_DEPTH]} />
        <meshStandardMaterial color="#718096" />
      </mesh>


      {/* Places */}
      {spots.map(spot =>
        spot.covered ? (
          <CoveredSpot
            key={spot.id}
            position={spot.pos}
            spotId={spot.id}
            occupied={spot.occupied}
            reserved={spot.reserved}
            blocked={spot.blocked}
            forbidden={spot.forbidden}
            spotType={spot.spotType}
          />
        ) : (
          <ParkingSpot
            key={spot.id}
            position={spot.pos}
            spotId={spot.id}
            occupied={spot.occupied}
            reserved={spot.reserved}
            blocked={spot.blocked}
            forbidden={spot.forbidden}
            spotType={spot.spotType}
          />
        )
      )}

      {/* ===== PARKING PANEL WITH SUPPORT ===== */}
<group position={[0, 2.5, -PARKING_DEPTH / 2 - 0.6]}>

  {/* Poles */}
  <mesh position={[-0.9, -1.2, 0]} castShadow>
    <cylinderGeometry args={[0.06, 0.06, 2.4, 12]} />
    <meshStandardMaterial color="#374151" />
  </mesh>

  <mesh position={[0.9, -1.2, 0]} castShadow>
    <cylinderGeometry args={[0.06, 0.06, 2.4, 12]} />
    <meshStandardMaterial color="#374151" />
  </mesh>

  {/* Panel board */}
  <mesh>
    <boxGeometry args={[3, 1.2, 0.15]} />
    <meshStandardMaterial color={statusColor} />
  </mesh>

  <Text position={[0, 0.3, 0.09]} fontSize={0.3} color="#fff">
    {name}
  </Text>

  <Text position={[0, -0.1, 0.09]} fontSize={0.4} color="#fff">
    {freeCount}/{spots.length}
  </Text>

  <Text position={[0, -0.5, 0.09]} fontSize={0.2} color="#fff">
    places disponibles
  </Text>
</group>


    </group>
  );
};

const PedestrianPathL = ({
  position,
  horizontalLength,
  verticalLength,
  width = 0.8,
  direction = "left",
}: {
  position: [number, number, number];
  horizontalLength: number;
  verticalLength: number;
  width?: number;
  direction?: "left" | "right";
}) => {
  const dir = direction === "left" ? -1 : 1;

  return (
    <group position={position}>

      {/* Horizontal segment _ */}
      <mesh
        position={[dir * horizontalLength / 2, 0.015, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
        receiveShadow
      >
        <planeGeometry args={[horizontalLength, width]} />
        <meshStandardMaterial color="#9ca3af" roughness={0.95} />
      </mesh>

      {/* Vertical segment | */}
      <mesh
        position={[dir * horizontalLength, 0.015, -verticalLength / 2]}
        rotation={[-Math.PI / 2, 0, 0]}
        receiveShadow
      >
        <planeGeometry args={[width, verticalLength]} />
        <meshStandardMaterial color="#9ca3af" roughness={0.95} />
      </mesh>

      {/* 🔹 CORNER PATCH (fixes the ugly joint) */}
      <mesh
        position={[dir * horizontalLength, 0.016, 0]}
        rotation={[-Math.PI / 2, 0, 0]}
        receiveShadow
      >
        <planeGeometry args={[width, width]} />
        <meshStandardMaterial color="#9ca3af" roughness={0.95} />
      </mesh>

    </group>
  );
};



// Bloc universitaire
const UniversityBlock = ({ position, label }: { position: [number, number, number]; label: string }) => {
  return (
    <group position={position}>
      {/* Base du bâtiment avec texture brique */}
      <mesh position={[0, 2, 0]} castShadow receiveShadow>
        <boxGeometry args={[3.5, 4, 3.5]} />
        <meshStandardMaterial 
          color="#8b4513" 
          roughness={0.9}
          metalness={0.1}
        />
      </mesh>
      {/* Bandes décoratives */}
      <mesh position={[0, 1, 0]} castShadow>
        <boxGeometry args={[3.55, 0.2, 3.55]} />
        <meshStandardMaterial color="#654321" roughness={0.8} />
      </mesh>
      <mesh position={[0, 3, 0]} castShadow>
        <boxGeometry args={[3.55, 0.2, 3.55]} />
        <meshStandardMaterial color="#654321" roughness={0.8} />
      </mesh>
      {/* Toit moderne */}
      <mesh position={[0, 4.3, 0]} castShadow>
        <boxGeometry args={[3.7, 0.3, 3.7]} />
        <meshStandardMaterial 
          color="#2c3e50" 
          metalness={0.6}
          roughness={0.3}
        />
      </mesh>
      {/* Fenêtres réalistes avec reflets */}
      {[...Array(3)].map((_, floor) =>
        [...Array(2)].map((_, col) => (
          <group key={`${floor}-${col}`}>
            {/* Cadre de fenêtre */}
            <mesh position={[-0.8 + col * 1.6, 1 + floor * 1.2, 1.77]}>
              <boxGeometry args={[0.65, 0.85, 0.03]} />
              <meshStandardMaterial color="#ffffff" />
            </mesh>
            {/* Vitre */}
            <mesh position={[-0.8 + col * 1.6, 1 + floor * 1.2, 1.78]}>
              <boxGeometry args={[0.6, 0.8, 0.02]} />
              <meshStandardMaterial 
                color="#87ceeb" 
                transparent
                opacity={0.5}
                metalness={0.9}
                roughness={0.1}
                emissive="#60a5fa" 
                emissiveIntensity={0.2}
              />
            </mesh>
          </group>
        ))
      )}
      {/* Porte d'entrée avec cadre */}
      <mesh position={[0, 0.6, 1.77]}>
        <boxGeometry args={[0.9, 1.3, 0.03]} />
        <meshStandardMaterial color="#a0522d" />
      </mesh>
      <mesh position={[0, 0.6, 1.78]}>
        <boxGeometry args={[0.8, 1.2, 0.02]} />
        <meshStandardMaterial 
          color="#1f2937" 
          metalness={0.5}
          roughness={0.4}
        />
      </mesh>
      {/* Poignée de porte */}
      <mesh position={[0.3, 0.6, 1.8]}>
        <sphereGeometry args={[0.05, 16, 16]} />
        <meshStandardMaterial color="#ffd700" metalness={0.9} roughness={0.1} />
      </mesh>
      {/* Auvent au-dessus de la porte */}
      <mesh position={[0, 1.35, 2.05]} castShadow>
        <boxGeometry args={[1.2, 0.1, 0.6]} />
        <meshStandardMaterial color="#2c3e50" metalness={0.5} roughness={0.4} />
      </mesh>
      {/* Logo/Texte avec panneau */}
      <mesh position={[0, 3.8, 1.79]} castShadow>
        <boxGeometry args={[1.8, 0.4, 0.1]} />
        <meshStandardMaterial color="#1e40af" metalness={0.3} roughness={0.5} />
      </mesh>
      <Text
        position={[0, 3.8, 1.85]}
        fontSize={0.2}
        color="#ffffff"
        anchorX="center"
        anchorY="middle"
      >
        {label}
      </Text>
    </group>
  );
};
const Campus3D = ({
  parkingAOccupied,
  parkingATotal,
  parkingBOccupied,
  parkingBTotal,
}: Campus3DProps) => {

  const { spots: spotsData, loading } = useParkingSpots();
  const raining = useWeather();
  /* ===== FIX: 20 spots per parking ===== */
  const parkingASpots = Array.from({ length: 20 }, (_, i) => `A-${i + 1}`);
  const parkingBSpots = Array.from({ length: 20 }, (_, i) => `B-${i + 1}`);

  return (
    <div className="w-full h-[600px] rounded-2xl overflow-hidden shadow-2xl border-2 border-border">
      {loading && (
        <div className="absolute inset-0 flex items-center justify-center bg-background/50 z-10">
          <p className="text-foreground">Loading parking data...</p>
        </div>
      )}

      <Canvas shadows dpr={[1, 2]}>
        <PerspectiveCamera makeDefault position={[15, 12, 15]} fov={50} />

        <OrbitControls
          enablePan
          enableZoom
          enableRotate
          minDistance={8}
          maxDistance={25}
          maxPolarAngle={Math.PI / 2.2}
          enableDamping
          dampingFactor={0.05}
        />

        {/* ===== LIGHTING ===== */}
        <ambientLight intensity={0.5} />
        <directionalLight
          position={[10, 20, 10]}
          intensity={0.8}
          castShadow
          shadow-mapSize-width={1024}
          shadow-mapSize-height={1024}
        />
        <hemisphereLight intensity={0.3} groundColor="#444444" />

        {/* ===== GROUND ===== */}
        <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[50, 50]} />
          <meshStandardMaterial color="#2d5016" roughness={0.95} />
        </mesh>

        {/* ===== UNIVERSITY BLOCKS ===== */}
        <UniversityBlock position={[-3, 0, -2]} label="BLOC A" />
        <UniversityBlock position={[3, 0, -2]} label="BLOC B" />
        <UniversityBlock position={[0, 0, -6]} label="BLOC C" />

        {/* ===== PARKINGS ===== */}
        <Parking
          position={[-11, 0, 2]}
          rotation={[0, 0, 0]}
          name="PARKING A"
          spotIds={parkingASpots}
          spotsData={spotsData}
        />

        <Parking
          position={[11, 0, 2]}
          rotation={[0, 0, 0]}
          name="PARKING B"
          spotIds={parkingBSpots}
          spotsData={spotsData}
        />

       {/* ===== TREES ===== */}

        /* Left lower campus */
        <Tree position={[-18, 0, -6]} />
        <Tree position={[-17.2, 0, -5.2]} />
        <Tree position={[-18.8, 0, -5.5]} />

        <Tree position={[-17.5, 0, 4]} />
        <Tree position={[-16.7, 0, 4.8]} />
        <Tree position={[-18.3, 0, 4.5]} />

        <Tree position={[-8, 0, -10]} />
        <Tree position={[-7.2, 0, -9.2]} />
        <Tree position={[-8.8, 0, -9.5]} />

        <Tree position={[-10, 0, 12]} />
        <Tree position={[-9.2, 0, 12.8]} />
        <Tree position={[-10.8, 0, 12.5]} />

        <Tree position={[8, 0, -11]} />
        <Tree position={[8.8, 0, -10.2]} />
        <Tree position={[7.2, 0, -10.5]} />

        <Tree position={[19, 0, -5]} />
        <Tree position={[19.8, 0, -4.2]} />
        <Tree position={[18.2, 0, -4.5]} />

        <Tree position={[18, 0, 3]} />
        <Tree position={[18.8, 0, 3.8]} />
        <Tree position={[17.2, 0, 3.5]} />

        <Tree position={[10, 0, 12]} />
        <Tree position={[10.8, 0, 12.8]} />
        <Tree position={[9.2, 0, 12.5]} />

        <Tree position={[-18, 0, 12]} />
        <Tree position={[-17.2, 0, 12.8]} />
        <Tree position={[-18.8, 0, 12.5]} />

        <Tree position={[18, 0, 12]} />
        <Tree position={[18.8, 0, 12.8]} />
        <Tree position={[17.2, 0, 12.5]} />

        <Tree position={[-18, 0, -14]} />
        <Tree position={[-17.2, 0, -13.2]} />
        <Tree position={[-18.8, 0, -13.5]} />

        <Tree position={[18, 0, -14]} />
        <Tree position={[18.8, 0, -13.2]} />
        <Tree position={[17.2, 0, -13.5]} />


        {/* ===== ROAD ===== */}
        <mesh position={[0, 0.02, 8]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[40, 3]} />
          <meshStandardMaterial color="#1a1a1a" roughness={0.9} />
        </mesh>
        {/* Road center dashed line */}
{Array.from({ length: 20 }).map((_, i) => (
  <mesh
    key={i}
    position={[-18 + i * 2, 0.025, 8]}
    rotation={[-Math.PI / 2, 0, 0]}
  >
    <planeGeometry args={[1, 0.15]} />
    <meshStandardMaterial
      color="#ffffff"
      roughness={0.6}
    />
  </mesh>
))}



        {/* ===== walk ===== */}
       <PedestrianPathL
        position={[-7.5, 0.04, 2.8]}
        horizontalLength={4.5}
        verticalLength={3.5}
        direction="right"
      />

      <PedestrianPathL
        position={[7.5, 0.04, 2.8]}
        horizontalLength={4.5}
        verticalLength={3.5}
        direction="left"
      />

        {/* ===== STREET LIGHTS ===== */}
{[-15, -8, 0, 8, 15].map((x, i) => (
  <group key={i} position={[x, 0, 9.5]}
  rotation={[0, Math.PI / 2, 0]}  >

    {/* Pole */}
    <mesh position={[0, 2, 0]} castShadow>
      <cylinderGeometry args={[0.09, 0.12, 4, 16]} />
      <meshStandardMaterial
        color="#4b5563"
        metalness={0.6}
        roughness={0.4}
      />
    </mesh>

    {/* Arm */}
    <mesh position={[0.6, 3.8, 0]} rotation={[0, 0, Math.PI / 2]}>
      <cylinderGeometry args={[0.04, 0.04, 1.2, 12]} />
      <meshStandardMaterial
        color="#4b5563"
        metalness={0.6}
        roughness={0.4}
      />
    </mesh>

    {/* Lamp head */}
    <mesh position={[1.2, 3.8, 0]} castShadow>
      <boxGeometry args={[0.4, 0.15, 0.25]} />
      <meshStandardMaterial
        color="#1f2937"
        metalness={0.7}
        roughness={0.3}
      />
    </mesh>

    {/* Light glass */}
    <mesh position={[1.2, 3.7, 0]}>
      <boxGeometry args={[0.38, 0.05, 0.23]} />
      <meshStandardMaterial
        color="#fde68a"
        emissive="#fde68a"
        emissiveIntensity={0.6}
        transparent
        opacity={0.9}
      />
    </mesh>

    {raining && <Rain />}

    {/* Light */}
    <pointLight
      position={[1.2, 3.6, 0]}
      intensity={raining ? 1.2 : 0.8}
      distance={12}
      decay={2}
      color="#fff7d6"
      castShadow
    />
  </group>
))}

      </Canvas>
    </div>
  );
};

export default Campus3D;
