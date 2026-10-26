/** Original, deliberately compact D1 readability assets. D2 will add full acting/illustration detail. */
const anim = {idle:{fps:4,loop:true,frames:[0,0,0,1,1,2,3,3]}};
function face(g,x,y,frame=0){
 if(frame===3){g.line(x,y+2,x+3,y+2,'ink');g.line(x+10,y+2,x+13,y+2,'ink');}
 else{g.rect(x,y,4,5,'paper').rect(x+10,y,4,5,'paper');g.rect(x+1,y+1,2,4,'ink').rect(x+10,y+1,2,4,'ink');}
 g.line(x+5,y+8,x+8,y+8,'ink');
}
function sock(g,frame,body='pink1',light='pink2',small=false){
 const x=small?16:10,y=small?18:6,w=small?13:23,h=small?23:35;
 g.polygon([[x,y],[x+w,y],[x+w,y+h-12],[x+w+6,y+h-9],[x+w+7,y+h-3],[x+w+3,y+h],[x+2,y+h],[x,y+h-4]],'ink');
 g.polygon([[x+2,y+2],[x+w-2,y+2],[x+w-2,y+h-10],[x+w+4,y+h-7],[x+w+4,y+h-3],[x+4,y+h-2],[x+2,y+h-5]],body);
 g.rect(x+3,y+3,w-6,5,light);g.line(x+3,y+10,x+3,y+h-7,light);
 g.rect(x+2,y+8,w-4,2,'rope4');g.rect(x+5,y+10,3,4,light);
 if(!small)face(g,x+4,y+14,frame);else{g.px(x+4,y+12,'ink');g.px(x+9,y+12,'ink');}
 if(frame===1||frame===2){g.rect(x-2,y+h-7,3,3,'water2');g.px(x-1,y+h-4,'water3');}
}
function lint(g,f){
 g.polygon([[8,17],[15,8],[26,6],[36,13],[40,25],[34,37],[21,40],[10,34],[5,25]],'ink');
 g.polygon([[10,18],[16,11],[26,9],[34,15],[37,25],[31,34],[21,37],[12,31],[8,25]],'lilac1');
 g.polygon([[12,18],[18,12],[26,11],[29,16],[22,19],[15,24]],'lilac2');
 g.line(9,33,5+(f%2),40,'ink').line(32,36,37-(f%2),42,'ink');face(g,17,22,f);
}
function insole(g,f){
 g.ellipse(12,5,25,38,'ink').ellipse(14,7,21,33,'rope1').ellipse(15,8,14,21,'rope3');
 g.rect(15,25,5,7,'rope2');face(g,17,19,f);
 for(const [x,y] of [[7,7],[36,13],[7,30]])g.line(x,y+(f%2),x+2,y-3+(f%2),'moss2');
}
function pin(g,f){
 g.polygon([[8,6],[17,5],[35,37],[30,42],[19,24],[9,39],[5,35],[15,16]],'ink');
 g.polygon([[11,8],[16,8],[31,36],[29,38],[19,20],[9,35],[8,34],[18,16]],'rope2');
 g.line(13,8,27,31,'rope4').ellipse(14,17,14,12,'ink').ellipse(16,19,10,8,'stone2');
 g.px(19,22,'ink');g.px(24,22,'ink');if(f===1)g.line(29,39,33,43,'rope3');
}
function bubble(g,f){
 g.ellipse(7,7,34,34,'ink').ellipse(9,9,30,30,'water1').ellipse(11,10,26,26,'water2');
 g.ellipse(12,11,17,10,'water4').rect(12,17,4,6,'paper');g.ellipse(22,30,11,5,'water3');face(g,17,22,f);
}
function drawer(g,f){
 g.rect(9,25,76,51,'ink').rect(12,28,70,44,'rope1');g.rect(15,29,64,4,'rope3');
 g.polygon([[9,25],[20,13],[78,13],[85,25]],'ink').polygon([[14,23],[23,16],[75,16],[81,23]],'rope2');
 g.rect(18,36,58,25,'ink2').rect(21,38,52,19,'rope0');
 g.line(22,39,70,39,'rope3');g.rect(39,44+(f%2),17,7,'ink').rect(42,45+(f%2),11,3,'stone3');
 g.rect(20,70,10,15,'rope0').rect(65,70,10,15,'rope0');g.rect(17,82,17,5,'ink').rect(63,82,16,5,'ink');
 face(g,39,25,f);if(f===2)g.rect(32,65,7,5,'lamp2');
}
function snake(g,f){
 const cells=[[129,90],[110,92],[90,87],[75,73],[91,61],[111,55],[115,37],[93,29],[70,35],[48,48]];
 cells.forEach(([x,y],i)=>{const dy=(i%3===f%3)?1:0;g.ellipse(x-13,y-12+dy,28,25,'ink').ellipse(x-10,y-10+dy,22,19,i%2?'lilac1':'pink1').ellipse(x-8,y-9+dy,14,7,i%2?'lilac2':'pink2');g.rect(x-10,y+4+dy,21,3,'rope4');});
 g.ellipse(14,37,48,37,'ink').ellipse(17,39,42,30,'pink1').ellipse(18,39,30,12,'pink2');
 g.rect(20,36,34,6,'rope4');face(g,28,49,f);g.line(29,65,48,65,'ink');
 g.rect(28,65,4,6,'paper').rect(43,65,4,5,'paper');
}
function ropeHead(g,f){
 g.rect(20,0,8,51,'ink').rect(22,0,4,49,'rope2');for(let y=0;y<48;y+=6)g.line(22,y,25,y+3,'rope4');
 g.ellipse(8,43,32,32,'ink').ellipse(10,45,28,28,'rope1').ellipse(12,46,20,18,'rope3');
 g.ellipse(17,50,19,22,'rope0').ellipse(19,52,13,16,'rope2');
 g.line(12,54,33,67,'rope4').line(11,61,30,72,'rope2');face(g,17,54,f);
 g.line(20,73,15,84+(f%2),'rope1').line(24,73,30,85-(f%2),'rope3');
}
const defs=[['enemy.wet_sock',[48,48],(g,f)=>sock(g,f)],['enemy.lonely_sock',[48,48],(g,f)=>sock(g,f,'lilac1','lilac2')],['enemy.lint_bug',[48,48],lint],['enemy.stinky_insole',[48,48],insole],['enemy.clothespin',[48,48],pin],['enemy.soap_bubble',[48,48],bubble],['enemy.sock_kid',[48,48],(g,f)=>sock(g,f,'pink1','pink2',true)],['elite.hungry_drawer',[96,96],drawer],['boss.sock_snake',[160,120],snake],['char.ma_ye',[48,96],ropeHead]];
const assets=defs.map(([id,size,draw])=>({meta:{id,file:id.replaceAll('.','/')+'.png',size,frames:4,anchor:[Math.floor(size[0]/2),size[1]-2],animations:anim},draw(g,{frame}){draw(g,frame);}}));
const intentShapes={attack(g){g.polygon([[4,2],[13,2],[9,8],[7,9]],'paper').line(3,11,8,6,'rope3').line(2,9,6,13,'lamp2');},guard(g){g.polygon([[3,3],[8,1],[13,3],[12,10],[8,14],[4,10]],'water2').line(5,4,8,3,'water4');},summon(g){g.rect(6,2,4,12,'lilac2').rect(2,6,12,4,'lilac2').rect(6,6,4,4,'paper');},buff(g){g.polygon([[8,1],[14,7],[10,7],[10,14],[6,14],[6,7],[2,7]],'lamp2').rect(7,5,2,7,'lamp4');},special(g){g.polygon([[8,1],[14,8],[8,14],[2,8]],'pink1').rect(7,4,2,5,'paper').rect(7,11,2,2,'paper');},idle(g){g.rect(3,4,10,2,'stone3').line(12,6,3,11,'stone3').rect(3,12,10,2,'stone3');}};
for(const [kind,draw]of Object.entries(intentShapes))assets.push({meta:{id:'intent.'+kind,file:'intent/'+kind+'.png',size:[16,16],frames:1,anchor:[8,8],animations:{}},draw(g){draw(g);g.outline('ink');}});
for(const [type,color]of [['attack','red1'],['guard','water2'],['special','lamp2']]){
 for(const [suffix,w,h]of [['s',56,76],['l',112,152]])assets.push({meta:{id:'card.frame_'+suffix+'.'+type,file:'card/frame-'+suffix+'-'+type+'.png',size:[w,h],frames:1,anchor:[0,0],animations:{}},draw(g){g.rect(1,0,w-2,h,'ink').rect(0,2,w,h-4,'ink');g.rect(2,2,w-4,h-4,'rope1').rect(3,3,w-6,h-6,'rope3');g.line(4,3,w-5,3,'rope4').rect(4,5,w-8,h-10,'paper');g.rect(4,5,w-8,5,color);g.rect(4,h-10,w-8,5,color);}});
 assets.push({meta:{id:'cardart.'+type+'_stub',file:'cardart/'+type+'-stub.png',size:[40,28],frames:1,anchor:[0,0],animations:{}},draw(g){g.fill('rope4');if(type==='attack'){g.polygon([[10,4],[26,4],[30,14],[10,16]],'ink').rect(13,6,12,8,'stone2').rect(18,14,5,12,'rope1').rect(19,15,2,10,'rope3');}else if(type==='guard'){g.polygon([[20,2],[32,8],[29,20],[20,26],[11,20],[8,8]],'ink').polygon([[20,4],[29,9],[26,19],[20,23],[14,19],[11,9]],'water2').line(14,10,20,7,'water4');}else{g.ellipse(6,4,27,19,'rope0').ellipse(9,6,21,15,'rope2').ellipse(13,8,13,10,'rope4');g.line(29,17,35,25,'rope1');}}});
}
for(const [id,lair]of [['board.sock_swamp',false],['board.sock_lair',true]])assets.push({meta:{id,file:id.replaceAll('.','/')+'.png',size:[640,360],frames:1,anchor:[0,0],animations:{}},draw(g){
 g.fill(lair?'deep0':'water0');g.polygon([[0,86],[79,61],[161,83],[244,51],[341,79],[436,57],[531,80],[640,57],[640,232],[0,232]],lair?'deep1':'stone0');
 g.rect(0,190,640,170,lair?'ink2':'moss0');g.polygon([[0,222],[107,208],[206,221],[318,201],[438,220],[551,209],[640,221],[640,300],[0,300]],'water0');
 g.ellipse(53,200,527,73,lair?'stone0':'water1');g.ellipse(88,209,459,46,lair?'deep1':'water2');
 for(const[x,y]of[[14,181],[596,179],[35,262],[610,260]]){g.line(x,y,x+4,y-36,'moss1').line(x+5,y,x+15,y-29,'moss2').line(x+1,y,x-8,y-24,'moss1');}
 g.rect(0,288,640,72,'ink2');g.line(0,288,639,288,'rope1');
 g.line(9,75,632,76,'rope1');for(let x=17;x<640;x+=82){g.rect(x,75,8,18,'lilac1').rect(x+5,87,11,8,'lilac1').line(x+1,77,x+6,77,'lilac2');}
 for(const x of [18,603]){g.rect(x,150,14,33,'ink').rect(x+2,153,10,24,'lamp1').rect(x+4,154,6,19,'lamp3').rect(x+4,154,4,11,'lamp4');}
}});
assets.push({meta:{id:'ui.target_rope',file:'ui/target-rope.png',size:[4,4],frames:1,anchor:[2,2],animations:{}},draw(g){g.rect(0,0,4,4,'ink');g.rect(1,0,2,4,'rope2');g.px(1,0,'rope4').px(2,1,'rope4').px(1,2,'rope3').px(2,3,'rope3');}});
export { assets };
