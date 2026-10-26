/** Original side-view miniature. Grouped facets, fixed top-left light, no image inputs. */
function stone(g,x,y,w,h,lit=false){
 g.polygon([[x+2,y],[x+w-3,y],[x+w-1,y+2],[x+w-1,y+h-2],[x+w-3,y+h],[x+1,y+h],[x,y+2]],'ink2');
 g.rect(x+2,y+1,w-5,h-2,lit?'stone2':'stone1');
 g.line(x+3,y+1,x+w-4,y+1,lit?'stone3':'stone2');
 g.line(x+2,y+2,x+2,y+h-3,lit?'stone3':'stone2');
}
function leaves(g,x,y,s,color){
 g.polygon([[x,y],[x+6*s,y-6*s],[x+12*s,y-5*s],[x+17*s,y],[x+23*s,y+2*s],[x+24*s,y+8*s],[x+19*s,y+12*s],[x+4*s,y+12*s],[x-3*s,y+7*s]],color);
}
function rope(g,x,y,length){
 g.rect(x,y,5,length,'rope0').rect(x+1,y,3,length,'rope2');
 for(let yy=y;yy<y+length-2;yy+=6)g.line(x+1,yy+1,x+3,yy+3,'rope4').line(x+1,yy+3,x+3,yy+5,'rope1');
}
export const assets=[{
 meta:{id:'board.title',file:'board/title.png',size:[640,360],frames:1,anchor:[0,0],animations:{}},
 draw(g){
  // Cool, quiet left half stays available for the engine-rendered title and menu.
  g.fill('deep0');
  g.polygon([[0,112],[70,91],[142,105],[202,89],[268,110],[329,75],[396,94],[462,80],[538,102],[640,78],[640,283],[0,283]],'deep1');
  g.polygon([[0,162],[83,146],[146,164],[225,138],[302,153],[381,126],[452,154],[548,136],[640,145],[640,295],[0,295]],'stone0');
  // Distant small town roofs, not an explorable map.
  for(const [x,y,w] of [[247,145,49],[304,133,56],[559,128,49]]){
   g.rect(x,y,w,67,'stone0');g.polygon([[x-7,y],[x+Math.floor(w/2),y-23],[x+w+7,y],[x+w+4,y+5],[x-5,y+5]],'ink2');
   g.rect(x+12,y+14,9,14,'deep1').rect(x+13,y+15,6,10,'rope1');
  }
  // Upper silhouettes frame the warm scene, without covering left-side words.
  g.polygon([[605,0],[626,0],[613,132],[622,218],[608,276],[591,276],[603,212],[594,131]],'ink2');
  g.line(606,84,557,50,'ink2').line(607,130,638,94,'ink2');
  leaves(g,527,8,3,'ink2');leaves(g,583,37,3,'ink2');
  leaves(g,-25,-18,4,'ink2');leaves(g,70,-23,3,'ink2');
  // Ground is made from broad grassy terraces and a few deliberate stone clusters.
  g.polygon([[0,283],[108,280],[189,287],[256,279],[323,286],[413,273],[515,279],[640,266],[640,360],[0,360]],'moss0');
  g.polygon([[0,323],[99,313],[196,318],[258,305],[353,312],[408,298],[528,301],[640,288],[640,360],[0,360]],'ink2');
  g.polygon([[320,285],[412,276],[510,279],[590,294],[563,319],[463,333],[321,326],[256,317]],'stone0');
  g.polygon([[368,289],[433,281],[507,286],[548,301],[502,316],[404,321],[325,313]],'stone1');
  // Rope hut: asymmetrical pitched roof, deep porch and golden window.
  g.rect(380,156,184,135,'ink');g.rect(386,160,170,127,'rope0');
  g.rect(389,161,92,124,'rope1');
  for(let y=173;y<286;y+=15)g.line(390,y,477,y,'rope0').line(390,y+1,475,y+1,'rope2');
  g.rect(484,171,69,116,'ink2');g.rect(488,176,60,111,'deep0');
  g.rect(503,179,35,108,'rope0').rect(506,181,28,104,'rope1');
  g.rect(510,182,4,101,'rope2').rect(530,184,2,99,'rope0');
  g.rect(526,232,3,4,'rope4');
  g.polygon([[385,158],[456,117],[553,158]],'rope0');
  g.line(414,144,518,144,'rope1').line(436,132,485,132,'rope1');
  g.polygon([[360,160],[387,125],[456,96],[510,116],[573,158],[568,168],[455,123],[386,168]],'ink');
  g.polygon([[367,157],[391,130],[456,102],[507,122],[565,158],[456,116],[387,160]],'rope0');
  g.polygon([[369,155],[395,132],[456,106],[455,117],[388,158]],'rope2');
  g.line(398,131,455,108,'rope3').line(383,151,453,121,'rope1');
  for(let x=466;x<=550;x+=20)g.line(x,123+Math.floor((x-466)/2),x+8,136+Math.floor((x-466)/2),'ink2');
  g.rect(390,158,7,130,'ink').rect(392,159,3,127,'rope3');
  g.rect(552,161,8,128,'ink').rect(553,162,3,124,'rope2');
  g.rect(383,285,183,5,'ink').rect(385,285,178,2,'rope2');
  // Deep-set window uses crisp nested bands, not alpha glows.
  g.rect(410,180,54,55,'ink');g.rect(412,181,50,51,'rope3').rect(416,184,42,45,'lamp0');
  g.rect(418,186,38,40,'lamp1').rect(420,187,33,32,'lamp2').rect(420,187,29,25,'lamp3');
  g.rect(421,188,21,17,'lamp4');g.rect(434,184,4,45,'rope0').rect(416,204,42,4,'rope0');
  g.rect(407,232,61,5,'ink').rect(409,232,57,2,'rope3');
  // Small shelf with a bread tin and a tied parcel, silhouettes kept simple.
  g.rect(406,252,62,5,'ink').rect(407,252,60,2,'rope2');
  g.rect(413,241,15,11,'ink').rect(415,242,11,9,'stone2').rect(414,240,13,3,'stone3');
  g.rect(444,239,14,13,'rope0').rect(445,240,12,10,'rope3').rect(450,239,2,12,'rope1');
  // Well windlass, rope and mossy stone lip: central storytelling object.
  g.rect(450,192,9,105,'ink').rect(452,194,4,101,'rope2').rect(452,194,1,98,'rope4');
  g.rect(537,192,9,105,'ink').rect(539,194,4,101,'rope1');
  g.rect(445,189,105,10,'ink').rect(447,190,101,6,'rope1').rect(448,190,98,2,'rope3');
  g.rect(484,185,29,18,'ink').rect(486,186,25,15,'rope0');
  for(let x=487;x<512;x+=5)g.rect(x,186,2,14,'rope3').rect(x+2,188,2,12,'rope1');
  rope(g,496,202,76);
  g.rect(543,184,4,28,'ink').rect(544,185,2,25,'rope3').rect(540,208,12,5,'ink').rect(542,209,9,2,'rope2');
  g.ellipse(437,271,119,47,'ink');g.ellipse(442,274,108,34,'stone1');
  g.rect(440,287,113,31,'ink');
  for(const [x,y,w,h]of[[443,287,28,14],[473,288,37,14],[512,286,36,14],[443,303,37,14],[482,304,34,14],[518,302,30,14]])stone(g,x,y,w,h,x<500);
  g.ellipse(436,267,121,32,'ink').ellipse(440,269,113,26,'stone2').ellipse(449,272,94,18,'stone0').ellipse(454,273,84,15,'deep0');
  g.line(447,271,471,269,'stone3').line(440,280,444,275,'stone3');
  g.rect(495,272,5,11,'rope0').rect(496,272,2,9,'rope2');
  g.polygon([[438,291],[446,289],[452,291],[454,297],[449,300],[443,298]],'moss1');
  g.line(440,292,447,291,'moss3').rect(446,294,5,2,'moss2');
  // Lamp on the well post: the warmest small focal point.
  g.line(456,224,467,224,'rope0').line(467,224,467,232,'ink');
  g.rect(462,231,13,22,'ink').rect(463,233,11,16,'lamp1').rect(465,234,7,12,'lamp3').rect(466,234,4,8,'lamp4');
  g.rect(462,231,13,3,'rope3').rect(463,250,11,3,'rope1').rect(468,232,2,18,'rope0');
  // Stones and grasses form authored clusters, never random scattered noise.
  for(const [x,y,w]of[[322,329,28],[365,335,34],[406,329,26],[561,319,29],[587,305,22],[288,307,20]])stone(g,x,y,w,5,false);
  for(const [x,y]of[[344,294],[569,283],[588,326],[262,301],[617,299],[187,291]]){
   g.line(x,y,x-5,y-11,'moss1').line(x+1,y,x+3,y-15,'moss2').line(x+3,y,x+10,y-8,'moss1');
   g.line(x+2,y-3,x+3,y-11,'moss3');
  }
  // A tidy folded rope at the doorstep, an invitation to return home.
  g.ellipse(376,275,25,13,'ink').ellipse(378,276,21,10,'rope2').ellipse(382,278,13,6,'rope0').ellipse(385,279,7,3,'ink2');
  g.line(379,279,383,277,'rope4').line(394,282,403,286,'rope2');
 }
}];
