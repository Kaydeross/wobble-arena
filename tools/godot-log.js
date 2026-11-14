'use strict';
/* Godot's exit log on Linux CI can end with shutdown-only resource/RID leak lines ("ERROR: 5 resources still in use at
   exit", "ERROR: N RID allocations ... were leaked at exit"): they appear after an otherwise passing headless run and
   the same suite can print none on macOS. A check must only treat real failures as fatal: a script error, or a load /
   compile / parse failure. (Same rule as tools/test-ui.js, which was fixed for this in #109.) */
module.exports.isFatal = out => /SCRIPT ERROR|^ERROR: Failed to (load|compile|parse)/m.test(out);
