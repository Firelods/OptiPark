import { Card } from "@/components/ui/card";
import { Slider } from "@/components/ui/slider";
import { Car } from "lucide-react";

interface ParkingCardProps {
  name: string;
  totalSpaces: number;
  occupiedSpaces: number;
  onOccupiedChange: (value: number) => void;
  position: "left" | "right";
}

const ParkingCard = ({
  name,
  totalSpaces,
  occupiedSpaces,
  onOccupiedChange,
  position,
}: ParkingCardProps) => {
  const availableSpaces = totalSpaces - occupiedSpaces;
  const occupancyRate = (occupiedSpaces / totalSpaces) * 100;

  const getStatusColor = () => {
    if (occupancyRate >= 90) return "bg-parking-full";
    if (occupancyRate >= 70) return "bg-parking-warning";
    return "bg-parking-available";
  };

  const getStatusText = () => {
    if (occupancyRate >= 90) return "Complet";
    if (occupancyRate >= 70) return "Presque plein";
    return "Disponible";
  };

  const getTextColor = () => {
    if (occupancyRate >= 90) return "parking-full";
    if (occupancyRate >= 70) return "parking-warning";
    return "parking-available";
  };

  return (
    <div
      className={`absolute ${
        position === "left" ? "left-[15%]" : "right-[15%]"
      } top-1/2 -translate-y-1/2 w-64`}
    >
      <Card className="p-6 shadow-lg border-2 transition-all duration-300 hover:shadow-xl animate-scale-in">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <div className={`w-3 h-3 rounded-full ${getStatusColor()} animate-pulse-slow`} />
            <h3 className="text-xl font-bold text-foreground">{name}</h3>
          </div>
          <Car className="w-6 h-6 text-muted-foreground" />
        </div>

        <div className="space-y-4">
          <div className="flex justify-between items-baseline">
            <span className="text-3xl font-bold text-foreground">
              {availableSpaces}
            </span>
            <span className="text-sm text-muted-foreground">
              / {totalSpaces} places
            </span>
          </div>

          <div className="flex items-center gap-2">
            <span className={`text-sm font-semibold ${getTextColor()}`}>
              {getStatusText()}
            </span>
            <span className="text-xs text-muted-foreground">
              ({Math.round(occupancyRate)}%)
            </span>
          </div>

          <div className="pt-4 border-t border-border">
            <div className="flex justify-between text-xs text-muted-foreground mb-2">
              <span>Places occupées</span>
              <span>{occupiedSpaces}</span>
            </div>
            <Slider
              value={[occupiedSpaces]}
              onValueChange={(value) => onOccupiedChange(value[0])}
              max={totalSpaces}
              step={1}
              className="w-full"
            />
          </div>
        </div>
      </Card>
    </div>
  );
};

export default ParkingCard;
