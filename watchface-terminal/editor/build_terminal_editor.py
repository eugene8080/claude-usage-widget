# Generates the self-contained "Claude Terminal" layout editor (a single HTML file).
# Same interaction model and upgrades as the Claude Grid editor (watchface-grid/editor):
#   click to select, drag / arrow-key nudge (Shift = 10 px), Tab / Shift+Tab to step through
#   elements, snap-to-align, colour themes (Claude, IV-22, the porttracker VS Code themes), a
#   grouped font menu incl. dot-matrix faces with flash-free loading, a preview time & date,
#   and a VFD style preview (glowing time + full-face mesh) with a glow colour.
# Text is placed exactly as the watch places it: the face draws every line TOP-aligned, and CIQ
# puts a glyph's baseline at line top + font ascent + 1 row. The editor does the same with the
# canvas font metrics (which equal the TTF metrics the watch fonts were generated from), so the
# preview and the simulator agree for any font.
#
# Run:  python build_terminal_editor.py   ->  claude-terminal-editor.html  (next to this file)
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude-terminal-editor.html")

# Same grouping as the Claude Grid editor. Every face has fixed-width digits (a terminal must be
# monospace); the dot-matrix group was checked 2026-09-25 (loads + ten equal digit widths).
FONT_GROUPS = [
 ("Modern / neo-grotesque", ["Chivo Mono","Geist Mono","Reddit Mono","Fragment Mono","Commit Mono",
   "DM Mono","Red Hat Mono","Spline Sans Mono","Martian Mono","Azeret Mono","Roboto Mono"]),
 ("Coding / humanist", ["JetBrains Mono","Fira Code","Fira Mono","Source Code Pro","IBM Plex Mono",
   "Inconsolata","Ubuntu Mono","Ubuntu Sans Mono","Noto Sans Mono","Oxygen Mono","Cousine","PT Mono",
   "Nanum Gothic Coding","Anonymous Pro","Victor Mono"]),
 ("Technical / squared", ["Share Tech Mono","Kode Mono","B612 Mono","Space Mono","Overpass Mono",
   "Lekton","Nova Mono"]),
 ("Typewriter / serif", ["Courier Prime","Cutive Mono","Xanh Mono"]),
 ("Display / novelty", ["Major Mono Display","Syne Mono","Monofett"]),
 ("Dot matrix / pixel / LED", ["Doto","Handjet","Bitcount Grid Double","Bitcount Grid Single",
   "Bitcount Grid Double Ink","Bitcount Single","Bitcount Single Ink","Bitcount","DotGothic16",
   "Press Start 2P","Tiny5","Workbench","Sixtyfour","Sixtyfour Convergence","VT323","Silkscreen"]),
]
_all = [f for _, fs in FONT_GROUPS for f in fs]
assert len(_all) == len(set(_all)), "a font is listed in two groups"
font_groups_js = "[" + ",".join('["%s",[%s]]' % (g, ",".join('"%s"' % f for f in fs))
                                for g, fs in FONT_GROUPS) + "]"

HTML = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude Terminal - editor</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link id="gf-Share-Tech-Mono" href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&display=swap" rel="stylesheet">
<style>
  body{margin:0;background:#141414;color:#ddd;font-family:ui-sans-serif,Segoe UI,Roboto,sans-serif;display:flex;gap:22px;padding:18px;flex-wrap:wrap;}
  h1{font-size:15px;color:#E8A487;margin:0 0 4px;} p.hint{color:#8a8a8a;font-size:12px;margin:0 0 10px;max-width:470px;line-height:1.5;}
  canvas{border-radius:50%;box-shadow:0 0 0 10px #2a2a2a,0 0 0 12px #000;touch-action:none;cursor:grab;}
  .side{flex:1 1 340px;min-width:320px;max-width:450px;}
  .panel{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:12px 15px;margin-bottom:12px;}
  .panel h2{font-size:13px;color:#D97757;margin:0 0 10px;text-transform:uppercase;letter-spacing:.5px;}
  .row{display:flex;align-items:center;gap:10px;margin:8px 0;font-size:12.5px;color:#bbb;}
  .row label{flex:0 0 92px;color:#999;} .row input[type=range]{flex:1;}
  .row .val{flex:0 0 46px;text-align:right;color:#E8A487;font-family:ui-monospace,monospace;}
  select,input[type=color]{background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:4px;font-family:inherit;font-size:12.5px;} select{flex:1;}
  input.hex{width:78px;background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:4px;font-family:ui-monospace,monospace;font-size:12px;}
  button{background:#D97757;color:#111;border:0;border-radius:8px;padding:8px 14px;font-family:inherit;font-weight:bold;cursor:pointer;margin:6px 8px 0 0;} button.sec{background:#333;color:#ddd;}
  textarea{width:100%;height:150px;background:#0c0c0c;border:1px solid #333;border-radius:8px;padding:10px;font-family:ui-monospace,monospace;font-size:11.5px;color:#bfe7d8;}
  .muted{color:#666;font-size:11.5px;} .chk{display:flex;gap:7px;align-items:center;}
</style></head>
<body>
  <div>
    <h1>Claude Terminal - layout editor</h1>
    <p class="hint"><b>Click</b> a line to select it; <b>drag</b> to move (snaps to align) or nudge with
      the <b>arrow keys</b> (Shift = 10 px); <b>Tab</b> / <b>Shift+Tab</b> selects the next / previous.
      Pick a <b>theme</b> or set <b>hex</b> colours, then <b>Copy</b> the block back to me.</p>
    <canvas id="c" width="454" height="454"></canvas>
  </div>
  <div class="side">
    <div class="panel">
      <div class="row"><label style="flex:0 0 40px">Font</label><select id="fontSel"></select></div>
      <div class="row chk"><input type="checkbox" id="snap" checked><label style="flex:0 0 auto">Snap to align (vertical + horizontal)</label></div>
      <div class="row chk"><input type="checkbox" id="secs"><label style="flex:0 0 auto">Show seconds (HH:MM:SS)</label></div>
      <div class="row chk"><input type="checkbox" id="vfd"><label style="flex:0 0 auto" title="glowing bitmap time + one mesh over the whole face">VFD style (glow time + full-face mesh)</label></div>
    </div>
    <div class="panel">
      <h2>Preview time &amp; date</h2>
      <div class="row"><label>Hour</label><input type="range" id="pvH" min="0" max="23" step="1"><span class="val" id="pvHV"></span></div>
      <div class="row"><label>Minute</label><input type="range" id="pvM" min="0" max="59" step="1"><span class="val" id="pvMV"></span></div>
      <div class="row"><label>Second</label><input type="range" id="pvS" min="0" max="59" step="1"><span class="val" id="pvSV"></span></div>
      <div class="row"><label>Day</label><input type="range" id="pvD" min="1" max="31" step="1"><span class="val" id="pvDV"></span></div>
      <div class="row"><label>Month</label><input type="range" id="pvMo" min="1" max="12" step="1"><span class="val" id="pvMoV"></span></div>
      <div class="row chk"><input type="checkbox" id="pv24" checked><label style="flex:0 0 auto">24-hour</label><button class="sec" id="pvNow" style="margin:0 0 0 auto">Now</button></div>
      <div class="muted">Drives the time and the date line. Preview only - not part of the settings block.</div>
    </div>
    <div class="panel">
      <h2>Selected: <span id="selName">- none -</span></h2>
      <div id="ctlText" class="row" style="display:none"><label>Text</label><input type="text" id="txt" maxlength="24" style="flex:1;background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:5px;font-family:inherit;font-size:12.5px"></div>
      <div id="ctlSize" class="row" style="display:none"><label id="sizeLbl">Text px</label><input type="range" id="sizeR" min="10" max="110" step="1"><span class="val" id="sizeRV"></span></div>
      <div id="ctlGap" class="row" style="display:none"><label>Row gap</label><input type="range" id="gapR" min="0.06" max="0.20" step="0.001"><span class="val" id="gapRV"></span></div>
      <div id="ctlLabelX" class="row" style="display:none"><label>Label x</label><input type="range" id="lxR" min="0.04" max="0.40" step="0.001"><span class="val" id="lxRV"></span></div>
      <div id="ctlBarX" class="row" style="display:none"><label>Bar x</label><input type="range" id="bxR" min="0.10" max="0.60" step="0.001"><span class="val" id="bxRV"></span></div>
      <div id="ctlBarW" class="row" style="display:none"><label>Bar width</label><input type="range" id="bwR" min="0.05" max="0.45" step="0.001"><span class="val" id="bwRV"></span></div>
      <div id="ctlBarH" class="row" style="display:none"><label>Bar height</label><input type="range" id="bhR" min="0.01" max="0.09" step="0.001"><span class="val" id="bhRV"></span></div>
      <div id="ctlPctX" class="row" style="display:none"><label>Percent x</label><input type="range" id="pxR" min="0.40" max="0.90" step="0.001"><span class="val" id="pxRV"></span></div>
      <div id="ctlResetX" class="row" style="display:none"><label>Reset x</label><input type="range" id="rxR" min="0.55" max="0.98" step="0.001"><span class="val" id="rxRV"></span></div>
      <div id="ctlCurW" class="row" style="display:none"><label>Cursor w</label><input type="range" id="cwR" min="0.01" max="0.12" step="0.001"><span class="val" id="cwRV"></span></div>
      <div id="ctlCurH" class="row" style="display:none"><label>Cursor h</label><input type="range" id="chR" min="0.01" max="0.09" step="0.001"><span class="val" id="chRV"></span></div>
      <div id="ctlNone" class="muted">Click a line on the watch to edit it.</div>
    </div>
    <div class="panel">
      <h2>Colours</h2>
      <div class="row"><label title="sets every colour below at once; editing any colour switches to Custom">Theme</label><select id="themeSel"></select></div>
      <div class="row"><label>Background</label><input type="color" id="cBg"><input type="text" id="cBgH" class="hex"></div>
      <div class="row"><label title="prompt, bar fill, cursor">Accent</label><input type="color" id="cAcc"><input type="text" id="cAccH" class="hex"></div>
      <div class="row"><label title="time + percent">Value</label><input type="color" id="cVal"><input type="text" id="cValH" class="hex"></div>
      <div class="row"><label title="date, labels, reset">Dim</label><input type="color" id="cDim"><input type="text" id="cDimH" class="hex"></div>
      <div class="row"><label title="empty bar track - neutral dark grey by default">Track</label><input type="color" id="cTrk"><input type="text" id="cTrkH" class="hex"></div>
      <div class="row"><label title="bar fill at 80%+">Cap (80%+)</label><input type="color" id="cCap"><input type="text" id="cCapH" class="hex"></div>
      <div class="row"><label title="VFD style: halo around the time (tools/build_glow_time.py --glow)">Time glow</label><input type="color" id="cGlw"><input type="text" id="cGlwH" class="hex"></div>
    </div>
    <div class="panel">
      <h2>Settings (paste back to me)</h2>
      <textarea id="out" readonly></textarea>
      <button onclick="copyOut()">Copy settings</button><button class="sec" onclick="reset()">Reset</button>
    </div>
  </div>
<script>
const FONT_GROUPS=__FONT_GROUPS__;
const SZ=454, cx=SZ/2;
const ctx=document.getElementById("c").getContext("2d"), out=document.getElementById("out");
// sample meter rows (5-hour, weekly, model), matching the face's three CLI rows
const ROWS=[{lb:"5H",pct:42,rs:"5:30p"},{lb:"1W",pct:63,rs:"Wed"},{lb:"FA",pct:88,rs:"Sep 20"}];

// Colour themes: Claude = the face's palette; IV-22 = measured from the IV-22 tube art; the rest
// use porttracker's chart THEMES hexes. value = foreground, dim = comment grey, accent = the
// theme's highlight, cap = its red (bar fill at 80%+), glow = accent. Track stays neutral grey.
const THEMES=[
 ["claude","Claude",{bg:"#000000",accent:"#D97757",val:"#FFFFFF",dim:"#AAAAAA",track:"#333333",cap:"#FF5F5F",glow:"#D97757"}],
 ["grid-teal","Claude Grid teal",{bg:"#000000",accent:"#1ec693",val:"#ffffff",dim:"#5fcfae",track:"#333333",cap:"#ff6b5b",glow:"#1ec693"}],
 ["iv22","IV-22 (VFD teal)",{bg:"#000000",accent:"#1ec693",val:"#a4f5e1",dim:"#5fcfae",track:"#333333",cap:"#ffb454",glow:"#1ec693"}],
 ["github-dark","GitHub Dark",{bg:"#000000",accent:"#f78166",val:"#e6edf3",dim:"#8b949e",track:"#333333",cap:"#f85149",glow:"#f78166"}],
 ["one-dark","One Dark",{bg:"#000000",accent:"#61afef",val:"#dcdfe4",dim:"#7f848e",track:"#333333",cap:"#e06c75",glow:"#61afef"}],
 ["dracula","Dracula",{bg:"#000000",accent:"#bd93f9",val:"#f8f8f2",dim:"#6272a4",track:"#333333",cap:"#ff5555",glow:"#bd93f9"}],
 ["monokai","Monokai",{bg:"#000000",accent:"#fd971f",val:"#f8f8f2",dim:"#88846f",track:"#333333",cap:"#f92672",glow:"#fd971f"}],
 ["nord","Nord",{bg:"#000000",accent:"#88c0d0",val:"#eceff4",dim:"#7b88a1",track:"#333333",cap:"#bf616a",glow:"#88c0d0"}],
 ["tokyo-night","Tokyo Night",{bg:"#000000",accent:"#7aa2f7",val:"#c0caf5",dim:"#737aa2",track:"#333333",cap:"#f7768e",glow:"#7aa2f7"}],
 ["solarized","Solarized",{bg:"#000000",accent:"#268bd2",val:"#eee8d5",dim:"#839496",track:"#333333",cap:"#dc322f",glow:"#268bd2"}],
 ["synthwave","Synthwave",{bg:"#000000",accent:"#ff7edb",val:"#ffffff",dim:"#848bbd",track:"#333333",cap:"#fe4450",glow:"#ff7edb"}],
 ["night-owl","Night Owl",{bg:"#000000",accent:"#82aaff",val:"#d6deeb",dim:"#7f9c9c",track:"#333333",cap:"#ef5350",glow:"#82aaff"}],
];

function defaults(){return {
  font:"IBM Plex Mono", showSeconds:true, vfd:true, theme:"night-owl",
  bg:"#000000", accent:"#82aaff", val:"#d6deeb", dim:"#7f9c9c", track:"#333333", cap:"#ef5350", glow:"#82aaff",
  el:{
    prompt:{name:"Prompt line", kind:"text", x:0.436, y:0.188, size:26, text:"eugene@tactix ~ $"},
    time:  {name:"Time",        kind:"time", x:0.500, y:0.247, size:70},
    date:  {name:"Date",        kind:"date", x:0.313, y:0.445, size:25},
    rows:  {name:"Meter rows",  kind:"rows", y:0.532, gap:0.113, size:25,
            labelX:0.148, barX:0.242, barW:0.287, barH:0.030, pctX:0.639, resetX:0.858},
    cursor:{name:"Cursor",      kind:"cursor", x:0.526, y:2.000, w:0.030, h:0.028},
  }};}

let P=defaults(), sel=null, guide=null, boxes={};

// Preview clock (sliders). Formats follow the face: hour "%02d" (12 h -> 01-12), date "Fri Sep 25".
const MONTHS=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"], DAYS=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
let PV;
function pvNow(){ const n=new Date(); PV={h:n.getHours(),m:n.getMinutes(),s:n.getSeconds(),day:n.getDate(),mon:n.getMonth()+1,year:n.getFullYear(),h24:PV?PV.h24:true}; }
pvNow();
function pad2(v){ return (v<10?"0":"")+v; }
function daysIn(){ return new Date(PV.year,PV.mon,0).getDate(); }
function previewDate(){ return new Date(PV.year,PV.mon-1,PV.day,PV.h,PV.m,PV.s); }
function HH(){ let h=PV.h; if(!PV.h24){ h=h%12; if(h==0) h=12; } return pad2(h); }
function timeStr(){ return HH()+":"+pad2(PV.m)+(P.showSeconds?":"+pad2(PV.s):""); }
function dateStr(){ const d=previewDate(); return DAYS[d.getDay()]+" "+MONTHS[PV.mon-1]+" "+PV.day; }

function fnt(px){return px+"px '"+P.font+"',monospace";}
function hexRgb(h){ h=(h||"#000000").replace("#",""); return [parseInt(h.slice(0,2),16)||0,parseInt(h.slice(2,4),16)||0,parseInt(h.slice(4,6),16)||0]; }

// Draw text exactly where the watch does. The face draws every line TOP-aligned; CIQ puts the
// glyph baseline at line top + the font's ascent + 1 row (the +1 measured in the simulator). The
// canvas fontBoundingBoxAscent equals that TTF ascent, so this matches the simulator for any font.
// It also resolves position exactly like the face's text() helper: x and top rounded to whole
// pixels, centre/right justification applied as an integer left edge.
function ciqText(s,x,top,align){ ctx.textAlign="left"; ctx.textBaseline="alphabetic";
  const m=ctx.measureText(s), w=Math.round(m.width); let left=Math.round(x);
  if(align=="center") left-=Math.floor(w/2); else if(align=="right") left-=w;
  ctx.fillText(s,left,Math.round(top)+m.fontBoundingBoxAscent+1); return w; }

// The VFD mesh: every third screen row and column darkened 30% (one lattice for the whole face).
const _mesh=document.createElement("canvas"); _mesh.width=3; _mesh.height=3;
{ const m=_mesh.getContext("2d"), d=m.createImageData(3,3); for(let yy=0;yy<3;yy++) for(let xx=0;xx<3;xx++){ const o=(yy*3+xx)*4; d.data[o+3]=(xx==2||yy==2)?77:0; } m.putImageData(d,0,0); }
function meshOverlay(){ ctx.fillStyle=ctx.createPattern(_mesh,"repeat"); ctx.fillRect(0,0,SZ,SZ); }

function drawEl(k){ const e=P.el[k];
  if(e.kind=="text"){ const x=e.x*SZ, y=e.y*SZ; ctx.fillStyle=P.accent; ctx.font=fnt(e.size); const w=ciqText(e.text,x,y,"center");
    boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="time"){ const x=e.x*SZ, y=e.y*SZ, t=timeStr(); ctx.fillStyle=P.val; ctx.font=fnt(e.size);
    if(P.vfd){ const g=hexRgb(P.glow); ctx.save(); ctx.shadowBlur=16; ctx.shadowColor="rgba("+g.join(",")+",0.9)"; ciqText(t,x,y,"center"); ctx.restore(); }
    const w=ciqText(t,x,y,"center"); boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="date"){ const x=e.x*SZ, y=e.y*SZ, t=dateStr(); ctx.fillStyle=P.dim; ctx.font=fnt(e.size); const w=ciqText(t,x,y,"center");
    boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="rows"){ const gy=e.gap*SZ, y0=e.y*SZ; ctx.font=fnt(e.size);
    for(let i=0;i<3;i++){ const y=y0+i*gy, r=ROWS[i];
      ctx.fillStyle=P.dim; ciqText(r.lb, e.labelX*SZ, y, "left");
      // bars on whole pixels, like the face (rect() snaps every edge)
      const bx=Math.round(e.barX*SZ), bw=Math.round(e.barW*SZ), bh=Math.round(e.barH*SZ), by=Math.round(y+0.018*SZ);
      ctx.fillStyle=P.track; ctx.fillRect(bx,by,bw,bh);
      const fw=Math.round(bw*Math.min(100,r.pct)/100); ctx.fillStyle=(r.pct>=80)?P.cap:P.accent; ctx.fillRect(bx,by,fw,bh);
      ctx.fillStyle=P.val; ciqText(r.pct+"%", e.pctX*SZ, y, "right");
      ctx.fillStyle=P.dim; ciqText(r.rs, e.resetX*SZ, y, "right");
    }
    boxes[k]=[e.labelX*SZ-6, y0-6, e.resetX*SZ+6, y0+2*gy+e.size+6]; return; }
  if(e.kind=="cursor"){ const x=e.x*SZ, y=e.y*SZ, w=e.w*SZ, h=e.h*SZ; ctx.fillStyle=P.accent;
    const x0=Math.round(x-w/2), y0=Math.round(y); ctx.fillRect(x0,y0,Math.round(x-w/2+w)-x0,Math.round(y+h)-y0);
    boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+h+4]; return; }
}

function draw(){ P.vfd=document.getElementById("vfd").checked; ctx.fillStyle=P.bg; ctx.fillRect(0,0,SZ,SZ); boxes={};
  ["prompt","time","date","rows","cursor"].forEach(drawEl);
  if(P.vfd) meshOverlay();
  if(sel&&boxes[sel]){ const b=boxes[sel]; ctx.strokeStyle="#D97757"; ctx.lineWidth=1; ctx.setLineDash([4,3]); ctx.strokeRect(b[0],b[1],b[2]-b[0],b[3]-b[1]); ctx.setLineDash([]); }
  if(guide){ ctx.strokeStyle="#39d98a"; ctx.lineWidth=1; ctx.setLineDash([3,3]);
    if(guide.x!=null){ ctx.beginPath(); ctx.moveTo(guide.x,0); ctx.lineTo(guide.x,SZ); ctx.stroke(); }
    if(guide.y!=null){ ctx.beginPath(); ctx.moveTo(0,guide.y); ctx.lineTo(SZ,guide.y); ctx.stroke(); } ctx.setLineDash([]); }
  refresh();
}
function hit(mx,my){ let best=null,bd=1e9; for(const k in boxes){ const b=boxes[k], ix=Math.max(b[0],Math.min(mx,b[2])), iy=Math.max(b[1],Math.min(my,b[3])); const d=(mx-ix)**2+(my-iy)**2; if(d<bd){bd=d;best=k;} } return bd<44*44?best:null; }
function snapAxis(val,others){ let best=val,g=null,bd=0.014; const t=[0.5].concat(others); for(const o of t){ if(Math.abs(val-o)<bd){ bd=Math.abs(val-o); best=o; g=o*SZ; } } return [best,g]; }

let drag=null; const cv=document.getElementById("c");
cv.addEventListener("pointerdown",ev=>{ if(document.activeElement&&document.activeElement!==document.body) document.activeElement.blur(); // arrows -> watch
  const r=cv.getBoundingClientRect(), mx=(ev.clientX-r.left)*SZ/r.width, my=(ev.clientY-r.top)*SZ/r.height; const k=hit(mx,my);
  if(k){ sel=k; drag=k; cv.setPointerCapture(ev.pointerId); cv.style.cursor="grabbing"; syncPanel(); draw(); } });
cv.addEventListener("pointermove",ev=>{ if(!drag)return; const r=cv.getBoundingClientRect(); let nx=Math.max(0.02,Math.min(0.98,(ev.clientX-r.left)/r.width)), ny=Math.max(0.02,Math.min(0.98,(ev.clientY-r.top)/r.height)); guide=null;
  const e=P.el[drag]; const hasX=(e.x!=null);
  if(document.getElementById("snap").checked){ const ox=[],oy=[]; for(const kk in P.el){ if(kk!=drag){ if(P.el[kk].x!=null)ox.push(P.el[kk].x); if(P.el[kk].y!=null)oy.push(P.el[kk].y);} } const sx=snapAxis(nx,ox), sy=snapAxis(ny,oy); nx=sx[0]; ny=sy[0]; guide={x:hasX?sx[1]:null,y:sy[1]}; }
  if(hasX){ e.x=nx; } e.y=ny; draw(); });
cv.addEventListener("pointerup",()=>{ drag=null; guide=null; cv.style.cursor="grab"; draw(); });

// Keyboard: arrows nudge the selection 1 px (Shift = 10 px); Tab / Shift+Tab steps through the
// elements in reading order (top to bottom, from the current positions). Ignored while typing.
function tabOrder(){ return Object.keys(P.el).sort((a,b)=>P.el[a].y-P.el[b].y); }
document.addEventListener("keydown",ev=>{
  const tag=(document.activeElement&&document.activeElement.tagName)||"";
  if(tag=="INPUT"||tag=="SELECT"||tag=="TEXTAREA"||tag=="BUTTON") return;
  if(ev.key=="Tab"){ ev.preventDefault(); const o=tabOrder(); const i=o.indexOf(sel);
    sel=(i<0)?o[ev.shiftKey?o.length-1:0]:o[(i+(ev.shiftKey?-1:1)+o.length)%o.length]; syncPanel(); draw(); return; }
  if(!sel) return;
  const d={ArrowLeft:[-1,0],ArrowRight:[1,0],ArrowUp:[0,-1],ArrowDown:[0,1]}[ev.key]; if(!d) return;
  ev.preventDefault(); const step=ev.shiftKey?10:1, e=P.el[sel], clamp=v=>Math.max(0.02,Math.min(0.98,v));
  if(e.x!=null) e.x=clamp(e.x+d[0]*step/SZ); e.y=clamp(e.y+d[1]*step/SZ); draw();
});

// Font menu (grouped) with flash-free switching: keep drawing in the current font until the new
// one has loaded, apply only the latest pick, prefetch the rest in the background.
const fontSel=document.getElementById("fontSel");
FONT_GROUPS.forEach(([label,list])=>{ const g=document.createElement("optgroup"); g.label=label;
  list.forEach(f=>{ const o=document.createElement("option"); o.value=f; o.textContent=f; g.appendChild(o); }); fontSel.appendChild(g); });
const _fontCss={};
function fontCss(name){
  if(!_fontCss[name]){ _fontCss[name]=new Promise(res=>{ const id="gf-"+name.replace(/ /g,'-');
    let l=document.getElementById(id);
    if(!l){ l=document.createElement("link"); l.id=id; l.rel="stylesheet"; l.href="https://fonts.googleapis.com/css2?family="+name.replace(/ /g,"+")+"&display=swap"; document.head.appendChild(l); }
    else if(l.sheet){ res(); return; }
    l.addEventListener("load",()=>res()); l.addEventListener("error",()=>res()); setTimeout(res,4000); }); }
  return _fontCss[name]; }
function fontLoaded(name){ return fontCss(name).then(()=> document.fonts&&document.fonts.load ? document.fonts.load("40px '"+name+"'").catch(()=>{}) : null); }
let fontReq=0;
function setFont(name){ const my=++fontReq; const apply=()=>{ if(my!==fontReq) return; P.font=name; draw(); };
  const giveUp=setTimeout(apply,5000); fontLoaded(name).then(()=>{ clearTimeout(giveUp); apply(); }); }
function prefetchFonts(){ const all=[].concat(...FONT_GROUPS.map(g=>g[1])); let i=0;
  const next=()=>{ if(i>=all.length) return; const f=all[i++]; fontLoaded(f).then(()=>setTimeout(next,40)); }; next(); next(); }
fontSel.onchange=function(){ setFont(this.value); };

function show(id,on){ document.getElementById(id).style.display=on?"flex":"none"; }
function setR(rid,vid,val,dp){ document.getElementById(rid).value=val; document.getElementById(vid).textContent=dp?(+val).toFixed(dp):(""+Math.round(val)); }
function syncPanel(){ const e=sel?P.el[sel]:null;
  document.getElementById("selName").textContent=e?e.name:"- none -";
  document.getElementById("ctlNone").style.display=e?"none":"block";
  const isRows=e&&e.kind=="rows", isCur=e&&e.kind=="cursor";
  show("ctlText",e&&e.kind=="text");
  show("ctlSize",e&&(e.kind=="text"||e.kind=="time"||e.kind=="date"||isRows));
  show("ctlGap",isRows); show("ctlLabelX",isRows); show("ctlBarX",isRows); show("ctlBarW",isRows);
  show("ctlBarH",isRows); show("ctlPctX",isRows); show("ctlResetX",isRows);
  show("ctlCurW",isCur); show("ctlCurH",isCur);
  if(!e)return;
  document.getElementById("sizeLbl").textContent=(e.kind=="time")?"Time px":"Text px";
  if(e.size!=null){ var sR=document.getElementById("sizeR"); if(e.kind=="time"){sR.min=30;sR.max=110;}else{sR.min=10;sR.max=60;} setR("sizeR","sizeRV",e.size,0); }
  if(e.kind=="text") document.getElementById("txt").value=e.text;
  if(isRows){ setR("gapR","gapRV",e.gap,3); setR("lxR","lxRV",e.labelX,3); setR("bxR","bxRV",e.barX,3); setR("bwR","bwRV",e.barW,3); setR("bhR","bhRV",e.barH,3); setR("pxR","pxRV",e.pctX,3); setR("rxR","rxRV",e.resetX,3); }
  if(isCur){ setR("cwR","cwRV",e.w,3); setR("chR","chRV",e.h,3); }
}
function bindR(rid,vid,dp,fn){ document.getElementById(rid).oninput=function(){ fn(+this.value); document.getElementById(vid).textContent=dp?(+this.value).toFixed(dp):(""+Math.round(+this.value)); draw(); }; }
bindR("sizeR","sizeRV",0,v=>{ if(sel)P.el[sel].size=v; });
bindR("gapR","gapRV",3,v=>{ if(sel)P.el[sel].gap=v; });
bindR("lxR","lxRV",3,v=>{ if(sel)P.el[sel].labelX=v; });
bindR("bxR","bxRV",3,v=>{ if(sel)P.el[sel].barX=v; });
bindR("bwR","bwRV",3,v=>{ if(sel)P.el[sel].barW=v; });
bindR("bhR","bhRV",3,v=>{ if(sel)P.el[sel].barH=v; });
bindR("pxR","pxRV",3,v=>{ if(sel)P.el[sel].pctX=v; });
bindR("rxR","rxRV",3,v=>{ if(sel)P.el[sel].resetX=v; });
bindR("cwR","cwRV",3,v=>{ if(sel)P.el[sel].w=v; });
bindR("chR","chRV",3,v=>{ if(sel)P.el[sel].h=v; });
document.getElementById("txt").oninput=function(){ if(sel&&P.el[sel].kind=="text"){ P.el[sel].text=this.value; draw(); } };
document.getElementById("secs").onchange=function(){ P.showSeconds=this.checked; draw(); };
document.getElementById("vfd").onchange=draw;

// Preview time & date sliders
function syncPV(){ document.getElementById("pvD").max=daysIn(); if(PV.day>daysIn()) PV.day=daysIn();
  setR("pvH","pvHV",PV.h,0); document.getElementById("pvHV").textContent=HH()+(PV.h24?"":(PV.h<12?"a":"p"));
  setR("pvM","pvMV",PV.m,0); document.getElementById("pvMV").textContent=pad2(PV.m);
  setR("pvS","pvSV",PV.s,0); document.getElementById("pvSV").textContent=pad2(PV.s);
  setR("pvD","pvDV",PV.day,0); setR("pvMo","pvMoV",PV.mon,0); document.getElementById("pvMoV").textContent=MONTHS[PV.mon-1].toUpperCase();
  document.getElementById("pv24").checked=PV.h24; }
[["pvH","h"],["pvM","m"],["pvS","s"],["pvD","day"],["pvMo","mon"]].forEach(([id,key])=>{ document.getElementById(id).oninput=function(){ PV[key]=+this.value; syncPV(); draw(); }; });
document.getElementById("pv24").onchange=function(){ PV.h24=this.checked; syncPV(); draw(); };
document.getElementById("pvNow").onclick=function(){ pvNow(); syncPV(); draw(); };

// Colours + themes
const themeSel=document.getElementById("themeSel");
THEMES.concat([["custom","Custom",null]]).forEach(([k,l])=>{ const o=document.createElement("option"); o.value=k; o.textContent=l; themeSel.appendChild(o); });
function applyTheme(k){ const th=THEMES.find(t=>t[0]==k); if(!th) return; Object.assign(P,th[2]); P.theme=k; themeSel.value=k; linkAllColours(); draw(); }
themeSel.onchange=function(){ if(this.value!="custom") applyTheme(this.value); else { P.theme="custom"; draw(); } };
function markCustom(){ P.theme="custom"; themeSel.value="custom"; }
function linkVal(pid,hid,val){ document.getElementById(pid).value=val; document.getElementById(hid).value=val; }
function bindColor(pid,hid,set){ const p=document.getElementById(pid), h=document.getElementById(hid);
  p.oninput=()=>{ h.value=p.value; set(p.value); markCustom(); draw(); };
  h.oninput=()=>{ let v=h.value.trim(); if(!/^#/.test(v)) v="#"+v; if(/^#[0-9a-fA-F]{6}$/.test(v)){ p.value=v; set(v); markCustom(); draw(); } }; }
bindColor("cBg","cBgH",v=>P.bg=v); bindColor("cAcc","cAccH",v=>P.accent=v); bindColor("cVal","cValH",v=>P.val=v);
bindColor("cDim","cDimH",v=>P.dim=v); bindColor("cTrk","cTrkH",v=>P.track=v); bindColor("cCap","cCapH",v=>P.cap=v); bindColor("cGlw","cGlwH",v=>P.glow=v);
function linkAllColours(){ linkVal("cBg","cBgH",P.bg); linkVal("cAcc","cAccH",P.accent); linkVal("cVal","cValH",P.val); linkVal("cDim","cDimH",P.dim); linkVal("cTrk","cTrkH",P.track); linkVal("cCap","cCapH",P.cap); linkVal("cGlw","cGlwH",P.glow); }

function refresh(){ const e=P.el; let L=[
  "font: "+P.font, "theme: "+P.theme, "style: "+(P.vfd?"VFD (glow time + full-face mesh)":"plain"), "showSeconds: "+P.showSeconds,
  "bg: "+P.bg+"  accent: "+P.accent+"  value: "+P.val+"  dim: "+P.dim+"  track: "+P.track+"  cap: "+P.cap+"  glow: "+P.glow, "",
  "prompt  x="+e.prompt.x.toFixed(3)+" y="+e.prompt.y.toFixed(3)+"  size="+e.prompt.size+"  text=\""+e.prompt.text+"\"",
  "time    x="+e.time.x.toFixed(3)+" y="+e.time.y.toFixed(3)+"  size="+e.time.size,
  "date    x="+e.date.x.toFixed(3)+" y="+e.date.y.toFixed(3)+"  size="+e.date.size,
  "rows    y="+e.rows.y.toFixed(3)+" gap="+e.rows.gap.toFixed(3)+" size="+e.rows.size
    +"  labelX="+e.rows.labelX.toFixed(3)+" barX="+e.rows.barX.toFixed(3)+" barW="+e.rows.barW.toFixed(3)
    +" barH="+e.rows.barH.toFixed(3)+" pctX="+e.rows.pctX.toFixed(3)+" resetX="+e.rows.resetX.toFixed(3),
  "cursor  x="+e.cursor.x.toFixed(3)+" y="+e.cursor.y.toFixed(3)+"  w="+e.cursor.w.toFixed(3)+" h="+e.cursor.h.toFixed(3),
]; out.value=L.join("\n"); }
function copyOut(){ out.select(); document.execCommand("copy"); }
function reset(){ P=defaults(); sel=null; guide=null; themeSel.value=P.theme; document.getElementById("vfd").checked=P.vfd;
  document.getElementById("fontSel").value=P.font; document.getElementById("secs").checked=P.showSeconds; linkAllColours(); syncPanel(); setFont(P.font); }

linkAllColours(); syncPV(); themeSel.value=P.theme;
document.getElementById("vfd").checked=P.vfd; document.getElementById("secs").checked=P.showSeconds;
document.getElementById("fontSel").value=P.font; syncPanel(); setFont(P.font); setTimeout(prefetchFonts,1500);
</script></body></html>"""
HTML = HTML.replace("__FONT_GROUPS__", font_groups_js)
open(OUT, "w", encoding="utf-8").write(HTML)
print("wrote", OUT, os.path.getsize(OUT), "bytes")
