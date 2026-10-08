# autoscan — „plug & scan" audytor sieci/serwera 🔌🛡️

Wpinasz PocketTerma kablem LAN do serwera albo switcha — a on **sam** robi rozpoznanie
(hosty, porty, usługi, podatności, WWW, TLS) i generuje **raport HTML**. Narzędzie
**defensywne**, dla adminów, którzy chcą sprawdzić i zabezpieczyć własny serwer.

> ⚠️ **Tylko własne sieci albo audyt z pisemną zgodą.** Nieautoryzowany skan cudzej sieci jest
> nielegalny. Masz tu bezpiecznik (patrz niżej) — używaj go.

## Co robi (fazy)

| Faza | Narzędzie | Po co |
|---|---|---|
| 1 | `netdiscover` | ARP — kto żyje w segmencie |
| 2 | `nmap -sn` | potwierdzenie żywych hostów |
| 3 | `nmap -sV -O --script default,vuln` | porty, usługi, wersje, OS, **podatności (NSE)** |
| 4 | `nikto` + `dirb` + `testssl` | audyt wykrytych serwerów WWW i TLS |
| 5 | `ettercap` *(opcja, OFF)* | MITM — **aktywne**, tylko na `--mitm` |

**OpenVAS** świadomie pominięty — na Raspberry Pi 4 2 GB jest niepraktyczny (feed + baza chcą
~4 GB RAM). Warstwę podatności robią skrypty `vuln` z nmapa + nikto + testssl. (Integrację z
OpenVAS na mocniejszej maszynie można dołożyć później.)

## Instalacja

```bash
# zależności (Debian/RPi OS/Kali)
sudo apt install nmap netdiscover dirb nikto arp-scan xsltproc testssl.sh ettercap-text-only chromium
# żeby autoremove ich nie skasował:
sudo apt-mark manual nmap netdiscover dirb nikto arp-scan testssl.sh ettercap-text-only

# skopiuj katalog autoscan na PocketTerma, np. do ~/pocketterm35/autoscan
chmod +x autoscan.sh report.py
# autoscan.conf jest dołączony (domyślnie AUTHORIZED=0) — dostosuj pod siebie
nano autoscan.conf
```

## Użycie — ręcznie

```bash
./autoscan.sh                 # auto: wykryj kabel + podsieć i skanuj
./autoscan.sh -t 10.0.0.5     # konkretny serwer
./autoscan.sh -t 10.0.0.0/24  # cała podsieć
./autoscan.sh --aggressive    # -T4 + wszystkie porty (głębiej, wolniej)
./autoscan.sh --mitm          # DODATKOWO ettercap (AKTYWNE!)
```
Raport ląduje w `~/audyt-raporty/audyt-<cel>-<data>/` jako **`raport.html`**.

## Użycie — automatycznie po wpięciu kabla (rubber-ducky style)

```bash
# 1. w autoscan.conf ustaw:  AUTHORIZED=1
# 2. zainstaluj trigger NetworkManagera:
sudo cp 99-autoscan /etc/NetworkManager/dispatcher.d/
sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-autoscan
sudo chown root:root /etc/NetworkManager/dispatcher.d/99-autoscan
```
Od teraz: wpinasz kabel → interfejs dostaje adres → audyt rusza sam, raport czeka w
`~/audyt-raporty/`. Log triggera: `~/audyt-raporty/dispatcher.log`.

## 🛡️ Blue Team — utwardzanie serwera (`blueteam.sh`)

Druga strona medalu: **obrona**. Uruchom `blueteam.sh` **na serwerze, który chcesz zabezpieczyć** —
zrobi audyt i **za Twoją zgodą załata typowe dziury**: firewall (ufw), SSH (root login, hasła),
zaległe aktualizacje bezpieczeństwa, fail2ban, automatyczne poprawki. Każda zmiana ma **kopię
zapasową** i wpis w **`undo.sh`** (pełne cofanie). Raport przed/po w HTML.

```bash
./blueteam.sh            # audyt + plan + pytanie o zgodę do każdej poprawki
./blueteam.sh --dry-run  # sam audyt i plan, NIC nie zmienia
./blueteam.sh --auto     # załataj wszystko (po jednym potwierdzeniu TAK)
```
Bezpieczeństwo: firewall **najpierw przepuszcza SSH** (zero lockoutu), zmiany `sshd_config`
są walidowane `sshd -t` przed przeładowaniem, a logowanie hasłem wyłącza się **tylko gdy masz
już klucze SSH**. Wszystko odwracalne przez `undo.sh`.

## 🧩 Wpisy w menu (PocketTerm35 / RPi OS)

Gotowe launchery w [`menu/`](menu/) — skopiuj do aplikacji pulpitu:
```bash
sudo cp menu/autoscan.desktop menu/autoscan-redteam.desktop menu/blueteam.desktop /usr/share/applications/
sudo update-desktop-database /usr/share/applications
```
Pojawią się w **Menu → Pentest → Skanowanie sieci**:
- **Autoscan — audyt** (nieinwazyjny recon)
- **Autoscan — RED TEAM 💥** (ofensywa: exploity/WAF/agresywne NSE)
- **Blue Team — utwardzanie serwera 🛡️** (obrona: audyt + auto-łatanie za zgodą)

## Bezpiecznik 🔒
- Bez `AUTHORIZED=1` (config) i bez `--yes` skrypt **pyta o potwierdzenie** („wpisz TAK").
- Dispatcher bez terminala **nie ruszy** skanu, dopóki świadomie nie ustawisz `AUTHORIZED=1`.
- `ettercap`/MITM domyślnie **wyłączone** — audyt jest nieinwazyjny, chyba że sam włączysz `--mitm`.
- W nagłówku raportu jest adnotacja „audyt za zgodą właściciela”.
