import time
from machine import UART, Pin

uart = UART(2, baudrate=115200, bits=8, parity=None, stop=1, rx=Pin(14))
print("FPGA Internal Sensor Oscilloscope")
print("Press buttons to change channel (0=Temp,1=VCCINT,2=VCCAUX,3=VCCBRAM)")

ch_names = ["Temp", "VCCINT", "VCCAUX", "VCCBRAM"]

while True:
    data = uart.read(256)
    if data:
        for i in range(len(data)-4):
            if data[i] == 0xAA and data[i+1] == 0x55:
                ch = data[i+2]
                hi = data[i+3]
                lo = data[i+4]
                raw16 = (hi << 8) | lo
                raw12 = raw16 >> 4
                if ch < 4:
                    print(f"CH{ch} ({ch_names[ch]}): raw12={raw12:4d}  raw16=0x{raw16:04X}")
                else:
                    print(f"CH{ch}: raw12={raw12}")
    time.sleep_ms(10)