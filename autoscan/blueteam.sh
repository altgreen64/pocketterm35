#!/bin/bash
# =============================================================================
#  blueteam.sh — BLUE TEAM: audyt + utwardzanie serwera (z Twoją zgodą)
#  Uruchom NA serwerze, który chcesz zabezpieczyć. Łata typowe dziury:
#  firewall, SSH, aktualizacje bezpieczeństwa, fail2ban, auto-poprawki.
#
#  ⚠️  Zmienia konfigurację systemu — ale TYLKO za Twoją zgodą, z kopią
#      zapasową każdego pliku i skryptem cofania (undo.sh). Zabezpieczone
#      przed odcięciem się od serwera (firewall najpierw przepuszcza SSH,
#      zmiany sshd walidowane przez `sshd -t`).
#
#  Użycie:
#    ./blueteam.sh            # audyt + plan + pytanie o zgodę (interaktywnie)
#    ./blueteam.sh --dry-run  # SAM audyt + plan, NIC nie zmienia
#    ./blueteam.sh --auto     # zastosuj wszystkie poprawki (po 1 potwierdzeniu)
# =============================================================================
set -u
export PATH="$PATH:/usr/sbin:/sbin"
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
MODE="interactive"
case "${1:-}" in
  --dry-run|-n) MODE="dry";;
  --auto|-a)    MODE="auto";;
  -h|--help) sed -n '2,20p' "$0"; exit 0;;
esac

TS="$(date +%Y%m%d-%H%M%S)"
OUT="$HOME/audyt-raporty/blueteam-$TS"
BK="$OUT/backup"; mkdir -p "$BK"
UNDO="$OUT/undo.sh"
{ echo '#!/bin/bash'; echo '# Cofanie zmian wprowadzonych przez blueteam.sh'; echo 'set -u; SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"'; } > "$UNDO"
chmod +x "$UNDO"

col(){ printf "\033[%sm%s\033[0m\n" "$1" "$2"; }
hr(){ printf '%s\n' "──────────────────────────────────────────────────────"; }
undo_add(){ echo "$1" >> "$UNDO"; }

# findings: równoległe tablice
F_NAME=(); F_SEV=(); F_STATE=(); F_FIX=(); F_FN=(); F_RESULT=()
add(){ F_NAME+=("$1"); F_SEV+=("$2"); F_STATE+=("$3"); F_FIX+=("$4"); F_FN+=("$5"); F_RESULT+=("-"); }

SSH_PORT="$(grep -oiP '^\s*Port\s+\K[0-9]+' /etc/ssh/sshd_config 2>/dev/null | head -1)"; [ -z "$SSH_PORT" ] && SSH_PORT=22
HAS_KEYS=0; [ -s "$HOME/.ssh/authorized_keys" ] && HAS_KEYS=1

clear 2>/dev/null
col '1;34' "╔══════════════════════════════════════════════════════╗"
col '1;34' "║     BLUE TEAM — audyt i utwardzanie serwera          ║"
col '1;34' "╚══════════════════════════════════════════════════════╝"
echo "Host: $(hostname)   Tryb: $MODE   Port SSH: $SSH_PORT"
echo "Kopie zapasowe + undo: $OUT"
hr

# ======================= AUDYT (wykrywanie dziur) ===========================
col '1;36' "Audyt systemu…"

# 1) Aktualizacje bezpieczeństwa
$SUDO apt-get update -qq >/dev/null 2>&1
SECU="$(apt-get -s upgrade 2>/dev/null | grep -ciE '\-security|security\.debian|Debian-Security')"
UPG="$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst')"
if [ "${UPG:-0}" -gt 0 ]; then
  add "Aktualizacje" "wysoka" "$UPG pakietów do aktualizacji ($SECU bezpieczeństwa)" \
      "apt upgrade (poprawki bezpieczeństwa)" "apply_updates"
else
  add "Aktualizacje" "ok" "system aktualny" "" ""
fi

# 2) Firewall (ufw)
if command -v ufw >/dev/null; then
  if $SUDO ufw status 2>/dev/null | grep -qi "Status: active"; then
    add "Firewall (ufw)" "ok" "włączony" "" ""
  else
    add "Firewall (ufw)" "wysoka" "WYŁĄCZONY — serwer bez zapory" \
        "włącz ufw (najpierw przepuść SSH $SSH_PORT), domyślnie deny incoming" "apply_ufw"
  fi
else
  add "Firewall" "srednia" "ufw niezainstalowany" "zainstaluj i włącz ufw" "apply_ufw_install"
fi

# 3) SSH — logowanie roota
RPL="$(grep -oiP '^\s*PermitRootLogin\s+\K\S+' /etc/ssh/sshd_config 2>/dev/null | head -1)"
if [ "${RPL,,}" = "no" ]; then
  add "SSH root login" "ok" "PermitRootLogin no" "" ""
else
  add "SSH root login" "wysoka" "root może logować się po SSH (${RPL:-domyślnie})" \
      "PermitRootLogin no" "apply_ssh_noroot"
fi

# 4) SSH — hasła (tylko rekomendacja jeśli brak kluczy, by nie odciąć dostępu)
PAUTH="$(grep -oiP '^\s*PasswordAuthentication\s+\K\S+' /etc/ssh/sshd_config 2>/dev/null | head -1)"
if [ "${PAUTH,,}" = "no" ]; then
  add "SSH hasła" "ok" "PasswordAuthentication no (tylko klucze)" "" ""
elif [ "$HAS_KEYS" = "1" ]; then
  add "SSH hasła" "srednia" "logowanie hasłem włączone (masz klucze)" \
      "PasswordAuthentication no — tylko klucze SSH" "apply_ssh_nopass"
else
  add "SSH hasła" "info" "logowanie hasłem włączone; BRAK kluczy SSH" \
      "najpierw dodaj klucz SSH, potem wyłącz hasła (nie ruszam automatycznie)" ""
fi

# 5) fail2ban
if command -v fail2ban-client >/dev/null && systemctl is-active fail2ban >/dev/null 2>&1; then
  add "fail2ban" "ok" "aktywny (ochrona przed brute-force)" "" ""
else
  add "fail2ban" "srednia" "brak ochrony przed brute-force SSH" \
      "zainstaluj i włącz fail2ban" "apply_fail2ban"
fi

# 6) Automatyczne aktualizacje bezpieczeństwa
if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && \
   grep -rqs 'Unattended-Upgrade::Allowed-Origins\|APT::Periodic::Unattended-Upgrade "1"' /etc/apt/apt.conf.d/ 2>/dev/null; then
  add "Auto-poprawki" "ok" "unattended-upgrades włączone" "" ""
else
  add "Auto-poprawki" "srednia" "brak automatycznych poprawek bezpieczeństwa" \
      "włącz unattended-upgrades" "apply_unattended"
fi

# ======================= FUNKCJE NAPRAWCZE (z backupem) =====================
backup_file(){ # $1 = ścieżka
  [ -f "$1" ] || return 0
  local dst="$BK$(echo "$1" | tr '/' '_')"
  $SUDO cp -a "$1" "$dst" 2>/dev/null
  undo_add "\$SUDO cp -a '$dst' '$1'"
}

apply_updates(){ $SUDO DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-confold upgrade; }

apply_ufw_install(){ $SUDO apt-get install -y ufw && apply_ufw; }
apply_ufw(){
  command -v ufw >/dev/null || { $SUDO apt-get install -y ufw || return 1; }
  $SUDO ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1   # NAJPIERW SSH — brak lockoutu
  $SUDO ufw default deny incoming  >/dev/null 2>&1
  $SUDO ufw default allow outgoing >/dev/null 2>&1
  $SUDO ufw --force enable
  undo_add "\$SUDO ufw disable"
}

apply_ssh_noroot(){
  backup_file /etc/ssh/sshd_config
  if grep -qiE '^\s*#?\s*PermitRootLogin' /etc/ssh/sshd_config; then
    $SUDO sed -i -E 's/^\s*#?\s*PermitRootLogin.*/PermitRootLogin no/I' /etc/ssh/sshd_config
  else
    echo "PermitRootLogin no" | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
  fi
  $SUDO sshd -t 2>/dev/null && $SUDO systemctl reload ssh 2>/dev/null || $SUDO systemctl reload sshd 2>/dev/null
  undo_add "\$SUDO systemctl reload ssh 2>/dev/null || \$SUDO systemctl reload sshd 2>/dev/null"
}

apply_ssh_nopass(){
  backup_file /etc/ssh/sshd_config
  if grep -qiE '^\s*#?\s*PasswordAuthentication' /etc/ssh/sshd_config; then
    $SUDO sed -i -E 's/^\s*#?\s*PasswordAuthentication.*/PasswordAuthentication no/I' /etc/ssh/sshd_config
  else
    echo "PasswordAuthentication no" | $SUDO tee -a /etc/ssh/sshd_config >/dev/null
  fi
  $SUDO sshd -t 2>/dev/null && { $SUDO systemctl reload ssh 2>/dev/null || $SUDO systemctl reload sshd 2>/dev/null; }
  undo_add "\$SUDO systemctl reload ssh 2>/dev/null || \$SUDO systemctl reload sshd 2>/dev/null"
}

apply_fail2ban(){
  $SUDO apt-get install -y fail2ban || return 1
  $SUDO systemctl enable --now fail2ban
  undo_add "\$SUDO systemctl disable --now fail2ban"
}

apply_unattended(){
  $SUDO apt-get install -y unattended-upgrades || return 1
  echo 'APT::Periodic::Update-Package-Lists "1";'  | $SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
  echo 'APT::Periodic::Unattended-Upgrade "1";'    | $SUDO tee -a /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
  undo_add "\$SUDO rm -f /etc/apt/apt.conf.d/20auto-upgrades"
}

# ======================= PLAN + ZGODA + NAPRAWA =============================
hr
col '1;36' "Wynik audytu:"
NFIX=0
for i in "${!F_NAME[@]}"; do
  case "${F_SEV[$i]}" in
    ok) c='1;32'; tag="[OK]  ";;
    wysoka) c='1;31'; tag="[!!!] "; [ -n "${F_FN[$i]}" ] && NFIX=$((NFIX+1));;
    srednia) c='1;33'; tag="[ ! ] "; [ -n "${F_FN[$i]}" ] && NFIX=$((NFIX+1));;
    *) c='1;90'; tag="[ i ] ";;
  esac
  col "$c" "  $tag${F_NAME[$i]}: ${F_STATE[$i]}"
  [ -n "${F_FIX[$i]}" ] && echo "         → poprawka: ${F_FIX[$i]}"
done
hr
echo "Do załatania: $NFIX pozycji."

run_fix(){ # $1 = index
  local fn="${F_FN[$1]}"; [ -z "$fn" ] && return 0
  col '1;34' "   ⚙ Łatam: ${F_NAME[$1]}…"
  if "$fn"; then F_RESULT[$1]="naprawione"; col '1;32' "   ✓ ${F_NAME[$1]} — OK";
  else F_RESULT[$1]="błąd"; col '1;31' "   ✗ ${F_NAME[$1]} — nie udało się"; fi
}

if [ "$MODE" = "dry" ]; then
  col '1;33' "Tryb --dry-run: NIC nie zmieniam. Powyżej masz plan."
elif [ "$NFIX" -eq 0 ]; then
  col '1;32' "Nie ma czego łatać — serwer wygląda solidnie. 👍"
else
  APPLY_ALL=0
  if [ "$MODE" = "auto" ]; then
    col '1;31' "⚠  Tryb --auto zastosuje WSZYSTKIE poprawki. To zmienia konfigurację systemu."
    read -r -p "   Wpisz TAK aby załatać wszystko (kopie zapasowe + undo.sh zostaną zrobione): " a
    [ "$a" = "TAK" ] && APPLY_ALL=1 || { col '1;33' "Przerwano."; MODE="dry"; }
  fi
  if [ "$MODE" != "dry" ]; then
    for i in "${!F_NAME[@]}"; do
      [ -z "${F_FN[$i]}" ] && continue
      if [ "$APPLY_ALL" = "1" ]; then run_fix "$i"
      else
        echo; col '1;37' "Pozycja: ${F_NAME[$i]} — ${F_STATE[$i]}"
        echo "   poprawka: ${F_FIX[$i]}"
        read -r -p "   Zastosować? [t/N]: " yn
        case "$yn" in t|T|tak|TAK|y|Y) run_fix "$i";; *) F_RESULT[$i]="pominięto";; esac
      fi
    done
  fi
fi
hr

# ======================= RAPORT HTML + PDF =================================
HTML="$OUT/raport-blueteam.html"
{
echo "<!doctype html><html lang=pl><head><meta charset=utf-8><title>Blue Team — $(hostname)</title><style>
:root{--bg:#0e141b;--card:#141c26;--ink:#e6e8ec;--mut:#8a97a4;--line:#223042;--ok:#3ddc84;--warn:#e8b23a;--bad:#e8533a;--acc:#4aa3ff}
@media print{:root{--bg:#fff;--card:#fff;--ink:#111;--mut:#555;--line:#ddd}}
body{margin:0;font-family:'DejaVu Sans',Arial,sans-serif;background:var(--bg);color:var(--ink);font-size:13px}
.w{max-width:900px;margin:0 auto;padding:26px}h1{font-size:25px;margin:0 0 4px}h2{font-size:16px;border-bottom:2px solid var(--acc);padding-bottom:5px;margin-top:22px}
.meta{color:var(--mut);font-size:12px}table{width:100%;border-collapse:collapse;margin:8px 0}td,th{border-bottom:1px solid var(--line);padding:7px 9px;text-align:left}
th{color:var(--mut);font-size:11px;text-transform:uppercase}.b{font-weight:700}
.s-wysoka{color:var(--bad)}.s-srednia{color:var(--warn)}.s-ok{color:var(--ok)}.s-info{color:var(--mut)}
.r-naprawione{color:var(--ok);font-weight:700}.r-pominięto{color:var(--mut)}.r-błąd{color:var(--bad)}
.disc{border-left:4px solid var(--ok);background:rgba(61,220,132,.08);padding:8px 12px;border-radius:0 7px 7px 0;margin:12px 0}</style></head><body><div class=w>"
echo "<h1>🛡️ Blue Team — raport utwardzania</h1>"
echo "<div class=meta>Host: <b>$(hostname)</b> · Tryb: $MODE · $(date '+%Y-%m-%d %H:%M')</div>"
echo "<div class=disc>Zmiany wykonane za zgodą administratora. Kopie zapasowe i skrypt cofania: <b>$OUT</b> (uruchom <b>undo.sh</b> aby cofnąć).</div>"
echo "<h2>Audyt i poprawki</h2><table><tr><th>Obszar</th><th>Waga</th><th>Stan</th><th>Poprawka</th><th>Wynik</th></tr>"
for i in "${!F_NAME[@]}"; do
  echo "<tr><td class=b>${F_NAME[$i]}</td><td class=s-${F_SEV[$i]}>${F_SEV[$i]}</td><td>${F_STATE[$i]}</td><td>${F_FIX[$i]:-—}</td><td class=r-${F_RESULT[$i]}>${F_RESULT[$i]}</td></tr>"
done
echo "</table><p class=meta>Wygenerowano narzędziem blueteam.sh · github.com/altgreen64/pocketterm35</p></div></body></html>"
} > "$HTML"

col '1;36' "GOTOWE ✓"
echo "  Raport : $HTML"
[ -s "$UNDO" ] && echo "  Cofanie: $UNDO  (uruchom, by przywrócić poprzedni stan)"
if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] && command -v xdg-open >/dev/null; then
  col '1;32' "  📄 Otwieram raport w przeglądarce…"
  xdg-open "$HTML" >/dev/null 2>&1 &
fi
# NIE zamykaj terminala od razu — daj zobaczyć wynik
if [ -t 0 ]; then echo; read -r -p "↩  Naciśnij Enter, aby zamknąć terminal…"; fi
