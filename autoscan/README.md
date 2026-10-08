# autoscan — „plug & scan" audytor sieci/serwera 🔌🛡️

Wpinasz PocketTerma kablem LAN do serwera albo switcha — a on **sam** robi rozpoznanie
(hosty, porty, usługi, podatności, WWW, TLS) i generuje **raport HTML + PDF**. Narzędzie
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
Raport ląduje w `~/audyt-raporty/audyt-<cel>-<data>/` jako **`raport.html`** i **`raport.pdf`**.

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

## Bezpiecznik 🔒
- Bez `AUTHORIZED=1` (config) i bez `--yes` skrypt **pyta o potwierdzenie** („wpisz TAK").
- Dispatcher bez terminala **nie ruszy** skanu, dopóki świadomie nie ustawisz `AUTHORIZED=1`.
- `ettercap`/MITM domyślnie **wyłączone** — audyt jest nieinwazyjny, chyba że sam włączysz `--mitm`.
- W nagłówku raportu jest adnotacja „audyt za zgodą właściciela”.
