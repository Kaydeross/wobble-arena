'use strict';
/*
  Server-authoritative coin wallet (WP 1.0-A, docs/PROTOCOL.md 4.3).

  One record per account: `wallet:<lower-case account>` = the balance and an append-only, bounded ledger
  (reason, amount, idempotency id, time). Every operation is idempotent by the caller's id, so a retried request
  never grants or spends twice, and it is serialised per account inside this process (a promise chain), so two
  requests cannot lose an update.

  The balance is the truth for signed-in accounts from now on. The cloud-save blob still carries `wallet.coins` for
  the web client, but the Godot client ignores it once the wallet exists and always shows the server balance.

  Migration: the first wallet use for an account seeds the balance ONCE from that account's existing cloud save,
  clamped to MAX_SEED (the blob is client-trusted today). The seed is written as a `migrate` ledger entry.

  Caps: earned coins are capped per request (derived from the shipped reward tables) and per UTC day.
  Spending uses ITEMS, a server-side price table that mirrors the shipped cosmetics/classes data and the 1500-coin
  Construction DLC (tools/test-server.js checks it against godot/data/extra/locker.json, classes.json and
  DlcUnlock.PRICE, so drift fails a gate).

  Store: the same accounts store as everything else (Upstash when configured, else data/db.json). The lock is
  in-process: a single Node instance is assumed, which is how the relay runs today. Running several server
  instances on one database would need an atomic compare-and-set in the store before the wallet can be sold.
*/
const MAX_SEED = 100000;          // migration clamp: the biggest balance an existing (client-trusted) cloud save may seed
const LEDGER_MAX = 100;           // newest ledger entries kept (append-only up to this bound)
const IDS_MAX = 300;              // idempotency ids remembered (must outlive the useful retry window)
const DAY_CAP = 5000;             // earned coins per account per UTC day
const MAX_KO = 60;                // K.O.s one request may claim for a match reward
const ID_RE = /^[A-Za-z0-9_-]{8,64}$/;
const MAX_AMOUNT = 10000000;

/* Shipped prices: godot/data/extra/locker.json (shop outfits + shop emotes), godot/data/extra/classes.json
   (Bulwark/Zippy/Ace) and DlcUnlock.PRICE (the Construction DLC, bought with coins, no separate entitlement). */
const ITEMS = Object.freeze({
  // outfits
  'skin:cowboy': 400, 'skin:pirate': 500, 'skin:wizard': 850, 'skin:astro': 700, 'skin:robot': 700,
  'skin:shadow': 800, 'skin:knight': 900, 'skin:samurai': 1000, 'skin:vampire': 1100, 'skin:hero': 1500,
  'skin:fire': 450, 'skin:detective': 500, 'skin:pilot': 550, 'skin:scientist': 650, 'skin:racer': 650,
  'skin:viking': 750, 'skin:jester': 850, 'skin:pharaoh': 1200, 'skin:tripleT': 3500, 'skin:ballerina': 3500,
  'skin:assassino': 3500, 'skin:thunder': 2000,
  // emotes sold in the Shop (outfit/code emotes are never sold on their own)
  'emote:hip': 150, 'emote:clap': 200, 'emote:disco': 250, 'emote:sit': 300, 'emote:robot': 350,
  'emote:spin': 450, 'emote:flip': 600, 'emote:griddy': 550, 'emote:floss': 650, 'emote:dab': 300,
  'emote:pump': 250, 'emote:shimmy': 250, 'emote:crane': 1300, 'emote:land': 1500, 'emote:guitar': 1800,
  'emote:galaxy': 3500, 'emote:wheelie': 3500, 'emote:flex': 250, 'emote:salute': 200, 'emote:bow': 250,
  'emote:zombie': 350, 'emote:sprinkler': 450, 'emote:cartwheel': 650, 'emote:jig': 450,
  'emote:storm': 1900, 'emote:nova': 4000,
  // Godot-only classes
  'class:tank': 1500, 'class:dash': 1200, 'class:ace': 2000,
  // Construction DLC: bought with coins (the corrections table: no separate dlc_construction entitlement)
  'dlc:construction': 1500,
  // The three extra DLC packs (godot/data/extra/<pack>/hub.json `price`; same rule as Construction)
  'dlc:kitchen': 1500, 'dlc:xmas': 1500, 'dlc:australia': 1500,
});

/* Per-request caps derived from SaveProfile (godot/autoload/save.gd) and Quests (godot/logic/quests.gd):
   match = MATCH_COINS 40 + WIN_COINS 60 + KO_COINS 5 per K.O. (0..MAX_KO) -> at most 400
   ko    = one K.O. worth KO_COINS 5
   quest = the biggest single claim: weekly/weekly bonus 400, daily goals up to 150 each, daily bonus 100,
           milestones up to 300 -> 500
   streak= STREAK_BASE 20 + STREAK_STEP 10 x (STREAK_MAX 6 - 1) = 70 -> 100
   earn  = a generic client award (SaveProfile.add_coins), itself only used by tests today
   A match request may also carry the K.O. coins (old clients/one-call clients), which the match formula covers. */
function matchCap(body) {
  const kos = body && Number.isFinite(Number(body.kos)) ? Math.max(0, Math.min(MAX_KO, Math.floor(Number(body.kos)))) : 0;
  const won = !!(body && body.won);
  return 40 + (won ? 60 : 0) + 5 * kos;
}
const REASONS = Object.freeze({ ko: 5, match: matchCap, quest: 500, streak: 100, earn: 1000 });

function capFor(reason, body) {
  const c = REASONS[reason];
  if (c === undefined) return -1;
  return typeof c === 'function' ? c(body) : c;
}

class WErr extends Error {
  constructor(status, err, msg, extra) { super(msg); this.status = status; this.err = err; this.extra = extra || null; }
}

const dayOf = now => Math.floor(now / 86400000);
const int0 = v => (Number.isFinite(Number(v)) ? Math.max(0, Math.floor(Number(v))) : 0);

function create(store) {
  const locks = new Map();                                     // account -> tail of its operation chain

  function withLock(l, fn) {
    const prev = locks.get(l) || Promise.resolve();
    const run = prev.then(fn, fn);
    const tail = run.catch(() => {});
    locks.set(l, tail);
    tail.then(() => { if (locks.get(l) === tail) locks.delete(l); });
    return run;
  }

  async function load(l) {
    try { const raw = await store.get('wallet:' + l); const w = raw ? JSON.parse(raw) : null; return w && typeof w === 'object' ? w : null; }
    catch (e) { return null; }
  }
  const save = (l, w) => store.set('wallet:' + l, JSON.stringify(w));

  /** Read the seed coins out of the account's existing cloud save (shape {t, d:{wallet:{coins}}}). */
  async function seedCoins(l) {
    try {
      const raw = await store.get('data:' + l);
      const doc = raw ? JSON.parse(raw) : null;
      const blob = doc && doc.d && typeof doc.d === 'object' ? doc.d : null;
      const w = blob && blob.wallet && typeof blob.wallet === 'object' ? blob.wallet : null;
      return Math.min(MAX_SEED, int0(w && w.coins));
    } catch (e) { return 0; }
  }

  /** The account's wallet record, seeded once on first use (docs/PROTOCOL.md 4.3). Caller holds the lock. */
  async function ensure(l) {
    let w = await load(l);
    if (w) return w;
    const now = Date.now(), coins = await seedCoins(l);
    w = {
      v: 1, coins, seeded: true, seededAt: now,
      ledger: [{ r: 'migrate', a: coins, id: 'migrate-1', t: now }],
      ids: { 'migrate-1': now },
      day: dayOf(now), granted: 0,
    };
    await save(l, w);
    return w;
  }

  function clip(w) {
    if (w.ledger.length > LEDGER_MAX) w.ledger = w.ledger.slice(-LEDGER_MAX);
    const ids = Object.keys(w.ids);
    if (ids.length > IDS_MAX) {
      for (const id of ids.slice(0, ids.length - IDS_MAX)) delete w.ids[id];
    }
  }
  function seen(w, id) { return Object.prototype.hasOwnProperty.call(w.ids, id); }
  function mark(w, id, now) { w.ids[id] = now; clip(w); }

  function view(w) {
    return {
      ok: true, coins: int0(w.coins), seeded: w.seeded !== false,
      today: { day: w.day, granted: int0(w.granted), cap: DAY_CAP },
      ledger: (w.ledger || []).slice(-10).map(e => ({ reason: e.r, amount: e.a, id: e.id, time: e.t })),
    };
  }

  async function read(l) { return withLock(l, async () => view(await ensure(l))); }

  async function grant(l, body) {
    return withLock(l, async () => {
      const id = body && body.id, reason = body && typeof body.reason === 'string' ? body.reason : '';
      if (typeof id !== 'string' || !ID_RE.test(id)) throw new WErr(400, 'id', 'Send an id of 8 to 64 letters, numbers, - or _.');
      if (!Object.prototype.hasOwnProperty.call(REASONS, reason)) throw new WErr(400, 'reason', 'Reason must be ko, match, quest, streak or earn.');
      const raw = body && body.amount;
      if (typeof raw !== 'number' || !Number.isFinite(raw) || !Number.isInteger(raw) || raw < 1 || raw > MAX_AMOUNT)
        throw new WErr(400, 'amount', 'Amount must be a whole number from 1 to ' + MAX_AMOUNT + '.');
      const amount = raw, cap = capFor(reason, body);
      const w = await ensure(l);
      if (seen(w, id)) return Object.assign(view(w), { replay: true });
      if (amount > cap) throw new WErr(400, 'cap', 'That is more coins than one ' + reason + ' reward can pay (max ' + cap + ').', { coins: int0(w.coins), cap });
      const now = Date.now(), day = dayOf(now);
      if (w.day !== day) { w.day = day; w.granted = 0; }
      if (int0(w.granted) + amount > DAY_CAP)
        throw new WErr(409, 'cap', 'The daily coin cap (' + DAY_CAP + ') is reached. Try again tomorrow.', { coins: int0(w.coins), cap: DAY_CAP });
      w.coins = int0(w.coins) + amount;
      w.granted = int0(w.granted) + amount;
      w.ledger.push({ r: reason, a: amount, id, t: now });
      mark(w, id, now);
      await save(l, w);
      return Object.assign(view(w), { added: amount });
    });
  }

  async function spend(l, body) {
    return withLock(l, async () => {
      const id = body && body.id, item = body && typeof body.item === 'string' ? body.item : '';
      if (typeof id !== 'string' || !ID_RE.test(id)) throw new WErr(400, 'id', 'Send an id of 8 to 64 letters, numbers, - or _.');
      if (!item || !Object.prototype.hasOwnProperty.call(ITEMS, item)) throw new WErr(400, 'item', 'Unknown item.');
      const w = await ensure(l);
      if (seen(w, id)) return Object.assign(view(w), { replay: true });
      const price = ITEMS[item];
      if (int0(w.coins) < price) throw new WErr(409, 'coins', 'Not enough coins.', { coins: int0(w.coins), price, item });
      const now = Date.now();
      w.coins = int0(w.coins) - price;
      w.ledger.push({ r: 'spend', a: -price, id, t: now, item });
      mark(w, id, now);
      await save(l, w);
      return Object.assign(view(w), { spent: price, item });
    });
  }

  /** Account deletion: the wallet goes with the account. */
  async function erase(l) { return withLock(l, () => store.del('wallet:' + l)); }

  return { read, grant, spend, erase, ITEMS, REASONS, MAX_SEED, DAY_CAP, LEDGER_MAX, IDS_MAX, MAX_KO, capFor };
}

module.exports = { create, ITEMS, REASONS, MAX_SEED, DAY_CAP, LEDGER_MAX, IDS_MAX, MAX_KO, capFor, ID_RE };
