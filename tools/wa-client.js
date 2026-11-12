'use strict';
/* Minimal Wobblers Arena protocol client (layer 1 server ops + layer 2 room messages, see docs/PROTOCOL.md). Used by the tests; the Godot client mirrors it. */
const { WebSocket } = require('ws');
const PROTO = 1, BUILD = 'b77.0';   // the web game's NET_BUILD (public/index.html)
class Client {
  constructor(url, name) { this.url = url; this.name = name || 'Bot'; this.inbox = []; this.waiters = []; this.cid = -1; this.slot = -1; this.role = null; }
  open() {
    return new Promise((res, rej) => {
      this.ws = new WebSocket(this.url);
      this.ws.on('message', d => { let m; try { m = JSON.parse(d.toString()); } catch (e) { return; } const i = this.waiters.findIndex(w => w.pred(m)); if (i >= 0) { const w = this.waiters.splice(i, 1)[0]; clearTimeout(w.tm); w.res(m); } else this.inbox.push(m); });
      this.ws.on('open', () => res(this)); this.ws.on('error', rej);
    });
  }
  tx(m) { this.ws.send(JSON.stringify(m)); }
  wait(pred, ms = 3000) {                                  // next message matching pred (looks at already received ones first)
    const i = this.inbox.findIndex(pred); if (i >= 0) return Promise.resolve(this.inbox.splice(i, 1)[0]);
    return new Promise((res, rej) => { const w = { pred, res, tm: setTimeout(() => { this.waiters.splice(this.waiters.indexOf(w), 1); rej(new Error('timeout waiting for message')); }, ms) }; this.waiters.push(w); });
  }
  op(op) { return this.wait(m => m.op === op); }
  async create(pub, build = BUILD) { this.tx({ op: 'create', pub: !!pub, info: { name: this.name + "'s room", host: this.name, mode: 'classic', modeName: 'Classic', map: 'Arena', max: 4, build } }); const m = await this.wait(x => x.op === 'created' || x.op === 'nocreate'); if (m.op !== 'created') throw new Error('nocreate ' + m.reason); this.role = 'host'; this.roomId = m.id; this.slot = 0; return m.id; }
  async join(id) { this.tx({ op: 'join', id, build: BUILD }); const m = await this.wait(x => x.op === 'joined' || x.op === 'nojoin'); if (m.op !== 'joined') throw new Error('nojoin ' + m.reason); this.role = 'guest'; this.cid = m.cid; return m; }
  hello() { this.tx({ op: 'tohost', m: { t: 'hello', build: BUILD, proto: PROTO, name: this.name, skin: 'none', hat: 'none', color: 0x39b5a8 } }); }
  toHost(m) { this.tx({ op: 'tohost', m }); }
  toAll(m, except) { this.tx({ op: 'all', m, except }); }
  to(cid, m) { this.tx({ op: 'to', cid, m }); }
  close() { try { this.ws.close(); } catch (e) { /* x */ } }
}
module.exports = { Client, PROTO, BUILD };
