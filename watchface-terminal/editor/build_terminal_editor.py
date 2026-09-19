# Generates the self-contained "Claude Terminal" layout editor (a single HTML file).
# Mirrors the Claude Grid editor's interaction model - click to select, drag to move (snaps to
# centre), sliders for sizes/columns, hex colour pickers - but for the terminal face's elements:
# a prompt line, the time, the date, three CLI meter rows, and the blinking cursor.
#
# Run:  python build_terminal_editor.py   ->  claude-terminal-editor.html  (next to this file)
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude-terminal-editor.html")

# Monospace-only families (a terminal must be mono). All are genuine mono faces on Google Fonts.
FONTS = ["JetBrains Mono","Roboto Mono","Space Mono","Fira Code","Fira Mono","Source Code Pro",
 "IBM Plex Mono","Inconsolata","Ubuntu Mono","Ubuntu Sans Mono","PT Mono","Cousine","Courier Prime",
 "Overpass Mono","Nova Mono","Share Tech Mono","VT323","Major Mono Display","Xanh Mono","Spline Sans Mono",
 "Martian Mono","DM Mono","Red Hat Mono","Noto Sans Mono","B612 Mono","Azeret Mono","Anonymous Pro",
 "Cutive Mono","Fragment Mono","Syne Mono","Kode Mono","Oxygen Mono","Victor Mono","Lekton","Chivo Mono",
 "Reddit Mono","Geist Mono","Commit Mono","Nanum Gothic Coding","Doto","Sixtyfour","Silkscreen","Monofett"]
fonts_js = "[" + ",".join('"%s"' % f for f in FONTS) + "]"

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
    <p class="hint"><b>Click</b> a line to select it, <b>drag</b> to move (snaps to centre). Tune
      sizes + the meter columns with the sliders, set <b>hex</b> colours, then <b>Copy</b> the
      block back to me and I'll build it into the face.</p>
    <canvas id="c" width="454" height="454"></canvas>
  </div>
  <div class="side">
    <div class="panel">
      <div class="row"><label style="flex:0 0 40px">Font</label><select id="fontSel"></select></div>
      <div class="row chk"><input type="checkbox" id="snap" checked><label style="flex:0 0 auto">Snap to align (vertical + horizontal)</label></div>
      <div class="row chk"><input type="checkbox" id="secs"><label style="flex:0 0 auto">Show seconds (HH:MM:SS)</label></div>
    </div>
    <div class="panel">
      <h2>Selected: <span id="selName">- none -</span></h2>
      <div id="ctlText" class="row" style="display:none"><label>Text</label><input type="text" id="txt" style="flex:1;background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:5px;font-family:inherit;font-size:12.5px"></div>
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
      <div class="row"><label>Background</label><input type="color" id="cBg"><input type="text" id="cBgH" class="hex"></div>
      <div class="row"><label title="prompt, bar fill, cursor">Accent</label><input type="color" id="cAcc"><input type="text" id="cAccH" class="hex"></div>
      <div class="row"><label title="time + percent">Value</label><input type="color" id="cVal"><input type="text" id="cValH" class="hex"></div>
      <div class="row"><label title="date, labels, reset">Dim</label><input type="color" id="cDim"><input type="text" id="cDimH" class="hex"></div>
      <div class="row"><label title="empty bar track">Track</label><input type="color" id="cTrk"><input type="text" id="cTrkH" class="hex"></div>
      <div class="row"><label title="bar fill at 80%+">Cap (80%+)</label><input type="color" id="cCap"><input type="text" id="cCapH" class="hex"></div>
    </div>
    <div class="panel">
      <h2>Settings (paste back to me)</h2>
      <textarea id="out" readonly></textarea>
      <button onclick="copyOut()">Copy settings</button><button class="sec" onclick="reset()">Reset</button>
    </div>
  </div>
<script>
const FONTS=__FONTS__;
const SZ=454, cx=SZ/2;
const ctx=document.getElementById("c").getContext("2d"), out=document.getElementById("out");
// sample meter rows (5-hour, weekly, model), matching the face's three CLI rows
const ROWS=[{lb:"5H",pct:42,rs:"5:30p"},{lb:"1W",pct:63,rs:"Wed"},{lb:"FA",pct:55,rs:"Sep 20"}];

function defaults(){return {
  font:"Share Tech Mono", showSeconds:false,
  bg:"#000000", accent:"#D97757", val:"#FFFFFF", dim:"#AAAAAA", track:"#333333", cap:"#FF5F5F",
  el:{
    prompt:{name:"Prompt line", kind:"text", x:0.500, y:0.177, size:26, text:"claude ~ %"},
    time:  {name:"Time",        kind:"time", x:0.500, y:0.250, size:90},
    date:  {name:"Date",        kind:"date", x:0.500, y:0.454, size:26},
    rows:  {name:"Meter rows",  kind:"rows", y:0.556, gap:0.113, size:25,
            labelX:0.148, barX:0.242, barW:0.287, barH:0.030, pctX:0.639, resetX:0.858},
    cursor:{name:"Cursor",      kind:"cursor", x:0.526, y:0.469, w:0.030, h:0.028},
  }};}

let P=defaults(), sel=null, guide=null, boxes={};

function fnt(px){return px+"px '"+P.font+"',monospace";}
function timeStr(){return P.showSeconds?"10:38:24":"10:38";}

function drawEl(k){ const e=P.el[k];
  if(e.kind=="text"){ const x=e.x*SZ, y=e.y*SZ; ctx.fillStyle=P.accent; ctx.font=fnt(e.size); ctx.textAlign="center"; ctx.textBaseline="top"; ctx.fillText(e.text,x,y);
    const w=ctx.measureText(e.text).width; boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="time"){ const x=e.x*SZ, y=e.y*SZ; ctx.fillStyle=P.val; ctx.font=fnt(e.size); ctx.textAlign="center"; ctx.textBaseline="top"; const t=timeStr(); ctx.fillText(t,x,y);
    const w=ctx.measureText(t).width; boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="date"){ const x=e.x*SZ, y=e.y*SZ; ctx.fillStyle=P.dim; ctx.font=fnt(e.size); ctx.textAlign="center"; ctx.textBaseline="top"; const t="Wed Sep 19"; ctx.fillText(t,x,y);
    const w=ctx.measureText(t).width; boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+e.size+4]; return; }
  if(e.kind=="rows"){ const gy=e.gap*SZ, y0=e.y*SZ; ctx.font=fnt(e.size); ctx.textBaseline="top";
    for(let i=0;i<3;i++){ const y=y0+i*gy, r=ROWS[i];
      ctx.fillStyle=P.dim; ctx.textAlign="left"; ctx.fillText(r.lb, e.labelX*SZ, y);
      const bx=e.barX*SZ, bw=e.barW*SZ, bh=e.barH*SZ, by=y+0.018*SZ;
      ctx.fillStyle=P.track; ctx.fillRect(bx,by,bw,bh);
      ctx.fillStyle=(r.pct>=80)?P.cap:P.accent; ctx.fillRect(bx,by,bw*Math.min(100,r.pct)/100,bh);
      ctx.fillStyle=P.val; ctx.textAlign="right"; ctx.fillText(r.pct+"%", e.pctX*SZ, y);
      ctx.fillStyle=P.dim; ctx.textAlign="right"; ctx.fillText(r.rs, e.resetX*SZ, y);
    }
    boxes[k]=[e.labelX*SZ-6, y0-6, e.resetX*SZ+6, y0+2*gy+e.size+6]; return; }
  if(e.kind=="cursor"){ const x=e.x*SZ, y=e.y*SZ, w=e.w*SZ, h=e.h*SZ; ctx.fillStyle=P.accent; ctx.fillRect(x-w/2,y,w,h);
    boxes[k]=[x-w/2-4,y-4,x+w/2+4,y+h+4]; return; }
}

function draw(){ ctx.fillStyle=P.bg; ctx.fillRect(0,0,SZ,SZ); boxes={};
  ["prompt","time","date","rows","cursor"].forEach(drawEl);
  if(sel&&boxes[sel]){ const b=boxes[sel]; ctx.strokeStyle="#D97757"; ctx.lineWidth=1; ctx.setLineDash([4,3]); ctx.strokeRect(b[0],b[1],b[2]-b[0],b[3]-b[1]); ctx.setLineDash([]); }
  if(guide){ ctx.strokeStyle="#39d98a"; ctx.lineWidth=1; ctx.setLineDash([3,3]);
    if(guide.x!=null){ ctx.beginPath(); ctx.moveTo(guide.x,0); ctx.lineTo(guide.x,SZ); ctx.stroke(); }
    if(guide.y!=null){ ctx.beginPath(); ctx.moveTo(0,guide.y); ctx.lineTo(SZ,guide.y); ctx.stroke(); } ctx.setLineDash([]); }
  refresh();
}
function hit(mx,my){ let best=null,bd=1e9; for(const k in boxes){ const b=boxes[k], ix=Math.max(b[0],Math.min(mx,b[2])), iy=Math.max(b[1],Math.min(my,b[3])); const d=(mx-ix)**2+(my-iy)**2; if(d<bd){bd=d;best=k;} } return bd<44*44?best:null; }
function snapAxis(val,others){ let best=val,g=null,bd=0.014; const t=[0.5].concat(others); for(const o of t){ if(Math.abs(val-o)<bd){ bd=Math.abs(val-o); best=o; g=o*SZ; } } return [best,g]; }

let drag=null; const cv=document.getElementById("c");
cv.addEventListener("pointerdown",ev=>{ const r=cv.getBoundingClientRect(), mx=(ev.clientX-r.left)*SZ/r.width, my=(ev.clientY-r.top)*SZ/r.height; const k=hit(mx,my);
  if(k){ sel=k; drag=k; cv.setPointerCapture(ev.pointerId); cv.style.cursor="grabbing"; syncPanel(); draw(); } });
cv.addEventListener("pointermove",ev=>{ if(!drag)return; const r=cv.getBoundingClientRect(); let nx=Math.max(0.02,Math.min(0.98,(ev.clientX-r.left)/r.width)), ny=Math.max(0.02,Math.min(0.98,(ev.clientY-r.top)/r.height)); guide=null;
  const e=P.el[drag]; const hasX=(e.x!=null);
  if(document.getElementById("snap").checked){ const ox=[],oy=[]; for(const kk in P.el){ if(kk!=drag){ if(P.el[kk].x!=null)ox.push(P.el[kk].x); if(P.el[kk].y!=null)oy.push(P.el[kk].y);} } const sx=snapAxis(nx,ox), sy=snapAxis(ny,oy); nx=sx[0]; ny=sy[0]; guide={x:hasX?sx[1]:null,y:sy[1]}; }
  if(hasX){ e.x=nx; } e.y=ny; draw(); });
cv.addEventListener("pointerup",()=>{ drag=null; guide=null; cv.style.cursor="grab"; draw(); });

const fontSel=document.getElementById("fontSel"); FONTS.forEach(f=>{ const o=document.createElement("option"); o.value=f; o.textContent=f; fontSel.appendChild(o); });
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

function linkVal(pid,hid,val){ document.getElementById(pid).value=val; document.getElementById(hid).value=val; }
function bindColor(pid,hid,set){ const p=document.getElementById(pid), h=document.getElementById(hid);
  p.oninput=()=>{ h.value=p.value; set(p.value); draw(); };
  h.oninput=()=>{ let v=h.value.trim(); if(!/^#/.test(v)) v="#"+v; if(/^#[0-9a-fA-F]{6}$/.test(v)){ p.value=v; set(v); draw(); } }; }
bindColor("cBg","cBgH",v=>P.bg=v); bindColor("cAcc","cAccH",v=>P.accent=v); bindColor("cVal","cValH",v=>P.val=v);
bindColor("cDim","cDimH",v=>P.dim=v); bindColor("cTrk","cTrkH",v=>P.track=v); bindColor("cCap","cCapH",v=>P.cap=v);
function linkAllColours(){ linkVal("cBg","cBgH",P.bg); linkVal("cAcc","cAccH",P.accent); linkVal("cVal","cValH",P.val); linkVal("cDim","cDimH",P.dim); linkVal("cTrk","cTrkH",P.track); linkVal("cCap","cCapH",P.cap); }

fontSel.onchange=function(){ setFont(this.value); };
function setFont(name){ P.font=name; const id="gf-"+name.replace(/ /g,'-'); if(!document.getElementById(id)){ const l=document.createElement("link"); l.id=id; l.rel="stylesheet"; l.href="https://fonts.googleapis.com/css2?family="+name.replace(/ /g,"+")+"&display=swap"; document.head.appendChild(l); }
  if(document.fonts&&document.fonts.load){ document.fonts.load("40px '"+name+"'").then(function(){draw();setTimeout(draw,150);}).catch(function(){draw();}); } setTimeout(draw,700); setTimeout(draw,1500); }

function refresh(){ const e=P.el; let L=[
  "font: "+P.font, "showSeconds: "+P.showSeconds,
  "bg: "+P.bg+"  accent: "+P.accent+"  value: "+P.val+"  dim: "+P.dim+"  track: "+P.track+"  cap: "+P.cap, "",
  "prompt  x="+e.prompt.x.toFixed(3)+" y="+e.prompt.y.toFixed(3)+"  size="+e.prompt.size+"  text=\""+e.prompt.text+"\"",
  "time    x="+e.time.x.toFixed(3)+" y="+e.time.y.toFixed(3)+"  size="+e.time.size,
  "date    x="+e.date.x.toFixed(3)+" y="+e.date.y.toFixed(3)+"  size="+e.date.size,
  "rows    y="+e.rows.y.toFixed(3)+" gap="+e.rows.gap.toFixed(3)+" size="+e.rows.size
    +"  labelX="+e.rows.labelX.toFixed(3)+" barX="+e.rows.barX.toFixed(3)+" barW="+e.rows.barW.toFixed(3)
    +" barH="+e.rows.barH.toFixed(3)+" pctX="+e.rows.pctX.toFixed(3)+" resetX="+e.rows.resetX.toFixed(3),
  "cursor  x="+e.cursor.x.toFixed(3)+" y="+e.cursor.y.toFixed(3)+"  w="+e.cursor.w.toFixed(3)+" h="+e.cursor.h.toFixed(3),
]; out.value=L.join("\n"); }
function copyOut(){ out.select(); document.execCommand("copy"); }
function reset(){ P=defaults(); sel=null; guide=null; document.getElementById("fontSel").value=P.font; document.getElementById("secs").checked=P.showSeconds; linkAllColours(); syncPanel(); setFont(P.font); }

linkAllColours();
document.getElementById("fontSel").value=P.font; syncPanel(); setFont(P.font);
</script></body></html>"""
HTML = HTML.replace("__FONTS__", fonts_js)
open(OUT, "w", encoding="utf-8").write(HTML)
print("wrote", OUT, os.path.getsize(OUT), "bytes")
