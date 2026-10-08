# PocketTerm35 - konfiguracja (wypracowana 2026-08-12 na Kali)

## Kluczowe ustalenie
Panel dotykowy Goodix GT911 odpowiada pod adresem I2C **0x5d**.
Oficjalny overlay Waveshare `waveshare-35dpi-4b` deklaruje go pod **0x14**
-> `I2C communication failure: -5`, dotyk nie dziala.
Overlay `5b` ma oba adresy (dziala, ale zawsze failuje na 0x14).
Rozwiazanie: wlasny overlay `pocketterm35-touch.dts` tylko z 0x5d.

## Jak wgrac na swiezy system
1. dtc -@ -I dts -O dtb -o pocketterm35-touch.dtbo pocketterm35-touch.dts
2. skopiowac .dtbo do overlays/ na partycji BOOT
   - Kali/RPi OS: /boot/firmware/overlays/  (NIE /boot/overlays jak pisze Waveshare)
3. dopisac zawartosc config.txt.dopisz na koniec config.txt
4. reboot

## Weryfikacja po boocie
    sudo i2cdetect -y 1          # ma byc 5d
    sudo dmesg | grep -i goodix  # ma byc "ID 911, version: 1060"
    xinput list                  # ma byc "Goodix Capacitive TouchScreen"

## Obrot dotyku (jesli osie przekrecone)
    xinput set-prop "<nazwa>" "Coordinate Transformation Matrix" 0 -1 1 1 0 0 0 0 1   # 90
    # 180: -1 0 1 0 -1 1 0 0 1     270: 0 1 0 -1 0 1 0 0 1     0: 1 0 0 0 1 0 0 0 1
Na stale -> /etc/X11/xorg.conf.d/99-pocketterm-touch.conf

## Sprzet - potwierdzone
- ekran HDMI-1 640x480@75Hz, wykrywa sie sam (bez hdmi_timings)
- klawiatura: "My Company My Custom Pico Keyboard" (RP2040, USB HID) - wymaga tylko dwc2,dr_mode=host
- osobno zglasza sie "Pico Mouse" (przyciski gamingowe)
- glosnik gra przez HDMI, nie przez jack
- dotyk na GPIO2/GPIO3/GPIO4 - nic innego nie moze zajmowac tych pinow
- Fn+C gasi/zapala ekran, Fn+- przyciemnia (obsluga w RP2040)
- AR9271 (Atheros) dziala out of the box, tryb monitor OK, regdomain PL z EEPROM
- UWAGA ZASILANIE: wpiecie drugiej karty WiFi (RTL8812AU) zwalilo zasilanie
  i Pi zresetowalo sie twardo. Na baterii jedna karta naraz.
