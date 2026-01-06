import { useFrame } from "@react-three/fiber";
import { useRef, useMemo } from "react";
import * as THREE from "three";

const RAIN_COUNT = 1300; // ⬅️ reduced (was probably 2000+)

export default function Rain() {
  const rainRef = useRef<THREE.Points>(null!);

  const positions = useMemo(() => {
    const arr = new Float32Array(RAIN_COUNT * 3);
    for (let i = 0; i < RAIN_COUNT; i++) {
      arr[i * 3]     = (Math.random() - 0.5) * 40; // X
      arr[i * 3 + 1] = Math.random() * 25 + 5;     // Y (spawn higher)
      arr[i * 3 + 2] = (Math.random() - 0.5) * 40; // Z
    }
    return arr;
  }, []);

  useFrame(() => {
    const pos = rainRef.current.geometry.attributes.position.array as Float32Array;

    for (let i = 0; i < RAIN_COUNT; i++) {
      pos[i * 3 + 1] -= 0.38; // ⬅️ slower fall

      if (pos[i * 3 + 1] < 0) {
        pos[i * 3 + 1] = Math.random() * 22 + 8;
      }
    }

    rainRef.current.geometry.attributes.position.needsUpdate = true;
  });

  return (
    <points ref={rainRef}>
      <bufferGeometry>
        <bufferAttribute
          attach="attributes-position"
          array={positions}
          count={positions.length / 3}
          itemSize={3}
        />
      </bufferGeometry>

      <pointsMaterial
        color="#9ca3af"
        size={0.06}          // ⬅️ thinner drops
        transparent
        opacity={0.5}       // ⬅️ lighter rain
        depthWrite={false}
      />
    </points>
  );
}
