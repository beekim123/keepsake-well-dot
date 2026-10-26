/** Integer-only, palette-only drawing. Clipping is allowed; fractional placement is not. */
export function integer(...values) {
  if (values.some(value => !Number.isSafeInteger(value))) throw new Error('Pixel coordinates must be safe integers');
}
export function validatePalette(palette) {
  if (palette.format !== 'palette/1' || Object.keys(palette.colors ?? {}).length !== 44) throw new Error('Expected palette/1 with exactly 44 colors');
  const hexes = new Set();
  for (const [name, hex] of Object.entries(palette.colors)) {
    if (!/^[a-z][a-z0-9]*$/.test(name) || !/^#[0-9a-f]{6}$/.test(hex) || hexes.has(hex)) throw new Error(`Invalid palette color: ${name}`);
    hexes.add(hex);
  }
  for (const [char, name] of Object.entries(palette.characters ?? {})) {
    if (char.length !== 1 || char === '.' || !Object.hasOwn(palette.colors, name)) throw new Error(`Invalid palette character: ${char}`);
  }
  if (new Set(Object.values(palette.characters)).size !== 44) throw new Error('Every palette color needs a character');
  return palette;
}
export class PixelCanvas {
  constructor(width, height, palette) {
    integer(width, height);
    if (width < 1 || height < 1 || width * height > 16_777_216) throw new Error('Invalid canvas dimensions');
    this.width = width; this.height = height; this.palette = palette; this.data = new Uint8Array(width * height * 4);
    this.colors = Object.fromEntries(Object.entries(palette.colors).map(([name, hex]) => [name, [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16), 255]]));
  }
  color(name) {
    if (name === '.') return [0, 0, 0, 0];
    if (!Object.hasOwn(this.colors, name)) throw new Error(`Unknown palette color: ${name}`);
    return this.colors[name];
  }
  px(x, y, color) {
    integer(x, y); const rgba = this.color(color);
    if (x >= 0 && y >= 0 && x < this.width && y < this.height) this.data.set(rgba, (y * this.width + x) * 4);
    return this;
  }
  fill(color) { return this.rect(0, 0, this.width, this.height, color); }
  rect(x, y, width, height, color) {
    integer(x, y, width, height); this.color(color);
    if (width < 0 || height < 0) throw new Error('Rectangle size must be nonnegative');
    for (let py = Math.max(0, y); py < Math.min(this.height, y + height); py++) for (let px = Math.max(0, x); px < Math.min(this.width, x + width); px++) this.px(px, py, color);
    return this;
  }
  line(x0, y0, x1, y1, color) {
    integer(x0, y0, x1, y1); this.color(color);
    const dx = Math.abs(x1 - x0), sx = x0 < x1 ? 1 : -1, dy = -Math.abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    let error = dx + dy;
    while (true) {
      this.px(x0, y0, color); if (x0 === x1 && y0 === y1) break;
      const twice = error * 2;
      if (twice >= dy) { error += dy; x0 += sx; }
      if (twice <= dx) { error += dx; y0 += sy; }
    }
    return this;
  }
  ellipse(x, y, width, height, color) {
    integer(x, y, width, height); this.color(color);
    if (width < 1 || height < 1) throw new Error('Ellipse size must be positive');
    for (let py = 0; py < height; py++) for (let px = 0; px < width; px++) {
      // Integer form of the pixel-center ellipse test; predictable at even dimensions.
      if ((2 * px + 1 - width) ** 2 * height ** 2 + (2 * py + 1 - height) ** 2 * width ** 2 <= width ** 2 * height ** 2) this.px(x + px, y + py, color);
    }
    return this;
  }
  polygon(points, color) {
    if (!Array.isArray(points) || points.length < 3) throw new Error('Polygon needs three points');
    for (const point of points) { if (point.length !== 2) throw new Error('Invalid polygon point'); integer(...point); }
    this.color(color);
    const minY = Math.max(0, Math.min(...points.map(p => p[1]))), maxY = Math.min(this.height - 1, Math.max(...points.map(p => p[1])));
    for (let y = minY; y <= maxY; y++) {
      const crossings = [];
      for (let i = 0; i < points.length; i++) {
        const [x1, y1] = points[i], [x2, y2] = points[(i + 1) % points.length];
        if ((y1 <= y && y < y2) || (y2 <= y && y < y1)) crossings.push(x1 + (y - y1) * (x2 - x1) / (y2 - y1));
      }
      crossings.sort((a, b) => a - b);
      for (let i = 0; i + 1 < crossings.length; i += 2) this.rect(Math.ceil(crossings[i]), y, Math.floor(crossings[i + 1]) - Math.ceil(crossings[i]) + 1, 1, color);
    }
    for (let i = 0; i < points.length; i++) this.line(...points[i], ...points[(i + 1) % points.length], color);
    return this;
  }
  stamp(other, x, y, scale = 1) {
    integer(x, y, scale); if (scale < 1) throw new Error('Stamp scale must be a positive integer');
    const allowed = new Set(Object.values(this.colors).map(rgba => rgba.join(',')));
    for (let sy = 0; sy < other.height; sy++) for (let sx = 0; sx < other.width; sx++) {
      const rgba = other.data.subarray((sy * other.width + sx) * 4, (sy * other.width + sx) * 4 + 4);
      if (rgba[3] === 0) continue;
      if (rgba[3] !== 255 || !allowed.has([...rgba].join(','))) throw new Error('Stamp contains a non-palette or partial-alpha pixel');
      for (let yy = 0; yy < scale; yy++) for (let xx = 0; xx < scale; xx++) {
        const dx = x + sx * scale + xx, dy = y + sy * scale + yy;
        if (dx >= 0 && dy >= 0 && dx < this.width && dy < this.height) this.data.set(rgba, (dy * this.width + dx) * 4);
      }
    }
    return this;
  }
  outline(color = 'ink') {
    const before = this.data.slice(); this.color(color);
    for (let y = 0; y < this.height; y++) for (let x = 0; x < this.width; x++) {
      if (before[(y * this.width + x) * 4 + 3]) continue;
      if ([[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([nx,ny]) => nx >= 0 && ny >= 0 && nx < this.width && ny < this.height && before[(ny * this.width + nx) * 4 + 3])) this.px(x, y, color);
    }
    return this;
  }
  mirror() {
    const before = this.data.slice();
    for (let y = 0; y < this.height; y++) for (let x = 0; x < this.width; x++) this.data.set(before.subarray((y * this.width + this.width - 1 - x) * 4, (y * this.width + this.width - 1 - x) * 4 + 4), (y * this.width + x) * 4);
    return this;
  }
  recolor(map) {
    const changes = new Map(Object.entries(map).map(([from, to]) => [this.color(from).join(','), this.color(to)]));
    for (let offset = 0; offset < this.data.length; offset += 4) {
      const color = changes.get([...this.data.subarray(offset, offset + 4)].join(','));
      if (color) this.data.set(color, offset);
    }
    return this;
  }
}
export function assertPalettePixels(image, palette) {
  const allowed = new Set(Object.values(palette.colors).map(hex => `${parseInt(hex.slice(1,3),16)},${parseInt(hex.slice(3,5),16)},${parseInt(hex.slice(5,7),16)}`));
  for (let i = 0; i < image.data.length; i += 4) {
    const alpha = image.data[i + 3];
    if (alpha !== 0 && alpha !== 255) throw new Error(`Partial alpha at pixel ${i / 4}`);
    if (alpha && !allowed.has([...image.data.subarray(i, i + 3)].join(','))) throw new Error(`Non-palette color at pixel ${i / 4}`);
    if (!alpha && image.data.subarray(i, i + 3).some(value => value !== 0)) throw new Error(`Nonzero transparent RGB at pixel ${i / 4}`);
  }
}
