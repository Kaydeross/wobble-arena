# Sharing a result card

The end-of-match panel can hand a player a **shareable result card**: a 1080x1920 portrait PNG with the logo, mode and
arena, the result, K.O.s, deaths and coins. Shipping starts with the image (WP 0.6-C); video clips are out of scope
until the image share shows uptake.

The card is rendered locally. This repo bundles **no third-party share SDK**: a platform adapter registers a provider
with the `Share` autoload, and the **Share card** control exists only while that provider is present.

## Route

- `godot/ui/result_card.gd` (`ResultCard`) normalises `Save.finish_match()`'s summary plus the match context, builds
  the card (theme colours, low-poly facets, a cheap wobbler portrait from the player's look), renders it in a
  `SubViewport` and writes a deterministic timestamped PNG under `user://share/`, e.g.
  `wobblers_classic_20260101-120000.png`. The filename adds `_2`, `_3`, … only if a share in the same second already
  exists.
- `godot/autoload/share.gd` (`Share`, registered in `project.godot` like `Ads`/`Entitlements`) owns the provider
  contract and `has_provider()`.
- `godot/world/world.gd` adds the control in `_show_offline_results` and `_show_results` beside Quit/Leave, so a small
  screen does not grow taller. The control is 60 canvas px tall (44 pt at the touch UI scale) and localised in all five
  languages. With no provider it is not created at all — no "Save image" fallback, and therefore no control on web,
  desktop or headless builds.

## Provider contract

```gdscript
Share.set_provider(provider)                       # provider may be any Object
Share.has_provider() -> bool                       # true only when share_image() exists
Share.share_image(path: String, text: String) -> bool
```

The provider implements `share_image(path: String, text: String) -> bool` and returns `true` when the system sheet
accepted the request. `Share` never touches the filesystem or the network; it passes the local PNG path and a short
localised caption. A provider may return `void`; only an explicit `false` counts as a refusal.

## Platform step (owner only)

iOS needs a native share plugin (a small `UIActivityViewController` wrapper) added in Xcode and to the export preset.
The plugin calls `Share.set_provider(self)` at startup and implements `share_image`. That step is owner-only: it needs
the Apple developer setup and the signed build, neither of which belongs in this repo. The same contract fits an
Android `Intent.ACTION_SEND` adapter or a desktop adapter later.

## Tests

`npm run test:godot-result-card` builds a card from a `finish_match` summary, checks the 1080x1920 PNG and its path,
checks the Share control disappears without a provider, and uses `godot/tests/fake_share_provider.gd` to prove the
provider receives the saved path. Headless has the dummy renderer, so the test PNG is a deterministic painted
placeholder at the same size; the layout itself is exercised without rendering.
