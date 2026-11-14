'use strict';
/* Cross-play HOST test (npm run test:godot-host): a Godot client hosts, a web-protocol guest and a Godot guest join.
   - the real server (REQUIRE_LOGIN=0);
   - Godot host (godot/tests/net_host_test.gd): HostSession + the real World headless, 4 seats, 1 bot, K.O. limit 1;
   - web guest (tools/wa-client.js, speaks exactly what public/index.html's guest sends): hello, streams its own `S`
     (walking along x), sends forged messages the host must drop, then kills the host's bot with an `h` (to 0);
   - Godot guest (godot/tests/net_host_peer.gd): GuestSession + World, walks, hits the host's own fighter.
   Checked: roster/welcome/start (slots human,human,human,bot with the bot's name, rules), the host's `S` at ~30 Hz
   with slots 0 and 3, the Godot guest's `S` relayed to the web guest stamped with its slot, guest input moves the
   ghosts on the host, the host's `h` reaches only its victim, the guest's hit on the host lowers its hp, forged
   pend/ko/h/start are dropped (netGuard), the bot K.O. arrives as `ko` and ends the match with `pend` (limit 1),
   rematch votes (rvs) and a second `start`, the web guest leaving turns its seat back into a bot (`slot`), no errors.
   The host picked Team Deathmatch (app-only) with Host-sheet rules: with a web guest in the room the `start` plays
   Classic and carries the standard rules fields (hp 150, grav 1.5, kb 0.5, crate fast, inf), no `gmode`; emotes are
   relayed (web guest -> Godot guest, stamped; the host's own -> web guest), a junk emote is dropped.
   Then (godot/tests/net_modes_host.gd + net_modes_peer.gd):
   B. a room whose guests are all Godot clients (`gd: 1`: the Godot peer and a protocol guest saying gd) plays every
      app-only mode to its end in turn (rules.gmode, gteam, pp, grav 0.15, hp 300; gm Chaos events; pend);
   C. host migration: the Godot host leaves mid-match, the relay promotes the Godot guest, which carries the match on
      (`start` with `rs`: same seats, K.O.s, bot, arena seed and clock); the web guest re-joins it with a plain hello.
   D. Arcade co-op (godot/tests/net_arcade_host.gd + net_arcade_peer.gd): a private app-only Construction room from the
      hub's "Play co-op" (2 seats, teammate bot, no Host sheet) starts alone; a Godot guest takes seat 1 mid-fight; the
      host puts that seat down (guest pins itself from `am.dn`) and revives it (`am.rv`); a stage clear and a retry pay
      the guest's OWN save once then nothing; the run advances to stage 2 (a new `start` with `arc.st` 1 and a fresh
      site seed, the same seed on both sides) where the guest's HUD/boss bar/shrink mirror `am`; the guest leaves (its
      seat becomes a fighting teammate bot with its class) and rejoins (current stage's `start`, seat 1 human again);
      the host wins and leaves (the guest pays the victory on its own save, then gets the run-over reason).
      `ONLY=arcade npm run test:godot-host` runs this scenario alone (dev aid). */
const { spawn, spawnSync } = require('child_process');
const path = require('path');
const os = require('os');
const assert = require('assert');
process.env.REQUIRE_LOGIN = '0'; process.env.DATA_DIR = os.tmpdir() + '/wa-nethost-' + process.pid;
const srv = require('../server');
const { Client, PROTO, BUILD } = require('./wa-client');
const GODOT = process.env.GODOT || '/Applications/Godot.app/Contents/MacOS/Godot';
const DIR = path.join(__dirname, '..', 'godot');
const ERR = /SCRIPT ERROR|^ERROR|Parse Error|leaked/i;
const sleep = ms => new Promise(r => setTimeout(r, ms));

function runGodot(script, args, tag) {
  const p = spawn(GODOT, ['--headless', '--path', DIR, '--script', script, '--', ...args, '--no-save']);
  const out = { p, lines: [], marks: {} };
  let buf = '';
  const onData = d => {
    buf += d.toString(); let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i); buf = buf.slice(i + 1); out.lines.push({ at: Date.now(), l });
      const k = l.split(' ')[0]; if (!out.marks[k]) out.marks[k] = Date.now();
      if (process.env.VERBOSE && !/^(GHOST|BOT|ME|SLOTS|HP) /.test(l)) console.log(tag + ': ' + l);
    }
  };
  p.stdout.on('data', onData); p.stderr.on('data', onData);
  out.exited = new Promise(r => p.on('exit', c => r(c)));
  out.waitLine = async (re, ms) => { const t0 = Date.now(); for (;;) { const x = out.lines.find(y => re.test(y.l)); if (x) return x.l; if (Date.now() - t0 > ms) throw new Error(tag + ': timeout waiting for ' + re); await sleep(50); } };
  return out;
}

let host = null, peer = null, peer2 = null;
const MODES = ['tdm', 'deathmatch', 'sudden', 'chaos', 'pillars', 'explosive', 'lowg', 'gungame'];
const r2 = v => +v.toFixed(2);

// a guest in Node that streams its own S (standing still) and records the room messages
function guestStream(c, slotOf, extra) {
  const st = { inbox: [], last: {}, start: null, starts: [], slot: -1 };
  c.ws.on('message', d => {
    let m; try { m = JSON.parse(d.toString()); } catch (e) { return; }
    if (m.op !== 'msg') { st.inbox.push({ at: Date.now(), op: m.op }); return; }
    const x = m.m; st.inbox.push({ at: Date.now(), m: x });
    if (x.t === 'welcome') st.slot = x.id;
    if (x.t === 'start') { st.start = x; st.starts.push({ at: Date.now(), m: x }); st.last = {}; }
    if (x.t === 'S' && Array.isArray(x.l)) for (const e of x.l) st.last[e.id] = Object.assign({ at: Date.now() }, e);
  });
  st.timer = setInterval(() => { const s = slotOf(st); if (s < 0 || !st.start) return; c.toHost({ t: 'S', l: [Object.assign({ id: s, x: -3, y: 0, z: 3, vx: 0, vy: 0, vz: 0, yaw: 0, ax: 0, ay: 0, az: 1, w: 'spatula', hp: 100, d: 0, g: 1, sq: 0, iv: 0, lv: 1, el: 0 }, extra || {})] }); }, 100);
  return st;
}

// B. every app-only mode in a room whose guests are all Godot clients
async function modesRoom(url) {
  host = runGodot('res://tests/net_modes_host.gd', [url, 'modes'], 'mhost');
  const code = (await host.waitLine(/^HOSTED code=/, 30000)).split('=')[1];
  const gd = await new Client(url, 'GdBot').open();
  await gd.join(code);
  gd.toHost({ t: 'hello', build: BUILD, proto: PROTO, name: 'GdBot', skin: 'none', hat: 'none', color: 0x39b5a8, gd: 1 });
  const st = guestStream(gd, s => s.slot);
  const w = await gd.wait(m => m.op === 'msg' && m.m.t === 'welcome', 5000);
  assert.equal(w.m.gd, 1, 'a Godot host says gd in welcome');
  peer = runGodot('res://tests/net_modes_peer.gd', [url, code, 'modes', String(MODES.length)], 'mpeer');
  const results = [];
  for (let i = 0; i < MODES.length; i++) {
    const t0 = Date.now();
    while (!(st.starts.length > i)) { if (Date.now() - t0 > 60000) throw new Error('no start for ' + MODES[i]); await sleep(50); }
    const S = st.starts[i].m, R = S.rules;
    const want = MODES[i];
    const webMode = ['explosive', 'gungame'].includes(want);
    console.log(`B ${want}: rules ${JSON.stringify(R)} limit ${S.limit}`);
    if (webMode) assert.ok(R.mode === want && !R.gmode, want + ' is a web mode: rules.mode');
    else assert.ok(R.mode === 'classic' && R.gmode === want, want + ': mode classic for the web, gmode for Godot');
    if (want === 'tdm' || want === 'chaos') assert.deepEqual(R.gteam, [0, 1, 0, 1], want + ' sides by slot');
    if (want === 'pillars') assert.ok(Array.isArray(R.pp) && R.pp.length >= 4 && new Set(R.pp).size === R.pp.length, 'pillars pp');
    if (want === 'lowg') assert.equal(R.grav, 0.15, 'Moon Drift gravity');
    if (want === 'explosive') assert.equal(R.hp, 300, 'Explosive health'); else assert.equal(R.hp, 150, 'host health');
    assert.ok(R.kb === 1.5 && R.crate === 'fast', 'host rules kept');
    const team = s => (R.gteam ? R.gteam[s] : -1);
    if (i === 0) {                                     // a web player cannot join a running app-only match: told why
      const late = await new Client(url, 'LateWeb').open();
      await late.join(code); late.hello();
      const k = await late.wait(m => m.op === 'msg' && (m.m.t === 'kick' || m.m.t === 'welcome'), 5000);
      console.log('B late web guest: ' + JSON.stringify(k.m));
      assert.ok(k.m.t === 'kick' && /Team Deathmatch.*app/.test(k.m.msg), 'a late web guest is refused with the reason');
      late.close();
    }
    if (want === 'chaos') await gd.wait(m => m.op === 'msg' && m.m.t === 'gm' && m.m.k === 'cs', 20000);
    await sleep(800);
    // K.O. everybody else (not my side) until the host ends the match
    const lastHit = {};
    let pend = null;
    const tk = Date.now();
    while (!pend) {
      if (Date.now() - tk > 90000) throw new Error('no pend in ' + want);
      for (const k of [0, 2, 3]) {
        if (R.gteam && team(k) === team(st.slot)) continue;
        const e = st.last[k];
        if (e && (e.d || e.el || e.hp <= 0)) continue;
        if (Date.now() - (lastHit[k] || 0) < 350) continue;
        lastHit[k] = Date.now();
        gd.toHost({ t: 'h', to: k === 2 ? 2 : 0, vs: k, from: st.slot, d: 250, x: 0, y: 0.2, z: 1, f: 5, hd: 0 });
      }
      await sleep(60);
      const p = st.inbox.find(x => x.m && x.m.t === 'pend' && x.at > st.starts[i].at);
      if (p) pend = p.m;
    }
    results.push(want + ':w' + pend.w);
    if (R.gteam) assert.equal(team(pend.w), team(st.slot), want + ': my side wins (' + pend.w + ')');
    else assert.equal(pend.w, st.slot, want + ': I win');
    if (i + 1 < MODES.length) gd.toHost({ t: 'rv' });
  }
  console.log('B results ' + results.join(' '));
  const gmS = st.inbox.filter(x => x.m && x.m.t === 'gm' && x.m.k === 'st');
  assert.ok(gmS.length > 10 && gmS.some(x => x.m.ko.some(v => v >= 3)), 'gm state messages with the K.O.s');
  await peer.waitLine(/^DONE /, 30000);
  clearInterval(st.timer);
  gd.tx({ op: 'leave' }); gd.close();
  const [ch, cp] = await Promise.all([Promise.race([host.exited, sleep(30000).then(() => 'hang')]), Promise.race([peer.exited, sleep(30000).then(() => 'hang')])]);
  if (ch === 'hang') host.p.kill(); if (cp === 'hang') peer.p.kill();
  const ht = host.lines.map(x => x.l), pt = peer.lines.map(x => x.l);
  console.log(ht.filter(l => /^(MATCH_OVER|ALL_MODES|DONE|FAIL)/.test(l)).map(l => 'mhost: ' + l).join('\n'));
  console.log(pt.filter(l => /^(MODE|GM|CHAOS_ON|MATCH_END|DONE|FAIL)/.test(l)).map(l => 'mpeer: ' + l).join('\n'));
  const errs = [...ht, ...pt].filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);
  assert.equal(errs.length, 0, 'no Godot errors (modes)');
  assert.ok(ht.some(l => /^ALL_MODES/.test(l)), 'the host played every mode');
  const modeL = pt.filter(l => /^MODE /.test(l));
  assert.equal(modeL.length, MODES.length, 'the Godot guest started every mode');
  MODES.forEach((m, i) => {
    const l = modeL[i];
    assert.ok(new RegExp('mode=' + m + ' ').test(l), 'the Godot guest plays ' + m + ': ' + l);
    if (!['explosive', 'gungame'].includes(m)) assert.ok(/remote=true/.test(l), m + ': the host decides the end: ' + l);
    if (m === 'tdm' || m === 'chaos') assert.ok(/teams=[1-9]\d* team=0 /.test(l), m + ': the Godot guest (slot 2) is on side 0: ' + l);
    if (m === 'lowg') assert.ok(/grav=0\.15/.test(l), 'Moon Drift gravity on the guest: ' + l);
    if (m === 'explosive') assert.ok(/maxhp=225 /.test(l), 'Explosive health (300 x Scamp 0.75) on the guest: ' + l);
    else assert.ok(/maxhp=112 /.test(l), 'host health (150 x Scamp 0.75) on the guest: ' + l);
  });
  assert.ok(pt.some(l => /^GM cw /.test(l)) && pt.some(l => /^GM cs /.test(l)), 'the Chaos event reached the Godot guest');
  assert.ok(pt.some(l => /^CHAOS_ON /.test(l)), 'the Godot guest ran the host\'s Chaos event');
  assert.equal(pt.filter(l => /^MATCH_END /.test(l)).length, MODES.length, 'the Godot guest saw every match end');
  assert.equal(ch, 0, 'modes host exit code'); assert.equal(cp, 0, 'modes peer exit code');
  console.log('B. app-only modes online pass');
}

// C. host migration: the Godot host leaves mid-match; the Godot guest (first in) carries the match on
async function migration(url) {
  host = runGodot('res://tests/net_modes_host.gd', [url, 'migrate'], 'xhost');
  const code = (await host.waitLine(/^HOSTED code=/, 30000)).split('=')[1];
  peer = runGodot('res://tests/net_modes_peer.gd', [url, code, 'migrate', '1'], 'xpeer');
  await peer.waitLine(/^WELCOMED slot=1/, 30000);
  const web = await new Client(url, 'WebGuest').open();
  await web.join(code); web.hello();
  const st = guestStream(web, s => s.slot);
  const t0 = Date.now();
  while (!st.start) { if (Date.now() - t0 > 40000) throw new Error('no start (migrate)'); await sleep(50); }
  const S1 = st.start;
  assert.deepEqual(S1.slots.map(s => s.kind), ['human', 'human', 'human', 'bot'], 'migrate room seats');
  assert.equal(st.slot, 2);
  const botName = S1.slots[3].name;
  await sleep(1500);
  let ko = null;
  for (let i = 0; i < 20 && !ko; i++) {
    web.toHost({ t: 'h', to: 0, vs: 3, from: 2, d: 250, x: 0, y: 0.2, z: 1, f: 5, hd: 0 });
    await sleep(400);
    ko = st.inbox.find(x => x.m && x.m.t === 'ko' && x.m.to === 3);
  }
  assert.ok(ko, 'the web guest K.O.d the bot before the host left');
  const rh = await web.wait(m => m.op === 'rehost', 20000);
  const tRe = Date.now();
  st.start = null; st.slot = -1;
  web.hello();                                         // the web game's netMigrate: a plain hello to the new host
  while (!st.start) { if (Date.now() - tRe > 15000) throw new Error('no resumed start'); await sleep(50); }
  const S2 = st.start;
  console.log('C resumed start: ' + JSON.stringify({ slots: S2.slots.map(s => s.kind + ':' + s.name), rules: S2.rules, rs: (S2.rs || []).length, ms: Date.now() - tRe }));
  assert.equal(st.slot, 2, 'the web guest keeps its seat');
  assert.deepEqual(S2.slots.map(s => s.kind), ['human', 'bot', 'human', 'bot'], 'seats: new host 0, the old host seat a bot, web guest, the bot');
  assert.equal(S2.slots[0].name, 'GodotPeer'); assert.equal(S2.slots[2].name, 'WebGuest'); assert.equal(S2.slots[3].name, botName, 'the same bot');
  for (const k of ['mode', 'hp', 'crate', 'wstate', 'grav', 'kb', 'inf', 'dyn', 'dseed']) assert.ok(k in S2.rules, 'resumed start has rules.' + k);
  assert.equal(S2.rules.dyn, 'wobble'); assert.equal(S2.rules.dseed, S1.rules.dseed, 'same arena seed');
  assert.ok(S2.rules.dt0 > 2, 'the arena clock goes on (dt0 ' + S2.rules.dt0 + ')');
  assert.ok(Array.isArray(S2.rs) && S2.rs.find(e => e.id === 2 && e.ko >= 1), 'rs carries my K.O.');
  await sleep(2000);
  clearInterval(st.timer);
  web.tx({ op: 'leave' }); web.close();
  const [ch, cp] = await Promise.all([Promise.race([host.exited, sleep(30000).then(() => 'hang')]), Promise.race([peer.exited, sleep(40000).then(() => 'hang')])]);
  if (ch === 'hang') host.p.kill(); if (cp === 'hang') peer.p.kill();
  const ht = host.lines.map(x => x.l), pt = peer.lines.map(x => x.l);
  console.log(ht.filter(l => /^(LEAVING|DONE|FAIL)/.test(l)).map(l => 'xhost: ' + l).join('\n'));
  console.log(pt.filter(l => /^(PROMOTED|RESUMED|START|MODE|DONE|FAIL)/.test(l)).map(l => 'xpeer: ' + l).join('\n'));
  const errs = [...ht, ...pt].filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);
  assert.equal(errs.length, 0, 'no Godot errors (migration)');
  assert.ok(pt.some(l => /^PROMOTED resuming=true/.test(l)), 'the Godot guest was promoted and resumes');
  const res = pt.find(l => /^RESUMED /.test(l));
  assert.ok(res && /^RESUMED human:GodotPeer:ko\d+ bot:[^:]+:ko\d+ human:WebGuest:ko[1-9]\d* bot:/.test(res), 'resumed seats and K.O.s: ' + res);
  assert.ok(/kind=wobble/.test(res), 'same floor');
  const pi = peer.lines.findIndex(x => /^PROMOTED/.test(x.l));
  const before = peer.lines.slice(0, pi).filter(x => /^ME /.test(x.l)).slice(-1)[0];
  const ri = peer.lines.findIndex(x => /^RESUMED/.test(x.l));
  const after = peer.lines.slice(peer.lines.findIndex((x, i) => i > pi && /^START /.test(x.l))).find(x => /^ME /.test(x.l));
  const pos = l => l.split(' ').slice(1, 4).map(Number);
  const a = pos(before.l), b = pos(after.l);
  const dist = Math.hypot(a[0] - b[0], a[2] - b[2]);
  console.log(`C new host before ${a} after ${b} (moved ${dist.toFixed(2)} m), resumed line ${ri}`);
  assert.ok(dist < 2.5 && Math.hypot(b[0], b[2] - 8) > 1.5, 'the new host carries on where it stood (not on its spawn)');
  assert.equal(cp, 0, 'new host exit code');
  console.log('C. host migration passes');
}
// D. Arcade co-op: the hub's "Play co-op" room (app-only Construction), 1 human + teammate bot, a Godot guest takes
//    seat 1 mid-run, the host puts that seat down and revives it, clears/retries stage 1 (the guest pays its OWN save
//    once, then not again), advances to stage 2 (a new `start` with arc.st=1 and a fresh site seed), the guest mirrors
//    the HUD/boss fraction/shrink; the guest leaves (seat -> fighting teammate bot keeping its class) and REJOINS
//    (current stage's `start`, seat 1 human again); the host wins and leaves (run over for the guest).
async function arcadeCoop(url) {
  host = runGodot('res://tests/net_arcade_host.gd', [url], 'ahost');
  const jl = s => JSON.parse(s.slice(s.indexOf(' ') + 1));
  const hosted = jl(await host.waitLine(/^HOSTED /, 30000));
  const code = hosted.code;
  const S1 = jl(await host.waitLine(/^START1 /, 60000));
  console.log('arcade host start: ' + JSON.stringify({ slots: S1.slots, kinds: S1.kinds, map: S1.map, arc: S1.arc, rules: S1.rules }));
  assert.equal(S1.map, 'sitegen', 'the arcade room plays the generated site');
  assert.equal(S1.slots, 6, 'slots = 2 seats + the 4 Tradies crew');
  assert.ok(S1.slots <= 8, 'seats + crew within the 8-slot snapshot budget');
  assert.deepEqual(S1.kinds, ['human', 'bot', 'bot', 'bot', 'bot', 'bot'], 'seat 0 human, seat 1 the teammate bot, then crew');
  assert.equal(S1.arc.st, 0); assert.equal(S1.arc.of, 6); assert.equal(S1.arc.diff, 'normal');
  assert.deepEqual(S1.arc.seats, [0, 1], 'start.arc.seats');
  assert.deepEqual(S1.arc.crew, [2, 3, 4, 5], 'start.arc.crew follows the seats');
  assert.equal(S1.arc.boss, -1, 'stage 1 has no boss');
  assert.equal(S1.arc.state, 'intro'); assert.equal(S1.arc.lv, 4, 'normal difficulty = 4 shared lives');
  assert.equal(S1.rules.gmode, 'construction', 'app-only construction gmode');
  const H0 = jl(await host.waitLine(/^HOST_STAGE /, 30000));
  console.log('arcade stage 1 (host): ' + JSON.stringify(H0));
  assert.equal(H0.st, 0); assert.equal(H0.seats, 2); assert.equal(H0.enemies, 4, 'the stage crew');
  assert.equal(H0.boss, -1); assert.equal(H0.count, 6);
  assert.equal(H0.arc_seed, S1.arc.seed, 'the arc seed is the stage site seed');
  const HF0 = jl(await host.waitLine(/^HOST_FIGHT /, 30000));
  assert.equal(HF0.st, 0); assert.equal(HF0.state, 'fight');

  // the guest joins a RUNNING stage-1 fight (its start.arc state is the stage's intro; am closes the card)
  peer = runGodot('res://tests/net_arcade_peer.gd', [url, code, 'main'], 'apeer');
  const J = jl(await peer.waitLine(/^JOINED /, 40000));
  console.log('arcade guest joined: ' + JSON.stringify(J));
  assert.equal(J.slot, 1, 'the guest takes the second seat (never a crew slot)');
  const P1 = jl(await peer.waitLine(/^START1 /, 40000));
  console.log('arcade guest start: ' + JSON.stringify({ slots: P1.slots, kinds: P1.kinds, arc: P1.arc }));
  assert.equal(P1.slots, 6); assert.equal(P1.map, 'sitegen');
  assert.equal(P1.arc.st, 0); assert.deepEqual(P1.arc.seats, [0, 1]); assert.deepEqual(P1.arc.crew, [2, 3, 4, 5]);
  const PI = jl(await host.waitLine(/^PEER_IN /, 30000));
  console.log('arcade host after the join: ' + JSON.stringify(PI));
  assert.equal(PI.seat1_kind, 'human', 'seat 1 is the guest now');
  assert.equal(PI.seat1_ghost, true, 'the host runs the guest seat as a ghost');
  assert.equal(PI.seat1_player, false, 'the ghost seat is not a locally played fighter');
  assert.equal(PI.state, 'fight', 'the guest joined mid-fight');
  const PS1 = jl(await peer.waitLine(/^PEER_STAGE /, 40000));
  console.log('arcade stage 1 (guest): ' + JSON.stringify(PS1));
  assert.equal(PS1.st, 0); assert.equal(PS1.count, 6); assert.equal(PS1.map, 'sitegen');
  assert.equal(PS1.seed, H0.seed, 'the guest rebuilt the same site seed');
  assert.equal(PS1.arc_seed, H0.seed);
  assert.equal(PS1.host_ghost, true, 'the host seat is a ghost on the guest');
  assert.equal(PS1.crew_ghosts, 4, 'every crew slot is a ghost on the guest');
  assert.equal(PS1.crew_n, 4); assert.equal(PS1.my_slot, 1);
  assert.equal(PS1.own_seat, 1); assert.equal(PS1.own_is_me, true, 'seat 1 is this guest own fighter');

  // -- the host puts the guest seat down: am.dn pins the guest (no local respawn), the overlay counts 6 s --
  const DN = jl(await host.waitLine(/^DOWN_SENT /, 30000));
  console.log('arcade down: ' + JSON.stringify(DN));
  assert.deepEqual(DN.dn, [1], 'the host says seat 1 is down');
  assert.equal(DN.lives, 4, 'a downed seat costs no life');
  const PD = jl(await peer.waitLine(/^DOWNED /, 30000));
  console.log('arcade guest downed: ' + JSON.stringify(PD));
  assert.equal(PD.seat, 1); assert.equal(PD.slot, 1);
  assert.equal(PD.pinned, true, 'the guest pins its own fighter (dead + elim) instead of respawning');
  assert.equal(PD.pinned_flag, true);
  assert.ok(/^Down! Back in \d/.test(PD.overlay), 'the guest shows the revive countdown overlay: ' + PD.overlay);
  assert.ok(PD.revive_left >= 5.0, 'the mirror counts the 6 s revive (' + PD.revive_left + ')');

  // -- the host auto-revives it: am.rv places the guest fighter at the host's spot/health fraction --
  const UP = jl(await host.waitLine(/^REVIVED_HOST /, 30000));
  console.log('arcade revive (host): ' + JSON.stringify(UP));
  assert.equal(UP.state, 'fight'); assert.equal(UP.lives, 4, 'a revive costs no life');
  assert.ok(UP.next_revive && UP.next_revive.n >= 1, 'the host recorded the revive instruction');
  const PR = jl(await peer.waitLine(/^REVIVED /, 30000));
  console.log('arcade guest revived: ' + JSON.stringify(PR));
  assert.equal(PR.alive, true, 'the guest fighter is back');
  assert.equal(PR.pinned_flag, false, 'the guest is no longer pinned');
  assert.equal(PR.seat_down, false);
  assert.ok(Math.abs(PR.hp_frac - PR.rv_hf) < 0.06, 'the guest took the host health fraction (' + PR.hp_frac + ' vs ' + PR.rv_hf + ')');
  assert.ok(PR.invuln > 0.0, 'the revive is invulnerable for a moment');
  assert.ok(PR.dxz < 0.6, 'the guest was placed at the host safe spot (' + PR.dxz + ' m)');

  // -- a real stage clear: the guest applies it to ITS OWN save exactly once --
  const C1 = jl(await host.waitLine(/^CLEAR1_H /, 30000));
  console.log('arcade clear 1 (host): ' + JSON.stringify(C1));
  assert.equal(C1.first, true); assert.ok(C1.coins > 0); assert.ok(C1.first_bonus > 0);
  const G1 = jl(await peer.waitLine(/^GUEST_SAVE .*"cn":1/, 30000));
  console.log('arcade guest save 1: ' + JSON.stringify(G1));
  assert.equal(G1.cn, C1.cn, 'the guest paid the am.cn the host paid');
  assert.equal(G1.first, true, 'the guest first clear is ITS OWN save check');
  assert.equal(G1.coins, C1.reward + C1.first_bonus, 'its own first-clear bonus: ' + G1.coins + ' = ' + C1.reward + ' + ' + C1.first_bonus);
  assert.equal(G1.cleared, true, 'DlcSave.mark_cleared wrote the guest save');
  assert.ok(G1.best >= 1, 'DlcSave.set_best wrote the guest record');
  assert.ok(G1.save_coins >= G1.coins, 'Save.coins got the guest coins (' + G1.save_coins + ')');
  const CARD1 = jl(await peer.waitLine(/^GUEST_CARD .*ArcadeClear/, 15000));
  console.log('arcade guest clear card: ' + JSON.stringify(CARD1));
  assert.equal(CARD1.name, 'ArcadeClear'); assert.equal(CARD1.wait, true, 'the guest card has host-controlled buttons');
  assert.equal(CARD1.wait_text, 'Waiting for the host');

  // -- a retry of the same stage pays NOTHING twice (same seeds rebuilt from a fresh start) --
  const RT = jl(await host.waitLine(/^RETRY /, 30000));
  const P2 = jl(await peer.waitLine(/^START2 /, 40000));
  console.log('arcade retry start: ' + JSON.stringify({ host: RT, guest: P2.arc }));
  assert.equal(P2.arc.st, 0, 'the retry is the same stage');
  assert.equal(RT.seed, Number(P2.arc.seed), 'the retry start carries the retry site seed');
  const PF2 = jl(await peer.waitLine(/^PEER_STAGE .*"n":2/, 40000));
  assert.equal(PF2.seed, RT.seed, 'the guest rebuilt the retry site seed');
  const C2 = jl(await host.waitLine(/^CLEAR2_H /, 60000));
  console.log('arcade clear 2 (host): ' + JSON.stringify(C2));
  assert.equal(C2.first, false, 'the host save already cleared the stage');
  assert.equal(C2.coins, 0);
  const G2 = jl(await peer.waitLine(/^GUEST_SAVE .*"cn":2/, 40000));
  console.log('arcade guest save 2: ' + JSON.stringify(G2));
  assert.equal(G2.cn, C2.cn);
  assert.equal(G2.first, false, 'the guest save already cleared the stage');
  assert.equal(G2.coins, 0, 'a retry pays the guest nothing twice');
  assert.equal(G2.save_coins, G1.save_coins, 'the guest coin total did not move on the retry');

  // -- stage 2: a new start (fresh seed), the guest mirrors the HUD, the boss fraction and the shrinking floor --
  const ADV = jl(await host.waitLine(/^ADVANCING /, 30000));
  assert.equal(ADV.to, 1);
  const H2 = jl(await host.waitLine(/^HOST_STAGE .*"st":1/, 60000));
  console.log('arcade stage 2 (host): ' + JSON.stringify(H2));
  assert.equal(H2.st, 1); assert.equal(H2.enemies, 1, 'stage 2 is the Engineer alone');
  assert.equal(H2.boss, 2, 'the boss is the first crew slot');
  assert.notEqual(H2.seed, H0.seed, 'a stage transition gets a fresh site seed');
  const P3 = jl(await peer.waitLine(/^START3 /, 60000));
  console.log('arcade stage 2 (start): ' + JSON.stringify({ slots: P3.slots, kinds: P3.kinds, arc: P3.arc }));
  assert.equal(P3.arc.st, 1, 'the next stage travels as a new start with arc.st = 1');
  assert.deepEqual(P3.arc.seats, [0, 1]); assert.deepEqual(P3.arc.crew, [2]); assert.equal(P3.arc.boss, 2);
  assert.equal(P3.arc.seed, H2.arc_seed, 'the stage 2 start carries the host stage seed');
  assert.equal(P3.slots, 3, 'stage 2: two seats and one crew slot');
  const PS2 = jl(await peer.waitLine(/^PEER_STAGE .*"n":3/, 60000));
  console.log('arcade stage 2 (guest): ' + JSON.stringify(PS2));
  assert.equal(PS2.st, 1); assert.equal(PS2.count, 6); assert.equal(PS2.map, 'sitegen');
  assert.equal(PS2.seed, H2.seed, 'stage 2: guest seed == host seed (' + H2.seed + ')');
  assert.equal(PS2.seed, Number(P3.arc.seed));
  assert.equal(PS2.crew_ghosts, 1); assert.equal(PS2.crew_n, 1);
  assert.equal(PS2.boss, 2); assert.equal(PS2.boss_ghost, true, 'the boss slot is a ghost on the guest');
  assert.equal(PS2.host_ghost, true);
  const HHF = jl(await host.waitLine(/^HOST_HF /, 30000));
  console.log('arcade stage 2 display state (host): ' + JSON.stringify(HHF));
  assert.ok(Math.abs(HHF.hf - 0.42) < 0.02, 'host boss fraction set to 0.42 (' + HHF.hf + ')');
  assert.equal(HHF.lives, 3);
  const PHUD = jl(await peer.waitLine(/^PEER_HUD /, 30000));
  console.log('arcade guest HUD: ' + JSON.stringify(PHUD));
  assert.ok(/Stage 2 \/ 6/.test(PHUD.strip), 'the guest HUD names the stage: ' + PHUD.strip);
  assert.ok(/Lives 3/.test(PHUD.strip), 'the guest HUD mirrors am.lv: ' + PHUD.strip);
  assert.equal(PHUD.boss_visible, true, 'the guest boss bar is visible');
  assert.ok(Math.abs(PHUD.hf - PHUD.am_hf) < 0.05, 'the guest bar mirrors am.hf (' + PHUD.hf + ' vs ' + PHUD.am_hf + ')');
  assert.ok(Math.abs(PHUD.am_hf - HHF.hf) < 0.06, 'the guest saw the host boss fraction (' + PHUD.am_hf + ' vs ' + HHF.hf + ')');
  assert.equal(PHUD.lives, 3, 'the guest mirrors am.lv');
  const PSH = jl(await peer.waitLine(/^SHRINK /, 30000));
  console.log('arcade guest shrink: ' + JSON.stringify(PSH));
  assert.ok(Math.abs(PSH.size - PSH.sh) < 0.5, 'the guest floor size mirrors am.sh (' + PSH.size + ' vs ' + PSH.sh + ')');
  assert.equal(PSH.mesh, true, 'the guest built the shrinking floor visual');

  // -- the guest leaves: its seat is a teammate bot that keeps fighting with the player's class/kit --
  await peer.waitLine(/^DONE /, 60000);
  const PO = jl(await host.waitLine(/^PEER_OUT /, 30000));
  console.log('arcade host after the guest left: ' + JSON.stringify(PO));
  assert.equal(PO.seat1_kind, 'bot', 'the guest leaving turns seat 1 into a bot');
  assert.equal(PO.seat1_ghost, false, 'the dropped seat is no longer a ghost');
  assert.equal(PO.seat1_player, true, 'the teammate-bot seat is a player seat (it fights the crew)');
  assert.equal(PO.seat1_cls, 'kid', 'the bot keeps the class the player picked');
  assert.ok(PO.seat1_name.startsWith('GodotArcadeP'), 'the bot keeps the player fighter/name (M3 handover): ' + PO.seat1_name);
  assert.ok(PO.bt.includes(1), 'am marks the bot-played seat');
  assert.equal(PO.started, true, 'the room keeps running after the guest leaves');
  assert.equal(PO.state, 'fight', 'the host is still in the stage 2 fight');
  const SB = jl(await host.waitLine(/^SEAT_BOT /, 30000));
  console.log('arcade teammate bot seat: ' + JSON.stringify(SB));
  assert.equal(SB.alive, true); assert.equal(SB.is_ghost, false); assert.equal(SB.is_player, true);
  assert.equal(SB.cls, 'kid', 'the teammate bot fights with the dropped player class');
  assert.equal(SB.brain, true, 'a BotBrain drives the seat');
  assert.ok(SB.weapon !== '', 'the seat bot keeps the player kit in hand (' + SB.weapon + ')');
  assert.ok(SB.target !== '', 'the seat bot targets the crew (' + SB.target + ')');

  // -- the guest REJOINS mid-run: current stage start + its own seat + its class back --
  peer2 = runGodot('res://tests/net_arcade_peer.gd', [url, code, 'rejoin'], 'apeer2');
  const J2 = jl(await peer2.waitLine(/^JOINED /, 40000));
  console.log('arcade guest rejoined: ' + JSON.stringify(J2));
  assert.equal(J2.slot, 1, 'the rejoin gets the same seat');
  const R = jl(await host.waitLine(/^REJOIN /, 30000));
  console.log('arcade host after the rejoin: ' + JSON.stringify(R));
  assert.equal(R.arc_st, 1, 'the rejoin start is the CURRENT stage');
  assert.equal(R.arc_seed, H2.arc_seed);
  assert.equal(R.seat1_kind, 'human'); assert.equal(R.seat1_ghost, true); assert.equal(R.seat1_human, true);
  assert.ok(R.seat1_name.startsWith('GodotArcadeP'));
  const P4 = jl(await peer2.waitLine(/^START1 /, 40000));
  console.log('arcade rejoin start: ' + JSON.stringify({ slots: P4.slots, kinds: P4.kinds, cls: P4.slots_cls, arc: P4.arc }));
  assert.equal(P4.arc.st, 1, 'the rejoining guest builds the current stage');
  assert.equal(Number(P4.arc.seed), R.arc_seed);
  assert.equal(P4.kinds[1], 'human', 'seat 1 is a human seat in the rejoin start');
  assert.equal(P4.slots_cls[1], 'kid', 'seat 1 has the class the player picked');
  const PS4 = jl(await peer2.waitLine(/^PEER_STAGE /, 40000));
  assert.equal(PS4.st, 1); assert.equal(PS4.seed, H2.seed, 'the rejoining guest rebuilt the current site');
  assert.equal(PS4.my_slot, 1); assert.equal(PS4.own_is_me, true);
  const W = jl(await host.waitLine(/^HOST_WON /, 30000));
  console.log('arcade victory (host): ' + JSON.stringify(W));
  assert.equal(W.first, true); assert.ok(W.coins > 0); assert.equal(W.hat_first, true);
  const V = jl(await peer2.waitLine(/^GUEST_VICTORY /, 30000));
  console.log('arcade victory (guest save): ' + JSON.stringify(V));
  assert.equal(V.first, true, 'the victory bonus is paid on the guest OWN save');
  assert.ok(V.coins > 0); assert.equal(V.hat_first, true, 'the guest wins the Site Foreman hat on its own save');
  assert.ok(V.save_coins >= V.coins);
  const HL = jl(await peer2.waitLine(/^HOSTLEFT /, 30000));
  console.log('arcade host left: ' + JSON.stringify(HL));
  assert.equal(HL.raw, 'promoted', 'the relay promotes the remaining player');
  assert.equal(HL.reason, 'The host left. The Arcade run is over.', 'the guest is told the run is over');
  const LEAVE = jl(await host.waitLine(/^LEAVE /, 30000));
  assert.equal(LEAVE.reason, 'The Arcade run is over.', 'the host own leave reason');
  await host.waitLine(/^DONE /, 30000);
  await peer2.waitLine(/^DONE /, 30000);

  const [ch, cp, cp2] = await Promise.all([Promise.race([host.exited, sleep(60000).then(() => 'hang')]),
    Promise.race([peer.exited, sleep(60000).then(() => 'hang')]),
    Promise.race([peer2.exited, sleep(60000).then(() => 'hang')])]);
  if (ch === 'hang') host.p.kill(); if (cp === 'hang') peer.p.kill(); if (cp2 === 'hang') peer2.p.kill();
  const ht = host.lines.map(x => x.l), pt = peer.lines.map(x => x.l), p2t = peer2.lines.map(x => x.l);
  console.log(ht.filter(l => /^(START|HOST_STAGE|PEER_IN|HOST_FIGHT|DOWN_SENT|REVIVED_HOST|CLEAR1_H|RETRY|CLEAR2_H|ADVANCING|HOST_HF|PEER_OUT|SEAT_BOT|REJOIN|HOST_WON|LEAVE|AM_SENT|DONE|FAIL)/.test(l)).map(l => 'ahost: ' + l).join('\n'));
  console.log(pt.filter(l => /^(JOINED|START|PEER_STAGE|AM|DOWNED|REVIVED|GUEST_SAVE|GUEST_CARD|PEER_HUD|SHRINK|DONE|FAIL)/.test(l)).map(l => 'apeer: ' + l).join('\n'));
  console.log(p2t.filter(l => /^(JOINED|START|PEER_STAGE|GUEST_VICTORY|HOSTLEFT|DONE|FAIL)/.test(l)).map(l => 'apeer2: ' + l).join('\n'));
  const errs = [...ht, ...pt, ...p2t].filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);
  assert.equal(errs.length, 0, 'no Godot errors (arcade co-op)');
  const ams = pt.filter(l => /^AM /.test(l)).map(jl);
  assert.ok(ams.some(a => a.st === 0 && a.s === 'fight'), 'the guest got the stage 1 fight am');
  assert.ok(ams.some(a => a.st === 1 && a.s === 'fight'), 'the guest got the stage 2 fight am');
  assert.ok(ams.some(a => Array.isArray(a.dn) && a.dn.includes(1)), 'am carried the downed seat slot');
  assert.ok(ams.some(a => a.rv && Number(a.rv.n) > 0), 'am carried the revive instruction');
  const amSent = jl(ht.find(l => /^AM_SENT /.test(l)));
  assert.ok(amSent.n > 30, 'the host sent am all along (' + amSent.n + ')');
  assert.ok(ht.some(l => /^HOST_FIGHT .*"st":0/.test(l)) && ht.some(l => /^HOST_FIGHT .*"st":1/.test(l)), 'the host started both fights');
  assert.ok(pt.some(l => /^DONE .*"stage":1/.test(l)), 'the first guest finished on stage 2');
  assert.equal(ch, 0, 'arcade host exit code'); assert.equal(cp, 0, 'arcade guest exit code'); assert.equal(cp2, 0, 'arcade rejoin exit code');
  console.log('D. arcade co-op passes');
}

(async () => {
  spawnSync(GODOT, ['--headless', '--path', DIR, '--import'], { timeout: 180000 });   // registers class_name scripts
  await srv.start(0);
  const url = 'ws://127.0.0.1:' + srv.server.address().port + '/ws';
  if (process.env.ONLY === 'arcade') {                     // dev aid: iterate on scenario D alone
    await arcadeCoop(url);
    console.log('godot net host test (arcade only) passes');
    await srv.stop(); process.exit(0);
  }

  // 0. the relay is unreachable: a clear error, no hang
  {
    const bad = runGodot('res://tests/net_host_test.gd', ['ws://127.0.0.1:9/ws'], 'bad');
    await bad.waitLine(/^ENDED /, 20000);
    const l = bad.lines.find(x => /^ENDED /.test(x.l)).l;
    console.log('unreachable relay -> ' + l);
    assert.match(l, /Couldn't reach the game server|didn't answer/, 'clear error when the relay is unreachable');
    bad.p.kill();
  }

  host = runGodot('res://tests/net_host_test.gd', [url], 'host');
  const code = (await host.waitLine(/^HOSTED code=/, 30000)).split('=')[1];
  assert.match(code, /^[A-Z2-9]{5}$/, 'private room code');

  // web guest: join + hello
  const web = await new Client(url, 'WebGuest').open();
  await web.join(code); web.hello();
  const welcome = await web.wait(m => m.op === 'msg' && m.m.t === 'welcome', 5000);
  assert.equal(welcome.m.id, 1, 'web guest is slot 1'); assert.equal(welcome.m.proto, 1); assert.equal(welcome.m.name, 'Godot room');
  const roster1 = await web.wait(m => m.op === 'msg' && m.m.t === 'roster', 5000);
  assert.deepEqual(roster1.m.roster.map(r => r.name), ['GodotHost', 'WebGuest'], 'roster after the web guest');
  assert.equal(roster1.m.roster[0].cls, 'bruiser'); assert.equal(roster1.m.max, 4); assert.equal(roster1.m.lim, 1);
  assert.ok(roster1.m.rl && roster1.m.rl.want === 'tdm' && roster1.m.rl.mode === 'classic', 'roster rl: TDM picked, Classic played with a web guest: ' + JSON.stringify(roster1.m.rl));
  assert.equal(roster1.m.modeName, 'Classic');
  { const l = await new Client(url, 'Lister').open(); l.tx({ op: 'list' }); const r = await l.wait(m => m.op === 'rooms'); assert.ok(!r.rooms.some(x => x.id === code), 'private room is not listed'); l.close(); }

  // Godot guest
  peer = runGodot('res://tests/net_host_peer.gd', [url, code], 'peer');
  const inbox = [];                                          // every room message the web guest gets: {at, m}
  web.ws.on('message', d => { let m; try { m = JSON.parse(d.toString()); } catch (e) { return; } if (m.op === 'msg') inbox.push({ at: Date.now(), m: m.m }); });
  const start = await web.wait(m => m.op === 'msg' && m.m.t === 'start', 40000);
  const tS = Date.now();
  const S0 = start.m;
  console.log('start: ' + JSON.stringify({ slots: S0.slots.map(s => s.kind + ':' + s.name), map: S0.map, limit: S0.limit, rules: S0.rules }));
  assert.deepEqual(S0.slots.map(s => s.kind), ['human', 'human', 'human', 'bot'], 'slots');
  assert.deepEqual(S0.slots.slice(0, 3).map(s => s.name), ['GodotHost', 'WebGuest', 'GodotPeer']);
  assert.ok(/^Bot /.test(S0.slots[3].name), 'the bot has its name');
  assert.equal(S0.slots[2].cls, 'kid', 'the Godot guest class');
  assert.equal(S0.map, 'arena'); assert.equal(S0.limit, 1);
  assert.equal(S0.rules.mode, 'classic'); assert.equal(S0.rules.hp, 150); assert.ok(Number.isInteger(S0.rules.dseed), 'dseed');
  assert.equal(S0.rules.dyn, 'off');
  assert.ok(S0.rules.grav === 1.5 && S0.rules.kb === 0.5 && S0.rules.crate === 'fast' && S0.rules.inf === true && typeof S0.rules.wstate === 'object', 'standard rules fields from the Host sheet');
  assert.ok(!('gmode' in S0.rules) && !('gteam' in S0.rules), 'no app-only mode with a web guest');
  web.toHost({ t: 'emote', e: 'wobble' }); web.toHost({ t: 'emote', e: 'no-such-emote' });

  // stream my own S: walking along x
  const r2 = v => +v.toFixed(2);
  let wx = -8, hpWeb = 200, sent = 0;
  const stream = setInterval(() => {
    const t = (Date.now() - tS) / 1000; const vx = t < 4 ? 3 : 0; wx = Math.min(4, -8 + 3 * Math.min(t, 4));
    // a second entry for slot 0 must be thrown away; the first one is stamped with my slot
    web.toHost({ t: 'S', l: [{ id: 0, x: r2(wx), y: 0, z: 6, vx, vy: 0, vz: 0, yaw: 1.57, ax: 0, ay: 0, az: 1, w: 'spatula', hp: hpWeb, d: 0, g: 1, sq: 0, iv: 0, lv: 0, el: 0 }, { id: 0, x: 0, y: 0, z: 0 }] });
    sent++;
  }, 1000 / 30);

  // the host's hit on me (slot 1) comes to me only. Wait for THAT hit (from slot 0, d 30): under CI load the host's
  // bot (slot 3) can land its first, and any-`h` would flake here (seen on the Linux runner).
  const h1 = await web.wait(m => m.op === 'msg' && m.m.t === 'h' && m.m.from === 0 && m.m.to === 1 && m.m.d === 30, 15000);
  console.log('host hit: ' + JSON.stringify(h1.m));
  assert.ok(h1.m.to === 1 && h1.m.vs === 1 && h1.m.from === 0 && h1.m.d === 30, 'host h routed to its victim');
  hpWeb = 170;

  // forged messages: the host must drop them
  web.toHost({ t: 'pend', w: 1 });
  web.toHost({ t: 'start', slots: [], map: 'park' });
  web.toHost({ t: 'ko', from: 1, to: 0 });
  web.toHost({ t: 'h', to: 0, vs: 3, from: 0, d: 250, x: 0, y: 0, z: 1, f: 5, hd: 0 });
  web.toHost({ t: 'take', cid: 999 });
  web.toHost({ t: 'sw', id: 3, yaw: 0.5, w: 'spatula' });   // legit, but id is stamped to 1
  await sleep(1500);

  await peer.waitLine(/^HIT0 /, 15000);                       // the Godot guest has hit the host
  const tHit0 = Date.now();
  await sleep(800);
  // kill the host's bot (slot 3): `h` with to 0, until its `ko` comes back
  let ko = null;
  for (let i = 0; i < 20 && !ko; i++) {
    web.toHost({ t: 'h', to: 0, vs: 3, from: 1, d: 9999, x: 0, y: 0.2, z: 1, f: 5, hd: 0 });
    ko = await web.wait(m => m.op === 'msg' && m.m.t === 'ko' && m.m.to === 3, 600).catch(() => null);
  }
  assert.ok(ko && ko.m.from === 1, 'bot K.O. credited to the web guest: ' + JSON.stringify(ko && ko.m));
  const pend = await web.wait(m => m.op === 'msg' && m.m.t === 'pend', 5000);
  assert.equal(pend.m.w, 1, 'K.O. limit 1 reached: the web guest wins');
  web.toHost({ t: 'rv' });
  const rvs = await web.wait(m => m.op === 'msg' && m.m.t === 'rvs', 10000);
  console.log('rvs: ' + JSON.stringify(rvs.m));
  const start2 = await web.wait(m => m.op === 'msg' && m.m.t === 'start', 40000);
  assert.deepEqual(start2.m.slots.map(s => s.kind), ['human', 'human', 'human', 'bot'], 'rematch keeps the players');
  assert.notEqual(start2.m.rules.dseed, S0.rules.dseed, 'fresh arena seed for the rematch');
  clearInterval(stream);

  // what the web guest got during match 1
  const m1 = inbox.filter(x => x.at > tS + 1000 && x.at < tS + 4000);
  const hostS = m1.filter(x => x.m.t === 'S' && x.m.l.some(e => e.id === 0));
  const rate = hostS.length / 3;
  const ids = new Set(hostS.flatMap(x => x.m.l.map(e => e.id)));
  const peerS = m1.filter(x => x.m.t === 'S' && x.m.l.length === 1 && x.m.l[0].id === 2);
  const peerZ = inbox.filter(x => x.m.t === 'S' && x.m.l[0] && x.m.l[0].id === 2 && x.at < tS + 5000).map(x => x.m.l[0].z);
  const hostZ = hostS.map(x => x.m.l.find(e => e.id === 0).z);
  const hostHp = inbox.filter(x => x.m.t === 'S' && x.at > tHit0 + 300 && x.at < tHit0 + 800).map(x => (x.m.l.find(e => e.id === 0) || {}).hp).filter(v => v !== undefined);
  console.log(`host S ${rate.toFixed(1)} Hz ids ${[...ids]}; host walked ${(Math.max(...hostZ) - Math.min(...hostZ)).toFixed(1)} m; peer S ${(peerS.length / 3).toFixed(1)} Hz walked ${(Math.max(...peerZ) - Math.min(...peerZ)).toFixed(1)} m; host hp after peer hit ${hostHp.slice(0, 3)}`);
  assert.ok(rate >= 25 && rate <= 35, 'host S at ~30 Hz (' + rate + ')');
  assert.ok(ids.has(0) && ids.has(3) && !ids.has(1) && !ids.has(2), 'host S carries its own fighter and its bot');
  assert.ok(peerS.length >= 60, 'the Godot guest S is relayed to the web guest (' + peerS.length + ')');
  assert.ok(Math.max(...peerZ) - Math.min(...peerZ) > 3, 'the Godot guest walked');
  assert.ok(Math.max(...hostZ) - Math.min(...hostZ) > 3, 'the host walked');
  const hpL = host.lines.filter(x => /^HP /.test(x.l));
  const hpSeq = [...hpL.filter(x => x.at < tHit0 - 300).slice(-1), ...hpL.filter(x => x.at >= tHit0 - 300 && x.at < tHit0 + 1500)].map(x => +x.l.split(' ')[1]);
  const drops = hpSeq.slice(1).map((v, i) => +(hpSeq[i] - v).toFixed(2));
  console.log('host hp around the Godot guest hit: ' + hpSeq.join(' '));
  assert.ok(hostHp.length && drops.some(d => Math.abs(d - 11.04) < 0.1 || Math.abs(d - 5.52) < 0.1), 'the Godot guest hit (12 x Scamp 0.92, halved while knocked down) lowered the host hp: drops ' + drops);

  // the web guest leaves: its seat turns back into a bot for the others (after the guests have rebuilt the match)
  await sleep(1500);
  web.tx({ op: 'leave' });
  await web.wait(m => m.op === 'left', 5000).catch(() => null);
  web.close();

  const [ch, cp] = await Promise.all([Promise.race([host.exited, sleep(60000).then(() => 'hang')]), Promise.race([peer.exited, sleep(60000).then(() => 'hang')])]);
  if (ch === 'hang') host.p.kill(); if (cp === 'hang') peer.p.kill();
  const ht = host.lines.map(x => x.l), pt = peer.lines.map(x => x.l);
  console.log(ht.filter(l => /^(HOSTED|ROSTER|STARTING|START|HIT1|MATCH_OVER|VOTES|SENT|RECV|GUARDED|DONE|FAIL|ENDED)/.test(l)).map(l => 'host: ' + l).join('\n'));
  console.log(pt.filter(l => /^(WELCOMED|START|HIT0|MATCH_END|SLOT1|SENT|RECV|DONE|FAIL|ENDED)/.test(l)).map(l => 'peer: ' + l).join('\n'));
  const errs = [...ht, ...pt].filter(l => ERR.test(l));
  for (const l of errs) console.log('godot:', l);

  // on the host: the ghosts follow their owners
  const ghost = (lines, s) => lines.filter(x => new RegExp('^GHOST ' + s + ' ').test(x.l) && x.at > tS + 500 && x.at < tS + 5000).map(x => { const f = x.l.split(' '); return { x: +f[2], z: +f[4], hp: +f[5] }; });
  const g1 = ghost(host.lines, 1), g2 = ghost(host.lines, 2), p0 = ghost(peer.lines, 0), p3 = ghost(peer.lines, 3), p1 = ghost(peer.lines, 1);
  const span = (a, k) => a.length ? Math.max(...a.map(v => v[k])) - Math.min(...a.map(v => v[k])) : 0;
  console.log(`host sees web guest x span ${span(g1, 'x').toFixed(1)}, Godot guest z span ${span(g2, 'z').toFixed(1)}; peer sees host z span ${span(p0, 'z').toFixed(1)}, web guest x span ${span(p1, 'x').toFixed(1)}, bot samples ${p3.length}`);
  assert.ok(span(g1, 'x') > 6, 'web guest input moves its fighter on the host');
  assert.ok(span(g2, 'z') > 3, 'Godot guest input moves its fighter on the host');
  assert.ok(span(p0, 'z') > 3 && span(p1, 'x') > 6 && p3.length > 10, 'the Godot guest sees the host, the web guest (relayed) and the bot');
  assert.ok(ht.some(l => /^HIT1 applied=true/.test(l)), 'host hit sent');
  assert.ok(ht.some(l => /^MATCH_OVER w=1/.test(l)), 'host ended the match');
  assert.ok(ht.some(l => /^START n=2 slots=human,human,human,bot/.test(l)), 'host rematch');
  const gl = ht.find(l => /^GUARDED /.test(l)); const guarded = gl ? +gl.split(' ')[1] : 0;
  assert.ok(guarded >= 5, 'forged messages dropped by the guard (' + guarded + ')');
  assert.ok(pt.some(l => /^WELCOMED slot=2/.test(l)), 'Godot guest is slot 2');
  assert.ok(pt.some(l => /^START n=1 map=arena slots=4 my_slot=2 kinds=human,human,human,bot/.test(l)), 'Godot guest started');
  assert.ok(pt.some(l => /^HIT0 applied=true/.test(l)), 'Godot guest hit the host');
  assert.ok(pt.some(l => /^MATCH_END w=1/.test(l)), 'Godot guest got pend');
  assert.ok(pt.some(l => /^START n=2 /.test(l)), 'Godot guest got the rematch');
  assert.ok(pt.some(l => /^SLOT1 kind=bot/.test(l)), 'the web guest seat went back to a bot');
  assert.ok(pt.some(l => /^EMOTE 1 wobble$/.test(l)), 'the web guest emote reached the Godot guest (stamped slot 1)');
  assert.ok(inbox.some(x => x.m.t === 'emote' && x.m.id === 0 && x.m.e === 'clap'), 'the host emote reached the web guest');
  assert.ok(ht.some(l => /^STATUS .*app-only, so the match plays Classic/.test(l)), 'the host was told TDM plays Classic');
  assert.equal(errs.length, 0, 'no Godot errors');
  assert.equal(ch, 0, 'host exit code'); assert.equal(cp, 0, 'peer exit code');
  console.log('godot net host test (mixed room) passes');
  await modesRoom(url);
  await migration(url);
  await arcadeCoop(url);
  console.log('godot net host test passes');
  await srv.stop(); process.exit(0);
})().catch(async e => {
  for (const [n, o] of [['host', host], ['peer', peer], ['rejoin', peer2]]) if (o) { console.log(o.lines.map(x => x.l).filter(l => !/^(GHOST|ME|BOT|SLOTS|HP) /.test(l)).slice(-40).map(l => n + ': ' + l).join('\n')); try { o.p.kill(); } catch (x) { /* x */ } }
  console.error('FAIL', e.stack || e.message); try { await srv.stop(); } catch (x) { /* x */ } process.exit(1);
});
