# Traits, settings and add-ons

[Back to contents](README.md) · [Español](../es/settings.md) · [Русский](../ru/settings.md)

## Character traits

| Trait | Points | Effect |
|---|---|---|
| You Are Special | costs 7 | +1 adaptation level and 25 % more adaptation XP. |
| Backstreet Installer | costs 10 | You start with a Prototype 05, an applicator harness, a homemade immunosuppressant (3 doses), two suture needles and alcohol wipes. |
| Chromed | costs 12 | You start with a lab implant **already installed** (1.1× wear, rejection 15), 24 hours of homemade immunosuppressant running, a 3-dose pack and the field guide. Cannot be combined with Backstreet Installer. |
| Ripperdoc's Apprentice | costs 7 | You know the three civilian recipes (synthetic compound, homemade immunosuppressant and herbal tincture) and start with the First Aid and Electrical books, vol. 1. +1 First Aid and +1 Electrical. |
| Edgerunner | costs 4 | With the implant on: +10 % movement and +15 % attack. Heat rises 25 % faster and cutoffs and collapses cost 50 % more rejection. |
| Ex-Corpo | costs 4 | You know the homemade Black Lace recipe and start with one. |
| Neurally Unstable | gives 4 | Neural load falls 30 % slower at rest. |
| Cyberpsycho Prone | gives 5 | Neural load rises 25 % faster. |
| Chrome Rejection | gives 6 | Rejection rises 50 % faster. |

Vanilla traits that matter: **Resilient** and **Prone to Illness** (immunodepression), **Fast Healer** and **Slow Healer** (healing under
immunodepression), **Herbalist** (the herbal tincture recipe).

## Difficulty presets

The sandbox option **Difficulty** picks a ready-made set. Anything other than *Custom* overrides the individual options.

| | Arcade | Relaxed | Normal | Realistic | Brutal |
|---|---|---|---|---|---|
| Rejection | ×0.4 | ×0.7 | ×1 | ×1.3 | ×2 |
| Heat rate | ×0.7 | ×0.85 | ×1 | ×1.1 | ×1.25 |
| Adaptation XP | ×2 | ×1.5 | ×1 | ×0.8 | ×0.6 |
| Immunosuppressant duration | ×1.5 | ×1.25 | ×1 | ×0.85 | ×0.7 |
| Immunodepression | off | Normal | Normal | Normal | Harsh |
| Overdrive death chance (cyberpsychosis) | 0 | 0.5 % | 1 % | 3 % | 8 % |
| Remission from cyberpsychosis | yes | yes | yes | yes | **no** |
| Thermal scarring | no | yes | yes | yes | yes |
| Homemade immunosuppressant known | yes | yes | no | no | no |
| Prototype 06 parts loot | ×2 | ×1.5 | ×1 | ×0.7 | ×0.4 |
| Cryogenic cases at the base | 2 | 2 | 2 | 1 | 1 |
| Mk. II buildable | yes | yes | yes | yes | no |
| All firmware known | yes | no | no | no | no |
| Guided by books | Gentle | Gentle | Normal | Harsh | Harsh |
| Cyberpsychosis symptoms | danger sense only | all but blackouts and misfire | all | all | all |

## Sandbox options

All of them are under **Sandevistan** in the sandbox settings. The ones worth knowing:

- **General:** traits in character creation, field guide on first implant, faster reloading, firmware on/off, dilation radius (8–30
  tiles, default 16), slow-motion zombie animations, faster player animations.
- **Balance:** Heat rate, rejection rate, adaptation XP, immunosuppressant duration, immunodepression (Off / Light / Normal / Harsh),
  stopgaps (pills), forcing the implant, light withdrawal,
  Overdrive chest wound and death chances, thermal scarring, remission.
- **World:** which campus has the civilian content (both, one at random, LSU or Ekron), cryogenic cases at the base (1–2), parts loot,
  chance of a second ex-subject per campus, ex-subject respawns, fast shamblers.
- **Crafting:** repairable Prototype 04, buildable Prototype 06 and Mk. II, homemade immunosuppressant known, all firmware known, guided
  by books (Off / Gentle / Normal / Harsh).
- **Cyberpsychosis:** **Intensity** (Off / Mild / Normal / Brutal) is one knob for every symptom, on top of the difficulty: Off removes
  all symptoms and hallucinations (neural load and its costs stay), Mild makes them half as frequent with no blackouts, misfires, jump
  scares or disguise, Brutal makes them 1.5× as frequent with more fake zombies and twice the jump scares. It never turns on something another option
  turned off. Each symptom can also be switched off on its own (audio hallucinations, danger sense, temporal instability, misfire,
  blackouts, fury, night terrors, overload, fake zombies, echoes, corrupted text, phantom figures), and so can hallucinations in general.
  **Disguise** has its own setting: Off, only zombies seen as people, players seen as zombies too only with PvP off (the default), or
  players seen as zombies too always.
- **Multiplayer:** *Respect the server hit-rate anti-cheat* (see below).

## Mod options

In *Options → Mods → Sandevistan* (each player sets their own):

- the activation key (default Z) and a key to show or hide the floating panel;
- panel size, and whether the panel also lists the states when moodles are on;
- screen glitches, afterimages (and rainbow afterimages), the 3D implant on your back, the installation scene;
- **Fewer flashes (photosensitivity):** nothing flickers. Screen glitches have no strips and come at most once per second,
  hallucinations fade out instead of flashing, danger marks do not blink. The symptoms still happen;
- lower zombie voices during dilation;
- cyberpsychosis neural monitor warnings and danger markers;
- the debug menu (for testing), the full debug menu (adds the internal tests) and a detailed console log (for bug reports).

## Multiplayer

- The server keeps the state. Other players see your implant, your afterimages and your back glowing.
- Players inside your bubble are slowed too. Admins never are.
- You can operate on (install, explant, calibrate) a player standing next to you. They get a prompt and must accept.
- **Hit-rate anti-cheat:** by default, servers kick players who hit more than 3 zombies in 1.2 seconds. With *Respect the server hit-rate
  anti-cheat* on (the default), Sandevistan attacks drop to normal speed just before that limit, so no server change is needed. If the
  server sets `AntiCheatHit` to 3 (log only) or 4 (off), you can turn the option off to get full speed.

## Add-ons and compatibility

![With the Afterimages with real pose add-on and Viewpoint, the afterimages are drawn in the 3D camera.](../../img/viewpoint-3d.jpg)
*With the Afterimages with real pose add-on and Viewpoint, the afterimages are drawn in the 3D camera.*

| Mod | What it adds |
|---|---|
| **Moodle Framework** | The mod's moodles. Recommended. |
| **Sandevistan - Slow sound and frozen rain (optional)** | Slowed zombies sound slower and deeper, rain and wind slow down, and rain and snow freeze in the air. During cyberpsychosis episodes, nearby sounds go slightly out of tune. Needs **ZombieBuddy**, which asks you to approve its jar the first time. |
| **Sandevistan - Cyberpsychosis hallucinations (optional)** | The Java side of cyberpsychosis: fake zombies only you see, your double, the disguise, figures at the edge of your view, corrupted text, glitching vanilla moodles, camera shake and the screen effects of the episodes. Needs **ZombieBuddy**. Without it, cyberpsychosis keeps its other symptoms. |
| **Beyond Ten** | Mastery levels 11–15 for military implants. |
| **Project A-Life** | NPCs dressed with the Sandevistan spine drop an implant you can extract. |
| **Sandevistan - Afterimages with real pose (optional)** | Afterimages drawn with your real pose instead of 2D silhouettes, in the isometric camera and in Viewpoint's 3D camera; with Viewpoint it also freezes the 3D rain and snow. Needs **ZombieBuddy**. |
| **Viewpoint** | The 2D afterimages and marks hide themselves in its 3D view. |

## Reporting a problem

Send `console.txt` (in your `Zomboid` folder) and describe what you were doing. In multiplayer, also attach the report from
*Debug → Tests and reports → Quick REPORT* (`Zomboid/Lua/Sandevistan_report.txt`). The debug menu has to be enabled in the mod options.
