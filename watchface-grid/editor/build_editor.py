# Generates the self-contained Claude Grid complication editor (v4).
import base64, os
from io import BytesIO
from PIL import Image, ImageFont, ImageDraw

TTF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "tabler-icons.ttf")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "claude-grid-editor.html")
GRAY = (158, 158, 158, 255)
font = ImageFont.truetype(TTF, 88)

def icon_datauri(cp):
    img = Image.new("RGBA", (104, 104), (0, 0, 0, 0))
    d = ImageDraw.Draw(img); ch = chr(cp)
    bb = d.textbbox((0, 0), ch, font=font); w, h = bb[2]-bb[0], bb[3]-bb[1]
    d.text(((104-w)/2-bb[0], (104-h)/2-bb[1]), ch, font=font, fill=GRAY)
    buf = BytesIO(); img.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()

CPS = [0xea34,0xec87,0xef92,0xea38,0xef62,0xeab1,0xeb38,0xec2c,0xeca5,0xef97,
       0xf0db,0xea97,0xff9b,0xea35,0xef1c,0xec31,0xea76,0xeaf8,0xf228,0xeb30,
       0xea72,0xea73,0xea74,0xecd9,0xec34,0xec0b,0x10265,0xea04,0xeb54]
ICONS = {("0x%x" % cp): icon_datauri(cp) for cp in CPS}
icons_js = "{" + ",".join('"%s":"%s"' % (k, v) for k, v in ICONS.items()) + "}"

# Monospace-only (so every digit column lines up). All are genuine mono families on Google Fonts.
FONTS = ["JetBrains Mono","Roboto Mono","Space Mono","Fira Code","Fira Mono","Source Code Pro",
 "IBM Plex Mono","Inconsolata","Ubuntu Mono","Ubuntu Sans Mono","PT Mono","Cousine","Courier Prime",
 "Overpass Mono","Nova Mono","Share Tech Mono","VT323","Major Mono Display","Xanh Mono","Spline Sans Mono",
 "Martian Mono","DM Mono","Red Hat Mono","Noto Sans Mono","B612 Mono","Azeret Mono","Anonymous Pro",
 "Cutive Mono","Fragment Mono","Syne Mono","Kode Mono","Oxygen Mono","Victor Mono","Lekton","Chivo Mono",
 "Reddit Mono","Geist Mono","Commit Mono","Nanum Gothic Coding","Doto","Sixtyfour","Silkscreen","Monofett"]
fonts_js = "[" + ",".join('"%s"' % f for f in FONTS) + "]"

HTML = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Claude Grid - editor</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link id="gf-JetBrains-Mono" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@600&display=swap" rel="stylesheet">
<style>
  body{margin:0;background:#141414;color:#ddd;font-family:ui-sans-serif,Segoe UI,Roboto,sans-serif;display:flex;gap:22px;padding:18px;flex-wrap:wrap;}
  h1{font-size:15px;color:#F2A98C;margin:0 0 4px;} p.hint{color:#8a8a8a;font-size:12px;margin:0 0 10px;max-width:470px;line-height:1.5;}
  canvas{border-radius:50%;box-shadow:0 0 0 10px #2a2a2a,0 0 0 12px #000;touch-action:none;cursor:grab;}
  .side{flex:1 1 340px;min-width:320px;max-width:450px;}
  .panel{background:#1a1a1a;border:1px solid #2a2a2a;border-radius:10px;padding:12px 15px;margin-bottom:12px;}
  .panel h2{font-size:13px;color:#E95625;margin:0 0 10px;text-transform:uppercase;letter-spacing:.5px;}
  .row{display:flex;align-items:center;gap:10px;margin:8px 0;font-size:12.5px;color:#bbb;}
  .row label{flex:0 0 92px;color:#999;} .row input[type=range]{flex:1;}
  .row .val{flex:0 0 42px;text-align:right;color:#F2A98C;font-family:ui-monospace,monospace;}
  select,input[type=color]{background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:4px;font-family:inherit;font-size:12.5px;} select{flex:1;}
  input.hex{width:78px;background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:4px;font-family:ui-monospace,monospace;font-size:12px;}
  button{background:#E95625;color:#111;border:0;border-radius:8px;padding:8px 14px;font-family:inherit;font-weight:bold;cursor:pointer;margin:6px 8px 0 0;} button.sec{background:#333;color:#ddd;}
  textarea{width:100%;height:150px;background:#0c0c0c;border:1px solid #333;border-radius:8px;padding:10px;font-family:ui-monospace,monospace;font-size:11.5px;color:#bfe7d8;}
  .muted{color:#666;font-size:11.5px;} .chk{display:flex;gap:7px;align-items:center;}
</style></head>
<body>
  <div>
    <h1>Claude Grid - complication editor</h1>
    <p class="hint"><b>Click</b> a field (or the top arc) to select it. Set its <b>complication</b> and
      sizes; <b>drag</b> to move (snaps to align). Colours take <b>hex</b>. <b>Copy</b> the block back to me.</p>
    <canvas id="c" width="454" height="454"></canvas>
  </div>
  <div class="side">
    <div class="panel">
      <div class="row"><label style="flex:0 0 40px">Font</label><select id="fontSel"></select></div>
      <div class="row chk"><input type="checkbox" id="snap" checked><label style="flex:0 0 auto">Snap to align (vertical + horizontal)</label></div>
      <div class="row chk"><input type="checkbox" id="mir" checked><label style="flex:0 0 auto">Mirror left/right (position + sizes)</label></div>
    </div>
    <div class="panel">
      <h2>Selected: <span id="selName">- none -</span></h2>
      <div id="ctlComp" class="row" style="display:none"><label>Complication</label><select id="compSel"></select></div>
      <div id="ctlRing" class="row" style="display:none"><label>Ring radius</label><input type="range" id="ringR" min="15" max="110" step="1"><span class="val" id="ringRV"></span></div>
      <div id="ctlNum" class="row" style="display:none"><label id="numLbl">Number px</label><input type="range" id="numR" min="8" max="120" step="1"><span class="val" id="numRV"></span></div>
      <div id="ctlSym" class="row" style="display:none"><label>Symbol px</label><input type="range" id="symR" min="8" max="80" step="1"><span class="val" id="symRV"></span></div>
      <div id="ctlGap" class="row" style="display:none"><label>HH/MM gap</label><input type="range" id="gapR" min="20" max="110" step="1"><span class="val" id="gapRV"></span></div>
      <div id="ctlFade" class="row" style="display:none"><label>Time fade</label><input type="range" id="fadeR" min="0" max="1" step="0.02"><span class="val" id="fadeRV"></span></div>
      <div id="ctlText" class="row" style="display:none"><label>Text</label><input type="text" id="brandT" style="flex:1;background:#0c0c0c;color:#ddd;border:1px solid #333;border-radius:6px;padding:5px;font-family:inherit;font-size:12.5px"></div>
      <div id="ctlDGap" class="row" style="display:none"><label>Month/day gap</label><input type="range" id="dgapR" min="20" max="180" step="1"><span class="val" id="dgapRV"></span></div>
      <div id="ctlWeek" class="row" style="display:none"><label>Week width</label><input type="range" id="wspanR" min="40" max="130" step="1"><span class="val" id="wspanRV"></span></div>
      <div id="ctlArcR" class="row" style="display:none"><label>Arc radius</label><input type="range" id="aradR" min="120" max="228" step="1"><span class="val" id="aradRV"></span></div>
      <div id="ctlArcSpan" class="row" style="display:none"><label>Arc width</label><input type="range" id="aspanR" min="30" max="150" step="1"><span class="val" id="aspanRV"></span></div>
      <div id="ctlArcW" class="row" style="display:none"><label>Dash width</label><input type="range" id="adwR" min="1" max="10" step="0.5"><span class="val" id="adwRV"></span></div>
      <div id="ctlArcL" class="row" style="display:none"><label>Dash length</label><input type="range" id="adlR" min="4" max="28" step="1"><span class="val" id="adlRV"></span></div>
      <div id="ctlNone" class="muted">Click a field on the watch to edit it.</div>
    </div>
    <div class="panel">
      <h2>Watch colours</h2>
      <div class="row"><label>Accent</label><input type="color" id="cAcc"><input type="text" id="cAccH" class="hex"></div>
      <div class="row"><label title="most values">Text 1</label><input type="color" id="cT1"><input type="text" id="cT1H" class="hex"></div>
      <div class="row"><label title="Data 04/05 + date">Text 2</label><input type="color" id="cT2"><input type="text" id="cT2H" class="hex"></div>
      <div class="row"><label title="icons, SEC, weekdays">Text 3</label><input type="color" id="cT3"><input type="text" id="cT3H" class="hex"></div>
      <div class="row"><label title="ring/arc gradient start">Gradient 1</label><input type="color" id="cG1"><input type="text" id="cG1H" class="hex"></div>
      <div class="row"><label title="ring/arc gradient end">Gradient 2</label><input type="color" id="cG2"><input type="text" id="cG2H" class="hex"></div>
    </div>
    <div class="panel">
      <h2>Settings (paste back to me)</h2>
      <textarea id="out" readonly></textarea>
      <button onclick="copyOut()">Copy settings</button><button class="sec" onclick="reset()">Reset</button>
    </div>
  </div>
<script>
const ICONS=__ICONS__, FONTS=__FONTS__;
const IMG={}; let ready=0, total=Object.keys(ICONS).length;
for(const k in ICONS){ const im=new Image(); im.onload=()=>{ready++; if(ready>=total) draw();}; im.src=ICONS[k]; IMG[k]=im; }
function img(cp){ return IMG["0x"+cp.toString(16)]; }
const SZ=454, cx=SZ/2, cy=SZ/2; let GA=[181,80,47], GB=[255,192,138]; const DIM="#9a9a9a", TRACK="#3A2A22";
const COMPS=[
 {k:"Battery",ic:0xea34,v:"50%",lb:"BAT"},{k:"Steps",ic:0x10265,v:"8420",lb:"STEPS"},
 {k:"Heart Rate",ic:0xef92,v:"72",lb:"HR"},{k:"Body Battery",ic:0xea38,v:"64",lb:"BODY"},
 {k:"VO2 Max",ic:null,v:"48",lb:"VO2"},{k:"Pressure",ic:null,v:"758",lb:"mmHg"},
 {k:"Temperature",ic:null,v:"18°",lb:""},{k:"High/Low Temp",ic:0xeb38,v:"18°/9°",lb:"HL",stack:true},
 {k:"Calories",ic:0xec2c,v:"1240",lb:"CAL"},{k:"Floors",ic:0xeca5,v:"12",lb:"FLR"},
 {k:"Altitude",ic:0xef97,v:"340",lb:"ALT"},{k:"Stress",ic:0xf0db,v:"28",lb:"STR"},
 {k:"Pulse Ox",ic:null,pox:true,v:"98",lb:"SPO2"},{k:"Intensity Min",ic:0xff9b,v:"45",lb:"INT"},
 {k:"Notifications",ic:0xea35,v:"3",lb:"NOTIF"},{k:"Sunrise",ic:0xef1c,v:"6:12",lb:"RISE"},
 {k:"Sunset",ic:0xec31,v:"19:48",lb:"SET"},{k:"Weather",ic:0xea76,v:"17°",lb:"WX"},
 {k:"Sleep Score",ic:0xeaf8,v:"82",lb:"SLP"},{k:"Recovery",ic:0xf228,v:"18",lb:"REC"},
 {k:"Solar",ic:0xeb30,v:"45",lb:"SOL"},{k:"Seconds",ic:null,v:"38",lb:"SEC",sec:true},
 {k:"Claude 5-hour",ic:null,v:"42%",lb:"5H"},{k:"Claude weekly",ic:null,v:"63%",lb:"1W"},
 {k:"Claude Fable",ic:null,v:"55%",lb:"FABLE"},
 {k:"Alt Time Zone",ic:0xeb54,v:"14:23",lb:"NY"},
];
const SEC_IDX=21;
function defaults(){return {font:"Commit Mono",accent:"#ff531a",text1:"#ff9c75",text2:"#ffffff",text3:"#9a9a9a",grad1:"#B5502F",grad2:"#FFC08A",
  arc:{span:75,dashW:10,dashLen:15,frac:0.5,rad:224},
  el:{
  batt:{name:"Data 01 (battery)",kind:"horiz",x:0.500,y:0.092,comp:22,num:24,sym:24},
  d02:{name:"Data 02 (upper-left)",kind:"chip",x:0.166,y:0.328,comp:7,num:30,sym:24},
  d03:{name:"Data 03 (upper-right)",kind:"chip",x:0.834,y:0.328,comp:1,num:30,sym:24},
  d04:{name:"Data 04 (left ring)",kind:"ring",x:0.137,y:0.516,comp:22,ring:56,num:36,sym:24,frac:0.53},
  d05:{name:"Data 05 (right ring)",kind:"ring",x:0.863,y:0.516,comp:23,ring:56,num:36,sym:24,frac:0.72},
  d06:{name:"Data 06 (lower-left)",kind:"chip",x:0.166,y:0.755,comp:17,num:30,sym:24},
  d08:{name:"Data 07 (lower-right)",kind:"chip",x:0.834,y:0.755,comp:2,num:30,sym:24},
  sec:{name:"Data 08 (dial)",kind:"tick",x:0.500,y:0.832,comp:SEC_IDX,ring:50,num:30,sym:24,frac:0.63},
  time:{name:"Time",kind:"time",x:0.500,y:0.500,gap:47,num:120,fade:0.6},
  brand:{name:"Brand text",kind:"brand",x:0.500,y:0.207,num:32,text:"TACTIX"},
  alarmi:{name:"Alarm indicator",kind:"ind",x:0.630,y:0.207,sym:22,ic:0xea04},
  swatch:{name:"Stopwatch indicator",kind:"ind",x:0.710,y:0.207,sym:22,ic:0xff9b},
  date:{name:"Date",kind:"date",x:0.500,y:0.832,num:34,gap:76},
  week:{name:"Week",kind:"week",x:0.500,y:0.980,num:27,span:52},
}};}
let P=defaults(), sel=null, guide=null, boxes={};
const PAIR={d02:"d03",d03:"d02",d04:"d05",d05:"d04",d06:"d08",d08:"d06"};
function mirror(k){ if(!document.getElementById("mir").checked)return; const q=PAIR[k]; if(!q)return; const a=P.el[k],b=P.el[q]; b.x=1-a.x; b.y=a.y; if(a.ring!=null)b.ring=a.ring; if(a.num!=null)b.num=a.num; if(a.sym!=null)b.sym=a.sym; }
const ctx=document.getElementById("c").getContext("2d"), out=document.getElementById("out");
function lerp(a,b,t){return `rgb(${Math.round(a[0]+(b[0]-a[0])*t)},${Math.round(a[1]+(b[1]-a[1])*t)},${Math.round(a[2]+(b[2]-a[2])*t)})`;}
function num(px){return px+"px '"+P.font+"',monospace";}
function hexRgb(h){ h=(h||"#000000").replace("#",""); return [parseInt(h.slice(0,2),16)||0,parseInt(h.slice(2,4),16)||0,parseInt(h.slice(4,6),16)||0]; }
const _tc=document.createElement("canvas"); _tc.width=160; _tc.height=160; const _tcx=_tc.getContext("2d");
function tintIcon(im,x,y,s,color){ _tcx.clearRect(0,0,160,160); _tcx.drawImage(im,0,0,s,s); _tcx.globalCompositeOperation="source-in"; _tcx.fillStyle=color; _tcx.fillRect(0,0,s,s); _tcx.globalCompositeOperation="source-over"; ctx.drawImage(_tc,0,0,s,s,x-s/2,y-s/2,s,s); }
function ring(x,y,r,pen,frac,striped){ ctx.lineWidth=pen; ctx.strokeStyle=TRACK; ctx.beginPath(); ctx.arc(x,y,r,0,2*Math.PI); ctx.stroke();
  const steps=36,lit=Math.round(steps*frac); for(let i=0;i<lit;i++){ if(striped&&i%2==0)continue; ctx.strokeStyle=lerp(GA,GB,i/steps);
    ctx.beginPath(); ctx.arc(x,y,r,-Math.PI/2+i*2*Math.PI/steps,-Math.PI/2+(i+1)*2*Math.PI/steps); ctx.stroke(); } }
function tickRing(x,y,r,frac){ const n=60,lit=Math.round(n*frac),len=9,pen=2; ctx.lineWidth=pen;
  for(let i=0;i<n;i++){ const a=-Math.PI/2+i*2*Math.PI/n,c=Math.cos(a),s=Math.sin(a);
    ctx.strokeStyle=i<lit?lerp(GA,GB,i/n):TRACK; ctx.beginPath(); ctx.moveTo(x+r*c,y+r*s); ctx.lineTo(x+(r-len)*c,y+(r-len)*s); ctx.stroke(); } }
function battArc(){ const a=P.arc, r=a.rad, n=16, lit=Math.round(n*a.frac), st=90+a.span/2, en=90-a.span/2; ctx.lineWidth=a.dashW;
  for(let i=0;i<n;i++){ const ang=(st-(st-en)*i/(n-1))*Math.PI/180, c=Math.cos(ang), s=Math.sin(ang);
    ctx.strokeStyle=i<lit?lerp(GA,GB,i/n):TRACK; ctx.beginPath(); ctx.moveTo(cx+r*c,cy-r*s); ctx.lineTo(cx+(r-a.dashLen)*c,cy-(r-a.dashLen)*s); ctx.stroke(); }
  boxes.arc=[cx-140,cy-r-8,cx+140,cy-r*Math.sin((90-a.span/2)*Math.PI/180)+a.dashLen+4]; }
function tabular(str,x,y,f,color){ ctx.font=f; ctx.textAlign="center"; ctx.textBaseline="middle"; let cw=0;
  for(let d=0;d<=9;d++) cw=Math.max(cw,ctx.measureText(""+d).width); const sx=x-str.length*cw/2;
  for(let i=0;i<str.length;i++){ ctx.fillStyle=color; ctx.fillText(str[i],sx+cw*(i+0.5),y); } }
function symbol(e,x,y){ const c=COMPS[e.comp], s=e.sym;
  if(c && c.pox){ const rr=s*0.5; ctx.strokeStyle=P.text3; ctx.lineWidth=Math.max(1.5,s*0.07); ctx.beginPath(); ctx.arc(x,y,rr,0,2*Math.PI); ctx.stroke(); ctx.beginPath(); ctx.moveTo(x-rr*0.72,y+rr*0.72); ctx.lineTo(x+rr*0.72,y-rr*0.72); ctx.stroke(); ctx.beginPath(); ctx.moveTo(x-rr*0.5,y); ctx.lineTo(x-rr*0.18,y+rr*0.3); ctx.lineTo(x+rr*0.12,y-rr*0.25); ctx.lineTo(x+rr*0.45,y+rr*0.2); ctx.stroke(); return; }
  if(c && c.ic!=null){ const im=img(c.ic); if(im&&im.complete) tintIcon(im,x,y,s,P.text3); return; }
  ctx.fillStyle=P.text3; ctx.font=num(Math.round(s*0.72)); ctx.textAlign="center"; ctx.textBaseline="middle"; ctx.fillText(c?c.lb:"",x,y); }
function drawEl(k){ const e=P.el[k], x=e.x*SZ, y=e.y*SZ, c=COMPS[e.comp]; ctx.textAlign="center"; ctx.textBaseline="middle";
  if(e.kind=="time"){ const f=num(e.num); const topY=y-e.gap-e.num*0.42, botY=y+e.gap+e.num*0.42; const g=ctx.createLinearGradient(0,topY,0,botY); const fw=Math.max(0.001,e.fade); g.addColorStop(0,P.grad1); g.addColorStop(Math.max(0,0.5-fw*0.5),P.grad1); g.addColorStop(Math.min(1,0.5+fw*0.5),P.grad2); g.addColorStop(1,P.grad2); tabular("01",x,y-e.gap,f,g); tabular("33",x,y+e.gap,f,g); boxes[k]=[x-72,y-e.gap-e.num*0.7,x+72,y+e.gap+e.num*0.7]; return; }
  if(e.kind=="brand"){ ctx.fillStyle=P.text3; ctx.font=num(e.num); ctx.textAlign="center"; ctx.textBaseline="middle"; ctx.fillText(e.text,x,y); boxes[k]=[x-70,y-18,x+70,y+18]; return; }
  if(e.kind=="ind"){ const im=img(e.ic); if(im&&im.complete) tintIcon(im,x,y,e.sym,P.text3); boxes[k]=[x-e.sym/2-5,y-e.sym/2-5,x+e.sym/2+5,y+e.sym/2+5]; return; }
  if(e.kind=="date"){ const d=e.gap; ctx.fillStyle=P.text2; ctx.font=num(e.num); ctx.fillText("SEP",x-d,y); ctx.fillText("19",x+d,y); boxes[k]=[x-d-42,y-24,x+d+42,y+24]; return; }
  if(e.kind=="week"){ const R=y-cy, sp=e.span, st=90+sp/2; ctx.font=num(e.num);
    for(let i=0;i<7;i++){ const th=(st-(sp/6)*i)*Math.PI/180, lx=cx+R*Math.cos(th), ly=cy+R*Math.sin(th);
      ctx.save(); ctx.translate(lx,ly); ctx.rotate(th-Math.PI/2); ctx.fillStyle=i==5?P.accent:P.text3; ctx.textAlign="center"; ctx.textBaseline="middle"; ctx.fillText("SMTWTFS"[i],0,0); ctx.restore(); }
    boxes[k]=[cx-110,y-26,cx+110,y+18]; return; }
  const isSec=c&&c.sec;
  if(e.kind=="tick"){ const rr=e.ring; tickRing(x,y,rr,e.frac); symbol(e,x,y-rr*0.5);
    ctx.fillStyle=isSec?P.accent:P.text1; ctx.font=num(e.num); ctx.textAlign="center"; ctx.textBaseline="middle"; ctx.fillText(c?c.v:"",x,y+e.num*0.3); boxes[k]=[x-rr-4,y-rr-4,x+rr+4,y+rr+4]; return; }
  if(e.kind=="ring"){ const rr=e.ring; ring(x,y,rr,6,e.frac,false); symbol(e,x,y-rr*0.42);
    ctx.fillStyle=P.text2; ctx.font=num(e.num); ctx.textAlign="center"; ctx.textBaseline="middle"; ctx.fillText(c?c.v:"",x,y+e.num*0.28); boxes[k]=[x-rr-4,y-rr-4,x+rr+4,y+rr+4]; return; }
  if(e.kind=="horiz"){ ctx.font=num(e.num); const vw=ctx.measureText(c.v).width; let iw=0, lbl=null;
    if(c.ic!=null){ iw=e.sym; } else { lbl=c.lb; ctx.font=num(Math.round(e.sym*0.72)); iw=ctx.measureText(lbl).width; ctx.font=num(e.num); }
    const gap=iw>0?7:0, tot=iw+gap+vw, sx=x-tot/2;
    if(c.ic!=null){ const im=img(c.ic); if(im&&im.complete) tintIcon(im,sx+e.sym/2,y,e.sym,P.text3); }
    else if(lbl){ ctx.fillStyle=P.text3; ctx.textAlign="left"; ctx.textBaseline="middle"; ctx.font=num(Math.round(e.sym*0.72)); ctx.fillText(lbl,sx,y); }
    ctx.fillStyle=P.text1; ctx.textAlign="left"; ctx.textBaseline="middle"; ctx.font=num(e.num); ctx.fillText(c.v,sx+iw+gap,y); ctx.textAlign="center"; boxes[k]=[x-tot/2-6,y-e.num*0.7,x+tot/2+6,y+e.num*0.7]; return; }
  if(!(c&&c.stack)) symbol(e,x,y-e.sym-4); ctx.textAlign="center"; ctx.textBaseline="middle";
  if(c&&c.stack){ const p=c.v.split("/"); ctx.font=num(Math.round(e.num*0.72)); ctx.fillStyle=P.text1; ctx.fillText(p[0],x,y-e.num*0.44);
    ctx.strokeStyle=P.text3; ctx.lineWidth=1; ctx.beginPath(); ctx.moveTo(x-e.num*0.6,y); ctx.lineTo(x+e.num*0.6,y); ctx.stroke(); ctx.fillText(p[1]||"",x,y+e.num*0.44); }
  else { ctx.fillStyle=P.text1; ctx.font=num(e.num); ctx.fillText(c?c.v:"",x,y); }
  boxes[k]=[x-46,y-38,x+46,y+38];
}
function draw(){ ctx.fillStyle="#000"; ctx.fillRect(0,0,SZ,SZ); boxes={}; GA=hexRgb(P.grad1); GB=hexRgb(P.grad2); battArc();
  ["batt","d02","d03","d04","d05","d06","d08","sec","time","date","week","brand","alarmi","swatch"].forEach(drawEl);
  if(sel&&boxes[sel]){ const b=boxes[sel]; ctx.strokeStyle="#E95625"; ctx.lineWidth=1; ctx.setLineDash([4,3]); ctx.strokeRect(b[0],b[1],b[2]-b[0],b[3]-b[1]); ctx.setLineDash([]); }
  if(guide){ ctx.strokeStyle="#39d98a"; ctx.lineWidth=1; ctx.setLineDash([3,3]);
    if(guide.x!=null){ ctx.beginPath(); ctx.moveTo(guide.x,0); ctx.lineTo(guide.x,SZ); ctx.stroke(); }
    if(guide.y!=null){ ctx.beginPath(); ctx.moveTo(0,guide.y); ctx.lineTo(SZ,guide.y); ctx.stroke(); } ctx.setLineDash([]); }
  refresh();
}
function hit(mx,my){ let best=null,bd=1e9; for(const k in boxes){ const b=boxes[k], ix=Math.max(b[0],Math.min(mx,b[2])), iy=Math.max(b[1],Math.min(my,b[3])); const d=(mx-ix)**2+(my-iy)**2; if(d<bd){bd=d;best=k;} } return bd<42*42?best:null; }
function snapAxis(val,others){ let best=val,g=null,bd=0.014; const t=[0.5].concat(others); for(const o of t){ if(Math.abs(val-o)<bd){ bd=Math.abs(val-o); best=o; g=o*SZ; } } return [best,g]; }
let drag=null; const cv=document.getElementById("c");
cv.addEventListener("pointerdown",ev=>{ const r=cv.getBoundingClientRect(), mx=(ev.clientX-r.left)*SZ/r.width, my=(ev.clientY-r.top)*SZ/r.height; const k=hit(mx,my);
  if(k){ sel=k; drag=k; cv.setPointerCapture(ev.pointerId); cv.style.cursor="grabbing"; syncPanel(); draw(); } });
cv.addEventListener("pointermove",ev=>{ if(!drag)return; const r=cv.getBoundingClientRect(); let nx=Math.max(0.02,Math.min(0.98,(ev.clientX-r.left)/r.width)), ny=Math.max(0.02,Math.min(0.98,(ev.clientY-r.top)/r.height)); guide=null;
  if(document.getElementById("snap").checked && drag!="arc"){ const ox=[],oy=[]; for(const kk in P.el){ if(kk!=drag){ ox.push(P.el[kk].x); oy.push(P.el[kk].y);} } const sx=snapAxis(nx,ox), sy=snapAxis(ny,oy); nx=sx[0]; ny=sy[0]; guide={x:sx[1],y:sy[1]}; }
  if(drag=="arc"){ P.arc.rad=Math.max(120,Math.min(228, cy - ny*SZ)); guide=null; } else if(drag=="week"){ P.el.week.y=ny; } else { P.el[drag].x=nx; P.el[drag].y=ny; mirror(drag); } draw(); });
cv.addEventListener("pointerup",()=>{ drag=null; guide=null; cv.style.cursor="grab"; draw(); });

const compSel=document.getElementById("compSel"); COMPS.forEach((c,i)=>{ const o=document.createElement("option"); o.value=i; o.textContent=c.k; compSel.appendChild(o); });
const fontSel=document.getElementById("fontSel"); FONTS.forEach(f=>{ const o=document.createElement("option"); o.value=f; o.textContent=f; fontSel.appendChild(o); });
function show(id,on){ document.getElementById(id).style.display=on?"flex":"none"; }
function cur(){ return sel=="arc"?P.arc:(sel?P.el[sel]:null); }
function syncPanel(){ const e=sel&&sel!="arc"?P.el[sel]:null; const isArc=sel=="arc";
  document.getElementById("selName").textContent=isArc?"Battery arc (top)":(e?e.name:"- none -");
  document.getElementById("ctlNone").style.display=(e||isArc)?"none":"block";
  const isData=e&&(e.kind=="chip"||e.kind=="ring"||e.kind=="tick"||e.kind=="horiz");
  const isRing=e&&(e.kind=="ring"||e.kind=="tick");
  show("ctlComp",isData); show("ctlRing",isRing); show("ctlGap",e&&e.kind=="time");
  show("ctlText",e&&e.kind=="brand"); show("ctlFade",e&&e.kind=="time"); show("ctlDGap",e&&e.kind=="date"); show("ctlWeek",e&&e.kind=="week");
  show("ctlArcR",isArc); show("ctlArcSpan",isArc); show("ctlArcW",isArc); show("ctlArcL",isArc);
  show("ctlNum",!!e&&!isArc&&!(e&&e.kind=="ind")); show("ctlSym",isData||(e&&e.kind=="ind"));
  document.getElementById("numLbl").textContent=(e&&(e.kind=="time"||e.kind=="date"||e.kind=="week"))?"Text px":"Number px";
  if(isArc){ setR("aradR","aradRV",P.arc.rad,0); setR("aspanR","aspanRV",P.arc.span,0); setR("adwR","adwRV",P.arc.dashW,1); setR("adlR","adlRV",P.arc.dashLen,0); return; }
  if(!e)return; if(isData) compSel.value=e.comp;
  if(isRing) setR("ringR","ringRV",e.ring,0);
  var _nr=document.getElementById("numR"); if(e.kind=="time"){_nr.min=85;_nr.max=200;}else{_nr.min=8;_nr.max=120;} setR("numR","numRV",e.num||1,0); if(e.sym!=null) setR("symR","symRV",e.sym,0);
  if(e.kind=="time"){ setR("gapR","gapRV",e.gap,0); setR("fadeR","fadeRV",e.fade,2); }
  if(e.kind=="brand") document.getElementById("brandT").value=e.text;
  if(e.kind=="date") setR("dgapR","dgapRV",e.gap,0);
  if(e.kind=="week") setR("wspanR","wspanRV",e.span,0);
}
function setR(rid,vid,val,dp){ document.getElementById(rid).value=val; document.getElementById(vid).textContent=dp?(+val).toFixed(dp):(""+Math.round(val)); }
function linkVal(pid,hid,val){ document.getElementById(pid).value=val; document.getElementById(hid).value=val; }
compSel.onchange=()=>{ if(sel&&sel!="arc"){P.el[sel].comp=+compSel.value; draw();} };
function bindR(rid,vid,dp,fn){ document.getElementById(rid).oninput=function(){ fn(+this.value); if(sel&&sel!="arc") mirror(sel); document.getElementById(vid).textContent=dp?(+this.value).toFixed(dp):(""+Math.round(+this.value)); draw(); }; }
bindR("ringR","ringRV",0,v=>{if(sel&&sel!="arc")P.el[sel].ring=v;});
bindR("numR","numRV",0,v=>{if(sel&&sel!="arc")P.el[sel].num=v;});
bindR("symR","symRV",0,v=>{if(sel&&sel!="arc")P.el[sel].sym=v;});
bindR("gapR","gapRV",0,v=>{if(sel&&sel!="arc")P.el[sel].gap=v;});
bindR("fadeR","fadeRV",2,v=>{if(sel&&sel!="arc")P.el[sel].fade=v;});
bindR("dgapR","dgapRV",0,v=>{if(sel&&sel!="arc")P.el[sel].gap=v;});
bindR("wspanR","wspanRV",0,v=>{ if(Math.abs(v-P.arc.span)<4) v=P.arc.span; if(sel=="week"||sel&&P.el[sel]&&P.el[sel].kind=="week")P.el.week.span=v; document.getElementById("wspanR").value=v; });
bindR("aradR","aradRV",0,v=>{P.arc.rad=v;});
bindR("aspanR","aspanRV",0,v=>{P.arc.span=v;});
bindR("adwR","adwRV",1,v=>{P.arc.dashW=v;});
bindR("adlR","adlRV",0,v=>{P.arc.dashLen=v;});
function bindColor(pid,hid,set){ const p=document.getElementById(pid), h=document.getElementById(hid);
  p.oninput=()=>{ h.value=p.value; set(p.value); draw(); };
  h.oninput=()=>{ let v=h.value.trim(); if(!/^#/.test(v)) v="#"+v; if(/^#[0-9a-fA-F]{6}$/.test(v)){ p.value=v; set(v); draw(); } }; }
bindColor("cAcc","cAccH",v=>P.accent=v); bindColor("cT1","cT1H",v=>P.text1=v); bindColor("cT2","cT2H",v=>P.text2=v);
bindColor("cT3","cT3H",v=>P.text3=v);
bindColor("cG1","cG1H",v=>P.grad1=v); bindColor("cG2","cG2H",v=>P.grad2=v);
document.getElementById("brandT").oninput=function(){ if(sel=="brand"){ P.el.brand.text=this.value; draw(); } };
fontSel.onchange=function(){ setFont(this.value); };
function setFont(name){ P.font=name; const id="gf-"+name.replace(/ /g,'-'); if(!document.getElementById(id)){ const l=document.createElement("link"); l.id=id; l.rel="stylesheet"; l.href="https://fonts.googleapis.com/css2?family="+name.replace(/ /g,"+")+"&display=swap"; document.head.appendChild(l); }
  if(document.fonts&&document.fonts.load){ document.fonts.load("40px '"+name+"'").then(function(){draw();setTimeout(draw,150);}).catch(function(){draw();}); } setTimeout(draw,700); setTimeout(draw,1500); }
function refresh(){ let L=["font: "+P.font,"accent: "+P.accent,"text1: "+P.text1+"  text2: "+P.text2+"  text3: "+P.text3,"grad1: "+P.grad1+"  grad2: "+P.grad2,
  "arc: rad="+Math.round(P.arc.rad)+" span="+P.arc.span+" dashW="+P.arc.dashW+" dashLen="+P.arc.dashLen,""];
  for(const k in P.el){ const e=P.el[k]; let s=k.padEnd(6)+" ("+e.name+")  x="+e.x.toFixed(3)+" y="+e.y.toFixed(3);
    if(e.comp!=null) s+="  comp="+COMPS[e.comp].k; if(e.ring!=null) s+="  ring="+Math.round(e.ring)+"px";
    if(e.num!=null) s+="  num="+Math.round(e.num)+"px"; if(e.sym!=null) s+="  sym="+Math.round(e.sym)+"px";
    if(e.gap!=null) s+="  gap="+Math.round(e.gap)+"px";
    if(e.span!=null) s+="  width="+e.span; if(e.fade!=null) s+="  fade="+(+e.fade).toFixed(2); if(e.text!=null) s+="  text=\""+e.text+"\""; L.push(s); }
  out.value=L.join("\n"); }
function linkAllColours(){ linkVal("cAcc","cAccH",P.accent); linkVal("cT1","cT1H",P.text1); linkVal("cT2","cT2H",P.text2); linkVal("cT3","cT3H",P.text3); linkVal("cG1","cG1H",P.grad1); linkVal("cG2","cG2H",P.grad2); }
function copyOut(){ out.select(); document.execCommand("copy"); }
function reset(){ P=defaults(); sel=null; guide=null; document.getElementById("fontSel").value=P.font; linkAllColours(); syncPanel(); setFont(P.font); }
linkAllColours();
document.getElementById("fontSel").value=P.font; syncPanel(); setFont(P.font);
</script></body></html>"""
HTML = HTML.replace("__ICONS__", icons_js).replace("__FONTS__", fonts_js)
open(OUT, "w", encoding="utf-8").write(HTML)
print("wrote", OUT, os.path.getsize(OUT), "bytes")
