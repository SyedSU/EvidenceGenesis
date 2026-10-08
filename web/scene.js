/** Original pixel artwork drawn on a low-resolution canvas. No external assets. */
const palettes = {mint: ['#31574a','#81b891','#c1d9a5'], coral: ['#704840','#d38b72','#efb795']};
export function drawSprite(ctx, x, y, palette, frame = 0, scale = 1) {
  const [dark, coat, light] = palettes[palette];
  ctx.save(); ctx.translate(Math.round(x),Math.round(y)); ctx.scale(scale,scale);
  const r = (x,y,w,h,c) => {ctx.fillStyle=c;ctx.fillRect(x,y,w,h);};
  r(-8,5,16,3,'#193b3525');
  r(-5,-7,4,10,dark);r(2,-7,4,10,dark);r(-6,2 + frame,5,3,dark);r(2,2 - frame,5,3,dark);
  r(-8,-19,16,14,coat);r(-10,-17,3,9,coat);r(8,-17,3,9,coat);r(-5,-18,10,5,light);
  r(-8,-32,16,14,dark);r(-7,-29,14,10,'#efd8ae');r(-6,-33,12,6,dark);r(-9,-30,3,6,dark);
  r(-4,-25,2,2,'#293e34');r(3,-25,2,2,'#293e34');r(-1,-21,3,1,'#b67f66');
  if(palette==='coral'){r(-8,-35,16,5,coat);r(-11,-31,22,3,coat);r(-5,-36,10,2,light);}
  else {r(-8,-34,4,6,dark);r(4,-34,4,6,dark);r(-3,-34,6,3,dark);}
  ctx.restore();
}
export function portrait(canvas, palette) {
  const c=canvas.getContext('2d');c.clearRect(0,0,44,44);drawSprite(c,22,41,palette,0,1);
}
export function createScene(canvas, stateProvider) {
  const buffer=document.createElement('canvas');buffer.width=450;buffer.height=330;
  const c=buffer.getContext('2d'), output=canvas.getContext('2d');
  let tick=0, busyId=null, selected=null, running=true;
  const reduced=matchMedia('(prefers-reduced-motion: reduce)');
  const iso=(x,y,z=0)=>[225+(x-y)*22,112+(x+y)*11-z];
  function polygon(points,color){c.fillStyle=color;c.beginPath();points.forEach(([x,y],i)=>i?c.lineTo(x,y):c.moveTo(x,y));c.closePath();c.fill();}
  function box(x,y,w,d,h,top,front,side){
    const a=iso(x,y,h),b=iso(x+w,y,h),e=iso(x+w,y+d,h),f=iso(x,y+d,h),aa=iso(x,y),bb=iso(x+w,y),ee=iso(x+w,y+d),ff=iso(x,y+d);
    polygon([f,e,ee,ff],front);polygon([b,e,ee,bb],side);polygon([a,b,e,f],top);
  }
  const rect=(x,y,w,h,color)=>{c.fillStyle=color;c.fillRect(Math.round(x),Math.round(y),w,h);};
  function plant(x,y){const [a,b]=iso(x,y);box(x-.22,y-.22,.44,.44,8,'#b47f53','#986747','#76533c');rect(a-1,b-26,2,19,'#52713e');rect(a-10,b-24,10,5,'#688e47');rect(a,b-28,10,6,'#83a356');rect(a-7,b-32,6,8,'#83a356');rect(a+1,b-35,5,8,'#557b45');}
  function desk(x,y){box(x,y,.15,.15,18,'#9d794c','#836044','#785938');box(x+1.65,y+.8,.15,.15,18,'#9d794c','#836044','#785938');box(x,y,1.8,1.1,23,'#d2ad74','#a77e4f','#8a673f');box(x+.45,y+.28,.7,.45,25,'#fff3cf','#d6c7a0','#ddcda4');const [a,b]=iso(x+.8,y+.1,24);rect(a-1,b-6,2,5,'#446e5e');}
  function render(){
    const state=stateProvider(), night=state.room.light==='night';
    c.clearRect(0,0,450,330);rect(0,0,450,330,night?'#b5c5bd':'#e5ecd8');
    // Soft floor shadow; raised foundation; two shaded walls.
    polygon([[43,229],[231,323],[408,232],[218,142]],night?'#82978b':'#ced9bc');
    box(0,0,8,8,8,'#dec89a','#b89c6b','#a58c62');
    polygon([[49,112],[225,24],[225,112],[49,200]],night?'#829e8e':'#b8c99b');
    polygon([[225,24],[401,112],[401,200],[225,112]],night?'#a0b39b':'#d6dfb8');
    // Floor tile diamond grid.
    for(let x=0;x<8;x++)for(let y=0;y<8;y++){const a=iso(x,y,8),b=iso(x+1,y,8),e=iso(x+1,y+1,8),f=iso(x,y+1,8);polygon([a,b,e,f],(x+y)%2?'#d1bb8f':'#dbc69d');}
    polygon([[49,111],[225,23],[225,28],[49,116]],'#7f996c');polygon([[225,23],[401,111],[401,116],[225,28]],'#8b9e72');
    // Window and landscape on right wall.
    polygon([[271,62],[337,95],[337,145],[271,112]],'#71896e');
    polygon([[275,68],[333,97],[333,136],[275,107]],night?'#365958':'#aad3c0');
    polygon([[276,99],[290,85],[307,112],[320,104],[333,124],[333,135],[276,107]],night?'#537a66':'#88b090');
    polygon([[301,81],[305,83],[305,122],[301,120]],'#eee5bb');polygon([[276,85],[333,113],[333,117],[276,89]],'#eee5bb');
    if(night){rect(323,101,3,3,'#f1dda4');rect(282,78,2,2,'#e7e4b9');}
    // Wall art.
    polygon([[97,111],[127,96],[127,128],[97,143]],'#779364');polygon([[100,113],[124,101],[124,125],[100,137]],'#f0deb1');polygon([[104,128],[112,114],[120,120],[120,125],[104,133]],'#8faa6b');
    box(.3,1.3,1.2,2,43,'#b2996a','#987e55','#796446');
    for(let k=0;k<3;k++){box(.3,1.3,1.25,2,12+k*12,'#ceb184','#ab9166','#876e49');for(let j=0;j<5;j++)box(1.3,1.4+j*.32,.22,.2,20+k*12,['#799977','#d0a471','#697e83','#b8795e'][j%4],'#a8875c','#607966');}
    plant(6.6,.6);
    // Workshop rug.
    polygon([iso(2.1,2.5,9),iso(5.7,2.5,9),iso(5.7,5.7,9),iso(2.1,5.7,9)],'#92ad82');
    polygon([iso(2.35,2.75,9),iso(5.45,2.75,9),iso(5.45,5.45,9),iso(2.35,5.45,9)],'#a9bd91');
    for(let j=0;j<4;j++){const [x,y]=iso(2.8+j*.6,3.5,10);rect(x-2,y-1,4,2,'#d6d4a1');}
    desk(4.8,1.5);desk(1.8,4.4);
    // Lamp, floor cushion and foreground gardening.
    box(6.5,5.8,.6,.6,5,'#aa805a','#855f43','#71513d');const [lx,ly]=iso(6.8,6.1);rect(lx,ly-49,2,44,'#6d7750');polygon([[lx-11,ly-49],[lx+12,ly-49],[lx+7,ly-64],[lx-6,ly-64]],'#e9cc84');rect(lx-5,ly-63,10,2,'#f5e4b0');
    box(.65,6,.9,.8,7,'#d69876','#b77f60','#ac745b');
    if(state.room.plant)plant(6.3,7);else plant(.5,4.1);
    // Characters move only to indicate an actual outstanding task.
    state.characters.forEach((ch,i)=>{
      const working=busyId===ch.id, wobble=working&&!reduced.matches?Math.sin(tick/9)*4:0;
      const [x,y]=iso(i?5.3:3.1,i?3.8:5.1,10);
      if(ch.id===state.selected){polygon([[x-13,y+2],[x,y-4],[x+13,y+2],[x,y+8]],'#f1e4a0');}
      drawSprite(c,x+wobble,y,ch.palette,working&&!reduced.matches?Math.round(Math.sin(tick/6)):0);
      c.fillStyle='#304b3c';c.font='7px monospace';c.textAlign='center';c.fillText(ch.name.slice(0,12),x,y+18);
      if(working){rect(x-9,y-52,18,10,'#ffefbf');c.fillStyle='#46624c';c.fillText('···',x,y-44);}
    });
    if(night){c.fillStyle='#24444c18';c.fillRect(0,0,450,330);}
    output.imageSmoothingEnabled=false;output.clearRect(0,0,900,660);output.drawImage(buffer,0,0,900,660);
    selected=state.selected;
  }
  let raf;
  function frame(){if(!running)return;if(!document.hidden){if(busyId || tick%15===0 || selected!==stateProvider().selected)render();tick++;}raf=requestAnimationFrame(frame);}
  frame();
  return {refresh:render, setBusy(id){busyId=id;render();}, stop(){running=false;cancelAnimationFrame(raf);}};
}
