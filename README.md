# PHD-FINAL-PROJECT

# FPGA + ESP32 Oscilloscope

## Overview
This project creates a simple oscilloscope using an **Arty A7-100T FPGA** and an **ESP32 microcontroller**. The FPGA reads its internal sensors (temperature and power supply voltages) using the XADC, sends the data over UART to the ESP32, which then displays live waveforms on a web page.

## Hardware
- **FPGA**: Digilent Arty A7-100T (Artix-7)
- **Microcontroller**: ESP32-WROOM-32E

## Connections
| FPGA Pin | ESP32 Pin |
|----------|-----------|
| JA1 (G13) | GPIO14 (UART RX) |
| GND | GND |

No external analog connections are needed – the FPGA uses its internal temperature and voltage sensors.

## How to Run

### 1. Program the FPGA
1. Open the Vivado project.
2. Generate the bitstream and program the Arty A7.

### 2. Run the ESP32
Copy `main.py` to the ESP32 and run it:

```bash
# Copy the file
mpremote connect COM5 fs cp main.py :main.py

# Run the script
mpremote connect COM5 exec "exec(open('main.py').read())"
```

Replace `COM5` with your ESP32's serial port.

### 3. Connect to the Web Interface
- The ESP32 creates a WiFi access point: **FPGA_SCOPE**
- Password: **12345678**
- Open a browser and go to **http://192.168.4.1**

## Buttons on the Arty A7
Press the four buttons to switch between different internal sensors:

| Button | Measurement |
|--------|-------------|
| BTN0 (North) | Temperature |
| BTN1 (South) | VCCINT (Core Voltage) |
| BTN2 (East) | VCCAUX (Auxiliary Voltage) |
| BTN3 (West) | VCCBRAM (Block RAM Voltage) |

## LEDs on the Arty A7
| LED | Function |
|-----|----------|
| LED0 | Heartbeat (blinking) |
| LED1 | XADC read attempts |
| LED2 | System alive (1 Hz blink) |
| LED3 | UART activity (blinks when sending) |

## How It Works
1. **FPGA**: The XADC reads the selected internal sensor. A UART transmitter sends 5‑byte frames: `AA 55 <channel> <data_hi> <data_lo>`.
2. **ESP32**: Receives the UART data, stores it in a circular buffer, and serves a web page that displays the waveform.
3. **Web Browser**: Polls the ESP32 every 100ms for new data and updates the canvas.

## Files
- `top.v` – FPGA Verilog code
- `main.xdc` – FPGA pin constraints
- `tb_top.v` – Test Bench fro verilog TOP
- `main.py` – ESP32 MicroPython code

## Notes
- The XADC wizard in Vivado must be configured for **single‑channel mode** with **Temperature**, **VCCINT**, **VCCAUX**, and **VCCBRAM** enabled.
- The UART baud rate is 115200.
- The web page shows the last 200 samples.
