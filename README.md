# BUSSYUI

A minimal **"busy" status indicator** for World of Warcraft: Midnight (12.0.x).

Shows a small, draggable frame that reports one of four states with precedence
**CASTING > COMBAT > GCD > READY**:

| State | Meaning | Color |
|-------|---------|-------|
| `BUSY · CASTING` | You are casting or channeling a spell. | Blue |
| `BUSY · COMBAT`  | You are in combat (regen disabled).   | Red |
| `BUSY · GCD`     | You are off-global-cooldown-locked.   | Yellow |
| `READY`          | None of the above.                    | Green |

## Install

1. Drop the `BUSSYUI` folder into your WoW `_retail_/Interface/AddOns/` directory.
2. Enable it in the AddOns menu at the character select screen.
3. `/bussyui` for commands.

## Slash commands

| Command | Effect |
|---------|--------|
| `/bussyui lock`     | Lock the frame (no dragging). |
| `/bussyui unlock`   | Unlock the frame so you can drag it. |
| `/bussyui reset`    | Reset position/scale to defaults. |
| `/bussyui scale <n>`| Set scale (clamped 0.5 – 3.0). |
| `/bussyui gcd`      | Toggle the GCD indicator on/off. |
| `/bussyui help`     | List commands. |

Aliases: `/busyui`.

## Saved variables

Layout (point, offset, scale, lock, showGcd) is persisted across sessions via
the `BUSSYUI_DB` saved variable declared in `BUSSYUI.toc`.

## API notes (Midnight 12.0.x)

- `C_SpecializationInfo`, `C_SpellBook`, `C_Spell`, `C_UnitAuras` — modern namespaces.
- `C_Spell.GetSpellCooldown` returns a table `{ start, duration, enable, modRate }`.
- `C_SpellBook.GetNumSpellBookSkills` / `GetSpellBookSkillLineInfo` — spellbook enumeration.
- `UnitAffectingCombat("player")` — still valid for combat detection.
- `BackdropTemplate` — required mixin for `SetBackdrop` in 9.0+.

## License

MIT — see [LICENSE](LICENSE).
