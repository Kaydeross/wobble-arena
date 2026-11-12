'use strict';
/*
  Exports every level's look from the web game (the real thing, run in headless Chromium) for the Godot app:
    - decor: every mesh the level's build() adds that is not a collision box, ladder, bounce pad or floor pad
      (trees, rocks, rings, lamps, snowmen, ...), plus the far scenery ring (buildFar: mountains, city, ships, ...),
      the clouds and the far hills / void plane, all baked to world space at t = 0 (moving pieces stand still)
    - look: the sky bands, fog, hemisphere and sun colours after setBackdrop + gradeLook, sun direction / size, night
  Writes godot/data/extra/decor/<map>.bin (triangles grouped by material kind, see FORMAT) and
  godot/data/extra/map_look.json. Needs network (three.js CDN) and playwright chromium.
    node tools/export-map-decor.js [mapId ...]          --stats  only print triangle counts

  FORMAT (little endian): "WAD1", u32 groupCount, then per group:
    u8 kind (0 lit, 1 unlit, 2 unlit transparent, 3 additive glow, 4 lit transparent), u8 fog (1 = fogged like the level),
    u8 shadow (bit 0 casts, bit 1 receives), u8 opacity*255, f32 emission (lit: emissive = colour * this),
    u32 vertexCount, u32 indexCount, f32[6] aabb (min xyz, size xyz),
    vertexCount * (u16 x, u16 y, u16 z quantised into the aabb, u8 r, g, b, a [, u8 u, v for kind 3]),
    padding to 4 bytes, [when shadow bit 2 is set: vertexCount * f32[12] motion, see ANIM below,]
    indexCount * u32 (triangles wound for Godot: clockwise front faces)
  ANIM (magic "WAD2"): the pieces the web game moves every frame (backdrop.anim: balloons, ships, blimps, turbines,
    smoke, ...) are measured here by running the anims for 8 s: each piece's motion is fitted as a steady rotation
    (angular velocity w round an axis through pivot c: orbits and spinning hubs) plus a bob (vector b * sin(f t)).
    Leaves get a wind flag (far scenery leaves the web sways: 1; trees in the level: 2) and liquids a shimmer flag
    (lava 3, water 4). Per vertex: c.xyz, 0, w.xyz, flag, b.xyz, f. Godot animates them in the decor vertex shader.
*/
const fs = require('fs'), os = require('os'), path = require('path');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-decor-' + process.pid;
const ROOT = path.join(__dirname, '..');
const OUT = path.join(ROOT, 'godot', 'data', 'extra', 'decor');
const LOOK = path.join(ROOT, 'godot', 'data', 'extra', 'map_look.json');
const args = process.argv.slice(2), stats = args.includes('--stats'), only = args.filter(a => !a.startsWith('--'));

// ---------------------------------------------------------------- runs inside the page
// Runs the backdrop's per-frame anims for 8 s (then puts every object back as it was) and fits each moving mesh's
// world motion: a steady rotation (axis through a pivot, from the t = 1 s and 2 s poses) and a bob (what is left).
// Returns Map(mesh -> [c.x, c.y, c.z, 0, w.x, w.y, w.z, 0, b.x, b.y, b.z, f]).
function measureAnims(W, T, bd, indoor) {
  const res = new Map();
  if (indoor || !bd.anim.length) return res;
  const objs = [], meshes = [];
  const roots = [bd.far, bd.farA, ...bd.clouds, ...W.hills, ...W.mapObjs];
  for (const r of roots) r.traverse(o => { objs.push(o); if (o.isMesh) meshes.push(o); });
  const saved = objs.map(o => [o.position.clone(), o.quaternion.clone(), o.scale.clone(), o.visible]);
  W.scene.updateMatrixWorld(true);
  const M0 = meshes.map(m => m.matrixWorld.clone());
  const DT = 0.05, N = 160, M1 = [], M2 = [], P = meshes.map(() => []);
  for (let s = 1; s <= N; s++) {
    const t = s * DT;
    for (const f of bd.anim) { try { f(t, DT); } catch (e) { /* ignore */ } }
    W.scene.updateMatrixWorld(true);
    meshes.forEach((m, i) => {
      if (s === 20) M1[i] = m.matrixWorld.clone();
      if (s === 40) M2[i] = m.matrixWorld.clone();
      P[i].push(new T.Vector3().setFromMatrixPosition(m.matrixWorld));
    });
  }
  objs.forEach((o, i) => { const [p, q, sc, v] = saved[i]; o.position.copy(p); o.quaternion.copy(q); o.scale.copy(sc); o.visible = v; });
  W.scene.updateMatrixWorld(true);
  const rot = (D) => { const p = new T.Vector3(), q = new T.Quaternion(), sc = new T.Vector3(); D.decompose(p, q, sc); if (q.w < 0) { q.x = -q.x; q.y = -q.y; q.z = -q.z; q.w = -q.w; } const th = 2 * Math.acos(Math.min(1, q.w)), sn = Math.sqrt(Math.max(0, 1 - q.w * q.w)); const ax = sn > 1e-6 ? new T.Vector3(q.x / sn, q.y / sn, q.z / sn) : new T.Vector3(0, 1, 0); return { th, ax, t: p }; };
  meshes.forEach((m, i) => {
    const p0 = new T.Vector3().setFromMatrixPosition(M0[i]);
    let moved = false;
    for (const p of P[i]) if (p.distanceTo(p0) > 0.02) { moved = true; break; }
    const D1 = M1[i].clone().multiply(M0[i].clone().invert()), D2 = M2[i].clone().multiply(M0[i].clone().invert());
    const r1 = rot(D1), r2 = rot(D2);
    let w = new T.Vector3(), c = p0.clone();
    if (r1.th > 0.003 && r1.th < 1.5 && Math.abs(r2.th - 2 * r1.th) < 0.25 * r1.th + 0.002 && r1.ax.dot(r2.ax) > 0.98) {
      const a = r1.ax, th = r1.th, tp = r1.t.clone().sub(a.clone().multiplyScalar(r1.t.dot(a)));
      const al = 1 - Math.cos(th), be = Math.sin(th);
      c = tp.clone().multiplyScalar(al).add(a.clone().cross(tp).multiplyScalar(be)).multiplyScalar(1 / (al * al + be * be));
      w = a.clone().multiplyScalar(th);
    } else if (!moved) return;
    // bob: what the rotation does not explain
    let best = new T.Vector3(), bl = 0;
    const res1 = [];
    P[i].forEach((p, s) => {
      const t = (s + 1) * DT, q = new T.Quaternion();
      if (w.lengthSq() > 0) q.setFromAxisAngle(w.clone().normalize(), w.length() * t);
      const pm = p0.clone().sub(c).applyQuaternion(q).add(c), r = p.clone().sub(pm);
      res1.push(r);
      if (r.length() > bl) { bl = r.length(); best = r.clone(); }
    });
    if (w.lengthSq() === 0 && bl < 0.05) return;
    if (bl > 4) best.multiplyScalar(4 / bl);
    const ax = Math.abs(best.x) > Math.abs(best.y) ? (Math.abs(best.x) > Math.abs(best.z) ? 'x' : 'z') : (Math.abs(best.y) > Math.abs(best.z) ? 'y' : 'z');
    let n = 0; for (let s = 1; s < res1.length; s++) if (Math.sign(res1[s][ax]) !== Math.sign(res1[s - 1][ax]) && Math.abs(res1[s][ax]) > 1e-4) n++;
    const f = n ? Math.PI * n / (N * DT) : 0.4;
    res.set(m, [c.x, c.y, c.z, 0, w.x, w.y, w.z, 0, bl < 0.05 ? 0 : best.x, bl < 0.05 ? 0 : best.y, bl < 0.05 ? 0 : best.z, +f.toFixed(3)]);
  });
  return res;
}

function grab(id) {
  const W = window.__wa, T = W.THREE;
  W.cfg.dyn = 'off';
  W.loadMap(id);
  const out = { id, groups: {}, notes: [] };
  const skipSet = new Set(W.solidMeshes);
  for (const p of W.pads) { skipSet.add(p.mesh); skipSet.add(p.core); }
  const m4 = new T.Matrix4(), v = new T.Vector3(), c = new T.Color();
  const add = (mesh, extraMat) => {
    const mat = mesh.material, an = animOf(mesh); if (!mat || Array.isArray(mat)) { out.notes.push('multi-material mesh skipped'); return; }
    if (mat.visible === false) return;
    const geo = mesh.geometry; if (!geo || !geo.attributes || !geo.attributes.position) return;
    const basic = mat.isMeshBasicMaterial, additive = mat.blending === T.AdditiveBlending, transp = !!mat.transparent && mat.opacity < 0.999;
    const kind = additive ? 3 : basic ? (transp ? 2 : 1) : (transp ? 4 : 0);
    let em = 0;
    if (!basic && mat.emissive && mat.emissiveIntensity > 0 && (mat.emissive.r + mat.emissive.g + mat.emissive.b) > 0) {
      const cc = mat.color; em = mat.emissiveIntensity * (cc.r + cc.g + cc.b > 0 ? (mat.emissive.r + mat.emissive.g + mat.emissive.b) / (cc.r + cc.g + cc.b) : 1);
    }
    const fog = mat.fog !== false ? 1 : 0, shadow = (mesh.castShadow ? 1 : 0) | (mesh.receiveShadow ? 2 : 0), op = transp ? Math.round(mat.opacity * 255) : 255;
    const key = [kind, fog, shadow | (an ? 4 : 0), op, em.toFixed(3)].join('|');
    let g = out.groups[key]; if (!g) g = out.groups[key] = { kind, fog, shadow: shadow | (an ? 4 : 0), op, em, pos: [], col: [], idx: [], anim: an ? [] : null };
    const pa = geo.attributes.position, ca = mat.vertexColors && geo.attributes.color, ix = geo.index, ua = geo.attributes.uv;
    if (!g.uv) g.uv = [];
    const base = mat.color || new T.Color(1, 1, 1), b0 = g.pos.length / 3;
    const doubled = mat.side === T.DoubleSide;
    const inst = mesh.isInstancedMesh ? mesh.count : 0;
    const mats = [];
    if (inst) { for (let k = 0; k < inst; k++) { const im = new T.Matrix4(); mesh.getMatrixAt(k, im); mats.push(new T.Matrix4().multiplyMatrices(mesh.matrixWorld, im)); } }
    else mats.push(mesh.matrixWorld);
    for (const mw of mats) {
      const s0 = g.pos.length / 3, det = mw.determinant();
      for (let i = 0; i < pa.count; i++) {
        v.fromBufferAttribute(pa, i).applyMatrix4(mw); g.pos.push(v.x, v.y, v.z);
        c.copy(base); if (ca) c.multiply(new T.Color(ca.getX(i), ca.getY(i), ca.getZ(i)));
        g.col.push(c.r, c.g, c.b);
        g.uv.push(ua ? ua.getX(i) : 0.5, ua ? ua.getY(i) : 0.5);
        if (an) g.anim.push(...an);
      }
      const n = ix ? ix.count : pa.count, tri = [];
      for (let t = 0; t < n; t += 3) {
        let a = ix ? ix.getX(t) : t, b = ix ? ix.getX(t + 1) : t + 1, d = ix ? ix.getX(t + 2) : t + 2;
        if (det < 0) [b, d] = [d, b];
        if (mat.side === T.BackSide) [b, d] = [d, b];
        g.idx.push(s0 + a, s0 + b, s0 + d);
        if (doubled) g.idx.push(s0 + a, s0 + d, s0 + b);
      }
    }
  };
  const walk = (o, skip) => {
    if (o.visible === false) return;
    if (skip && skip.has(o)) return;
    if (o.userData && o.userData.__skip) return;
    if (o.isMesh) add(o);
    for (const ch of o.children) walk(ch, skip);
  };
  W.scene.updateMatrixWorld(true);
  const bd = W.backdrop, indoor = bd.noSky;
  const anims = window.__measureAnims(W, T, bd, indoor);
  const flatBlue = (c0, box) => c0.b > c0.r * 1.25 && c0.b > 0.25 && (box.max.y - box.min.y) < 0.6 && (box.max.x - box.min.x) * (box.max.z - box.min.z) > 400;
  const isLava = c0 => c0.r > 0.6 && c0.g < c0.r * 0.62 && c0.b < c0.r * 0.4;
  const animOf = mesh => {
    if (anims.has(mesh)) return anims.get(mesh);
    const mat = mesh.material;
    if (!mat || Array.isArray(mat) || !mat.color) return null;
    const p = new T.Vector3().setFromMatrixPosition(mesh.matrixWorld);
    if (mesh === W.voidPlane) return isLava(mat.color) ? [p.x, p.y, p.z, 0, 0, 0, 0, 3, 0, 0, 0, 0] : flatBlueVoid(mat.color) ? [p.x, p.y, p.z, 0, 0, 0, 0, 4, 0, 0, 0, 0] : null;
    if (mat.customProgramCacheKey && mat.customProgramCacheKey() === 'farw') return [p.x, p.y, p.z, 0, 0, 0, 0, 1, 0, 0, 0, 0];
    const geo = mesh.geometry, gt = geo && geo.type;
    if (inLevel.has(mesh) && /Icosahedron|Dodecahedron|Sphere|Cone/.test(gt || '') && mat.color.g > mat.color.r * 1.12 && mat.color.g > mat.color.b * 1.12 && p.y > 1.5) return [p.x, p.y, p.z, 0, 0, 0, 0, 2, 0, 0, 0, 0];
    if (geo) { if (!geo.boundingBox) geo.computeBoundingBox(); const bb = geo.boundingBox.clone().applyMatrix4(mesh.matrixWorld); if (flatBlue(mat.color, bb)) return [p.x, p.y, p.z, 0, 0, 0, 0, 4, 0, 0, 0, 0]; }
    return null;
  };
  const flatBlueVoid = c0 => c0.b > c0.r * 1.25 && c0.b > 0.3 && c0.b - c0.r > 0.15;
  const inLevel = new Set();
  for (const o of W.mapObjs) o.traverse(ch => inLevel.add(ch));
  for (const o of W.mapObjs) walk(o, skipSet);
  if (!indoor) {
    walk(bd.far); walk(bd.farA);
    for (const cl of bd.clouds) walk(cl);
    for (const h of W.hills) walk(h);
  }
  walk(W.voidPlane);
  // the look
  const hex = col => col.getHex();
  const env = Object.assign({}, W.ENV_DEFAULT[id] || {}, (W.MAPS[id] || {}).env || {});
  out.look = {
    indoor, night: !!bd.night,
    bands: bd.bands.map(b => [+(b.userData.pm).toFixed(4), hex(b.material.color)]),
    background: W.scene.background && W.scene.background.isColor ? hex(W.scene.background) : null,
    fog: W.scene.fog ? [hex(W.scene.fog.color), W.scene.fog.near, W.scene.fog.far] : null,
    hemi: [hex(W.hemi.color), hex(W.hemi.groundColor), +W.hemi.intensity.toFixed(4)],
    sun: [hex(W.sun.color), +W.sun.intensity.toFixed(4)],
    sunDir: [bd.sunDir.x, bd.sunDir.y, bd.sunDir.z].map(x => +x.toFixed(4)),
    sunDisc: [hex(bd.sunM.material.color), +(env.sunSize || 1).toFixed(3)],
    haze: W.fxSky && W.fxSky.haze ? [hex(W.fxSky.haze.children[0].material.color), +W.fxSky.haze.children[0].material.opacity.toFixed(3)] : null,
    moon: bd.night ? [hex(bd.moonM.material.color), +(env.moonSize || 1).toFixed(3)] : null,
    exposure: W.renderer.toneMappingExposure,
    moving: indoor ? 0 : bd.anim.length,                                    // drifting balloons, ships, smoke, turbines: still in Godot
    specks: bd.kind, birds: !indoor && bd.birds.some(b => b.visible),       // drifting specks and circling birds: not in Godot
  };
  // collision boxes the level restyled after addBox (glass domes, hidden walls, glowing tiles, other colours): by box index
  const boxes = {};
  W.solidMeshes.forEach((mesh, i) => {
    const mt = mesh.material, st = {};
    if (!mt || Array.isArray(mt)) return;
    if (mesh.visible === false || mt.visible === false) st.hidden = 1;
    if (mt.isMeshBasicMaterial) st.basic = 1;
    if (mt.transparent && mt.opacity < 0.999) st.op = +mt.opacity.toFixed(3);
    if (mt.emissive && mt.emissiveIntensity > 0 && mt.emissive.getHex() !== 0) { st.emissive = mt.emissive.getHex(); st.ei = +mt.emissiveIntensity.toFixed(3); }
    const sol = W.solids[i]; if (sol && mt.color && mt.color.getHex() !== sol.color) st.color = mt.color.getHex();
    if (!mesh.castShadow) st.noShadow = 1;
    if (Object.keys(st).length) boxes[i] = st;
  });
  if (W.solidMeshes.length !== W.solids.length) out.notes.push('solid meshes ' + W.solidMeshes.length + ' != solids ' + W.solids.length);
  out.look.boxes = boxes;
  // flatten
  const res = { id, look: out.look, notes: out.notes, groups: [] };
  for (const g of Object.values(out.groups)) res.groups.push({ kind: g.kind, fog: g.fog, shadow: g.shadow, op: g.op, em: g.em, pos: g.pos, col: g.col, uv: g.uv, idx: g.idx, anim: g.anim });
  return res;
}

function packGroups(groups) {
  const parts = [];
  const head = Buffer.alloc(8); head.write('WAD2', 0, 'ascii'); head.writeUInt32LE(groups.length, 4); parts.push(head);
  for (const g of groups) {
    const nv = g.pos.length / 3, ni = g.idx.length;
    let mn = [1e9, 1e9, 1e9], mx = [-1e9, -1e9, -1e9];
    for (let i = 0; i < nv; i++) for (let k = 0; k < 3; k++) { const x = g.pos[i * 3 + k]; if (x < mn[k]) mn[k] = x; if (x > mx[k]) mx[k] = x; }
    const sz = mn.map((m, k) => Math.max(1e-4, mx[k] - m));
    const h = Buffer.alloc(4 + 4 + 8 + 24);
    h.writeUInt8(g.kind, 0); h.writeUInt8(g.fog, 1); h.writeUInt8(g.shadow, 2); h.writeUInt8(g.op, 3); h.writeFloatLE(g.em, 4);
    h.writeUInt32LE(nv, 8); h.writeUInt32LE(ni, 12);
    for (let k = 0; k < 3; k++) { h.writeFloatLE(mn[k], 16 + k * 4); h.writeFloatLE(sz[k], 28 + k * 4); }
    parts.push(h);
    const st = g.kind === 3 ? 12 : 10, vb = Buffer.alloc(nv * st);
    for (let i = 0; i < nv; i++) {
      for (let k = 0; k < 3; k++) vb.writeUInt16LE(Math.round((g.pos[i * 3 + k] - mn[k]) / sz[k] * 65535), i * st + k * 2);
      for (let k = 0; k < 3; k++) vb.writeUInt8(Math.max(0, Math.min(255, Math.round(Math.pow(g.col[i * 3 + k], 1 / 2.2) * 255))), i * st + 6 + k);   // stored as sRGB
      vb.writeUInt8(g.op, i * st + 9);
      if (st === 12) { vb.writeUInt8(Math.round(Math.max(0, Math.min(1, g.uv[i * 2])) * 255), i * st + 10); vb.writeUInt8(Math.round(Math.max(0, Math.min(1, g.uv[i * 2 + 1])) * 255), i * st + 11); }
    }
    parts.push(vb);
    const pad = (4 - (vb.length % 4)) % 4; if (pad) parts.push(Buffer.alloc(pad));
    if (g.shadow & 4) { const ab = Buffer.alloc(nv * 48); for (let i = 0; i < nv * 12; i++) ab.writeFloatLE(g.anim[i], i * 4); parts.push(ab); }
    const ib = Buffer.alloc(ni * 4); for (let i = 0; i < ni; i++) ib.writeUInt32LE(g.idx[i - i % 3 + [0, 2, 1][i % 3]], i * 4); parts.push(ib);   // Godot's front faces wind the other way round from three.js
  }
  return Buffer.concat(parts);
}

// weld identical vertices (position + colour) so the file is small: decor is flat shaded in the shader, normals are not stored
function weld(g) {
  const map = new Map(), pos = [], col = [], uv = [], idx = [], anim = g.anim ? [] : null, remap = new Int32Array(g.pos.length / 3);
  for (let i = 0; i < g.pos.length / 3; i++) {
    const q = [g.pos[i * 3], g.pos[i * 3 + 1], g.pos[i * 3 + 2]].map(x => Math.round(x * 500)).join(',') + '|' + [0, 1, 2].map(k => Math.round(g.col[i * 3 + k] * 255)).join(',') + (g.kind === 3 ? '|' + Math.round(g.uv[i * 2] * 255) + ',' + Math.round(g.uv[i * 2 + 1] * 255) : '') + (anim ? '|' + g.anim.slice(i * 12, i * 12 + 12).map(x => x.toFixed(3)).join(',') : '');
    let j = map.get(q); if (j === undefined) { j = pos.length / 3; map.set(q, j); pos.push(g.pos[i * 3], g.pos[i * 3 + 1], g.pos[i * 3 + 2]); col.push(g.col[i * 3], g.col[i * 3 + 1], g.col[i * 3 + 2]); uv.push(g.uv[i * 2], g.uv[i * 2 + 1]); if (anim) anim.push(...g.anim.slice(i * 12, i * 12 + 12)); }
    remap[i] = j;
  }
  for (let t = 0; t < g.idx.length; t += 3) {
    const a = remap[g.idx[t]], b = remap[g.idx[t + 1]], c = remap[g.idx[t + 2]];
    if (a === b || b === c || a === c) continue;
    idx.push(a, b, c);
  }
  return Object.assign({}, g, { pos, col, uv, idx, anim });
}

(async () => {
  const srv = require('../server');
  const { chromium } = require('playwright');
  await srv.start(0);
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 852, height: 393 }, deviceScaleFactor: 1 });
  const page = await ctx.newPage(); const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  let html = fs.readFileSync(path.join(ROOT, 'public', 'index.html'), 'utf8');
  const patch = (a, b) => { if (!html.includes(a)) throw new Error('patch target missing: ' + a.slice(0, 60)); html = html.split(a).join(b); };
  // tag the pieces Godot builds itself (floor pads, ladders) so they are not exported twice
  patch('m.rotation.x = -Math.PI / 2; m.position.y = 0.01; m.receiveShadow = true; return addDecor(m);', 'm.rotation.x = -Math.PI / 2; m.position.y = 0.01; m.receiveShadow = true; m.userData.__skip = 1; return addDecor(m);');
  patch('r.castShadow = true; addDecor(r);', 'r.castShadow = true; r.userData.__skip = 1; addDecor(r);');
  patch('r.position.set(x + nx * 0.1, y, z + nz * 0.1); addDecor(r);', 'r.position.set(x + nx * 0.1, y, z + nz * 0.1); r.userData.__skip = 1; addDecor(r);');
  const hook = 'window.__wa = { THREE, MAPS, loadMap, cfg, scene, sun, hemi, renderer, backdrop, hills, voidPlane, fxSky, ENV_DEFAULT, get mapObjs() { return mapObjs; }, get solidMeshes() { return solidMeshes; }, get solids() { return solids; }, get pads() { return pads; } };\n';
  await page.route(/\/(index\.html)?(\?.*)?$/, r => r.request().url().match(/127\.0\.0\.1:\d+\/(index\.html)?(\?.*)?$/) ? r.fulfill({ contentType: 'text/html', body: html.replace(/<\/script>\s*<\/body>/, hook + '</script></body>') }) : r.continue());
  await page.goto('http://127.0.0.1:' + srv.server.address().port + '/', { waitUntil: 'load' });
  await page.waitForFunction(() => { const b = document.getElementById('boottxt'); return b && b.textContent === 'Ready!'; }, null, { timeout: 180000 });
  await page.evaluate(src => { window.__measureAnims = (0, eval)('(' + src + ')'); }, measureAnims.toString());
  const maps = JSON.parse(fs.readFileSync(path.join(ROOT, 'godot', 'data', 'maps.json'), 'utf8'));
  const ids = Object.keys(maps).concat(['custom', 'pillars2']).filter(id => !only.length || only.includes(id));
  if (!stats) fs.mkdirSync(OUT, { recursive: true });
  let look = {}; try { look = JSON.parse(fs.readFileSync(LOOK, 'utf8')); } catch (e) { /* new */ }
  let total = 0;
  for (const id of ids) {
    const r = await page.evaluate(grab, id);
    const groups = r.groups.map(weld).filter(g => g.idx.length);
    const tris = groups.reduce((s, g) => s + g.idx.length / 3, 0), verts = groups.reduce((s, g) => s + g.pos.length / 3, 0);
    const buf = packGroups(groups); total += buf.length;
    const tags = {}; for (const g of groups) if (g.anim) for (let i = 0; i < g.anim.length; i += 12) { const k = g.anim[i + 7] ? ['', 'wind', 'leaves', 'lava', 'water'][g.anim[i + 7]] : 'moving'; tags[k] = (tags[k] || 0) + 1; }
    console.log(id.padEnd(12), 'groups', groups.length, 'tris', tris, 'verts', verts, 'bytes', buf.length, 'animated verts', JSON.stringify(tags), r.notes.length ? r.notes.join('; ') : '');
    if (!stats) { fs.writeFileSync(path.join(OUT, id + '.bin'), buf); look[id] = r.look; }
  }
  console.log('total bytes', total);
  if (!stats) fs.writeFileSync(LOOK, JSON.stringify(look, null, 0).replace(/\},"/g, '},\n"') + '\n');
  if (errors.length) console.log('page errors: ' + errors.join('; '));
  await browser.close(); await srv.stop(); process.exit(0);
})().catch(e => { console.error('FAIL', e.stack || e.message); process.exit(1); });
