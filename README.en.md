![PocketTerm35](assets/banner.png)

# PocketTerm35 — configuration & scripts

🇵🇱 [Wersja polska / Polish version](README.md)

A set of files that gets the **Waveshare PocketTerm35** handheld (Raspberry Pi based) fully
working — touchscreen, keyboard, and a few handy tools — plus my WiFi-security learning scripts.

Target hardware: **Raspberry Pi 4** inside a PocketTerm35 case, running **Raspberry Pi OS / Debian**
(works on Kali too). 3.5" 640×480 screen, Goodix GT911 touch, RP2040-based keyboard.

> ⚠️ **Legal / ethical note.** The tools in [`pentest/`](pentest/) are for learning security and
> testing **only on your own networks**, or where you have written permission. Unauthorized access
> to networks you don't own is illegal. Use at your own risk.

---

## What's inside

| Folder / file | What it is |
|---|---|
| [`pocketterm35/`](pocketterm35/) | Hardware config: touch overlay, `config.txt` additions, **mousekeys.py** (CapsLock → mouse) |
| [`scripts/restart-klawiatury.sh`](scripts/restart-klawiatury.sh) | Reset a frozen keyboard (RP2040) |
| [`pentest/`](pentest/) | WiFi security learning scripts + the **pwnpet** tool |

---

## 1. Touchscreen — setup (MOST IMPORTANT)

On this unit the Goodix GT911 touch panel answers at I2C address **0x5d**, while Waveshare's
official overlay `waveshare-35dpi-4b` looks for it at **0x14** → touch doesn't work. The fix is a
tiny custom overlay that declares only `0x5d`.

```bash
cd pocketterm35
# 1. build the overlay
dtc -@ -I dts -O dtb -o pocketterm35-touch.dtbo pocketterm35-touch.dts
# 2. copy to the BOOT partition (RPi OS & Kali: /boot/firmware, NOT /boot as Waveshare says)
sudo cp pocketterm35-touch.dtbo /boot/firmware/overlays/
# 3. append config.txt.dopisz to the end of /boot/firmware/config.txt
cat config.txt.dopisz | sudo tee -a /boot/firmware/config.txt
# 4. reboot
sudo reboot
```

Verify after reboot (details & axis rotation in [`pocketterm35/README.md`](pocketterm35/README.md)):
```bash
sudo i2cdetect -y 1          # should show 5d
sudo dmesg | grep -i goodix  # should show "ID 911"
```

## 2. CapsLock as a mouse (mousekeys.py)

Press **CapsLock** and the arrow keys move the cursor like a mouse; **L / R** are left / right
click. Press CapsLock again to exit the mode (the CapsLock LED shows the state).

```bash
# dependency
sudo apt install python3-evdev
# run manually (test)
python3 pocketterm35/mousekeys.py
```

**Autostart on every boot** (ready-made systemd unit):
```bash
sudo cp pocketterm35/mousekeys.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mousekeys.service
```
> The unit's script path is `/home/pi/pocketterm35/mousekeys.py` — adjust if you keep it elsewhere.
> Also, `SOURCE_DEV` in `mousekeys.py` points to a specific Pico keyboard serial (`by-id/...`) —
> replace it with yours if different (`ls /dev/input/by-id/`).

## 3. Reset a frozen keyboard

The PocketTerm keyboard can go dead after sitting unused for a while — the RP2040 chip hangs.
The script tries to recover it in software (USB re-enumeration / exiting bootloader); if that
fails, it prints the only reliable fix (full power-cycle).

```bash
bash scripts/restart-klawiatury.sh
```

## 4. Pentest tools

See [`pentest/README.md`](pentest/README.md) — WiFi card management and the **pwnpet** network
monitor. **Your own networks / authorized tests only.**

---

License: [MIT](LICENSE). Waveshare photos/firmware are not part of this repo.
