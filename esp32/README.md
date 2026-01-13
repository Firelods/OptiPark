# OptiPark - ESP32 Parking Gate Controller

**Supported Targets:** ESP32 | ESP32-C2 | ESP32-C3 | ESP32-C6 | ESP32-H2 | ESP32-S2 | ESP32-S3

## Description

This ESP32 application controls a parking gate system with the following features:
- **IR Parking Occupancy Detection**: Monitors 5 parking spots using infrared sensors
- **Status LED Indicators**: Green (available) and Blue (occupied) LEDs for each spot
- **Servo Gate Control**: Automated gate opening/closing via servo motor
- **MQTT Connectivity**: Publishes parking status and sensor data
- **LCD Display**: 16x2 I2C LCD for QR code validation and user feedback
- **Rain Sensor**: ADC-based rain detection for parking lot conditions

---

## Hardware Configuration

### Parking Spots (5 Sensors)

| Spot ID | IR Sensor Pin | Green LED Pin | Blue LED Pin | Notes |
|---------|---------------|---------------|--------------|-------|
| A-3     | GPIO 32       | GPIO 25       | GPIO 4       | IR active-low |
| A-2     | GPIO 33       | GPIO 26       | GPIO 5       | IR active-low |
| A-20    | GPIO 34       | GPIO 14       | GPIO 18      | IR active-low |
| A-18    | GPIO 35       | GPIO 16       | GPIO 19      | IR active-low |
| A-10    | GPIO 27       | GPIO 17       | GPIO 23      | IR active-low |

**Note:** LED anodes are common (active-low logic: 0 = ON, 1 = OFF)

### Gate Control

| Component | GPIO Pin | Configuration |
|-----------|----------|----------------|
| Servo Motor | GPIO 13 | LEDC Timer 1, Channel 4, 50 Hz, 16-bit resolution |
| Servo Min Pulse | - | 1000 µs (0°) |
| Servo Max Pulse | - | 2000 µs (180°) |
| Gate Open Angle | - | 0° |
| Gate Close Angle | - | 90° |
| Gate Cooldown | - | 5000 ms |

### LCD Display (I2C)

| Component | Connection |
|-----------|-----------|
| LCD Type | 16x2 I2C with PCF8574 Expander |
| I2C Pins | Default SDA/SCL (ESP32 internal) |
| Library | Avinashee LCD I2C Library |

### Rain Sensor (ADC)

| Sensor | ADC Channel | GPIO | Configuration |
|--------|-------------|------|----------------|
| Rain Sensor | ADC1_CH0 | GPIO 36 | 11dB attenuation |
| Wet Threshold | - | 1200 (raw) |
| Dry Threshold | - | 3500 (raw) |
| Active Threshold | - | 2500 (raw) |

---

## MQTT Configuration

### Connection Details

- **Broker URI:** `mqtt://10.111.229.124:1883`
- **Protocol:** TCP MQTT
- **Quality of Service (QoS):** 1 (at least once)
- **Retain Messages:** Enabled
- **Update Interval:** 150 ms

### Published Topics

#### Parking Status Topic
```
parking/nice_sophia.A/status
```

**Message Format (JSON):**
```json
{
  "parking_id": "nice_sophia.A",
  "timestamp": 1234567890,
  "free_spots": 3,
  "occupied_spots": 2,
  "spots": [
    {"id": "A-3", "occupied": true},
    {"id": "A-2", "occupied": false},
    {"id": "A-20", "occupied": true},
    {"id": "A-18", "occupied": false},
    {"id": "A-10", "occupied": false}
  ]
}
```

#### Rain Status Topic
```
parking/rain
```

**Message Format:**
```json
{
  "sensor_id": "rain-1",
  "raining": true,
  "raw_adc": 1500,
  "timestamp": 1234567890
}
```

---

## 🚨 Required Configuration (IMPORTANT!)

Before flashing to the ESP32, you **MUST** update these two configuration parameters in `app_main.c`:

### WiFi Configuration
```c
#define WIFI_SSID "SSID"       // ⚠️  CHANGE TO YOUR WIFI SSID
#define WIFI_PASS "PASSWORD"   // ⚠️  CHANGE TO YOUR WIFI PASSWORD
```

### MQTT Broker Configuration
```c
#define MQTT_URI  "mqtt://BROKER_IP:1883"  // ⚠️  CHANGE TO YOUR BROKER IP:PORT
```

**Location in file:** Lines ~47 and ~57 in `main/app_main.c`

---

## Setup Instructions

### Prerequisites

- **ESP-IDF:** v5.1 or higher
- **ESP32 Board:** Compatible ESP32 development board (e.g., ESP32-DEVKIT-V1)
- **Toolchain:** ESP32 C compiler
- **Python:** 3.7 or higher (for ESP-IDF tools)

### 1. Install ESP-IDF

#### On Windows (PowerShell):
```powershell
# Clone ESP-IDF repository
git clone https://github.com/espressif/esp-idf.git
cd esp-idf

# Run installation script
.\install.bat

# Export environment variables
.\export.bat
```

#### On Linux/macOS:
```bash
git clone https://github.com/espressif/esp-idf.git
cd esp-idf
./install.sh
source ./export.sh
```

### 2. Clone or Navigate to Project

```bash
cd c:\GitHub\OptiPark\esp32
```

### 3. Configure Project

Open the project configuration menu:

```bash
idf.py menuconfig
```

Navigate to:
- **Example Configuration** → Configure broker URL (if needed)
- Set WiFi SSID and password via code (in `app_main.c`)

### 4. Build the Project

```bash
idf.py build
```

### 5. Flash to ESP32 Board

Identify your COM port (Windows) or /dev/ttyUSBX (Linux/macOS):

```bash
idf.py -p COM3 flash monitor
```

**Parameters:**
- `-p COM3`: Serial port (replace with your port)
- `flash`: Flash the compiled binary
- `monitor`: Open serial monitor (view logs in real-time)

**Exit Serial Monitor:** Press `Ctrl + ]`

### 6. Verify Connection

Look for these log messages in serial monitor:

```
I (xxxx) PARKING: WiFi connected
I (xxxx) PARKING: MQTT connected
I (xxxx) PARKING: Servo ready on GPIO13
I (xxxx) PARKING: Starting sensor read loop
```

---

## Project Structure

```
esp32/
├── main/
│   ├── app_main.c          # Main application (gate control, MQTT, sensors)
│   ├── i2c.c / i2c.h       # I2C communication
│   ├── lcd_i2c.c / lcd_i2c.h # LCD driver (PCF8574)
│   ├── CMakeLists.txt      # Build configuration
│   ├── Kconfig.projbuild   # Menu configuration
│   └── idf_component.yml   # Component dependencies
├── build/                  # Build artifacts (generated)
├── CMakeLists.txt          # Project-level CMake configuration
├── README.md               # This file
└── sdkconfig               # Build configuration output
```

---

## Common Issues & Troubleshooting

### Port Not Found
```bash
# List available COM ports
python -m esptool.py list-ports

# Use correct port in flash command
idf.py -p /dev/ttyUSB0 flash monitor  # Linux/macOS
idf.py -p COM3 flash monitor          # Windows
```

### MQTT Connection Failed
- Verify broker IP: `10.111.229.124:1883`
- Check WiFi connection (should see "sta ip:" in logs)
- Ensure firewall allows port 1883

### Sensors Not Responding
- Verify GPIO pins in [Hardware Configuration](#hardware-configuration) section
- Check hardware connections
- Run GPIO tests individually

### LCD Not Displaying
- Verify I2C address (default usually 0x27 or 0x3F)
- Check SDA/SCL connections
- Enable I2C in `menuconfig`

### Build Errors
```bash
# Clean build
idf.py fullclean
idf.py build
```

---

## Development & Reproducibility

### For Code Reproducibility

1. **Version Lock:** All dependencies in `idf_component.yml`
2. **Configuration:** Store `sdkconfig` in version control
3. **Pin Configuration:** All pins defined as constants in `app_main.c`
4. **MQTT Topics:** Centralized in code (search `#define MQTT_TOPIC_`)

### To Reproduce Exact Build

```bash
# Clone repository with locked dependencies
git clone <repo-url>
cd esp32

# Restore exact configuration
cp sdkconfig.ci sdkconfig  # Use CI configuration if available

# Use exact ESP-IDF version (stored in manifest)
idf.py -p COM3 flash monitor
```

### Environment Variables

Ensure these are set before building:
```bash
# Linux/macOS
source /path/to/esp-idf/export.sh

# Windows
C:\path\to\esp-idf\export.bat
```

---

## Deployment Checklist

- [ ] WiFi SSID and password configured in `app_main.c`
- [ ] MQTT broker address verified: `10.111.229.124:1883`
- [ ] Serial port identified and flashed
- [ ] Sensors tested (IR + Rain ADC)
- [ ] Servo motor response verified
- [ ] LCD display working
- [ ] MQTT messages published successfully
- [ ] Serial monitor shows no errors

---

## Support & Resources

- [ESP-IDF Documentation](https://docs.espressif.com/projects/esp-idf/)
- [ESP32 GPIO Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/gpio.html)
- [MQTT Client Library](https://github.com/espressif/esp-idf/tree/master/components/mqtt)
- [LEDC Documentation](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/ledc.html)
