import time
import socket
import network
import json
from machine import UART, Pin

# ------------------------- UART -------------------------
UART_PORT = 2
UART_BAUD = 115200
UART_RX_PIN = 14
uart = UART(UART_PORT, baudrate=UART_BAUD, bits=8, parity=None, stop=1, rx=Pin(UART_RX_PIN))

# Data buffers
BUF_N = 200
buf = [0] * BUF_N
buf_i = 0

latest = {
    "ch": 0,
    "raw": 0,
    "frames": 0,
    "bad": 0
}

rxbuf = bytearray()

def uart_poll():
    global buf_i, rxbuf, latest
    data = uart.read(256)
    if data:
        rxbuf += data
    if len(rxbuf) > 4096:
        rxbuf = rxbuf[-2048:]

    i = 0
    while i <= len(rxbuf) - 5:
        if rxbuf[i] == 0xAA and rxbuf[i+1] == 0x55:
            ch = rxbuf[i+2] & 0x03      # lower two bits = channel
            hi = rxbuf[i+3]
            lo = rxbuf[i+4]
            raw16 = (hi << 8) | lo
            raw12 = raw16 >> 4           # 12‑bit value in upper bits
            latest["ch"] = ch
            latest["raw"] = raw12
            latest["frames"] += 1
            buf[buf_i] = raw12
            buf_i = (buf_i + 1) % BUF_N
            i += 5
        else:
            i += 1
    if len(rxbuf) > 4:
        rxbuf = rxbuf[-4:]

# ------------------------- WiFi -------------------------
WIFI_SSID = ""      # leave empty for AP mode
WIFI_PASS = ""

def wifi_connect():
    wlan_sta = network.WLAN(network.STA_IF)
    wlan_ap = network.WLAN(network.AP_IF)
    wlan_sta.active(False)
    wlan_ap.active(False)
    time.sleep_ms(300)

    if WIFI_SSID:
        wlan_sta.active(True)
        time.sleep_ms(300)
        print("Connecting WiFi (STA):", WIFI_SSID)
        try:
            wlan_sta.connect(WIFI_SSID, WIFI_PASS)
        except:
            pass
        t0 = time.ticks_ms()
        while not wlan_sta.isconnected():
            uart_poll()
            time.sleep_ms(250)
            if time.ticks_diff(time.ticks_ms(), t0) > 8000:
                print("STA timeout")
                break
        if wlan_sta.isconnected():
            print("STA connected:", wlan_sta.ifconfig())
            return ("STA", wlan_sta.ifconfig()[0])

    # AP mode fallback
    print("Starting AP mode...")
    wlan_ap.active(True)
    wlan_ap.config(essid="FPGA_SCOPE", password="12345678",
                   authmode=network.AUTH_WPA2_PSK, channel=6, hidden=False)
    time.sleep_ms(500)
    print("AP active:", wlan_ap.ifconfig())
    return ("AP", wlan_ap.ifconfig()[0])

# ------------------------- Web server -------------------------
HTML = """<!DOCTYPE html>
<html>
<head>
    <title>FPGA Internal Sensor Scope</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial; margin:20px; background:#f0f2f5; }
        .container { max-width:1000px; margin:0 auto; }
        .card { background:white; padding:20px; margin:20px 0; border-radius:12px; box-shadow:0 2px 8px rgba(0,0,0,0.1); }
        .row { display:flex; gap:20px; flex-wrap:wrap; }
        .value-box { background:linear-gradient(135deg,#667eea 0%,#764ba2 100%); color:white; padding:15px; border-radius:10px; min-width:200px; flex:1; }
        .value-box .label { font-size:14px; opacity:0.9; }
        .value-box .value { font-size:32px; font-weight:bold; }
        canvas { width:100%; height:auto; background:#fafafa; border-radius:8px; }
        .stat { background:#eef2f6; padding:5px 15px; border-radius:20px; font-size:14px; display:inline-block; margin:5px; }
        .btn-info { background:#e3f2fd; padding:10px; border-radius:8px; margin:10px 0; display:flex; gap:10px; flex-wrap:wrap; }
        .btn { background:#2196F3; color:white; padding:8px 15px; border-radius:20px; font-size:14px; }
    </style>
</head>
<body>
<div class="container">
    <div class="card">
        <h1>🔬 FPGA Internal Sensor Oscilloscope</h1>
        <p>Reads real temperature and voltage rails from the Artix‑7.</p>
        <div class="btn-info">
            <span class="btn">BTN0: Temp</span>
            <span class="btn">BTN1: VCCINT</span>
            <span class="btn">BTN2: VCCAUX</span>
            <span class="btn">BTN3: VCCBRAM</span>
        </div>
        <div class="row">
            <div class="value-box">
                <div class="label" id="ch_name">Channel</div>
                <div class="value" id="ch_val">0</div>
            </div>
            <div class="value-box">
                <div class="label">Raw Value</div>
                <div class="value" id="raw_val">0</div>
            </div>
        </div>
        <div>
            <span class="stat">Frames: <span id="frames">0</span></span>
            <span class="stat">Bad: <span id="bad">0</span></span>
        </div>
    </div>
    <div class="card">
        <h2>Live Waveform (last 200 samples)</h2>
        <canvas id="scope" width="800" height="400"></canvas>
    </div>
</div>
<script>
const ch_names = ["🌡️ Temp", "⚡ VCCINT", "⚡ VCCAUX", "⚡ VCCBRAM"];
const canvas = document.getElementById('scope');
const ctx = canvas.getContext('2d');

function drawPlot(data) {
    const w = canvas.width, h = canvas.height;
    ctx.clearRect(0,0,w,h);
    ctx.strokeStyle = "#2196F3";
    ctx.lineWidth = 2;
    ctx.beginPath();
    for(let i=0; i<data.length; i++) {
        const x = 40 + i*(w-80)/(data.length-1);
        const y = h-40 - (data[i]/4095)*(h-80);
        if(i===0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
    }
    ctx.stroke();
    // axes
    ctx.strokeStyle = "#aaa";
    ctx.beginPath();
    ctx.moveTo(40,20); ctx.lineTo(40,h-20); ctx.lineTo(w-20,h-20);
    ctx.stroke();
}

async function update() {
    try {
        const r = await fetch('/data');
        const j = await r.json();
        document.getElementById('ch_name').innerText = ch_names[j.ch] || "CH"+j.ch;
        document.getElementById('ch_val').innerText = j.ch;
        document.getElementById('raw_val').innerText = j.raw;
        document.getElementById('frames').innerText = j.frames;
        document.getElementById('bad').innerText = j.bad;
        if(j.buf) drawPlot(j.buf);
    } catch(e) { console.log(e); }
}
setInterval(update, 100);
</script>
</body>
</html>
"""

def handle_client(conn):
    try:
        req = conn.recv(1024)
        if not req: return
        uart_poll()
        path = req.split(b' ')[1]
        if path == b'/':
            conn.send(b'HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n' + HTML.encode())
        elif path == b'/data':
            # reorder buffer to show most recent last
            b = buf[buf_i:] + buf[:buf_i]
            payload = {
                "ch": latest["ch"],
                "raw": latest["raw"],
                "frames": latest["frames"],
                "bad": latest["bad"],
                "buf": b
            }
            conn.send(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n' + json.dumps(payload).encode())
        else:
            conn.send(b'HTTP/1.1 404\r\n\r\n')
    except:
        pass
    finally:
        conn.close()

def run_server(host='0.0.0.0', port=80):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((host, port))
    s.listen(2)
    s.settimeout(0.2)
    print("Server listening on", host, port)
    while True:
        try:
            uart_poll()
            conn, addr = s.accept()
            handle_client(conn)
        except OSError:
            pass
        except Exception as e:
            print("Error:", e)

def main():
    print("\n=== FPGA Internal Sensor Oscilloscope ===")
    mode, ip = wifi_connect()
    print("Open http://{}/ in your browser".format(ip))
    run_server()

if __name__ == "__main__":
    main()