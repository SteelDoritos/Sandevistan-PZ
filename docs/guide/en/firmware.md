# Firmware

[Back to contents](README.md) · [Español](../es/firmware.md) · [Русский](../ru/firmware.md)

Firmware chips change how the implant behaves. The implant has **two slots**:

- **System:** how it handles Heat, cooling, neural load and rejection.
- **Skill:** what it lets you do.

An empty slot means the normal behavior. Firmware is optional, and a sandbox option can turn it off.

## Installing and removing chips

- **Install:** right-click the chip in your inventory (about 10 seconds, with the implant **off**). No surgery or computer needed.
- Each change adds **3 rejection** and leaves the implant **recalibrating** for one game hour (Heat rises 10 % faster). You can't
  change chips at rejection 75 or more.
- **See or remove** installed chips: right-click the floor → *Firmware*. If the implant is removed by surgery, its chips come back to
  your inventory.

## The programs

You learn programs by raising your adaptation: each one "occurs to you" at a certain level. The Implant tab shows how many you know
and when the next one comes. The sandbox option *Know every firmware program from the start* skips this.

| Program | Slot | Learned at | What it does | The cost |
|---|---|---|---|---|
| **Hammer** | Skill | level 3 | For heavy weapons: slower swings that hit much harder, more knockdown, double critical damage. | Much less stamina back per hit; the weapon wears faster. |
| **Compatibility** | System | level 4 | Rejection rises a quarter slower, cutoffs and collapses cost a quarter less rejection, passive adaptation is 1.5 times faster and immunodepression is a quarter lower. | A little more Heat. |
| **Sentinel** | System | level 4 | Heat depends on how much you move: standing still costs far less, walking is normal, running costs more. Standing still also gives half the XP of use. | Neural load and stamina don't change. |
| **Filter** | System | level 4 | Fake zombies, echoes, corrupted text, the echo of your own noises, phantom marks and figures at the edge of your view appear **four times less often**. | It leaves you **without a danger sense** (no real or phantom marks) and without the Heat sound warning. The clone and the disguise are not filtered. |
| **Apogee** | Skill | level 4 | Each kill with the implant on lowers Heat by 20 (at most 3 kills every 3 seconds) and gives more adaptation XP. | Base Heat rises a little faster: without kills you last less. |
| **Cryo Chamber** | System | level 5 | With the implant off it cools almost twice as fast. A military design. | Heat rises faster, the Heat cap drops to 80 % and the Overdrive window is shorter. |
| **Reactor** | System | level 5 | The Heat bar fills as if it went up to 150, so you stay on much longer, and momentum builds faster and fades slower. | It cools at half speed when off: a full bar takes about three times as long to recover. |
| **Overclock** | Skill | level 5 | No Overdrive, but from half the Heat cap upward your movement and attack bonuses climb and zombies slow down more, peaking at the cap. | 50 % more neural load per second and stronger symptoms. |
| **Workshop** | Skill | level 5 | The key turns on a **work mode** instead of combat dilation: zombies 25 % slower, crafting, repairing and reading 25 % faster, and very little Heat and neural load (none at stable adaptation while you keep working). | No combat bonuses, no Overdrive or fury. It suspends itself if a zombie gets close, and won't run at neural load 60+ or rejection 50+. |

Every program works on both lab and military implants.

## Writing a program

You need:

- a **blank firmware chip** (built with Electrical 4, see [Recipes](surgery-and-crafting.md#recipes), or found now and then);
- a **computer with power**, or a **Firmware Terminal** (it can't be built: it is only found in military places). The terminal uses
  one battery per program;
- for military designs (Cryo Chamber), a **Military-Grade Microchip** as well.

Right-click the computer or the terminal → write the program. It takes **60 seconds** without adaptation and down to **25** at stable
adaptation. It needs no Electrical skill, because it is code: what counts is how used to the implant you are.

## Programmed chips and decompiling

Chips that come already programmed are very rare (labs, offices, army depots and the military base). You can:

- **install** it right away; or
- **decompile** it on a computer with power or with the terminal (half the writing time). You learn the program even if your level
  is too low, and the chip is left blank so you can reuse it.

Carrying **both complete military dossiers** also teaches you **Compatibility** and **Cryo Chamber**.
