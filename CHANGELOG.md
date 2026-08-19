# Changelog

## 1.2.2
- Declared `games: ["gen1", "gen2"]` in manifest.json. Per the modkit's
  Gen 2 compatibility rules, omitting `games` means Gen 1 only, so the
  loader would have refused to run this mod on Gold/Silver/Crystal despite
  `battle.exp_award` already handling both generations.

## 1.2.1
- Classic Even Split: collapsed the per-member EXP lines into one summary,
  keeping the active battler's own "gained" line and a single
  "The rest of your party each received N EXP. Points!" line for the bench.

## 1.2.0
- Ported distribution onto the cross-generation `battle.exp_award` hook:
  works on Red/Blue/Yellow and Gold/Silver/Crystal.
- Removed all engine-internal coupling (EXP.ALL save hack, queue insertion
  surgery, reimplemented stat box, Pikachu-follower happiness); dropped the
  `engine_internals` permission.
- EXP.ALL (Gen 1) and held EXP.SHARE (Gen 2) no longer alter any mode's pool.

## 1.1.0
- Added Even Split mode: every living party member receives the full un-divided EXP share, including bench members who did not participate.

## 1.0.0
- Added Off, Classic Even Split and Modern Progressive modes.
- Added Mod Manager option with Classic Even Split as the default.
- Preserved level-up messages, stat window, move learning and event emission.
