// node stitch.cjs <repo> <left> <right> <out>  — side by side, top aligned, both 1440 wide
const path = require('path');
const sharp = require(path.join(process.argv[2], 'node_modules/sharp'));
(async () => {
  const [, , , l, r, out] = process.argv;
  const ml = await sharp(l).metadata(), mr = await sharp(r).metadata();
  const W = 1440, gap = 40, label = 60;
  const H = Math.max(ml.height, mr.height) + label;
  const svg = Buffer.from(`<svg width="${W*2+gap}" height="${label}"><style>text{font:bold 32px sans-serif}</style>
<text x="20" y="42">LEFT: Ryze  ${path.basename(l)}</text><text x="${W+gap+20}" y="42">RIGHT: ours  ${path.basename(r)}</text></svg>`);
  await sharp({ create: { width: W * 2 + gap, height: H, channels: 3, background: '#ff00ff' } })
    .composite([{ input: svg, top: 0, left: 0 }, { input: l, top: label, left: 0 }, { input: r, top: label, left: W + gap }])
    .png().toFile(out);
  console.log(out, W * 2 + gap, H, 'left', ml.width, ml.height, 'right', mr.width, mr.height);
})();
