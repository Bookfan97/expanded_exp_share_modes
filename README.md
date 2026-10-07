Forked From: https://github.com/FAFF0x/gen1recomp/blob/main/exp_share_modes_v1.0.0.zip

# EXP Share Modes

A configurable EXP distribution mod for Gen1Recomp. Works on Red/Blue/Yellow,
Gold/Silver/Crystal, and FireRed/LeafGreen/Ruby/Sapphire/Emerald.

Gen 1 and Gen 2 share the `battle.exp_award` hook, so the same rules run on both
generations. Gen 3 uses the per-recipient `exp.gain` hook, so the mod returns
the adjusted amount for each eligible mon.

## Modes

- **Off** — Vanilla-style distribution without EXP.ALL: only living Pokémon
  that participated against the defeated opponent receive EXP.
- **Classic Even Split** *(default)* — The full EXP pool is divided evenly
  across every living party member. Total EXP remains approximately unchanged,
  apart from the engine's normal integer rounding/minimum-one behavior.
- **Modern Progressive** — Participating Pokémon divide the normal full pool.
  Living nonparticipants divide a separate 50% pool, for approximately 1.5x
  total EXP.
- **Modern Even Split** — The full EXP pool is divided evenly across every
  living party member. Total EXP remains approximately unchanged, apart from the
  engine's normal integer rounding/minimum-one behavior.

Fainted Pokémon receive no EXP in any mode.

## Configuration

Open the Mod Manager, select **EXP Share Modes**, open **OPTIONS**,
choose the desired **EXP SHARE MODE**, then use **APPLY & RESTART**.
The selected mode is used for every Pokémon defeated after the restart.

## Compatibility

The mod replaces the vanilla EXP award (the participant/EXP.ALL split on
Red/Blue/Yellow and the participant/EXP.SHARE split on Gold/Silver/Crystal,
and the participant/EXP.SHARE split on FireRed/LeafGreen/Ruby/Sapphire/Emerald)
with its own selected rule. The vanilla passes are never run, so the EXP.ALL
item and the held EXP.SHARE item do not alter any mode's pool. It does not
change encounter EXP values, trainer bonuses, traded-Pokémon bonuses, level
caps, learnsets, or evolution requirements.

On Gen 3 the engine only calls `exp.gain` for Pokémon that participated or
are holding EXP.SHARE, so the modes apply within that eligible set. The pool
is not taxed by EXP.SHARE, and Lucky Egg, trainer-battle, and traded-Pokémon
multipliers are preserved.

This mod uses only the standard mod API (`mod.options`, `mod.generation`, the
`battle.exp_award` hook, and the `exp.gain` hook) and needs no
`engine_internals` permission. The engine's own award flow still drives the
messages, level-up screens, move learning, happiness, stat EXP / EVs, and
post-battle flow.
