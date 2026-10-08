#!/usr/bin/env python3
# report.py — buduje samodzielny raport HTML z wyników autoscan.
# Użycie: report.py <katalog_roboczy> <cel> <audytor> <interfejs>
import sys, os, html, glob, datetime, xml.etree.ElementTree as ET

WORK = sys.argv[1]
TARGET = sys.argv[2] if len(sys.argv) > 2 else "?"
AUDITOR = sys.argv[3] if len(sys.argv) > 3 else "?"
IFACE = sys.argv[4] if len(sys.argv) > 4 else "?"
now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")

def esc(s): return html.escape(str(s))
def readf(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f: return f.read()
    except Exception: return ""

# --- parse nmap xml ---------------------------------------------------------
hosts = []
xmlp = os.path.join(WORK, "nmap.xml")
if os.path.exists(xmlp):
    try:
        root = ET.parse(xmlp).getroot()
    except Exception:
        root = None
    if root is not None:
        for h in root.findall("host"):
            a = h.find("address[@addrtype='ipv4']")
            ip = a.get("addr") if a is not None else "?"
            mac = h.find("address[@addrtype='mac']")
            vendor = mac.get("vendor") if (mac is not None and mac.get("vendor")) else ""
            macaddr = mac.get("addr") if mac is not None else ""
            hn = h.find(".//hostname")
            name = hn.get("name") if hn is not None else ""
            osm = h.find(".//osmatch")
            osname = osm.get("name") if osm is not None else ""
            ports = []
            for p in h.findall(".//port"):
                st = p.find("state")
                if st is None or st.get("state") != "open": continue
                svc = p.find("service")
                name_s = svc.get("name") if svc is not None else ""
                prod = (svc.get("product") if svc is not None else "") or ""
                ver = (svc.get("version") if svc is not None else "") or ""
                scripts = []
                for sc in p.findall("script"):
                    scripts.append((sc.get("id"), sc.get("output") or ""))
                ports.append(dict(port=p.get("portid"), proto=p.get("protocol"),
                                  name=name_s, product=(prod+" "+ver).strip(), scripts=scripts))
            if ports or osname:
                hosts.append(dict(ip=ip, mac=macaddr, vendor=vendor, name=name, os=osname, ports=ports))

# --- zbierz znaleziska vuln (skrypty NSE zaczynające się od vuln/ lub z VULNERABLE) ---
vuln_findings = []
for h in hosts:
    for p in h["ports"]:
        for sid, out in p["scripts"]:
            if "VULNERABLE" in out or sid.startswith(("vulners","vuln","http-vuln","ssl-")):
                sev = "high" if "VULNERABLE" in out else "info"
                vuln_findings.append((h["ip"], p["port"], sid, out.strip(), sev))

# --- pliki per-host (nikto/dirb/testssl) ------------------------------------
def host_files(ip):
    out = {}
    for kind in ("nikto","dirb","testssl"):
        for f in glob.glob(os.path.join(WORK, f"web_{ip}_*_{kind}.txt")):
            out.setdefault(kind, []).append((os.path.basename(f), readf(f)))
    return out

nd = readf(os.path.join(WORK, "netdiscover.txt"))
n_hosts = len(hosts)
n_ports = sum(len(h["ports"]) for h in hosts)
n_vuln = len([v for v in vuln_findings if v[4] == "high"])

# --- HTML -------------------------------------------------------------------
P = []
P.append(f"""<!doctype html><html lang="pl"><head><meta charset="utf-8">
<title>Raport audytu {esc(TARGET)}</title><style>
:root{{--bg:#0e141b;--card:#141c26;--ink:#e6e8ec;--mut:#8a97a4;--line:#223042;--ok:#3ddc84;--warn:#e8b23a;--bad:#e8533a;--acc:#4aa3ff}}
@media print{{:root{{--bg:#fff;--card:#fff;--ink:#111;--mut:#555;--line:#ddd}}body{{background:#fff}}}}
*{{box-sizing:border-box}}body{{margin:0;font-family:'DejaVu Sans',Arial,sans-serif;background:var(--bg);color:var(--ink);font-size:13px;line-height:1.5}}
.wrap{{max-width:1000px;margin:0 auto;padding:28px 22px}}
h1{{font-size:26px;margin:0 0 4px}}h2{{font-size:17px;margin:26px 0 10px;border-bottom:2px solid var(--acc);padding-bottom:5px}}
h3{{font-size:14px;margin:14px 0 6px;color:var(--acc)}}
.meta{{color:var(--mut);font-size:12px}}.acc{{color:var(--acc)}}
.kpis{{display:flex;gap:12px;margin:18px 0}}
.kpi{{flex:1;background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px}}
.kpi b{{display:block;font-size:28px}}.kpi span{{color:var(--mut);font-size:12px}}
.bad b{{color:var(--bad)}}.warn b{{color:var(--warn)}}.ok b{{color:var(--ok)}}
table{{width:100%;border-collapse:collapse;margin:6px 0}}td,th{{border-bottom:1px solid var(--line);padding:6px 8px;text-align:left;vertical-align:top}}
th{{color:var(--mut);font-weight:600;font-size:11px;text-transform:uppercase}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;margin:10px 0}}
.badge{{display:inline-block;padding:2px 8px;border-radius:5px;font-size:11px;font-weight:700}}
.b-high{{background:#3a1512;color:#ff8a6b}}.b-info{{background:#122a3a;color:#6fb7ff}}
pre{{background:#0a0e13;border:1px solid var(--line);border-radius:7px;padding:10px;overflow:auto;font-size:11px;white-space:pre-wrap;color:#cdd6df}}
.mono{{font-family:'DejaVu Sans Mono',monospace}}.note{{color:var(--mut);font-size:11px}}
.disc{{border-left:4px solid var(--warn);background:rgba(232,178,58,.08);padding:8px 12px;border-radius:0 7px 7px 0;margin:14px 0}}
</style></head><body><div class="wrap">""")

P.append(f"""<h1>Raport audytu sieci / serwera</h1>
<div class="meta">Cel: <b class="acc">{esc(TARGET)}</b> · Interfejs: {esc(IFACE)} · Audytor: {esc(AUDITOR)} · {now}</div>
<div class="disc">⚠ Audyt przeprowadzony za zgodą właściciela systemu, w celu podniesienia bezpieczeństwa. Narzędzie: <b>autoscan</b> (PocketTerm35).</div>
<div class="kpis">
 <div class="kpi"><b>{n_hosts}</b><span>żywych hostów</span></div>
 <div class="kpi"><b>{n_ports}</b><span>otwartych portów</span></div>
 <div class="kpi {'bad' if n_vuln else 'ok'}"><b>{n_vuln}</b><span>potwierdzonych podatności</span></div>
</div>""")

# sekcja podatności
if vuln_findings:
    P.append("<h2>🔴 Znaleziska bezpieczeństwa</h2>")
    for ip, port, sid, out, sev in vuln_findings:
        if sev != "high": continue
        P.append(f'<div class="card"><span class="badge b-high">PODATNOŚĆ</span> '
                 f'<b class="mono">{esc(ip)}:{esc(port)}</b> — {esc(sid)}<pre>{esc(out[:4000])}</pre></div>')

# tabela hostów
P.append("<h2>🖥️ Wykryte hosty i usługi</h2>")
for h in hosts:
    head = f'<b class="mono acc">{esc(h["ip"])}</b>'
    if h["name"]: head += f' <span class="note">({esc(h["name"])})</span>'
    if h["os"]: head += f' · OS: {esc(h["os"])}'
    if h["vendor"]: head += f' · {esc(h["vendor"])}'
    P.append(f'<div class="card"><h3 style="margin-top:0">{head}</h3>')
    if h["ports"]:
        P.append("<table><tr><th>Port</th><th>Usługa</th><th>Wersja / produkt</th></tr>")
        for p in h["ports"]:
            P.append(f'<tr><td class="mono">{esc(p["port"])}/{esc(p["proto"])}</td>'
                     f'<td>{esc(p["name"])}</td><td>{esc(p["product"]) or "—"}</td></tr>')
        P.append("</table>")
    # pliki web
    hf = host_files(h["ip"])
    for kind, label in (("testssl","Audyt TLS (testssl)"),("nikto","Nikto (WWW)"),("dirb","Dirb (katalogi)")):
        for fn, content in hf.get(kind, []):
            if content.strip():
                P.append(f'<h3>{label} — <span class="note">{esc(fn)}</span></h3><pre>{esc(content[:6000])}</pre>')
    P.append("</div>")

# --- RED TEAM: searchsploit / wafw00f / hydra ---
ss = readf(os.path.join(WORK, "searchsploit.txt"))
waf = readf(os.path.join(WORK, "wafw00f.txt"))
hyd = readf(os.path.join(WORK, "hydra.txt"))
# hydra "login: x password: y" = złamane poświadczenie
cracked = [l for l in hyd.splitlines() if "login:" in l and "password:" in l]

if ss.strip() or waf.strip() or hyd.strip():
    P.append('<h2>💥 RED TEAM</h2>')
    if cracked:
        P.append('<div class="card"><span class="badge b-high">SŁABE HASŁA</span> '
                 'hydra złamała poświadczenia:<pre>' + esc("\n".join(cracked)) + '</pre></div>')
    if ss.strip():
        has = "VULNERABLE" in ss or any(c.isdigit() for c in ss)
        P.append('<h3>Mapowanie exploitów (searchsploit)</h3>'
                 '<p class="note">Znane exploity pasujące do wykrytych wersji usług. '
                 'Zweryfikuj CVE i załataj.</p>'
                 f'<pre>{esc(ss[:8000])}</pre>')
    if waf.strip():
        P.append(f'<h3>WAF (wafw00f)</h3><pre>{esc(waf[:3000])}</pre>')
    if hyd.strip() and not cracked:
        P.append(f'<h3>Audyt haseł (hydra)</h3><pre>{esc(hyd[:3000])}</pre>')

# netdiscover raw
if nd.strip():
    P.append(f'<h2>📡 netdiscover (ARP)</h2><pre>{esc(nd[:4000])}</pre>')

P.append(f'<h2>ℹ️ Surowe wyniki</h2><p class="note">Pełne logi i pliki .xml/.txt w katalogu raportu obok tego pliku.</p>')
P.append("<p class='note'>Wygenerowano narzędziem autoscan · github.com/altgreen64/pocketterm35</p>")
P.append("</div></body></html>")

outp = os.path.join(WORK, "raport.html")
with open(outp, "w", encoding="utf-8") as f:
    f.write("\n".join(P))
print(f"[report] {outp}  ({n_hosts} hostów, {n_ports} portów, {n_vuln} podatności)")
