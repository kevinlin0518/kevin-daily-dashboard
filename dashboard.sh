#!/bin/bash

# ============================================
# Kevin's Daily Dashboard — xyz_daily_dashboard
# AESOP-inspired nature theme
# Sources: Fox News, Fox Business, Google News
# Excluded: CNN, BBC, Washington Post
# ============================================

GCAL_ICS_URL=""
OUTPUT="$HOME/Desktop/XYZ/xyz_daily_dashboard/xyz_daily_dashboard.html"
TODAY=$(date '+%Y-%m-%d')
YESTERDAY=$(date -v-1d '+%Y-%m-%d')
TOMORROW=$(date -v+1d '+%Y-%m-%d')

translate_to_zh() {
    local from="${2:-en}"
    local encoded=$(echo "$1" | python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read().strip()))")
    local result=$(curl -s "https://translate.googleapis.com/translate_a/single?client=gtx&sl=${from}&tl=zh-TW&dt=t&q=${encoded}" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(''.join([s[0] for s in d[0]]))" 2>/dev/null)
    [ -n "$result" ] && echo "$result" || echo "$1"
}

fetch_rss() {
    curl -s "$1" 2>/dev/null | python3 -c "
import sys, xml.etree.ElementTree as ET
data = sys.stdin.buffer.read()
try:
    root = ET.fromstring(data)
    skip = ['fox news','fox business','latest','google news','google']
    ban = ['cnn','bbc','washington post','washingtonpost']
    count = 0
    for item in root.findall('.//item'):
        if count >= 5: break
        title = (item.find('title').text or '').strip()
        link = (item.find('link').text or '').strip()
        low = title.lower()
        if not title or any(s in low for s in skip): continue
        if any(b in low for b in ban): continue
        src = item.find('source')
        if src is not None and src.text and any(b in src.text.lower() for b in ban): continue
        print(f'{title}|||{link}')
        count += 1
except: pass
" 2>/dev/null
}

build_section() {
    local title="$1" url="$2" lang="${3:-en}"
    local html="<div class='section'><h2>$title</h2>"
    local items=$(fetch_rss "$url")
    local n=1
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local headline=$(echo "$line" | sed 's/|||.*//')
        local link=$(echo "$line" | sed 's/.*|||//')
        if [ "$lang" != "zh" ]; then
            headline=$(translate_to_zh "$headline" "$lang" | sed 's/ - .*$//')
        else
            headline=$(echo "$headline" | sed 's/ - .*$//')
        fi
        html+="<a href='$link' target='_blank' class='news-link'><span class='num'>$n.</span>$headline</a>"
        n=$((n+1))
    done <<< "$items"
    html+="</div>"
    echo "$html"
}

# ============================================
# CALENDAR — 3 day columns + modal data
# ============================================
GCAL_CACHE=""
if [ -n "$GCAL_ICS_URL" ]; then
    GCAL_CACHE=$(curl -s "$GCAL_ICS_URL" 2>/dev/null)
fi

fetch_day_events() {
    local target="$1"
    if [ -n "$GCAL_CACHE" ]; then
        echo "$GCAL_CACHE" | python3 -c "
import sys
target='${target}'.replace('-','')
data=sys.stdin.read().replace('\r\n ','\r\n\t','')
in_ev=False; cur={}
for line in data.split('\n'):
    line=line.strip()
    if line=='BEGIN:VEVENT': in_ev=True; cur={}
    elif line=='END:VEVENT':
        in_ev=False; dt=cur.get('DTSTART',''); sm=cur.get('SUMMARY','')
        dv=dt.split(':')[-1] if ':' in dt else dt
        dc=dv.replace('-','')
        if dc[:8]==target:
            if 'T' in dc: print(dc.split('T')[1][:2]+':'+dc.split('T')[1][2:4]+'|||'+sm)
            else: print('全天|||'+sm)
    elif in_ev and ':' in line:
        k=line.split(':',1)[0].split(';')[0]; v=line.split(':',1)[1]; cur[k]=v
" 2>/dev/null
    else
        sqlite3 "$HOME/Library/Calendars/Calendar.sqlitedb" "
        SELECT strftime('%H:%M',ci.start_date+978307200,'unixepoch','localtime')||'|||'||ci.summary
        FROM CalendarItem ci
        WHERE date(ci.start_date+978307200,'unixepoch','localtime')='${target}'
        ORDER BY ci.start_date;" 2>/dev/null
    fi
}

build_day_column() {
    local label="$1" date_str="$2" date_disp="$3" is_today="$4"
    local cls="day-col"
    [ "$is_today" = "1" ] && cls="day-col today-col"
    local html="<div class='${cls}'>"
    html+="<div class='day-label'>${label}</div>"
    html+="<div class='day-date'>${date_disp}</div>"
    local events=$(fetch_day_events "$date_str")
    if [ -z "$events" ]; then
        html+="<p class='no-events'>沒有行程</p>"
    else
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local time=$(echo "$line" | cut -d'|' -f1)
            local title=$(echo "$line" | cut -d'|' -f4-)
            html+="<div class='event-row'><span class='ev-time'>${time}</span><span class='ev-title'>${title}</span></div>"
        done <<< "$events"
    fi
    html+="</div>"
    echo "$html"
}

COL1=$(build_day_column "Yesterday" "$YESTERDAY" "$(date -v-1d '+%m/%d %A')" "0")
COL2=$(build_day_column "Today" "$TODAY" "$(date '+%m/%d %A')" "1")
COL3=$(build_day_column "Tomorrow" "$TOMORROW" "$(date -v+1d '+%m/%d %A')" "0")

# Calendar JSON for modal (3 months)
fetch_month_events() {
    local ym="$1"
    if [ -n "$GCAL_CACHE" ]; then
        echo "$GCAL_CACHE" | python3 -c "
import sys
ym='${ym}'.replace('-','')
data=sys.stdin.read().replace('\r\n ','\r\n\t','')
in_ev=False; cur={}
for line in data.split('\n'):
    line=line.strip()
    if line=='BEGIN:VEVENT': in_ev=True; cur={}
    elif line=='END:VEVENT':
        in_ev=False; dt=cur.get('DTSTART',''); sm=cur.get('SUMMARY','')
        dv=dt.split(':')[-1] if ':' in dt else dt
        dc=dv.replace('-','')
        if dc[:6]==ym:
            ds=dc[:4]+'-'+dc[4:6]+'-'+dc[6:8]
            if 'T' in dc: print(f'{ds}|||{dc.split(\"T\")[1][:2]}:{dc.split(\"T\")[1][2:4]}|||{sm}')
            else: print(f'{ds}|||全天|||{sm}')
    elif in_ev and ':' in line:
        k=line.split(':',1)[0].split(';')[0]; v=line.split(':',1)[1]; cur[k]=v
" 2>/dev/null
    else
        sqlite3 "$HOME/Library/Calendars/Calendar.sqlitedb" "
        SELECT date(ci.start_date+978307200,'unixepoch','localtime')||'|||'||
               strftime('%H:%M',ci.start_date+978307200,'unixepoch','localtime')||'|||'||ci.summary
        FROM CalendarItem ci
        WHERE strftime('%Y-%m',ci.start_date+978307200,'unixepoch','localtime')='${ym}'
        ORDER BY ci.start_date;" 2>/dev/null
    fi
}

ALL_EVENTS=$(fetch_month_events "$(date -v-1m '+%Y-%m')")
ALL_EVENTS+=$'\n'
ALL_EVENTS+=$(fetch_month_events "$(date '+%Y-%m')")
ALL_EVENTS+=$'\n'
ALL_EVENTS+=$(fetch_month_events "$(date -v+1m '+%Y-%m')")

CAL_JSON=$(echo "$ALL_EVENTS" | python3 -c "
import sys,json
ev={}
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    p=line.split('|||')
    if len(p)>=3:
        d,t,ti=p[0],p[1],'|||'.join(p[2:])
        if d not in ev: ev[d]=[]
        ev[d].append({'time':t,'title':ti})
print(json.dumps(ev,ensure_ascii=False))
" 2>/dev/null)
[ -z "$CAL_JSON" ] && CAL_JSON="{}"

# ============================================
# WEATHER
# ============================================
WEATHER=$(curl -s "wttr.in/Taipei?format=%t+%C&lang=zh-tw" 2>/dev/null)
WEATHER="${WEATHER:-無法取得}"

# ============================================
# STOCK INDICES
# ============================================
STOCK_HTML=""
declare -a SYMBOLS=("^GSPC" "^N225" "000001.SS" "^TWII")
declare -a NAMES=("S&P 500" "Nikkei 225" "上證指數" "加權指數")
declare -a REGIONS=("美國" "日本" "中國" "台灣")

for i in 0 1 2 3; do
    SYM="${SYMBOLS[$i]}"
    NAME="${NAMES[$i]}"
    REGION="${REGIONS[$i]}"
    DATA=$(curl -s -H "User-Agent: Mozilla/5.0" "https://query1.finance.yahoo.com/v8/finance/chart/${SYM}?interval=1d&range=5d" 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
r=d['chart']['result'][0]; meta=r['meta']
closes=[c for c in r['indicators']['quote'][0]['close'] if c is not None]
if len(closes)>=2: prev=closes[-2]; curr=closes[-1]; chg=((curr-prev)/prev)*100
else: curr=meta.get('regularMarketPrice',0); prev=meta.get('chartPreviousClose',0); chg=((curr-prev)/prev)*100 if prev else 0
arrow='▲' if chg>=0 else '▼'
color='#5B7553' if chg>=0 else '#9B6B6B'
print(f'{curr:,.2f}|||{chg:+.2f}%|||{arrow}|||{color}')
" 2>/dev/null)

    PRICE=$(echo "$DATA" | cut -d'|' -f1)
    CHG=$(echo "$DATA" | cut -d'|' -f4)
    ARROW=$(echo "$DATA" | cut -d'|' -f7)
    COLOR=$(echo "$DATA" | cut -d'|' -f10)

    STOCK_HTML+="<div class='stock-card'>"
    STOCK_HTML+="<span class='stock-region'>$REGION</span>"
    STOCK_HTML+="<span class='stock-name'>$NAME</span>"
    STOCK_HTML+="<span class='stock-price'>$PRICE</span>"
    STOCK_HTML+="<span class='stock-chg' style='color:$COLOR'>$ARROW $CHG</span>"
    STOCK_HTML+="</div>"
done

# ============================================
# NEWS SECTIONS
# ============================================
SEC1=$(build_section "地緣政治與國際局勢" "https://moxie.foxnews.com/google-publisher/world.xml" "en")
SEC2=$(build_section "財經與市場" "https://moxie.foxbusiness.com/google-publisher/latest.xml" "en")
SEC3=$(build_section "AI 與科技" "https://news.google.com/rss/search?q=AI+artificial+intelligence+startup+when:1d+-CNN+-BBC+-site:washingtonpost.com&hl=en-US&gl=US&ceid=US:en" "en")
SEC4=$(build_section "AI 自動化實戰案例" "https://news.google.com/rss/search?q=AI+automation+replace+workflow+business+use+case+when:3d+-CNN+-BBC+-site:washingtonpost.com&hl=en-US&gl=US&ceid=US:en" "en")
SEC5=$(build_section "製造業與供應鏈" "https://news.google.com/rss/search?q=manufacturing+supply+chain+industrial+valve+data+center+cooling+when:3d+-CNN+-BBC+-site:washingtonpost.com&hl=en-US&gl=US&ceid=US:en" "en")
SEC6=$(build_section "美國市場動態" "https://moxie.foxnews.com/google-publisher/us.xml" "en")

# ============================================
# ARCHIVE — scan existing reports
# ============================================
ARCHIVE_DIR="$HOME/Desktop/XYZ/xyz_daily_dashboard/archive"
mkdir -p "$ARCHIVE_DIR"
ARCHIVE_JSON=$(ls "$ARCHIVE_DIR"/*.html 2>/dev/null | while read f; do basename "$f" .html; done | sort | python3 -c "
import sys,json
print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))" 2>/dev/null)
[ -z "$ARCHIVE_JSON" ] && ARCHIVE_JSON="[]"

# ============================================
# GENERATE HTML
# ============================================
cat > "$OUTPUT" << HTMLEOF
<!DOCTYPE html>
<html lang="zh-TW">
<head>
<meta charset="utf-8">
<title>Kevin's Daily</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;}
:root{
  --bg:#F6F3EE;--card:#FFFFFF;--text:#333;--muted:#8A8070;
  --green:#5B7553;--green-light:#E8EFE6;
  --teal:#4A6B7A;--teal-light:#E0EBF0;
  --border:#E5E0D8;--sand:#C4B9A8;
}
body{background:var(--bg);color:var(--text);font-family:-apple-system,"PingFang TC","Helvetica Neue",sans-serif;line-height:1.6;min-height:100vh;}
.nature-bg{position:fixed;inset:0;pointer-events:none;z-index:0;overflow:hidden;}
.leaf{position:absolute;opacity:.05;color:var(--green);}
.leaf svg{width:100%;height:100%;}
.l1{width:80px;top:6%;right:6%;animation:drift 25s ease-in-out infinite;}
.l2{width:55px;top:40%;left:4%;animation:drift 30s ease-in-out infinite reverse;transform:rotate(45deg);}
.l3{width:65px;bottom:10%;right:10%;animation:drift 22s ease-in-out infinite;transform:rotate(-25deg);}
@keyframes drift{0%,100%{transform:translateY(0) rotate(var(--r,0deg));}50%{transform:translateY(-12px) rotate(calc(var(--r,0deg) + 8deg));}}

.container{position:relative;z-index:1;max-width:920px;margin:0 auto;padding:48px 40px 60px;}
header{text-align:center;margin-bottom:36px;}
header h1{font-family:Georgia,"Noto Serif TC",serif;font-size:32px;font-weight:400;letter-spacing:2px;color:var(--text);}
.leaf-accent{display:inline-block;width:20px;height:20px;vertical-align:middle;margin:0 8px;opacity:.35;}

/* === 3 Day Columns === */
.three-days{display:grid;grid-template-columns:repeat(3,1fr);gap:16px;margin-bottom:16px;}
.day-col{background:var(--card);border-radius:14px;padding:24px 22px;box-shadow:0 2px 16px rgba(0,0,0,.05);min-height:120px;}
.day-col.today-col{border:2px solid var(--green);box-shadow:0 4px 20px rgba(91,117,83,.12);}
.day-label{font-family:Georgia,serif;font-size:17px;color:var(--text);letter-spacing:1px;margin-bottom:2px;}
.today-col .day-label{color:var(--green);}
.day-date{font-size:13px;color:var(--muted);margin-bottom:14px;padding-bottom:10px;border-bottom:1px solid var(--border);}
.event-row{display:flex;gap:10px;padding:7px 0;border-bottom:1px solid #F0EBE5;font-size:13.5px;}
.event-row:last-child{border-bottom:none;}
.ev-time{color:var(--green);font-weight:600;white-space:nowrap;min-width:44px;}
.ev-title{color:var(--text);}
.no-events{color:var(--muted);font-size:13px;font-style:italic;}

/* === Browse Button === */
.browse-row{text-align:center;margin-bottom:32px;}
.browse-btn{
  background:none;border:1px solid var(--border);color:var(--muted);
  padding:9px 24px;border-radius:24px;font-size:13px;cursor:pointer;
  transition:all .2s;letter-spacing:1px;font-family:-apple-system,"PingFang TC",sans-serif;
}
.browse-btn:hover{border-color:var(--green);color:var(--green);}

/* === Weather === */
.weather-bar{
  text-align:center;font-size:14px;color:var(--muted);margin-bottom:28px;
  letter-spacing:1px;
}
.weather-bar span{color:var(--text);font-weight:500;}

/* === Stocks === */
.stocks-section{margin-bottom:28px;}
.stocks-section>h2{font-family:Georgia,"Noto Serif TC",serif;font-size:14px;font-weight:400;color:var(--green);letter-spacing:1px;margin-bottom:14px;}
.stocks-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;}
.stock-card{background:var(--card);border-radius:12px;padding:18px 16px;box-shadow:0 2px 12px rgba(0,0,0,.04);display:flex;flex-direction:column;gap:3px;}
.stock-region{font-size:11px;color:var(--muted);letter-spacing:1px;}
.stock-name{font-size:13px;color:var(--text);font-weight:500;}
.stock-price{font-size:20px;font-weight:600;color:var(--text);margin:4px 0 2px;}
.stock-chg{font-size:13px;font-weight:600;}

/* === News === */
.divider{text-align:center;margin:28px 0;color:var(--sand);font-size:13px;letter-spacing:4px;}
.news-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:32px;}
.section{background:var(--card);border-radius:14px;padding:22px 24px;box-shadow:0 2px 12px rgba(0,0,0,.04);}
.section h2{font-family:Georgia,"Noto Serif TC",serif;font-size:13px;font-weight:400;color:var(--green);letter-spacing:1px;margin-bottom:12px;padding-bottom:8px;border-bottom:1px solid var(--border);}
.news-link{display:block;padding:8px 0;color:var(--text);text-decoration:none;font-size:13.5px;line-height:1.6;border-bottom:1px solid #F5F0EA;transition:color .2s;}
.news-link:last-child{border-bottom:none;}
.news-link:hover{color:var(--green);}
.num{color:var(--green);font-weight:600;margin-right:6px;font-size:12px;}

/* === Footer === */
footer{text-align:center;color:var(--muted);font-size:13px;padding-top:24px;border-top:1px solid var(--border);font-family:Georgia,"Noto Serif TC",serif;letter-spacing:1px;}

/* === Modal === */
.modal-overlay{display:none;position:fixed;inset:0;background:rgba(0,0,0,.25);z-index:200;justify-content:center;align-items:center;backdrop-filter:blur(3px);}
.modal-overlay.active{display:flex;}
.modal-box{background:var(--card);border-radius:18px;padding:32px;max-width:500px;width:92%;max-height:85vh;overflow-y:auto;box-shadow:0 12px 48px rgba(0,0,0,.15);position:relative;animation:modalIn .25s ease;}
@keyframes modalIn{from{opacity:0;transform:translateY(16px);}to{opacity:1;transform:translateY(0);}}
.modal-close{position:absolute;top:16px;right:18px;background:none;border:none;font-size:22px;color:var(--muted);cursor:pointer;padding:4px 8px;border-radius:6px;transition:all .2s;}
.modal-close:hover{background:var(--green-light);color:var(--green);}
.modal-title{font-family:Georgia,serif;font-size:16px;color:var(--text);margin-bottom:20px;letter-spacing:1px;}

/* Calendar widget inside modal */
.cal-nav{display:flex;justify-content:space-between;align-items:center;margin-bottom:14px;}
.cal-nav span{font-family:Georgia,serif;font-size:15px;color:var(--text);letter-spacing:1px;}
.cal-nav button{background:none;border:none;font-size:22px;color:var(--muted);cursor:pointer;padding:4px 12px;border-radius:6px;transition:all .2s;}
.cal-nav button:hover{background:var(--green-light);color:var(--green);}
.cal-grid{display:grid;grid-template-columns:repeat(7,1fr);gap:2px;text-align:center;margin-bottom:20px;}
.cal-weekday{font-size:11px;color:var(--muted);padding:6px 0;font-weight:500;}
.cal-date{font-size:13px;padding:9px 4px;border-radius:8px;cursor:pointer;transition:all .2s;position:relative;}
.cal-date:hover{background:var(--green-light);}
.cal-date.empty{cursor:default;}
.cal-date.empty:hover{background:none;}
.cal-date.is-today{background:var(--green);color:#fff;font-weight:600;}
.cal-date.is-today:hover{background:#4A6545;}
.cal-date.is-selected:not(.is-today){background:var(--teal-light);color:var(--teal);font-weight:600;}
.cal-date .dot{position:absolute;bottom:3px;left:50%;transform:translateX(-50%);width:4px;height:4px;border-radius:50%;background:var(--sand);}
.cal-date.is-today .dot{background:rgba(255,255,255,.6);}
.modal-events-title{font-size:13px;color:var(--teal);font-weight:500;margin-bottom:10px;padding-bottom:8px;border-top:1px solid var(--border);padding-top:14px;}
.modal-event-row{display:flex;gap:10px;padding:7px 0;border-bottom:1px solid #F0EBE5;font-size:13.5px;}
.modal-event-row:last-child{border-bottom:none;}
.back-banner{display:none;text-align:center;padding:14px;background:var(--green-light);border-radius:10px;margin-bottom:24px;}
.back-banner a{color:var(--green);text-decoration:none;font-size:13px;letter-spacing:1px;font-weight:500;}
.back-banner a:hover{text-decoration:underline;}
.cal-date.has-archive{background:rgba(91,117,83,.1);}
.cal-date.has-archive.is-today{background:var(--green);}
.cal-date.has-archive.is-selected:not(.is-today){background:var(--teal-light);}
.archive-link{margin-top:14px;padding-top:12px;border-top:1px solid var(--border);text-align:center;}
.archive-link a{color:var(--green);text-decoration:none;font-size:13px;font-weight:500;letter-spacing:1px;}
.archive-link a:hover{text-decoration:underline;}

@media(max-width:768px){
  .container{padding:24px 16px 40px;}
  .three-days,.news-grid{grid-template-columns:1fr;}
  .stocks-grid{grid-template-columns:1fr 1fr;}
}
</style>
</head>
<body>

<div class="nature-bg">
  <div class="leaf l1" style="--r:0deg"><svg viewBox="0 0 40 60"><path d="M20 2C12 14 4 26 4 38c0 12 7 18 16 18s16-6 16-18C36 26 28 14 20 2z" fill="currentColor"/><line x1="20" y1="12" x2="20" y2="52" stroke="rgba(255,255,255,.25)" stroke-width=".6"/></svg></div>
  <div class="leaf l2" style="--r:45deg"><svg viewBox="0 0 40 60"><path d="M20 2C12 14 4 26 4 38c0 12 7 18 16 18s16-6 16-18C36 26 28 14 20 2z" fill="currentColor"/></svg></div>
  <div class="leaf l3" style="--r:-25deg"><svg viewBox="0 0 40 60"><path d="M20 2C12 14 4 26 4 38c0 12 7 18 16 18s16-6 16-18C36 26 28 14 20 2z" fill="currentColor"/></svg></div>
</div>

<div class="container">

<div id="back-banner" class="back-banner">
  <a href="../xyz_daily_dashboard.html">← 返回今天的報告</a>
</div>

<header>
  <h1>
    <svg class="leaf-accent" viewBox="0 0 40 60"><path d="M20 2C12 14 4 26 4 38c0 12 7 18 16 18s16-6 16-18C36 26 28 14 20 2z" fill="#5B7553"/></svg>
    Kevin's Daily
  </h1>
</header>

<div class="weather-bar">台北 · <span>$WEATHER</span></div>

<div class="three-days">
  $COL1
  $COL2
  $COL3
</div>

<div class="browse-row">
  <button class="browse-btn" onclick="openModal()">瀏覽其他日期</button>
</div>

<div class="stocks-section">
  <h2>全球市場</h2>
  <div class="stocks-grid">
    $STOCK_HTML
  </div>
</div>

<div class="divider">- - -</div>

<div class="news-grid">
  $SEC1
  $SEC2
  $SEC3
  $SEC4
  $SEC5
  $SEC6
</div>

<footer><p>祝你有美好的一天</p></footer>

</div>

<!-- Modal -->
<div id="modal" class="modal-overlay" onclick="if(event.target===this)closeModal()">
  <div class="modal-box">
    <button class="modal-close" onclick="closeModal()">&times;</button>
    <div class="modal-title">瀏覽行事曆</div>
    <div id="cal-widget"></div>
    <div id="modal-events"></div>
  </div>
</div>

<script>
const calData =
HTMLEOF

# Part 2: Calendar JSON + JS constants
echo "${CAL_JSON};" >> "$OUTPUT"
echo "const TODAY = '${TODAY}';" >> "$OUTPUT"
echo "let viewYear = $(date '+%Y');" >> "$OUTPUT"
echo "let viewMonth = $((10#$(date '+%m') - 1));" >> "$OUTPUT"
echo "let selectedDate = TODAY;" >> "$OUTPUT"
echo "var archiveDates = ${ARCHIVE_JSON};" >> "$OUTPUT"

# Part 3: JS code (quoted heredoc — no variable expansion)
cat >> "$OUTPUT" << 'JSEOF'

function openModal() {
  document.getElementById('modal').classList.add('active');
  renderCalendar();
  renderModalEvents();
}
function closeModal() {
  document.getElementById('modal').classList.remove('active');
}

function renderCalendar() {
  var first = new Date(viewYear, viewMonth, 1).getDay();
  var days = new Date(viewYear, viewMonth + 1, 0).getDate();
  var offset = (first + 6) % 7;
  var mNames = ['1 月','2 月','3 月','4 月','5 月','6 月','7 月','8 月','9 月','10 月','11 月','12 月'];

  var h = '<div class="cal-nav">';
  h += '<button onclick="changeMonth(-1)">\u2039</button>';
  h += '<span>' + viewYear + ' 年 ' + mNames[viewMonth] + '</span>';
  h += '<button onclick="changeMonth(1)">\u203A</button>';
  h += '</div><div class="cal-grid">';

  var wd = ['一','二','三','四','五','六','日'];
  for (var w = 0; w < 7; w++) h += '<div class="cal-weekday">' + wd[w] + '</div>';
  for (var e = 0; e < offset; e++) h += '<div class="cal-date empty"></div>';

  for (var d = 1; d <= days; d++) {
    var mm = String(viewMonth + 1).padStart(2, '0');
    var dd = String(d).padStart(2, '0');
    var ds = viewYear + '-' + mm + '-' + dd;
    var cls = 'cal-date';
    if (ds === TODAY) cls += ' is-today';
    if (ds === selectedDate) cls += ' is-selected';
    var hasEv = calData[ds] && calData[ds].length > 0;
    if (hasEv) cls += ' has-events';
    if (archiveDates.indexOf(ds) !== -1) cls += ' has-archive';
    h += '<div class="' + cls + '" onclick="pickDate(\'' + ds + '\')">' + d;
    if (hasEv) h += '<span class="dot"></span>';
    h += '</div>';
  }
  h += '</div>';
  document.getElementById('cal-widget').innerHTML = h;
}

function pickDate(ds) {
  selectedDate = ds;
  renderCalendar();
  renderModalEvents();
}

function renderModalEvents() {
  var events = calData[selectedDate] || [];
  var p = selectedDate.split('-');
  var dt = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
  var wk = ['日','一','二','三','四','五','六'];
  var label = p[0] + '/' + p[1] + '/' + p[2] + ' 星期' + wk[dt.getDay()];
  if (selectedDate === TODAY) label += '（今天）';

  var h = '<div class="modal-events-title">' + label + '</div>';
  if (events.length === 0) {
    h += '<p class="no-events">沒有行程</p>';
  } else {
    for (var i = 0; i < events.length; i++) {
      h += '<div class="modal-event-row"><span class="ev-time">' + events[i].time + '</span><span class="ev-title">' + events[i].title + '</span></div>';
    }
  }
  if (archiveDates.indexOf(selectedDate) !== -1) {
    var prefix = location.pathname.indexOf('/archive/') !== -1 ? '' : 'archive/';
    h += '<div class="archive-link"><a href="' + prefix + selectedDate + '.html">查看當日完整報告 \u2192</a></div>';
  }
  document.getElementById('modal-events').innerHTML = h;
}

function changeMonth(delta) {
  viewMonth += delta;
  if (viewMonth > 11) { viewMonth = 0; viewYear++; }
  if (viewMonth < 0) { viewMonth = 11; viewYear--; }
  renderCalendar();
}

if(location.pathname.indexOf('/archive/')!==-1){document.getElementById('back-banner').style.display='block';}
JSEOF

echo "</script></body></html>" >> "$OUTPUT"

# ============================================
# Archive today's report
# ============================================
cp "$OUTPUT" "$ARCHIVE_DIR/${TODAY}.html"

# ============================================
# Push to GitHub Pages
# ============================================
DASH_DIR="$HOME/Desktop/XYZ/xyz_daily_dashboard"
cd "$DASH_DIR"
git add xyz_daily_dashboard.html archive/ 2>/dev/null
git commit -m "Update dashboard ${TODAY}" 2>/dev/null
git push origin main 2>/dev/null

DASHBOARD_URL="https://kevinlin0518.github.io/kevin-daily-dashboard/xyz_daily_dashboard.html"

# ============================================
# Send email with link
# ============================================
osascript << MAILEOF
tell application "Mail"
    set newMsg to make new outgoing message with properties {subject:"Kevin's Daily — ${TODAY}", visible:false}
    tell newMsg
        make new to recipient at end of to recipients with properties {address:"linkevi2@gmail.com"}
        set html content to "<html><body style='font-family:-apple-system,sans-serif;padding:40px;background:#F6F3EE;'><div style='max-width:480px;margin:0 auto;background:#fff;border-radius:14px;padding:32px;box-shadow:0 2px 16px rgba(0,0,0,.06);text-align:center;'><p style='font-family:Georgia,serif;font-size:22px;color:#333;margin-bottom:6px;'>Kevin's Daily</p><p style='color:#8A8070;font-size:14px;margin-bottom:24px;'>${TODAY}</p><a href='${DASHBOARD_URL}' style='display:inline-block;background:#5B7553;color:#fff;padding:12px 32px;border-radius:24px;text-decoration:none;font-size:14px;letter-spacing:1px;'>打開今日報告</a><p style='color:#8A8070;font-size:12px;margin-top:24px;'>祝你有美好的一天</p></div></body></html>"
    end tell
    send newMsg
end tell
MAILEOF

# ============================================
# Notify & Open
# ============================================
osascript -e 'display notification "每日簡報已更新" with title "Kevin'\''s Daily" sound name "Glass"'
open "$OUTPUT"
