#!/usr/bin/env node
import { readFile, writeFile, mkdir, readdir, unlink } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { PixelCanvas, integer, validatePalette, assertPalettePixels } from '../../resources/art/lib/pixel.mjs';
import { encodePNG, decodePNG } from '../../resources/art/lib/png.mjs';
import { label } from '../../resources/art/lib/labels.mjs';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const DEFAULT_ART=path.join(ROOT,'resources/art');
export const sha256=bytes=>createHash('sha256').update(bytes).digest('hex');
const json=object=>Buffer.from(JSON.stringify(object,null,2)+'\n');
async function filesIn(directory){
 let entries;try{entries=await readdir(directory,{withFileTypes:true});}catch(error){if(error.code==='ENOENT')return [];throw error;}
 const files=[];
 for(const entry of entries.sort((a,b)=>a.name.localeCompare(b.name,'en'))){
  if(entry.isSymbolicLink())throw new Error(`Symlinks are not art sources: ${entry.name}`);
  const filename=path.join(directory,entry.name);
  if(entry.isDirectory())files.push(...await filesIn(filename));else if(entry.isFile())files.push(filename);
 }
 return files;
}
export function validateMeta(meta){
 if(!/^[a-z][a-z0-9_]*(\.[a-z0-9_]+)+$/.test(meta.id??''))throw new Error('Invalid art id');
 if(!Array.isArray(meta.size)||meta.size.length!==2)throw new Error(`${meta.id}: invalid frame size`);
 integer(...meta.size,meta.frames);const [w,h]=meta.size;
 if(w<1||h<1||meta.frames<1||w*h*meta.frames>16_777_216)throw new Error(`${meta.id}: invalid dimensions/frames`);
 if(!Array.isArray(meta.anchor)||meta.anchor.length!==2)throw new Error(`${meta.id}: invalid anchor`);
 integer(...meta.anchor);if(meta.anchor[0]<0||meta.anchor[1]<0||meta.anchor[0]>w||meta.anchor[1]>h)throw new Error(`${meta.id}: anchor outside frame`);
 if(!meta.animations||typeof meta.animations!=='object'||Array.isArray(meta.animations))throw new Error(`${meta.id}: invalid animations`);
 for(const [name,animation]of Object.entries(meta.animations)){
  if(!/^[a-z][a-z0-9_]*$/.test(name)||!Number.isFinite(animation.fps)||animation.fps<=0||typeof animation.loop!=='boolean'||!Array.isArray(animation.frames)||!animation.frames.length)throw new Error(`${meta.id}: invalid animation ${name}`);
  if(animation.frames.some(frame=>!Number.isSafeInteger(frame)||frame<0||frame>=meta.frames))throw new Error(`${meta.id}: animation frame out of range`);
  if(Object.keys(animation).sort().join(',')!=='fps,frames,loop')throw new Error(`${meta.id}: unexpected animation fields`);
 }
 if(meta.nineSlice!==undefined){
  if(!meta.id.startsWith('ui.panel.')||!Array.isArray(meta.nineSlice)||meta.nineSlice.length!==4)throw new Error(`${meta.id}: invalid nineSlice`);
  integer(...meta.nineSlice);const [left,top,right,bottom]=meta.nineSlice;
  if(meta.nineSlice.some(v=>v<0)||left+right>=w||top+bottom>=h)throw new Error(`${meta.id}: nineSlice leaves no center`);
 }
 const file=meta.file??`${meta.id.replaceAll('.','/')}.png`;
 if(!/^[a-z0-9_/-]+\.png$/.test(file)||file.startsWith('/')||file.split('/').some(part=>!part||part==='.'||part==='..')||file.startsWith('sheets/'))throw new Error(`${meta.id}: unsafe file path`);
 return {id:meta.id,file,size:[...meta.size],frames:meta.frames,anchor:[...meta.anchor],animations:structuredClone(meta.animations),...(meta.nineSlice===undefined?{}:{nineSlice:[...meta.nineSlice]})};
}
export function loadCharacter(source,palette){
 if(source.format!=='art/1'||!Array.isArray(source.frames))throw new Error('Invalid art/1 character source');
 const meta=validateMeta({...source,frames:source.frames.length});
 const frames=source.frames.map((rows,index)=>{
  if(!Array.isArray(rows)||rows.length!==meta.size[1]||rows.some(row=>typeof row!=='string'||row.length!==meta.size[0]))throw new Error(`${meta.id}: invalid character rows in frame ${index}`);
  const g=new PixelCanvas(...meta.size,palette);
  rows.forEach((row,y)=>[...row].forEach((character,x)=>{
   if(character==='.')return;
   const color=palette.characters[character];if(!color)throw new Error(`${meta.id}: unknown source character ${character}`);
   g.px(x,y,color);
  }));
  return g;
 });
 return {meta,frames};
}
export async function renderAssets({artRoot=DEFAULT_ART}={}){
 const palette=validatePalette(JSON.parse(await readFile(path.join(artRoot,'palette.json'),'utf8')));
 const sources=await filesIn(path.join(artRoot,'source'));const rendered=[];
 for(const filename of sources){
  let assets=[];
  if(filename.endsWith('.json'))assets=[loadCharacter(JSON.parse(await readFile(filename,'utf8')),palette)];
  else if(filename.endsWith('.mjs')){
   const module=await import(pathToFileURL(filename));
   if(!Array.isArray(module.assets))throw new Error(`Missing procedural assets array: ${filename}`);
   assets=module.assets.map(asset=>{
    const meta=validateMeta(asset.meta);if(typeof asset.draw!=='function')throw new Error(`${meta.id}: missing draw function`);
    return {meta,frames:Array.from({length:meta.frames},(_,frame)=>{const g=new PixelCanvas(...meta.size,palette);asset.draw(g,{frame,seed:0x41535549});assertPalettePixels(g,palette);return g;})};
   });
  }
  for(const {meta,frames}of assets){
   const strip=new PixelCanvas(meta.size[0]*meta.frames,meta.size[1],palette);
   frames.forEach((frame,index)=>strip.stamp(frame,index*meta.size[0],0));
   assertPalettePixels(strip,palette);const png=encodePNG(strip);
   if(png.length>2_000_000)throw new Error(`${meta.id}: PNG exceeds 2 MB`);
   rendered.push({meta:{...meta,hash:sha256(png)},png,strip});
  }
 }
 rendered.sort((a,b)=>a.meta.id.localeCompare(b.meta.id,'en'));
 if(!rendered.length)throw new Error('No art sources');
 if(new Set(rendered.map(a=>a.meta.id)).size!==rendered.length)throw new Error('Duplicate art id');
 if(new Set(rendered.map(a=>a.meta.file)).size!==rendered.length)throw new Error('Duplicate art output file');
 return {palette,rendered,manifest:{format:'art-manifest/1',assets:rendered.map(a=>a.meta)}};
}
export async function build({artRoot=DEFAULT_ART,exportRoot=path.join(artRoot,'export')}={}){
 const result=await renderAssets({artRoot});
 await mkdir(exportRoot,{recursive:true});
 let previous;try{previous=JSON.parse(await readFile(path.join(exportRoot,'manifest.json'),'utf8'));}catch(error){if(error.code!=='ENOENT')throw error;}
 for(const asset of result.rendered){const filename=path.join(exportRoot,asset.meta.file);await mkdir(path.dirname(filename),{recursive:true});await writeFile(filename,asset.png);}
 // Only retire files tracked by the previous manifest; never delete unknown user files.
 for(const old of previous?.assets??[]){const meta=validateMeta(old);if(!result.manifest.assets.some(asset=>asset.file===meta.file))await unlink(path.join(exportRoot,meta.file)).catch(error=>{if(error.code!=='ENOENT')throw error;});}
 await writeFile(path.join(exportRoot,'manifest.json'),json(result.manifest));
 return result;
}
const ART_KEYS=new Set(['art','artId','assetId','texture','textureId','backgroundArt','portraitArt']);
export async function checkReferences(manifest,contentRoot=path.join(ROOT,'content')){
 const ids=new Set(manifest.assets.map(a=>a.id)),used=new Set();
 function walk(value,key=''){
  if(typeof value==='string'&&ART_KEYS.has(key)){if(!ids.has(value))throw new Error(`Missing content art reference: ${value}`);used.add(value);}
  else if(Array.isArray(value))value.forEach(child=>walk(child,key));
  else if(value&&typeof value==='object')for(const [childKey,child]of Object.entries(value))walk(child,childKey);
 }
 for(const filename of await filesIn(contentRoot))if(filename.endsWith('.json'))walk(JSON.parse(await readFile(filename,'utf8')));
 return {used:[...used].sort(),warnings:[...ids].filter(id=>!used.has(id)).map(id=>`${id}: no content art reference (may be used by view code)`)};
}
export async function verify({artRoot=DEFAULT_ART,exportRoot=path.join(artRoot,'export'),contentRoot=path.join(ROOT,'content')}={}){
 const expected=await renderAssets({artRoot});
 // A second render catches stateful drawing even when an old export happens to match.
 const repeated=await renderAssets({artRoot});
 for(let i=0;i<expected.rendered.length;i++)if(!expected.rendered[i].png.equals(repeated.rendered[i].png))throw new Error('Non-deterministic art source');
 const bytes=await readFile(path.join(exportRoot,'manifest.json'));const actual=JSON.parse(bytes);
 if(actual.format!=='art-manifest/1'||!Array.isArray(actual.assets))throw new Error('Invalid art manifest');
 for(const meta of actual.assets)validateMeta(meta);
 if(!isDeepStrictEqual(actual,expected.manifest)||!bytes.equals(json(expected.manifest)))throw new Error('Manifest differs from source rebuild');
 for(const asset of actual.assets){
  const png=await readFile(path.join(exportRoot,asset.file));const decoded=decodePNG(png);
  if(decoded.width!==asset.size[0]*asset.frames||decoded.height!==asset.size[1])throw new Error(`${asset.id}: PNG dimensions mismatch`);
  assertPalettePixels(decoded,expected.palette);
  if(sha256(png)!==asset.hash)throw new Error(`${asset.id}: PNG hash mismatch`);
  if(!png.equals(expected.rendered.find(item=>item.meta.id===asset.id).png))throw new Error(`${asset.id}: PNG differs from source rebuild`);
 }
 const known=new Set(actual.assets.map(asset=>path.resolve(exportRoot,asset.file)));
 for(const filename of await filesIn(exportRoot))if(filename.endsWith('.png')&&!filename.startsWith(path.join(exportRoot,'sheets')+path.sep)&&!known.has(path.resolve(filename)))throw new Error(`Untracked exported PNG: ${path.relative(exportRoot,filename)}`);
 const refs=await checkReferences(actual,contentRoot);
 return {assets:actual.assets.length,...refs};
}
export async function sheets({artRoot=DEFAULT_ART,exportRoot=path.join(artRoot,'export')}={}){
 const {palette,rendered}=await renderAssets({artRoot});const output=path.join(exportRoot,'sheets');await mkdir(output,{recursive:true});const results=[];
 for(const asset of rendered){
  const {id,size,frames}=asset.meta;
  // All source art and labels are uniformly scaled exactly 3×, nearest-neighbor.
  const logicalWidth=Math.max(asset.strip.width+16,id.length*4+20,144),logicalHeight=size[1]+34;
  const page=new PixelCanvas(logicalWidth,logicalHeight,palette).fill('ink2');
  label(page,id,8,6,'rope4');label(page,`${size[0]}X${size[1]} - ${frames} FRAMES`,8,14,'stone3');
  for(let y=24;y<logicalHeight-6;y+=8)for(let x=8;x<logicalWidth-8;x+=8)page.rect(x,y,Math.min(8,logicalWidth-8-x),Math.min(8,logicalHeight-6-y),((x-8)/8+(y-24)/8)%2?'stone0':'stone1');
  page.stamp(asset.strip,8,24);
  const final=new PixelCanvas(logicalWidth*3,logicalHeight*3,palette).stamp(page,0,0,3);const png=encodePNG(final);
  if(png.length>2_000_000)throw new Error(`${id}: sheet exceeds 2 MB`);
  const filename=path.join(output,`${id}.png`);await writeFile(filename,png);results.push(filename);
 }
 return results;
}
async function main(){
 const command=process.argv[2];
 if(process.argv.length!==3||!['build','verify','sheet'].includes(command))throw new Error('Usage: node tools/resources/art.mjs build|verify|sheet');
 if(command==='build'){const result=await build();console.log(`Art build: ${result.rendered.length} assets (deterministic RGBA PNG)`);}
 if(command==='verify'){const result=await verify();for(const warning of result.warnings)console.warn(`Warning: ${warning}`);console.log(`Art verify: ${result.assets} assets; bytes, hashes, palette, alpha, dimensions, anchors, animation references and content references OK`);}
 if(command==='sheet'){for(const filename of await sheets())console.log(path.relative(ROOT,filename));}
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)main().catch(error=>{console.error(`Art: ${error.message}`);process.exitCode=1;});
