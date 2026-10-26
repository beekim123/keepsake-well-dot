import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateSync } from 'node:zlib';
import { PixelCanvas, validatePalette, assertPalettePixels } from '../resources/art/lib/pixel.mjs';
import { encodePNG, decodePNG, crc32 } from '../resources/art/lib/png.mjs';
import { build, verify, sheets, renderAssets, validateMeta, loadCharacter, checkReferences, sha256 } from '../tools/resources/art.mjs';
const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const artRoot=path.join(ROOT,'resources/art');
const palette=JSON.parse(await readFile(path.join(artRoot,'palette.json'),'utf8'));
const character=JSON.parse(await readFile(path.join(artRoot,'source/char/asui.json'),'utf8'));
// Contract IDs, not a magic asset count: retained D0 art plus D1 readability pack.
const requiredArtIds=["board.sock_lair", "board.sock_swamp", "board.title", "boss.sock_snake", "card.frame_l.attack", "card.frame_l.guard", "card.frame_l.special", "card.frame_s.attack", "card.frame_s.guard", "card.frame_s.special", "cardart.attack_stub", "cardart.guard_stub", "cardart.special_stub", "char.asui", "char.ma_ye", "elite.hungry_drawer", "enemy.clothespin", "enemy.lint_bug", "enemy.lonely_sock", "enemy.soap_bubble", "enemy.sock_kid", "enemy.stinky_insole", "enemy.wet_sock", "intent.attack", "intent.buff", "intent.guard", "intent.idle", "intent.special", "intent.summon", "ui.panel.default", "ui.target_rope"];
const baseMeta={id:'ui.panel.test',size:[16,16],frames:1,anchor:[0,0],animations:{},nineSlice:[4,4,4,4]};

async function temp(fn){const directory=await mkdtemp(path.join(tmpdir(),'keepsake-art-'));try{await fn(directory);}finally{await rm(directory,{recursive:true,force:true});}}
function pngChunk(type,payload){const result=Buffer.alloc(payload.length+12);result.writeUInt32BE(payload.length);result.write(type,4,4,'ascii');payload.copy(result,8);result.writeUInt32BE(crc32(result.subarray(4,-4)),result.length-4);return result;}
function pngWithFilter(filter){
 const header=Buffer.alloc(13);header.writeUInt32BE(2);header.writeUInt32BE(2,4);header[8]=8;header[9]=6;
 const original=Uint8Array.from([27,22,34,255,255,250,240,255,90,58,38,255,232,195,90,255]);
 const rows=[];
 for(let y=0;y<2;y++){
  rows.push(filter);
  for(let x=0;x<8;x++){
   const i=y*8+x,a=x>=4?original[i-4]:0,b=y?original[i-8]:0,c=y&&x>=4?original[i-12]:0,p=a+b-c;
   const pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);
   const predictor=[0,a,b,Math.floor((a+b)/2),pa<=pb&&pa<=pc?a:pb<=pc?b:c][filter];
   rows.push((original[i]-predictor+256)&255);
  }
 }
 return {original,png:Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),pngChunk('IHDR',header),pngChunk('IDAT',deflateSync(Buffer.from(rows))),pngChunk('IEND',Buffer.alloc(0))])};
}

test('the exact original 44 named colors and complete character mapping are kept',()=>{
 assert.equal(validatePalette(palette),palette);
 const expected={ink:'#1b1622',ink2:'#2d2433',deep0:'#241a3a',deep1:'#3d2d5c',stone0:'#3a4150',stone1:'#566070',stone2:'#7d8794',stone3:'#aab3ba',stone4:'#d8dcdc',rope0:'#5a3a26',rope1:'#8a5a36',rope2:'#b9844e',rope3:'#ddb57a',rope4:'#f3dcab',lamp0:'#a8481e',lamp1:'#e07a2c',lamp2:'#f6b444',lamp3:'#ffe08a',lamp4:'#fff6d6',moss0:'#1f3a2e',moss1:'#2e5e3e',moss2:'#4f8a48',moss3:'#8cbf5a',moss4:'#c9e58a',water0:'#1a3348',water1:'#24607a',water2:'#3a95a8',water3:'#7cd0cc',water4:'#c8f0e6',pink1:'#e889a6',pink2:'#f7bfd0',lilac1:'#8e78c8',lilac2:'#c2b2ec',red0:'#6e2230',red1:'#b23a3e',red2:'#e8604c',skin0:'#8c5040',skin1:'#c98466',skin2:'#f0bf98',skin3:'#fbe2c8',navy0:'#22304e',navy1:'#34507a',wheat:'#e8c35a',paper:'#fffaf0'};
 assert.deepEqual(palette.colors,expected);
 const invalid=structuredClone(palette);delete invalid.colors.ink;assert.throws(()=>validatePalette(invalid),/44 colors/);
});
test('PNG encoding is deterministic and RGBA round-trips, including transparent pixels',()=>{
 const g=new PixelCanvas(9,7,palette).rect(1,2,4,3,'lamp3');const a=encodePNG(g),b=encodePNG(g);
 assert.deepEqual(a,b);assert.deepEqual(decodePNG(a),{width:g.width,height:g.height,data:g.data});
 assert.equal(crc32(Buffer.from('123456789')),0xcbf43926);
 assert.throws(()=>encodePNG({width:1.5,height:1,data:new Uint8Array(4)}),/dimensions/);
 assert.throws(()=>encodePNG({width:1,height:1,data:new Uint8Array(3)}),/length/);
});
test('PNG decoder handles all five row filters and rejects corrupt/truncated PNG bytes',()=>{
 for(let filter=0;filter<=4;filter++){const {original,png}=pngWithFilter(filter);assert.deepEqual(decodePNG(png).data,original);}
 const good=pngWithFilter(0).png,bad=Buffer.from(good);bad[40]^=1;
 assert.throws(()=>decodePNG(bad),/CRC/);assert.throws(()=>decodePNG(good.subarray(0,-3)),/Truncated|Missing/);
 assert.throws(()=>decodePNG(Buffer.concat([good,Buffer.from([0])])),/end/);
});
test('PixelCanvas permits clipped integers but forbids fractional coordinates and raw colors',()=>{
 const g=new PixelCanvas(8,8,palette).rect(-2,-2,5,5,'rope3').line(-1,1,7,7,'ink').ellipse(2,1,4,5,'lamp3').polygon([[0,0],[5,0],[3,5]],'rope1');
 assertPalettePixels(g,palette);
 for(const action of [()=>g.px(.1,0,'ink'),()=>g.rect(0,0,1.2,2,'ink'),()=>g.line(0,0,2,3.2,'ink'),()=>g.ellipse(0,0,2.5,3,'ink'),()=>g.polygon([[0,0],[1,1],[2,.2]],'ink'),()=>g.stamp(g,0,0,1.5)])assert.throws(action,/integers/);
 assert.throws(()=>g.px(0,0,'#ffffff'),/Unknown palette/);assert.throws(()=>g.rect(0,0,-1,1,'ink'),/nonnegative/);
});
test('outline, mirror, recolor and integer nearest-neighbor stamping preserve the palette',()=>{
 const g=new PixelCanvas(5,5,palette).px(1,2,'rope4').outline('ink');const before=g.data.slice();
 g.mirror().mirror();assert.deepEqual(g.data,before);g.recolor({rope4:'lamp4'});assertPalettePixels(g,palette);
 const enlarged=new PixelCanvas(15,15,palette).stamp(g,0,0,3);
 for(let y=0;y<15;y++)for(let x=0;x<15;x++)assert.deepEqual(enlarged.data.slice((y*15+x)*4,(y*15+x)*4+4),g.data.slice((Math.floor(y/3)*5+Math.floor(x/3))*4,(Math.floor(y/3)*5+Math.floor(x/3))*4+4));
 const bad=new PixelCanvas(1,1,palette).px(0,0,'ink');bad.data[3]=120;assert.throws(()=>g.stamp(bad,0,0),/partial-alpha/);
});
test('palette validation rejects partial alpha, non-palette RGB, and hidden RGB',()=>{
 for(const [rgba,message]of [[[27,22,34,128],/Partial alpha/],[[1,2,3,255],/Non-palette/],[[1,0,0,0],/transparent RGB/]])assert.throws(()=>assertPalettePixels({data:Uint8Array.from(rgba)},palette),message);
});
test('character source has four real poses, planted feet, held idle timing and valid bounds',()=>{
 const {meta,frames}=loadCharacter(character,palette);assert.deepEqual(meta.size,[48,64]);assert.equal(frames.length,4);assert.equal(new Set(frames.map(g=>sha256(g.data))).size,4);
 assert.equal(meta.animations.idle.fps,4);assert.ok(meta.animations.idle.frames.length>4);
 // Four lower boot rows stay identical while the upper body/eyes/hand differ.
 for(const frame of frames.slice(1))for(let y=57;y<60;y++)assert.deepEqual(frame.data.slice((y*48+12)*4,(y*48+36)*4),frames[0].data.slice((y*48+12)*4,(y*48+36)*4));
 const malformed=structuredClone(character);malformed.frames[0][0]='.';assert.throws(()=>loadCharacter(malformed,palette),/rows/);
 const unknown=structuredClone(character);unknown.frames[0][0]='?'+unknown.frames[0][0].slice(1);assert.throws(()=>loadCharacter(unknown,palette),/unknown source character/);
});
test('metadata rejects dimensions, anchors, invalid animation frames, unsafe paths and nine-slice margins',()=>{
 assert.deepEqual(validateMeta(baseMeta).nineSlice,[4,4,4,4]);
 for(const modification of [{size:[0,16]},{anchor:[17,0]},{anchor:[.5,0]},{file:'../outside.png'},{file:'/tmp/a.png'},{frames:0},{nineSlice:[8,4,8,4]},{animations:{idle:{fps:4,loop:true,frames:[1]}}},{animations:{idle:{fps:0,loop:true,frames:[0]}}}])assert.throws(()=>validateMeta({...baseMeta,...modification}));
});
test('build/rebuild is byte-identical; verify is read-only; sheet output is exactly 3× nearest',async()=>temp(async directory=>{
 const exportRoot=path.join(directory,'export'),contentRoot=path.join(directory,'content');await mkdir(contentRoot);
 const first=await build({artRoot,exportRoot}),before=await readFile(path.join(exportRoot,'manifest.json'));
 const second=await build({artRoot,exportRoot});assert.deepEqual(first.manifest,second.manifest);
 assert.deepEqual(first.manifest.assets.map(asset=>asset.id).sort(),requiredArtIds);
 assert.deepEqual(first.rendered.map(asset=>asset.meta.id).sort(),requiredArtIds);
 for(const [i,asset]of first.rendered.entries())assert.deepEqual(asset.png,second.rendered[i].png);
 const result=await verify({artRoot,exportRoot,contentRoot});assert.equal(result.assets,requiredArtIds.length);assert.deepEqual(await readFile(path.join(exportRoot,'manifest.json')),before);
 const filenames=await sheets({artRoot,exportRoot});assert.deepEqual(filenames.map(filename=>path.basename(filename,'.png')).sort(),requiredArtIds);
 for(const filename of filenames){const image=decodePNG(await readFile(filename));assert.equal(image.width%3,0);assert.equal(image.height%3,0);assertPalettePixels(image,palette);assert.ok((await readFile(filename)).length<2_000_000);
  for(let y=0;y<image.height;y+=3)for(let x=0;x<image.width;x+=3){const pixel=image.data.slice((y*image.width+x)*4,(y*image.width+x)*4+4);for(let yy=0;yy<3;yy++)for(let xx=0;xx<3;xx++)assert.deepEqual(image.data.slice(((y+yy)*image.width+x+xx)*4,((y+yy)*image.width+x+xx)*4+4),pixel);}
 }
}));
test('verify rejects edited pixels, dimensions, palette, alpha, hashes, manifests and orphan exports',async()=>temp(async directory=>{
 const exportRoot=path.join(directory,'export'),contentRoot=path.join(directory,'content');await mkdir(contentRoot);const built=await build({artRoot,exportRoot});
 const target=built.rendered.find(asset=>asset.meta.id==='char.asui'),filename=path.join(exportRoot,target.meta.file),manifestFile=path.join(exportRoot,'manifest.json'),manifestBytes=await readFile(manifestFile);
 const restore=async()=>{await writeFile(filename,target.png);await writeFile(manifestFile,manifestBytes);};
 for(const change of [image=>image.data.set([255,250,240,255],0),image=>image.data.set([1,2,3,255],0),image=>image.data.set([27,22,34,128],0)]){
  const image=decodePNG(target.png);change(image);await writeFile(filename,encodePNG(image));await assert.rejects(verify({artRoot,exportRoot,contentRoot}),/hash|Non-palette|Partial alpha/);await restore();
 }
 await writeFile(filename,encodePNG(new PixelCanvas(1,1,palette)));await assert.rejects(verify({artRoot,exportRoot,contentRoot}),/dimensions/);await restore();
 const altered=structuredClone(built.manifest);altered.assets[1].anchor=[999,0];await writeFile(manifestFile,JSON.stringify(altered));await assert.rejects(verify({artRoot,exportRoot,contentRoot}),/anchor/);await restore();
 const hashEdit=structuredClone(built.manifest);hashEdit.assets[0].hash='0'.repeat(64);await writeFile(manifestFile,JSON.stringify(hashEdit,null,2)+'\n');await assert.rejects(verify({artRoot,exportRoot,contentRoot}),/Manifest differs/);await restore();
 await writeFile(path.join(exportRoot,'orphan.png'),target.png);await assert.rejects(verify({artRoot,exportRoot,contentRoot}),/Untracked/);
}));
test('content art references resolve recursively, with missing assets rejected and unused warnings',async()=>temp(async directory=>{
 const {manifest}=await renderAssets({artRoot});await writeFile(path.join(directory,'cards.json'),JSON.stringify([{nested:{art:'ui.panel.default'}}]));
 const good=await checkReferences(manifest,directory);assert.deepEqual(good.used,['ui.panel.default']);assert.equal(good.warnings.length,requiredArtIds.length-good.used.length);
 for(const id of requiredArtIds.filter(id=>!good.used.includes(id)))assert.ok(good.warnings.some(warning=>warning.includes(id)),`unused warning for ${id}`);
 await writeFile(path.join(directory,'cards.json'),JSON.stringify([{art:'enemy.missing'}]));await assert.rejects(checkReferences(manifest,directory),/Missing content art reference/);
}));
