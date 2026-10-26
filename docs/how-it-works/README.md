# How Sandevistan works inside

For anyone who wants to understand, debug or learn from the mod's code: where each part runs, what is saved where, how an
activation flows, how multiplayer is handled and what the optional Java add-ons do. For how to *play* the mod, read the
[player guide](../guide/README.md) instead.

> Describes version **0.8 (build 201)** on Project Zomboid Build 42.21. All the numbers live in `Config.lua`; this page names the
> mechanisms and leaves the values to the code. Code comments are in Spanish.

## Contents

1. [Layout of the mod](#1-layout-of-the-mod)
2. [Where each part runs](#2-where-each-part-runs)
3. [Modules and load order](#3-modules-and-load-order)
4. [Time and units](#4-time-and-units)
5. [What is saved where](#5-what-is-saved-where)
6. [The life of an activation](#6-the-life-of-an-activation)
7. [Systems, module by module](#7-systems-module-by-module)
8. [Multiplayer](#8-multiplayer)
9. [Resources: scripts, translations, sandbox, the 3D spine](#9-resources)
10. [Interface: moodles, the Implant tab and the floating panel](#10-interface)
11. [The Java add-ons](#11-the-java-add-ons)
12. [Debugging and the report](#12-debugging-and-the-report)
13. [Build 42 API lessons](#13-build-42-api-lessons)

---

## 1. Layout of the mod

```
mod/
├── Sandevistan/                  the base mod (the only one a dedicated server needs)
│   ├── 42/
│   │   ├── mod.info              id, version, loadModAfter=MoodleFramework
│   │   └── media/
│   │       ├── perks.txt         the "Sandevistan: Adaptation" skill (Perks.SandevistanAdaptation)
│   │       └── sandbox-options.txt   55 server options (option Sandevistan.<Name>)
│   └── common/media/
│       ├── registries.lua        registers the "sandevistan:spine" body location and the traits (runs before everything)
│       ├── clothing/clothingItems/   the 3D implant worn on the back, as clothing XML
│       ├── scripts/              items (61, firmware chips included), spine clothing, recipes (21), models, sounds
│       └── lua/
│           ├── shared/Sandevistan/   Config, Firmware, Core, Kerenzikov, RecipeCode, TraitDefs, BookGuide... (client and server)
│           ├── shared/Translate/{EN,AR,ES,RU}/   JSON translations
│           ├── client/Sandevistan/   everything the player does and sees
│           └── server/Sandevistan/   World (placements, ex-subjects), Net (relay), Loot, ActionSpeed, ALife
├── SandevistanFX/                optional: slowed zombie voices, frozen rain (Java, client)
├── SandevistanPsychosis/         optional: the Java side of cyberpsychosis (client)
└── SandevistanViewpoint/         optional: afterimages with real pose, 3D camera support (client)
java/<add-on>/src/                Java source of the three add-ons
```

Conventions:
- Each Lua file defines **one global table** prefixed `Sandevistan…` and returns it. Modules use short local aliases: `S` = Core
  (`Sandevistan`), `CFG` = `SandevistanConfig`, `R` = Runtime, `E` = Effects, `SD` = Slowdown, `M` = Medical.
- **No magic numbers:** every value is in `Config.lua`. The values that a server can change are overwritten from
  `SandboxVars.Sandevistan` by `SandevistanConfig.applySandbox()`, after the difficulty preset is merged in.
- Visible text always goes through `getText("IGUI_Sandevistan_…")`. Logs are not translated.
- Every event handler is wrapped: `Events.X.Add(S.safe("Module.X", fn))`. An error is reported once with a counter instead of
  flooding the console, and the handler's cost is measured for the performance test.

## 2. Where each part runs

Project Zomboid loads `shared/` on client **and** server, `client/` only on clients, and `server/` on the server **and also on
multiplayer clients**. In single player and split screen everything runs in the same process.

| Folder | Single player | MP client | Dedicated server |
|---|---|---|---|
| `shared/` | yes | yes | yes |
| `client/` (the whole player side) | yes | yes | **no** |
| `server/World.lua`, `server/ALife.lua` | yes | loaded but **inactive** | yes |
| `server/Net.lua` | inactive | inactive | yes |
| `client/Net.lua`, `client/RemoteSurgery.lua` | inactive | yes | no |

- `SandevistanWorld.authority` = `isServer() or not isClient()`: the world code only registers its events with authority, so an
  MP client never places loot sets or ex-subjects itself.
- **The implant's state lives on the client** (the player's ModData, §5). The server doesn't simulate the implant: it validates,
  applies what only it can apply, saves and relays (§8).

## 3. Modules and load order

```
Config ─► Firmware ─► Core ─┬─► Kerenzikov
                            ├─► Effects
                            ├─► Slowdown
                            └─► Runtime ─► (Slowdown, Effects, Kerenzikov)
                                   ├─► Input, Combat, Periodic, Medical ─► ContextMenus ─► RemoteSurgery
                                   │        └─► FirmwareClient
                                   └─► Spine
HUD ─► HUDPanel, Afterimages, Spine, Psychosis, Moodles
InfoView ─► Core, Runtime, Moodles, HUDPanel, HUD
World (server) ─► Core
registries.lua ─► (nothing; runs first)
```

The game loads `registries.lua`, then the scripts (`*.txt`), then Lua `shared`, then `client`/`server`, alphabetically inside
each folder. That's why every file `require`s what it uses instead of relying on order.

## 4. Time and units

- **Real seconds** (`S.realMs()`): everything that happens *during* an activation (Heat, cooling, stamina, neural load per
  second, key timing, Overdrive, momentum). Real time is used because the game-time multiplier can be changed.
- **In-game hours** (`S.worldHours()`): everything biological or slow (rejection, neural load decay, immunosuppressants, toxicity,
  Kerenzikov, antidepressants, passive XP). Fields ending in `…Until` are **absolute** in-game hours.
- With the default day length, 1 in-game hour ≈ 2.5 real minutes.
- The tick's `dt` is capped at 0.25 s and is 0 while the game is paused.

## 5. What is saved where

### Player ModData: `player:getModData().Sandevistan`

Read with `S.data(player)`, which creates the table and fills missing fields with defaults. It's saved with the character.

| Field | Meaning |
|---|---|
| `variant` | `nil` (none), `"lab"`, `"military"` or `"destroyed"` |
| `prototype` | alternative design: `"04"`/`"06"` (lab) or `"07"` (Mk. II, military) |
| `plateName` | the name the player gave the board (P06 and Mk. II) |
| `degradation`, `degradationFloor` | Heat multiplier of a worn implant and its calibration floor |
| `heat` | 0–100, keeps going after switching off and drops with cooling |
| `neuralLoad` | 0–100 |
| `cyberpsychosisActive` | permanent once neural load reaches the threshold (until remission) |
| `rejection` | 0–100; at 100 the implant is destroyed |
| `adaptXP` | **source of truth** for adaptation; the level comes from `S.level(d)`. The vanilla skill is only a mirror |
| `immuno` | end of coverage per tier (`clinicalUntil`, `craftedUntil`, `herbalUntil`) |
| `immunoDoses`, `immunodep`… | doses in the last 24 h (shock dose and tolerance) and immunodepression |
| `herbalToxicity`, `antidepUntil` | toxicity of herbal immunosuppressants, antidepressant coverage |
| `staminaDebt` | stamina borrowed while the implant was on |
| `lockUntilCool` | after a thermal cut, emergency or Overdrive: can't switch on again until Heat 0 |
| `knows` | learned recipes and designs |
| `firmware`, `fwKnown`, `fwRecalUntil` | installed chips per slot (`sistema`, `habilidad`), known programs, recalibration end |
| `incidents`, `neuralScar`, `seen` | cyberpsychosis black box, neural scar and the hallucinations already discovered |
| `hudX`, `hudY`, `hudFloating` | floating panel position and visibility (`nil` = automatic) |

### Other ModData

| Where | Key | Content |
|---|---|---|
| player | `Kerenzikov` | active/crash windows, tolerance, last dose |
| world (`ModData.getOrCreate("SandevistanWorld")`, server) | placements, zones, subjects… | which loot sets were placed, state per zone, the ex-subject registry |
| corpse | `Sandevistan` | the implant that can be extracted from it |
| implant item | `heatDegradationMultiplier`, `degradationFloor`, `prototype` | quality of a loose implant |

Zombies lose their ModData identity when they unload, so ex-subjects are recognized by their **persistent outfit id**, not by
ModData on the zombie.

### In memory only

The active session (`SandevistanRuntime.sessions[playerNum]`: active, armed, Overdrive, momentum, effective tier…), the set of
slowed zombies, the key state machine and the remote players' state. **When a game loads, the implant starts off.**

## 6. The life of an activation

Everything happens on the **player's client**:

1. **Key** (`Input.lua`). A state machine `IDLE → ACTIVATING → ACTIVE → ARMING → ARMED`: a tap switches on or off, holding arms
   the Overdrive. Key release is detected by polling `isKeyDown` every tick, because `OnKeyPressed` doesn't reliably report it.
2. **`R.activate`** (`Runtime.lua`). `canActivate` checks a working implant, no vehicle or sleep, no lock, Heat < 100, rejection
   below its limit, enough stamina and the reuse delay. Then it picks the dilation tier from the adaptation level and variant,
   computes the effective tier (momentum, Overdrive, traits, firmware) and calls `SD.activate`.
3. **Every tick** (`R.onTick` → `tickActive`). Heat rises (`S.heatPerSecond`). Stamina doesn't drop: what you spend is stored as
   **debt** and charged when you switch off. Neural load rises per second of use (the only neural load from normal use). Momentum
   builds up. XP is flushed every few seconds. At Heat 100 it either enters Overdrive (if armed) or cuts out. Thresholds are
   checked (cyberpsychosis, destruction by rejection).
4. **Dilation** (`SD.tick`). The default strategy is *zonal*: every tick, zombies within a radius of each active source (local
   or remote player) have their movement damped, their animations switched to slow copies (an animation variable) and, with the
   FX add-on, their voices pitched down. The player gets a small push toward reachable tiles (`nudge`) plus faster animations.
   The game's own speed setters have no effect on zombies in B42, so the mod damps their displacement instead.
5. **Switching off** (`R.deactivate(player, kind)`). Charges the stamina debt (go over the margin and you stumble and can't
   sprint). `manual` leaves a short reuse delay; `auto` and `emergency` lock the implant until it's cool and add rejection.
6. **Overdrive.** A window of extra power that grows with adaptation, and always ends in **`R.collapse`**: stumble or
   unconsciousness, a slow drag on the player, Heat 100, neural load and rejection spikes, noise, and a thermal scar that lowers
   the Heat cap for a while. With cyberpsychosis, the collapse can kill.
7. **Cooling** (`tickCooling`, while off). Heat drops by `S.coolPerSecond` times an **ambient** bonus: cold, a wet body and
   outdoor wind cool faster (bonus only, with a cap). Momentum fades.

All the formulas are pure functions in `Core.lua` (level from XP, Heat/s, cooling/s, dilation tier, Overdrive window, rejection
per hour, neural load decay), fed by `Config.lua`. The balance simulator in the development tools reuses those same files to
simulate whole lives of a character.

## 7. Systems, module by module

### Core and config
- **`shared/Config.lua`**: the single source of numbers (variants, dilation tiers, stamina, Overdrive, momentum, combat, neural
  load, rejection, immunosuppressants, Kerenzikov, XP, surgery, extraction, calibration, prototypes, crafting, world, loot, net,
  cyberpsychosis, firmware, presets).
- **`shared/Core.lua`**: utilities with no side effects: logging (`S.log` goes to a buffer for the report and only prints with
  verbose logging; `S.logAlways` for warnings), `S.try`/`S.safe`, clocks, `S.data`, the formulas, and the mirror with the vanilla
  skill: if someone raises the skill from outside (admin, another mod), `adaptXP` adopts it.

### The player side (`client/`)
- **Effects**: everything that touches stats, the body or animation: stats, speech bubbles, world noise, stumble and
  unconsciousness (done by damping the player's movement, never by forcing vanilla "bump" states), pain, wounds, nosebleeds,
  screams. In MP, stat and body changes go through the server (§8).
- **Runtime**: the session (§6), Overdrive, collapse, catastrophic failure, XP, thresholds, stamina debt.
- **Slowdown**: the single interface for dilation (`activate`, `deactivate`, `tick`, `setTier`). Level of detail for far zombies,
  a gradual release when they leave the radius, slow animation copies, the player's fast animations, holds during climbing.
- **SlowAudio**: lowers the user volume of zombie voice events while they're slowed (FMOD voice events can't be pitched from Lua;
  the FX add-on does that).
- **Combat**: melee bonuses while active: attack speed (`setCombatSpeed` on swing), shorter delay between hits, extra damage
  computed from what the vanilla hit would lose, knockdowns, stamina refund, XP per kill. **Firearms** speeds up aiming and
  reloading and adds Heat per shot.
- **Periodic**: the slow clocks (every minute and every ten minutes): rejection, immunodepression, neural load decay, passive XP,
  toxicity, symptoms, nosebleeds, screams, Kerenzikov, withdrawal, neural scar recovery.
- **Immunodep**: the immunosuppressant downside. Each minute it amplifies what the game already did: an extra infection roll with
  the same formula as vanilla wounds, faster infection growth, slower healing, stronger colds.
- **Medical**: requirements and results of **every** item action (surgery, extraction, calibration, explanting, doses, studying
  and building prototypes). The context menus only call it. Long actions are a `SandevistanAction` (a timed action) and **the
  roll only happens in `perform`**: cancelling never consumes or punishes. **BookGuide** lets vanilla skill books stand in for
  missing skill levels (longer and riskier, with a floor per roll).
- **ContextMenus**: inventory and world context menus.
- **Traits**: the mod's character traits and starting kits; restores them on the server in hosted games when the engine drops them.
- **Firmware** (`shared/Firmware.lua` + `client/FirmwareClient.lua`): two typed slots (System and Skill) and 9 programs. Each
  installed chip contributes a *profile* (multipliers, offsets, flags); `FW.profile(d)` merges them, caches the result per player
  and returns a shared neutral table when there are no chips, so every hook (`S.heatPerSecond`, `S.dilationTier`, combat,
  rejection, neural load…) behaves as before. `FirmwareClient` handles chips as objects: flashing, removing, writing on a powered
  computer or a portable terminal, decompiling, and the live layer (movement, kills, the "work mode" of the Taller program).
- **Psychosis** and friends: stages from neural load, psychotic pressure (fatigue, pain, zombies, heat), crises that announce
  themselves (`Crisis`), humanity anchors (`Anchors`), the black box, the neural scar, danger sense with phantom marks, positional
  audio roles, time glitches, fury, blackouts, night terrors, and the hallucinations that need Java (fake zombies, the double,
  phantom figures, echoes, the disguise, corrupted text, screen effects) through bridges to the add-ons (§11). Without the add-ons,
  those features are skipped and the rest keeps working.
- **Afterimages**: trails of tinted silhouettes at past positions, by gait; with the Viewpoint add-on, real poses instead.
- **Spine**: the implant on the back is a **clothing item** the mod equips and keeps in sync with the state (off, on, red).
  **CorpseVisual** puts the 3D board on corpses that still carry an implant.
- **Dossier**, **Reader**, **InstallScene**, **Walkthrough**: lore notes filed into dossiers, the reading window, the installation
  scene and the guided walkthrough.

### The world (`server/`)
- **World**: global ModData, active campuses, one-time placement of loot sets per zone (when a player gets close to an anchor and
  the area is loaded), a room scan by keywords around the anchor, the ex-subject registry (by persistent outfit), corpses that
  carry an implant (claimed by searching around the death point, because the corpse events are client-side and don't fire on a
  dedicated server), and a loose implant if the body disappears.
- **Loot**: inserts the mod's items into the vanilla procedural distributions whose names match patterns in `Config.Loot`.
- **ALife**: compatibility with Project A-Life, whose NPCs are zombies inside: an NPC wearing the spine leaves an implant on death.
- **ActionSpeed**: in MP the server computes action durations, so the speed-ups of work mode and reloading are applied there too.
- **Net**: the relay and validation layer (§8).

## 8. Multiplayer

The design is deliberately simple: **each client is the authority over its own player** (a trusted client). The server
validates, saves its copy of the ModData and relays messages between clients. It's enough for co-op; it is **not cheat-proof**.

What the server owns in Build 42.21, and how the mod deals with it:
- **Player stats** (endurance, fatigue, panic, pain…): the server simulates them and sends them back, overwriting client changes.
  Every stat change goes through `E.setStat`, which on an MP client queues it; every 250 ms a `stats` command carries the
  differences and the server applies them, clamped.
- **The player's save** is the server's copy. Client ModData reaches it only with `player:transmitModData()`: the mod sends it
  every 15 s and **immediately** after anything important (installing, explanting, calibrating, kits, firmware chips, learning
  recipes, antidepressants), so a disconnect doesn't lose it.
- **Items** created on a client exist only on that client's screen. On an MP client `S.grantItem` asks the server (`give`), which
  creates the item with its ModData and name. Item ModData changes (`itemMd`) and consumption (`consume`) go the same way.
- **Body changes** (pain, wounds, bleeding, health, death) go through a `body` command. Skill level and recipes too.
- **Timed actions:** `SandevistanAction` lives in `shared/` and is marked `setCustomRemoteTimedActionSync(true)`, so the client
  doesn't send it to the server as a network timed action (a dedicated server doesn't load `client/` and would reject the packet).

Commands go `sendClientCommand(player, "Sandevistan", cmd, args)` → server `OnClientCommand` → `sendServerCommand` → client
`OnServerCommand`. Main ones:

| Command | What the server does | Used for |
|---|---|---|
| `active`, `look` | validates and broadcasts | slowing zombies around remote players; showing other players' implant |
| `scream` | broadcasts and makes noise | seeing another player's psychotic scream |
| `stats`, `body`, `perk`, `recipes` | applies to the player | effects that would otherwise be undone by the server |
| `give`, `grant`, `itemMd`, `consume` | creates or changes items (only the mod's types, rate-limited) | chips, implants, kits, doses, the spine |
| `spineWorn` | equips/removes the spine and syncs clothing | others see the implant and it doesn't duplicate |
| `surgery*`, `op*` | relays with the patient's **consent**, distance and sanitized values | surgery, explanting and calibration on another player |
| `implantDeath`, `subjectExtracted` | registers in the world | a dead player's corpse carries their implant |
| `traits`, `fileNotes`, `stashMap`, `speed` | server-side helpers | traits in hosted games, dossiers, annotated maps, action speed |
| `mpDiag`, `mpMeasure` | diagnostics | the debug full test: does the server see the zombies slowed? |

Two details: an **empty table** sent with `sendClientCommand` arrives as `nil`, so every request carries at least one field; and
the cyberpsychosis sounds are played with a local-only call, so **only the affected player hears them**.

## 9. Resources

- **Item scripts** (`scripts/*.txt`): B42.20+ syntax (`ItemType = base:normal`, `BodyLocation = sandevistan:spine`), module
  `Sandevistan`. Recipes are native crafting recipes with Lua callbacks in `shared/RecipeCode.lua`. These `.txt` files can't hold
  Lua comments: the parser takes them as a property and aborts the whole script load.
- **Translations** (`lua/shared/Translate/{EN,AR,ES,RU}/`): B42 reads JSON (`IG_UI.json`, `UI.json`, `Sandbox.json`,
  `Moodles.json`, `ItemName.json`, `Recipes.json`, `Tooltip.json`). AR (Rioplatense) is the hand-written source for Spanish, ES
  (neutral) is generated from it, RU is translated by hand from EN. `getText` takes at most 4 arguments, so some texts are split.
- **Sandbox options** (`42/media/sandbox-options.txt`): 55 options, starting with a difficulty `Preset` that overrides the rest
  unless it's Custom. Each one is mapped in `Config.applySandbox`.
- **The 3D spine** is a chain where every link matters: `registries.lua` registers the body location → `BodyLocations.lua` adds it
  to the human group → the spine items in `scripts/` → the clothing XML (full model path, `textureChoices`) → the GUID table →
  the skinned DirectX model → `Spine.lua` equips it. A missing GUID entry makes the clothing exist but invisible.
- **Animation sets**: slowed copies of vanilla zombie nodes (walk, lunge, attack, get up, fall…) gated by a `SandevistanSlow`
  variable, and fast copies of player movement and climbing nodes gated by `SandevistanFast`, with the speed scale read from a
  variable. They're generated from the vanilla files by a script, which is why they aren't in this repository.

## 10. Interface

The hierarchy is: 1) **moodles** are the real state indicator, 2) the **Implant tab** in the character window has the details and
the numbers, 3) the **floating panel** is a fallback and shortcut.

- **Moodles** (`Moodles.lua`, via the optional Moodle Framework): 17 moodles (Heat, lockout, rejection, neural load,
  cyberpsychosis, withdrawal, recovery, toxicity, immunodepression, Kerenzikov crash, borrowed breath, destroyed, active,
  Kerenzikov, coverage, antidepressant, recalibrating). Each has a `level(...)` from 0 (hidden) to 4. Registration retries until
  the framework is ready and never depends on it existing when the file loads. If it's missing or fails, the floating panel shows
  the same states as text rows.
- **Implant tab** (`InfoView.lua`): added by wrapping the vanilla character window. Its content comes from a **pure function**,
  `buildLines`, that returns lines of text with the numbers (Heat per second, time to cut-off, rejection per hour, time to
  thresholds, rest needed, cyberpsychosis stage and what it means…), so it can be tested outside the game.
- **Floating panel** (`HUD.lua` + `HUDPanel.lua`): an `ISUIElement` that draws everything from `prerender`. There are no
  full-screen elements (they capture the mouse). The panel is model/view: `H.buildModel` builds a plain table and
  `HUDPanel.draw` only draws it, with a few drawing calls. Lab and military boards are made of generated textures.
- The heat vignette, Overdrive red, screen glitches, the install scene and the cyberpsychosis overlays are drawn every frame from
  the same `prerender`, with or without the panel.

## 11. The Java add-ons

Three optional client mods load a jar through **ZombieBuddy**, which patches game classes at runtime (enter/exit advice on
methods). The jars are built and tested against the real game classes, so a hook that no longer matches fails at build time;
at runtime a feature whose target changed switches itself off (the Viewpoint add-on checks every class, method and field it uses
before enabling anything). On the Lua side a `Bridge.lua` per add-on connects the base mod to the global the jar exposes;
the base mod treats each backend as optional.

- **SandevistanFX** (`sandevistan.fx`): calls FMOD's `SetPitch` on the event instances of each slowed zombie's voice, footsteps
  and extra emitters (through Java's foreign function API, since the game's FMOD binding doesn't expose pitch), slows the world
  ambience, and slows and freezes rain, snow, splashes and puddle ripples by scaling their update deltas.
- **SandevistanPsychosis** (`sandevistan.psychosis`): *puppets* drawn only on this client (an animated zombie model with an
  outfit, queued into the world render) for fake zombies, your double and phantom figures; the *disguise* (zombies drawn as people,
  or other players as zombies); corrupted text by hooking the font renderer and replacing strings of the same length; glitching
  moodles; screen shake and episode effects by changing shader variables and redrawing the frame with offset copies. Lua sees the
  class as `SandevistanPsy`.
- **SandevistanViewpoint** (`sandevistan.viewpoint`): in the isometric camera it copies each character's real pose when an
  afterimage is stamped and draws it again later with a tint and fade. With Viewpoint's 3D camera it appends those draws to the
  frame's model list, draws the puppets in 3D, hides disguised characters and freezes the 3D rain.

Everything these add-ons show is **local**: no packets, no effect on other players or the server.

## 12. Debugging and the report

- Everything the mod prints starts with `[Sandevistan]`. In the published build only warnings and errors are printed;
  `[Sandevistan] WARN <key>` appears **once** per key, and `ERROR en <handler> (xN)` counts repeated errors (log texts are in
  Spanish). The mod option *Detailed console log* (or `-debug`) prints the rest.
- **The report** (`Zomboid/Lua/Sandevistan_report.txt`, *Debug → Tests and reports → Quick REPORT*, with the debug menu enabled
  in the mod options): version, language, sandbox, the implant's ModData and derived values, inventory, translation checks, the
  moodle and 3D spine diagnostics, world state, multiplayer, the Java add-ons and the last lines of the log. Each section is
  protected, so one failure doesn't stop the rest.
- The debug menu also has a **full test** (dozens of checks with simulated time, a measurement of the dilation, and a server
  measurement in MP), a performance test, a hit bench and per-feature tests. Use a test character: it saves and restores state, but
  it's meant for testing.
- Outside the game, the development repository runs Lua 5.1 tests against stubs of the game API, Python checkers (translations,
  assets, recipes, versions, multiplayer rules, load order) and builds each jar against the real game classes so that hooks fail at
  build time when the game changes.

## 13. Build 42 API lessons

Things that cost time and are worth knowing if you mod B42:

- **Kahlua** (PZ's Lua) has no `next()`, and `string.gsub`/`gmatch` with accented characters isn't reliable. A failing Java call
  inside `pcall` still dumps a stack trace, and the debugger with *Break On Error* stops even inside `pcall`: check that a method
  exists before calling it.
- **Movement:** `setMoveSpeed`, `speedMod` and walk/run speeds don't slow zombies in B42; damping their displacement does. Attack
  speed works with `setCombatSpeed` on `OnWeaponSwing`.
- **Animations:** don't force "bump" states on the player (it can lose control or go invisible).
- **Keys:** `OnKeyPressed` doesn't reliably mark the release; poll `isKeyDown` per tick.
- **UI:** don't create full-screen UI elements: they capture the mouse.
- **42.13+:** body locations are a registry (`media/registries.lua`, `ItemBodyLocation.register`) and script identifiers are
  namespaced (`base:clothing`). Clothing XML needs the full model path and `textureChoices`; an item missing from
  `fileGuidTable.xml` is invisible.
- **Items in 42.21:** `InventoryItemFactory` doesn't exist in Lua (use `ItemContainer:AddItem(String)` or `instanceItem`), and
  `sendAddItemToContainer` does nothing when a client calls it.
- **Multiplayer:** the server owns stats, the player save and item creation (see §8). Check a packet's handling type in the game
  jar before assuming a client can do something.
- **Zombies** lose ModData identity when they unload; use the persistent outfit id.
- The [PZ-Umbrella](https://github.com/PZ-Umbrella/Umbrella) type definitions are the most reliable reference for signatures.
