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
./autoscan.sh                 # auto: wykryj interfejs + podsieć i skanuj
./autoscan.sh --fast          # SZYBKI AUDYT: top-100 portów, lekkie NSE, bez WWW/TLS
./autoscan.sh -t 10.0.0.5     # konkretny serwer
./autoscan.sh -t 10.0.0.0/24  # cała podsieć
./autoscan.sh --aggressive    # -T4 + wszystkie porty (głębiej, wolniej)
./autoscan.sh --mitm          # DODATKOWO ettercap (AKTYWNE!)
```
Raport ląduje w `~/audyt-raporty/audyt-<cel>-<data>/` jako **`raport.html`**.

## 📶 WiFi czy kabel LAN?

**Sam skan jest tak samo skuteczny po WiFi i po kablu** — nmap i cała reszta robią dokładnie to
samo. autoscan wykrywa aktywny interfejs z adresem IP (kabel *lub* WiFi) i skanuje jego podsieć.
Różnica to **zasięg i pewność**, nie jakość skanu:

- **📶 WiFi wystarcza**, gdy cel jest w tej samej sieci WiFi, do której jesteś podłączony.
  Uruchamiasz z menu albo `-t <IP/CIDR>`.
- **🔌 Kabel LAN** bierzesz, gdy:
  - cel jest w **sieci, której WiFi nie obejmuje** (serwerownia, osobny VLAN, izolowana podsieć),
  - chcesz tryb **„wpiąłem i samo ruszyło"** (auto-trigger niżej — tylko kabel),
  - robisz **duży/ciężki skan** i zależy Ci na stabilności i szybkości,
  - WiFi ma **izolację klientów** (blokuje wykrywanie hostów ARP między urządzeniami).

> Krótko: cel w Twoim WiFi → WiFi starczy. Cel poza zasięgiem WiFi albo ciężki skan → kabel.

## Profile skanu

| Profil | Komenda | Co robi |
|---|---|---|
| ⚡ Szybki | `--fast` | top-100 portów, lekkie NSE, bez WWW/TLS — recon w kilkadziesiąt sekund |
| 🔎 Zwykły | *(brak flag)* | top-1000 portów + NSE `vuln`, nikto/dirb/testssl dla WWW |
| 💪 Głęboki | `--aggressive` | wszystkie porty (`-p-`), wolniej ale dokładniej |
| 💥 Red team | `--redteam` | + searchsploit, WAF, agresywne NSE (`--brute` dokłada hydrę) |

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
sudo cp menu/*.desktop /usr/share/applications/
sudo update-desktop-database /usr/share/applications
```
Pojawią się w **Menu → Pentest → Skanowanie sieci**:
- **Autoscan — szybki audyt ⚡** (błyskawiczny recon)
- **Autoscan — audyt** (nieinwazyjny, pełny recon)
- **Autoscan — RED TEAM 💥** (ofensywa: exploity/WAF/agresywne NSE)
- **Blue Team — utwardzanie serwera 🛡️** (obrona: audyt + auto-łatanie za zgodą)

## Bezpiecznik 🔒
- Bez `AUTHORIZED=1` (config) i bez `--yes` skrypt **pyta o potwierdzenie** („wpisz TAK").
- Dispatcher bez terminala **nie ruszy** skanu, dopóki świadomie nie ustawisz `AUTHORIZED=1`.
- `ettercap`/MITM domyślnie **wyłączone** — audyt jest nieinwazyjny, chyba że sam włączysz `--mitm`.
- W nagłówku raportu jest adnotacja „audyt za zgodą właściciela”.
