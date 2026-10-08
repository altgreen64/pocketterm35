#!/bin/bash
# restart-klawiatury.sh — próba zresetowania klawiatury PocketTerm35 (układ RP2040)
# bez pełnego power-cycle. Jeśli to nie pomoże, skrypt poda jedyny pewny sposób.
#
# Dlaczego to bywa potrzebne: klawiatura PocketTerma to układ RP2040 zgłaszający się jako USB HID.
# Po dłuższym leżakowaniu potrafi się zawiesić i nie reagować, mimo że USB się enumeruje.
set -u
echo "== Restart klawiatury PocketTerm35 (RP2040) =="

# 1) Czy RP2040 wpadł w tryb bootloader (np. ktoś wcisnął tylny przycisk BOOTSEL)?
if lsusb | grep -qi "2e8a:0003"; then
  echo "[!] RP2040 jest w trybie bootloader (widoczny jako RPI-RP2)."
  if command -v picotool >/dev/null 2>&1; then
    echo "    -> picotool reboot (powrót do firmware klawiatury)"
    sudo picotool reboot -f && { echo "    OK — poczekaj ~5 s"; sleep 5; }
  else
    echo "    -> zainstaluj picotool i zresetuj:"
    echo "       sudo apt install picotool && sudo picotool reboot -f"
  fi
fi

# 2) Znajdź port USB klawiatury Pico i spróbuj re-enumeracji (unbind/bind)
KBD_PRODUCT="$(grep -il 'Pico' /sys/bus/usb/devices/*/product 2>/dev/null | head -1)"
if [ -n "${KBD_PRODUCT:-}" ]; then
  DEV="$(basename "$(dirname "$KBD_PRODUCT")")"
  echo "[*] Pico na porcie USB: $DEV — re-enumeruję (unbind/bind)"
  echo -n "$DEV" | sudo tee /sys/bus/usb/drivers/usb/unbind >/dev/null 2>&1
  sleep 1
  echo -n "$DEV" | sudo tee /sys/bus/usb/drivers/usb/bind   >/dev/null 2>&1
  sleep 2
else
  echo "[*] Nie znalazłem portu Pico po USB (może już zniknął z magistrali)."
fi

# 3) Weryfikacja
if grep -q "Pico Keyboard" /proc/bus/input/devices 2>/dev/null; then
  echo "[OK] Klawiatura widoczna jako urządzenie wejściowe — powinno działać."
  exit 0
fi

cat <<'EOF'

[!] Klawiatura nadal nie odpowiada.
    RP2040 siedzi na module zasilania/UPS — reboot Pi ani reset USB go NIE resetują.
    JEDYNY pewny fix to PEŁNY POWER-CYCLE:
      1. sudo poweroff   (albo wyłącz system)
      2. odłącz kabel USB-C
      3. przełącznik zasilania na OFF
      4. odczekaj 30-60 sekund (RP2040 musi stracić zasilanie na zimno)
      5. włącz z powrotem — NIE dotykając tylnych przycisków (to RESET i BOOTSEL!)
EOF
exit 1
