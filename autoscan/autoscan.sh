#!/bin/bash
# =============================================================================
#  autoscan — "plug & scan" audytor sieci/serwera dla PocketTerm35
#  Wpinasz PocketTerma kablem LAN do serwera/switcha, a on robi rozpoznanie
#  i generuje raport (HTML + PDF). Narzędzie DEFENSYWNE — dla adminów, którzy
#  chcą sprawdzić własny serwer.
#
#  ⚠️  TYLKO własne sieci albo testy z pisemną zgodą. Nieautoryzowany skan
#      cudzej sieci jest nielegalny.
#
#  Użycie:
#     ./autoscan.sh                 # auto: wykryj kabel+podsieć i skanuj
#     ./autoscan.sh -t 10.0.0.0/24  # ręczny cel (CIDR lub pojedynczy host)
#     ./autoscan.sh -i eth0         # wymuś interfejs
#     ./autoscan.sh --aggressive    # szybszy/głębszy nmap (-T4, pełne porty)
#     ./autoscan.sh --mitm          # DODATKOWO ettercap (AKTYWNE! domyślnie OFF)
#     ./autoscan.sh --yes           # pomiń pytanie o autoryzację (tryb auto)
# =============================================================================
set -u
export PATH="$PATH:/usr/sbin:/sbin:$HOME/.local/bin:/opt/exploitdb"  # sbin, wafw00f, searchsploit
HERE="$(cd "$(dirname "$0")" && pwd)"
CONF="$HERE/autoscan.conf"
[ -f "$CONF" ] && . "$CONF"

# --- ustawienia domyślne (nadpisywane przez autoscan.conf / flagi) ----------
: "${AUTHORIZED:=0}"              # 1 = zgoda na skan (dla trybu auto)
: "${AUDITOR:=$(whoami)}"         # kto przeprowadza audyt (do raportu)
: "${OUTDIR:=$HOME/audyt-raporty}"
: "${NMAP_TIMING:=-T3}"           # kultura skanu (T2=cicho, T4=szybko)
: "${NMAP_PORTS:=--top-ports 1000}"
: "${DO_MITM:=0}"
: "${DIRB_WORDLIST:=/usr/share/dirb/wordlists/common.txt}"
# --- RED TEAM (aktywne techniki) ---
: "${REDTEAM:=0}"                # 1 = włącz moduł red team
: "${REDTEAM_BRUTE:=0}"          # 1 = hydra brute poświadczeń (ryzyko blokady kont!)
: "${HYDRA_USERS:=admin,root,user}"
: "${HYDRA_PASS:=admin,password,root,123456,toor,raspberry,qwerty}"

IFACE=""; TARGET=""; CONFIRM="$AUTHORIZED"
while [ $# -gt 0 ]; do case "$1" in
  -t|--target) TARGET="$2"; shift 2;;
  -i|--iface)  IFACE="$2"; shift 2;;
  --aggressive) NMAP_TIMING="-T4"; NMAP_PORTS="-p-"; shift;;
  --redteam) REDTEAM=1; shift;;
  --brute) REDTEAM=1; REDTEAM_BRUTE=1; shift;;
  --mitm) DO_MITM=1; shift;;
  --yes|-y) CONFIRM=1; shift;;
  -h|--help) sed -n '2,22p' "$0"; exit 0;;
  *) echo "Nieznany argument: $1"; exit 1;;
esac; done

col(){ printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
hr(){ printf '%s\n' "────────────────────────────────────────────────────────"; }
need_root(){ [ "$(id -u)" -eq 0 ] || SUDO="sudo"; }
need_root

# --- wykrycie interfejsu z kablem (carrier UP) ------------------------------
if [ -z "$IFACE" ]; then
  for p in /sys/class/net/*; do
    n="$(basename "$p")"; [ "$n" = "lo" ] && continue
    car="$(cat "$p/carrier" 2>/dev/null)"
    # preferuj kabel (eth/usb), ale dowolny z carrier=1 i IP
    if [ "$car" = "1" ] && ip -4 addr show "$n" | grep -q 'inet '; then IFACE="$n"; break; fi
  done
fi
[ -z "$IFACE" ] && IFACE="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '/dev/{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1);exit}')"

# --- ustalenie celu ---------------------------------------------------------
if [ -z "$TARGET" ]; then
  CIDR="$(ip -4 -o addr show "$IFACE" 2>/dev/null | awk '{print $4}' | head -1)"
  [ -z "$CIDR" ] && { col '1;31' "Brak IP na $IFACE — wepnij kabel LAN albo podaj -t <cel>."; exit 1; }
  # zamień adres hosta na adres sieci (x.y.z.0/24 itp.) przez ipcalc-light
  TARGET="$(python3 -c "import ipaddress,sys;print(ipaddress.ip_network('$CIDR',strict=False))" 2>/dev/null)"
fi

clear 2>/dev/null
col '1;36' "╔══════════════════════════════════════════════════════╗"
col '1;36' "║        autoscan — audyt sieci/serwera (blue team)    ║"
col '1;36' "╚══════════════════════════════════════════════════════╝"
echo "Interfejs : $IFACE"
echo "Cel skanu : $TARGET"
echo "Audytor   : $AUDITOR"
echo "Profil    : nmap $NMAP_TIMING $NMAP_PORTS | RED TEAM=$REDTEAM (brute=$REDTEAM_BRUTE) | MITM=$DO_MITM"
hr

# --- BEZPIECZNIK: autoryzacja ----------------------------------------------
if [ "$CONFIRM" != "1" ]; then
  col '1;33' "⚠  Potwierdź, że masz PRAWO skanować ten cel ($TARGET)."
  read -r -p "   Wpisz TAK aby kontynuować: " ans
  [ "$ans" = "TAK" ] || { col '1;31' "Przerwano — brak potwierdzenia."; exit 1; }
fi

# --- OFERTA / UZBROJENIE RED TEAM -------------------------------------------
if [ "$REDTEAM" != "1" ] && [ -t 0 ]; then
  col '1;31' "💥 Uruchomić także moduł RED TEAM (AKTYWNE: mapowanie exploitów, enum, WAF; brute osobno)?"
  read -r -p "   [t/N]: " rt
  case "$rt" in t|T|tak|TAK|y|Y) REDTEAM=1;; esac
fi
if [ "$REDTEAM" = "1" ] && [ "$CONFIRM" != "1" ]; then
  col '1;31' "⚠  RED TEAM = techniki aktywne. Potwierdź, że to TWÓJ system albo masz pisemną zgodę."
  read -r -p "   Wpisz RED aby uzbroić strzelbę: " r2
  [ "$r2" = "RED" ] || { col '1;33' "Red team OFF — lecę w trybie audytu (nieinwazyjnie)."; REDTEAM=0; }
fi

TS="$(date +%Y%m%d-%H%M%S)"
SAFE="$(echo "$TARGET" | tr '/.' '--')"
WORK="$OUTDIR/audyt-$SAFE-$TS"; mkdir -p "$WORK"
echo "Raport    : $WORK"; hr

# ============================ FAZY SKANU ====================================
# 1) netdiscover — ARP (kto żyje w segmencie)
col '1;32' "[1/5] netdiscover — rozpoznanie ARP…"
if command -v netdiscover >/dev/null; then
  $SUDO timeout 40 netdiscover -i "$IFACE" -r "$TARGET" -P -N 2>/dev/null | tee "$WORK/netdiscover.txt"
else echo "  (netdiscover niezainstalowany — pomijam)"; fi
hr

# 2) nmap ping sweep -> lista żywych hostów
col '1;32' "[2/5] nmap — wykrywanie żywych hostów…"
$SUDO nmap -sn "$NMAP_TIMING" "$TARGET" -oG "$WORK/live.gnmap" | tee "$WORK/ping.txt"
LIVE="$(awk '/Up$/{print $2}' "$WORK/live.gnmap" | tr '\n' ' ')"
[ -z "$LIVE" ] && LIVE="$TARGET"
echo "  Żywe hosty: $LIVE"; hr

# 3) nmap głęboki: usługi, wersje, OS + skrypty NSE
NSE="default,vuln"
[ "$REDTEAM" = "1" ] && NSE="default,vuln,exploit,intrusive,auth"
col '1;32' "[3/5] nmap — usługi / wersje / OS / NSE ($NSE)…"
if [ "$REDTEAM" = "1" ]; then
  col '1;33' "    ⏳ Tryb RED TEAM robi głębokie skrypty (intrusive/auth) — to potrwa"
  col '1;33' "       NAWET KILKANAŚCIE MINUT. To normalne, skan NIE jest zawieszony."
  col '1;90' "       Poniżej leci na żywo postęp i czas do końca (ETC):"
fi
# --stats-every = nmap sam co 15 s wypisuje % done + ETA; streamujemy postęp
# (bez 'tail', który chował output aż do końca i wyglądał jak zwis)
$SUDO nmap "$NMAP_TIMING" $NMAP_PORTS -sV -O --script "$NSE" --stats-every 15s \
     $LIVE -oX "$WORK/nmap.xml" -oN "$WORK/nmap.txt" 2>&1 \
  | stdbuf -oL grep --line-buffered -E "Stats:|% done|Discovered open|Completed .* scan|NSE Timing|Service scan Timing" \
  | sed -u 's/^/    › /'
echo "    ✓ nmap zakończony"
hr

# 4) usługi WWW -> nikto + dirb ; TLS -> testssl
col '1;32' "[4/5] WWW (nikto/dirb) + TLS (testssl) dla serwerów…"
WEB_HOSTS="$(awk '/open/ && /(http|https|8080|8443)/{print $0}' "$WORK/nmap.txt" >/dev/null 2>&1; \
  grep -lE . /dev/null 2>/dev/null; true)"
# wyłuskaj host:port z nmap.txt
python3 - "$WORK/nmap.xml" > "$WORK/web_targets.txt" <<'PY'
import sys,xml.etree.ElementTree as ET
try: r=ET.parse(sys.argv[1]).getroot()
except Exception: sys.exit(0)
for h in r.findall('host'):
    a=h.find("address[@addrtype='ipv4']")
    ip=a.get('addr') if a is not None else None
    if not ip: continue
    for p in h.findall('.//port'):
        st=p.find('state');
        if st is None or st.get('state')!='open': continue
        svc=p.find('service'); name=(svc.get('name') if svc is not None else '') or ''
        port=p.get('portid')
        if 'http' in name or port in ('80','443','8080','8443','8000'):
            tls='s' if ('https' in name or (svc is not None and svc.get('tunnel')=='ssl') or port in('443','8443')) else ''
            print(f"{ip} {port} {tls}")
PY
while read -r ip port tls; do
  [ -z "${ip:-}" ] && continue
  scheme="http"; [ "$tls" = "s" ] && scheme="https"
  base="$WORK/web_${ip}_${port}"
  echo "  → $scheme://$ip:$port"
  command -v nikto >/dev/null && timeout 180 nikto -host "$scheme://$ip:$port" -maxtime 170 > "${base}_nikto.txt" 2>&1
  command -v dirb  >/dev/null && timeout 180 dirb "$scheme://$ip:$port/" "$DIRB_WORDLIST" -S -w > "${base}_dirb.txt" 2>&1
  TESTSSL="$(command -v testssl || command -v testssl.sh)"
  if [ "$tls" = "s" ] && [ -n "$TESTSSL" ]; then
    timeout 180 "$TESTSSL" --quiet --color 0 "$ip:$port" > "${base}_testssl.txt" 2>&1
  fi
done < "$WORK/web_targets.txt"
hr

# R) RED TEAM — mapowanie exploitów / WAF / brute (tylko gdy uzbrojone)
if [ "$REDTEAM" = "1" ]; then
  col '1;31' "[RT] RED TEAM — mapowanie exploitów (searchsploit) / WAF / enum…"
  # produkty+wersje z nmapa -> searchsploit
  SS="$(command -v searchsploit || echo /opt/exploitdb/searchsploit)"
  if [ -x "$SS" ]; then
    python3 - "$WORK/nmap.xml" <<'PY' | sort -u > "$WORK/_products.txt"
import sys,xml.etree.ElementTree as ET
try: r=ET.parse(sys.argv[1]).getroot()
except Exception: sys.exit(0)
for s in r.findall('.//service'):
    prod=s.get('product')
    if prod: print((prod+' '+(s.get('version') or '')).strip())
PY
    : > "$WORK/searchsploit.txt"
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "### $line" >> "$WORK/searchsploit.txt"
      "$SS" --color=never "$line" 2>/dev/null \
        | grep -viE "No Results|---------|Exploit Title" >> "$WORK/searchsploit.txt"
      echo >> "$WORK/searchsploit.txt"
    done < "$WORK/_products.txt"
    echo "  searchsploit: sprawdzono $(grep -c '^###' "$WORK/searchsploit.txt" 2>/dev/null) usług"
  else
    echo "  (searchsploit niegotowy — pomijam mapowanie exploitów)"
  fi
  # wafw00f na serwisach web
  WAF="$(command -v wafw00f || echo "$HOME/.local/bin/wafw00f")"
  if [ -x "$WAF" ] && [ -s "$WORK/web_targets.txt" ]; then
    : > "$WORK/wafw00f.txt"
    while read -r ip port tls; do [ -z "${ip:-}" ] && continue
      sch=http; [ "$tls" = s ] && sch=https
      echo "### $sch://$ip:$port" >> "$WORK/wafw00f.txt"
      timeout 60 "$WAF" "$sch://$ip:$port" >> "$WORK/wafw00f.txt" 2>&1
    done < "$WORK/web_targets.txt"
  fi
  # hydra — TYLKO z --brute (ryzyko blokady kont!)
  if [ "$REDTEAM_BRUTE" = "1" ] && command -v hydra >/dev/null; then
    col '1;31' "  [brute] hydra — audyt słabych haseł ssh/ftp (UWAGA: może blokować konta!)…"
    printf '%s\n' "$HYDRA_USERS" | tr ',' '\n' > "$WORK/_users.txt"
    printf '%s\n' "$HYDRA_PASS"  | tr ',' '\n' > "$WORK/_pass.txt"
    python3 - "$WORK/nmap.xml" <<'PY' > "$WORK/_brute.txt"
import sys,xml.etree.ElementTree as ET
r=ET.parse(sys.argv[1]).getroot()
for h in r.findall('host'):
    a=h.find("address[@addrtype='ipv4']"); ip=a.get('addr') if a is not None else None
    if not ip: continue
    for p in h.findall('.//port'):
        st=p.find('state')
        if st is None or st.get('state')!='open': continue
        port=p.get('portid'); svc=p.find('service'); nm=svc.get('name') if svc is not None else ''
        if port=='22' or nm=='ssh': print(ip,'ssh')
        elif port=='21' or nm=='ftp': print(ip,'ftp')
PY
    : > "$WORK/hydra.txt"
    while read -r ip proto; do [ -z "${ip:-}" ] && continue
      echo "### hydra $proto://$ip" >> "$WORK/hydra.txt"
      timeout 150 hydra -L "$WORK/_users.txt" -P "$WORK/_pass.txt" -t 4 -f \
        "$proto://$ip" 2>/dev/null >> "$WORK/hydra.txt"
    done < "$WORK/_brute.txt"
  else
    echo "  [brute] hydra pominięty (włącz --brute; ryzyko blokady kont)"
  fi
  hr
fi

# 5) (opcjonalnie) ettercap — AKTYWNE, tylko na żądanie
if [ "$DO_MITM" = "1" ] && command -v ettercap >/dev/null; then
  col '1;31' "[5/5] ettercap — pasywny nasłuch 30 s (AKTYWNE!)…"
  $SUDO timeout 30 ettercap -T -q -i "$IFACE" -M arp:remote // // > "$WORK/ettercap.txt" 2>&1 || true
else
  col '1;90' "[5/5] ettercap pominięty (domyślnie OFF; włącz --mitm)."
fi
hr

# ============================ RAPORT ========================================
col '1;32' "Generuję raport HTML…"
python3 "$HERE/report.py" "$WORK" "$TARGET" "$AUDITOR" "$IFACE" || col '1;31' "report.py nie zadziałał"
HTML="$WORK/raport.html"
if [ -f "$HTML" ]; then
  # PDF z tego samego HTML (Chromium headless)
  CHROME="$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable)"
  if [ -n "$CHROME" ]; then
    "$CHROME" --headless --disable-gpu --no-sandbox --no-pdf-header-footer \
      --password-store=basic --use-mock-keychain \
      --print-to-pdf="$WORK/raport.pdf" "file://$HTML" >/dev/null 2>&1 && \
      col '1;32' "PDF: $WORK/raport.pdf"
  fi
  col '1;36' "GOTOWE ✓"
  echo "  HTML: $HTML"
  echo "  Katalog: $WORK"
fi
