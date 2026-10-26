# Surgery and crafting

[Back to contents](README.md) · [Español](../es/surgery-and-crafting.md)

Everything here is done from right-click menus or from the **Sandevistan** tab of the crafting menu. Options you can't use yet
appear greyed out, and their tooltip lists what is missing.

## Without the skill level: the books

Every First Aid, Electrical, Metal Welding and Tailoring requirement in this page can be covered with the **vanilla skill books** of
that skill in your inventory. With the books the option is available again, but it takes longer and it can go wrong: you need the book
of **every level you are missing** (the volume N teaches levels 2N−1 and 2N), and the penalty is smaller the closer you are to the
level.

| Skill required | You have | Books you need |
|---|---|---|
| First Aid 4 | FA 0 | First Aid vol. 1 and 2 |
| First Aid 4 | FA 2 | First Aid vol. 2 |
| First Aid 4 | FA 3 | First Aid vol. 2 |
| Electrical 5 | Elec 0 | Electrical vol. 1, 2 and 3 |

- **With the required level there is no penalty at all.**
- The books have to be **in your inventory** (backpacks count; a container next to you does not).
- Below the level, surgeries (install, explant), repairing the Prototype 04 and assembling the Prototype 06 or the Mk. II use a
  **lower success chance**: 8 points less per missing level on Normal, never below 25 % (45 % for explanting). Surgeries also leave
  the **mild deep wound** even when they work. Calibrating and studying a design add a **chance to fail** instead (you lose the
  material and nothing changes). Crafting a part or a chip with the books can also go wrong: the item is lost and you get back part
  of the material.
- The option's tooltip and the crafting panel say which skill the books are covering, how many levels you are missing, how much
  longer it takes and the chance it goes wrong. With the level, the crafting panel just says which skill the recipe asks for.
- The **sandbox option *Guided by books*** (Off / Gentle / Normal / Harsh) sets how harsh the penalty is; the difficulty preset picks
  it for you. It is never off in the presets: it is the way to play alone.
- The books are normal items: you can find them, buy them or take them from a library, and they still teach their levels when read.

## Installing an implant

Right-click the implant in your inventory. You can install it on yourself or on another player standing next to you, who has to
accept. In every case you need a **suture needle** (or, as when stitching a wound, a **sewing needle and thread** for 3 stitches) and
**disinfectant** (or alcohol wipes).

| Method | Who | Also needs | Minimum First Aid | Success chance |
|---|---|---|---|---|
| Guided (harness) | yourself | applicator harness | 4 | 75 % (95 % from FA 6) |
| Blind (mirror) | yourself | mirror (item or standing in front of one), scalpel, painkillers | 7 | 65 % |
| Assisted with harness | another player | applicator harness | 2 | 80 % (95 % from FA 4) |
| Assisted without harness | another player | scalpel | 4 | 70 % (90 % from FA 6) |

- The **Surgical Applicator Harness** comes with the military implants (inside the cryogenic case) and with the Backstreet Installer
  trait. Without a harness you have to go blind, and blind means **a mirror**: the item in your inventory, or a mirror in the world
  right next to you (the same thing the game checks to put on makeup).
- **A failed surgery never loses the implant.** It just comes out a little more worn (+0.1×) and you can try again.
- After surgery you feel pain. **Take an immunosuppressant right away:** the warning before the operation reminds you.
- **Student Lab Binder:** if the surgeon carries the complete binder (5/5), any method works on a **lab** implant from First Aid 1.
  The chance is lower below the usual minimum (for example 35 % for a blind surgery at FA 1), and a successful operation still
  leaves a mild deep wound in your back that you have to stitch and bandage.
- The first time someone receives an implant, they also get the **field guide**.

## Removing an implant (explant)

Right-click the floor near you: *Explant* yourself or a player next to you. You need a **scalpel and disinfectant**, plus a
**mirror** if you do it on yourself. No suture needle: the incision is left open, so bandage it afterwards.

- First Aid **6** (70 %, 90 % from FA 8). A destroyed implant needs First Aid **7**.
- With the First Aid books below that level the chance drops, but never below **45 %**, even at First Aid 0.
- It always causes heavy bleeding and pain, whether it works or not. If it fails, the implant stays in place.
- The removed implant comes out +0.2× more worn.
- You keep **all** your adaptation for the next implant (half if the old one was destroyed). The next one starts at 30 rejection.
- Reasons to explant: swapping lab for military, removing a destroyed implant, or starting the 5 days of
  [remission](your-body.md#remission).

## Extracting an implant from a body

Some zombies carry an implant (an **ex-subject**: you can see the glowing implant on their back). So does the body of any player
who died with one. Right-click the body:

- **With a scalpel:** a clean extraction. Wear depends only on your First Aid: 1.6× at FA 0, falling to **1.0× (perfect) at FA 4**.
- **With any sharp knife** (kitchen knife, hunting knife, scissors, machete...): a rough extraction. It adds 0.2× more wear, takes
  twice as long and has a 50 % chance to cut your hand.
- An extraction never makes the implant better than it was.
- If an ex-subject's body disappears before you get to it, its implant is left on the ground, worn 1.5×.
- With **Project A-Life**, NPCs dressed with the Sandevistan spine also drop an implant (military 1.0×, lab 1.15×).

## Calibration

Calibration brings a worn implant back to 1.0×. Right-click the loose implant, or the floor to calibrate an installed one (yours or a
nearby player's).

- First Aid **4**, Electrical **3**, a screwdriver.
- **Electronics scrap:** 1 for every 0.1× of wear removed (at least 1).

## Repairing a Prototype 04

Prototype 04 is a defective lab implant. Right-click it → *Repair Prototype 04*.

- Electrical **5**, First Aid **4**, a screwdriver, 2 electronics scrap, a **Neural Interface Board**, a **Power Cell** and a **Synthetic
  Compound Sample**.
- Chance by Electrical: 60 % at 5, 85 % at 7.
- It comes out at 1.2× and can never be calibrated below that.
- If it fails you lose the compound and the scrap, and the parts come back more worn. The implant is never lost.

## Recipes

All recipes show up in the **Sandevistan** tab of the crafting menu once you know them.

| Recipe | Ingredients | How you learn it |
|---|---|---|
| Synthetic Compound | mortar and pestle, 3 painkillers, a cold pack or baking soda, 0.1 L of rubbing alcohol, vodka or whiskey | Lab Notebook (Synthesis), or the Ripperdoc's Apprentice trait |
| Homemade Immunosuppressant (3 doses) | mortar and pestle, 2 painkillers, 1 synthetic compound, 0.1 L of alcohol | Lab Notebook (Synthesis), the Ripperdoc's Apprentice trait, or a sandbox option |
| Herbal Immunosuppressant Tincture | mortar and pestle, 2 wild garlic, 2 black sage or comfrey, 0.1 L of water or alcohol | Lab Notebook (Synthesis), the Ripperdoc's Apprentice trait, Foraging 3 or the Herbalist trait |
| Homemade Black Lace (3 doses) | 1 painkiller, 1 caffeine pill, 0.1 L of alcohol | Black Lace Formulation Report, or the Ex-Corpo trait |
| Blank firmware chip | screwdriver, 3 electronics scrap, 1 wire; **Electrical 4** | known by anyone who has (or had) an implant |

To learn from a notebook or report, **read** it (like any skill book).

## Building your own implant

### Prototype 06 (lab replica)

**1. Learn the design.** Right-click a loose lab implant (Prototype 05 or 04) → *Study*. You need **Electrical 4**, a screwdriver and
the **complete Student Lab Binder** (5/5) in your inventory. Studying a working implant wears it +0.1×. You learn the five parts, the
assembly and the blueprints.

**2. Build the five parts.** Each one needs a single skill, so on a server each player can specialize and trade parts.

| Part | Skill | Ingredients (plus a screwdriver) |
|---|---|---|
| Neural Interface Board | Electrical 5 | 4 electronics scrap, 2 wire |
| Thermal Regulator | Metalworking 4 | 2 small sheet metal or scrap metal, 1 wire, 2 electronics scrap |
| Power Cell | Electrical 3 | 1 battery, 1 wire, 2 electronics scrap |
| Implant Chassis | none | 6 screws, 4 small sheet metal or scrap metal |
| Neural Link Harness | Tailoring 3 | sewing needle, thread or twine, 2 leather strips, 2 wire |

**Part quality** depends on the crafter's skill level: from 1.5× at level 0 down to 1.0× at level 10. Metalworking counts as 2
levels higher. The chassis is always 1.0×. Parts you find in the world are 1.3×. The finished implant gets the **average** of its
parts, graded Fine (up to 1.05×), Good (1.2×), Standard (1.35×) or Crude.

**3. Assemble.** *Build Sandevistan Prototype 06*: the five parts, 2 electronics scrap, 1 synthetic compound and a screwdriver.
**First Aid 4**: 50 % (75 % at FA 6, 90 % at FA 8), +10 % with the complete Student Lab Binder. If it fails you lose the scrap and
the compound, and the parts come back a little more worn. You can try again.

### Mk. II (military replica)

**1. Learn the design.** Right-click a **working military implant** → *Study the military design*. You need **Electrical 6**, a
screwdriver and **both military dossiers complete** in your inventory: the Researcher Dossier (12/12) and the Depot Guard Dossier
(3/3). The dossiers are not used up.

**2. Build the parts.**

| Part | Skill | Ingredients (plus a screwdriver) |
|---|---|---|
| Military-Grade Microchip | Electrical 7 | 12 electronics scrap, 3 wire (or find one: they are very rare) |
| Military Neural Lattice | Electrical 7 | 6 electronics scrap, 2 wire, 1 military microchip |
| Cryogenic Regulator | Metalworking 5 | 2 sheet metal or scrap metal, 1 wire, 2 electronics scrap, 3 cold packs |
| High-Density Power Cell | Electrical 6 | 2 batteries, 2 wire, 2 electronics scrap |
| Reinforced Military Chassis | none | 8 screws, 5 small sheet metal or aluminum scrap |
| Shielded Neural Harness | Tailoring 5 | sewing needle, heavy thread or twine, 3 leather strips, 3 wire, 2 electronics scrap |

**3. Assemble.** *Build Sandevistan Mk. II*: the five parts, 2 electronics scrap, a screwdriver and a stabilizer: a **Black Lace
Autoinjector** or a **full** homemade Black Lace. **First Aid 6**: 55 % (75 % at FA 8, 90 % at FA 10).

### Blueprints

Once you know a design you can write it down to teach it to someone else: *Write Prototype 06 blueprints* (a pen or pencil and 3
sheets of paper) or *Write military replica blueprints* (5 sheets). Whoever **reads** the blueprints learns the design, without
needing the dossiers or an implant to study.

### Nameplate

Implants you build (P06 and Mk. II) carry a nameplate. With the implant in your inventory (not installed), right-click → *Name the
plate* and type up to 16 characters (you need a pen). The name follows the implant through surgery and shows on the HUD panel.
