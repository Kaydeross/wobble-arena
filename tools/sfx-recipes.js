'use strict';
/* The Godot client's sound-effect recipes (frozen). These are the web game's original `tone` / `noise` recipes, kept
   here after the web build moved to the layered SoundManager (public/index.html), so tools/render-sfx.js keeps
   producing the committed godot/audio/sfx/*.wav byte for byte. Edit a recipe here, then run `npm run sfx`.
   tone(f0, f1, dur, type, vol, delay) / noise(dur, vol, freq, delay): see tools/render-sfx.js. */
const SFX = {
  click: () => { tone(620, 880, 0.06, 'triangle', 0.09); },
  pop: () => { tone(300, 760, 0.12, 'sine', 0.12); },
  whack: () => { noise(0.12, 0.35, 1800); tone(190, 60, 0.16, 'square', 0.18); },
  clink: () => { tone(1400, 900, 0.12, 'triangle', 0.2); noise(0.06, 0.2, 5000); },
  slap: () => { noise(0.09, 0.4, 3500); tone(420, 160, 0.1, 'triangle', 0.2); },
  swing: () => noise(0.14, 0.12, 3500),
  shot: () => { noise(0.1, 0.3, 4000); tone(520, 120, 0.1, 'square', 0.12); },
  shotgun: () => { noise(0.22, 0.45, 2500); tone(180, 50, 0.22, 'sawtooth', 0.2); },
  flame: () => { noise(0.12, 0.28, 1400); tone(110, 70, 0.1, 'sawtooth', 0.06); },
  mammoth: () => { noise(0.45, 0.7, 1500); tone(110, 28, 0.5, 'sawtooth', 0.32); tone(260, 60, 0.18, 'square', 0.12); },
  sniper: () => { noise(0.3, 0.5, 6000); tone(900, 90, 0.35, 'sawtooth', 0.2); },
  rocket: () => { noise(0.35, 0.3, 1200); tone(300, 90, 0.3, 'sawtooth', 0.15); },
  boom: () => { noise(0.9, 0.7, 600); noise(0.3, 0.45, 2600); tone(120, 24, 0.9, 'sine', 0.55); tone(70, 20, 1.2, 'triangle', 0.3, 0.05); },
  wind: () => noise(0.1, 0.1, 2200),
  kick: () => { noise(0.1, 0.18, 1200); tone(140, 70, 0.1, 'sine', 0.2); },
  boing: () => { tone(220, 520, 0.25, 'sine', 0.22); tone(520, 180, 0.3, 'sine', 0.18, 0.2); },
  bounce: () => tone(260, 760, 0.22, 'sine', 0.22),
  pickup: () => { tone(520, 780, 0.1, 'triangle', 0.22); tone(780, 1170, 0.14, 'triangle', 0.22, 0.09); },
  drop: () => tone(900, 300, 0.35, 'sine', 0.16),
  mag: () => { noise(0.05, 0.22, 3200); tone(240, 130, 0.07, 'square', 0.09); },
  shellIn: () => { tone(760, 520, 0.05, 'triangle', 0.1); noise(0.03, 0.1, 2500); },
};
