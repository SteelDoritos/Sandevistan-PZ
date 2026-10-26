# Your body

[Back to contents](README.md) · [Español](../es/your-body.md) · [Русский](../ru/your-body.md)

The implant itself never breaks from overuse. **You** do. There are four things to manage: **rejection**, **immunodepression**,
**neural load** and, if you let it go, **cyberpsychosis**.

## Rejection

Your body treats the implant as an invader. Rejection goes from 0 to 100.

**What raises it:**

- Simply having the implant: **1.4 per game hour** at adaptation level 0, falling in a straight line to **zero at stable
  adaptation** (level 5 lab, level 7 military). It rises at half speed while you sleep. Untreated at level 0, it reaches 100 in
  **three to four days** (less the less you sleep).
- Chronic neural load: +0.3 per hour while neural load is 60 or more, at any adaptation level.
- Events: a thermal cutout (+2 to 4, nothing at stable adaptation), an Overdrive collapse (+10 to 18, half at stable adaptation), a
  firmware change (+3), a reflex misfire (+3).
- Installing an implant after removing another starts you at 30.

**What lowers it:**

- Immunosuppressants (next section).
- Your own body, slowly: with the implant **off**, neural load under 60 and adaptation at least 60 % of stable, rejection falls on
  its own (up to 0.5 per hour at stable adaptation, faster asleep). Under immunosuppressant coverage it falls at the full rate.

**What it does:**

| Rejection | Effect |
|---|---|
| 35+ | Low fever (37.4 °C), rising with rejection: 37.8 at 50, 38.3 at 75, 38.8 at 90. |
| 75+ | You can't switch the implant on, and you can't fall asleep. |
| 90+ | It wakes you up and starts hurting you (about 3 health per hour). |
| 100 | **The implant is destroyed.** It burns out and stays in your spine, unusable. You need surgery (First Aid 7) to take it out before you can install another, and you keep only half your adaptation. |

Things that change the rate: the **Chrome Rejection** trait (×1.5), the **Edgerunner** trait (event costs ×1.5), the complete
**Researcher Dossier** (−15 %), the **Compatibility** firmware (−25 %) and the sandbox multiplier.

### Stopgaps: pills buy time

You can slow rejection down for a while with ordinary pills, but they never replace immunosuppressants:

| Pill | What it does | Notes |
|---|---|---|
| Painkillers | Rejection builds 15 % slower for 6 h, and the fever is a bit lower | Tolerance: each extra dose in 24 h gives half of what the previous one gave |
| Sleeping pills | Much less rejection while you sleep (×0.35) and no night terrors | You can sleep up to rejection 89; lasts 12 h |
| Beta blockers | Neural load per use ×0.9, and half the screams and night terrors | 6 h |

They only count when **you take them** (not when a recipe or a surgery uses the painkillers). The sandbox option *Stopgaps* turns the whole
thing off.

## Immunosuppressants

They keep rejection in check. Each unit holds **3 doses**. Take one from the item's right-click menu. The option tells you in
advance what will happen: rejection before and after, hours of coverage and immunodepression before and after.

| | Clinical | Homemade | Herbal tincture |
|---|---|---|---|
| Coverage | 48 h | 24 h | 8 h |
| When you take it | rejection to 0 | rejection halved | rejection −25 % |
| While it covers you | rejection doesn't rise | rejection doesn't rise | rejection rises at 25 % |
| Neural load per use | −50 % | −35 % | −15 % |
| Side effects | none | nausea, and a 10 % chance it fails (halves rejection, no coverage) | +25 herbal toxicity per dose |
| Immunodepression | +45 (floor 50) | +30 (floor 30) | +10 (floor 10) |

- Coverage from several doses adds up, to a maximum of **72 hours** ahead.
- While you are covered, neural load **falls twice as fast**.
- **Tolerance:** each extra dose within 24 hours covers 25 % fewer hours (down to a quarter).
- **Herbal toxicity** fades by 2.5 per hour. From 50 on it makes you sick.
- **Shock dosing:** stacking doses within 24 hours cuts neural load from use even more. With clinical doses: 50 %, then 65 %, 75 %
  and at most 80 %. From the second dose on, neural load also falls 1.5 times faster. The price is shorter coverage per dose, more
  immunodepression and a possible **rejection rebound** (see below).

## Immunodepression

Every dose lowers your defenses. **Immunodepression** goes from 0 to 100 and has its own moodle (a broken shield).

- Each dose raises it (table above). While you are covered it never falls below the **floor** of the dose you took.
- When coverage ends it falls on its own: **4 per hour awake, 6 asleep**. If you are sick (an infected wound, a cold or the
  sickness moodle) it falls at 60 % of that speed, never slower than 2 per hour.
- The Implant tab shows the level, its current effects and how long until it is back to 0.

**What it does** (at 100 on Normal, and proportionally less below that):

- Open wounds that aren't disinfected, cleanly bandaged or treated with antibiotics are **twice as likely to get infected**, and
  infections grow twice as fast.
- Wounds heal **1.6 times slower**.
- You catch colds twice as easily, they hit twice as hard and you recover 1.5 times slower.
- Spoiled food and corpses make you **1.5 times sicker**.

The usual care still works: disinfect, use clean bandages, take antibiotics, stay warm, sleep.

**Rejection rebound:** if a course of doses pushed immunodepression to 60 or more, then when coverage ends rejection rises **1.5
times faster for 6 hours**. Plan the end of a heavy course somewhere safe.

What changes it: **Resilient** halves the effects and makes it fall faster. **Prone to Illness** does the opposite. **Fast Healer**
and **Slow Healer** change the healing penalty. The **Compatibility** firmware cuts it by a quarter. A sandbox option sets it to
Off, Light, Normal or Harsh.

## Neural load

Neural load (0 to 100) is what the implant costs your mind.

**What raises it:** only time with the implant on (switching on costs nothing). About **6 per minute of use with a lab implant and 9
with a military one**, before reductions:

- adaptation: down to −25 % at stable adaptation;
- immunosuppressant coverage: −15 % to −50 % (up to −80 % with shock dosing);
- an Overdrive collapse: +5 to 10.

It rises faster with cyberpsychosis (×2), with the **Cyberpsycho Prone** trait (×1.25), after a remission (×1.25, for good) and with
the **Overclock** firmware.

**What lowers it:** rest. After **1 game hour** without using the implant it starts to fall, very slowly: about 0.5 per hour below
30, 0.25 per hour from 30 to 60 and 0.1 per hour above 60. It falls faster under immunosuppressant coverage (×2), with shock dosing
(×1.5) and with antidepressants (×1.5). It falls slower with the **Neurally Unstable** trait.

In practice, minutes of use cost days of rest. Use it in bursts.

**Symptoms from 60:** screen glitches, nosebleeds, hallucinations, "neural monitor" warnings on screen, Heat that rises faster and
chronic rejection. From 60, during sleep, **night terrors** can wake you up screaming. Sometimes a noise you made (a hit, a shot, a
door, your running steps) **echoes back 5–20 seconds later** from somewhere else, usually behind you; it gets more frequent with cyberpsychosis.
Only you hear it and it does not attract zombies.

## Cyberpsychosis

![Cyberpsychosis: the screen bleeds red and the implant warns that the neural link is unstable.](../../img/cyberpsychosis.jpg)
*Cyberpsychosis: the screen bleeds red and the implant warns that the neural link is unstable.*

At **neural load 80** cyberpsychosis sets in. It **does not go away when the load drops**: the only way out is remission (below).
If the load falls under 60 its symptoms quiet down, but the condition stays, and they come back when the load climbs again.

- **Temporal instability:** the dilation stutters and nearby zombies snap back to normal speed for a moment.
- **Danger sense:** faint red brackets mark nearby zombies you can't see (behind walls or corners). Some of them aren't real.
- **Audio hallucinations:** footsteps, groans, banging, glass, whispers. Only you hear them.
- **Hallucinated messages:** now and then, inside one of the texts that is being corrupted (a label, a tooltip, a chat line), a
  short coherent phrase appears and stays fixed for about two seconds ("LOOK BEHIND YOU", "IT'S NOT YOURS", "WHO'S TALKING?"), while
  the rest of that text keeps glitching around it. It is local and only you see it. It needs the corrupted text option on.
- **Psychotic pressure:** being tired, in pain or surrounded by zombies makes every hallucination come more often (up to 1.5 times).
  It never raises your neural load. The Implant tab shows it as low, medium or high and what is raising it; resting and getting away
  from the horde bring it down.
- **Humanity anchors:** sleeping in a bed, reading a book or a magazine, eating something you like and, in multiplayer, staying near
  another player for a while **lower the pressure** (not the neural load) and push the next crisis away. Each one has its own cooldown.
  High Heat also adds pressure from 70 % of the cap; after an Overdrive collapse or a total fury, for the next 24 game minutes the
  next warning is scheduled at half the usual wait.
- **Light withdrawal:** with neural load at 60 or more and **12 game hours without using the implant**, stress and unhappiness slowly
  climb and the monitor insists. It fades on its own at 48 hours (or if the load drops below 60). Using it for 10 seconds resets it;
  in Work mode it counts half. It never touches neural load.
- **Mental state:** the Implant tab gathers the stage and what it means, how close the next crisis is, the scar, the Heat vulnerable
  window, the last black box entries and the hallucinations you have already discovered (fake zombies you touched or hit, the clone,
  the disguise, the phantom marks, the figures at the edge of your view).
- **Figures at the edge** (with the hallucinations add-on): now and then a dark, see-through figure at the edge of what you see, about
  10 tiles away, standing and watching you or walking slowly. It never makes a sound or attacks. Look straight at it or walk closer and it falls apart.
- **Screaming fits** that **do** attract zombies.
- **Fury:** with the implant on you hit harder (+25 % melee damage and attack speed), you feel no panic and less pain, but your
  weapons wear out twice as fast.
- Arming the Overdrive gets harder, and an Overdrive collapse can kill you (1 %).

**At 95 and above:** the implant can **misfire**. It switches itself on for a few seconds when a zombie attacks you. You can also
get **blackouts**: tunnel vision, heartbeat and moments of darkness (you can still move). Rarely, with the hallucinations add-on, you
get a **disguise** for 20–40 seconds: zombies in sight look like people (they are still zombies and **really bite**), or in
multiplayer other players look like zombies. Now and then the disguised one flickers back to what it really is.

**The disguised one acts like a zombie** (multiplayer, with the hallucinations add-on). While the disguise lasts:

- If they are standing still and you come closer, they **turn slowly toward you** from about 5 tiles away; within 2.5 tiles they
  **raise their arms** and groan louder. Only you hear it.
- If they walk, they stop watching you and walk like themselves again.
- The first time they raise their arms on each approach there is a 35 % chance the disguise **breaks free**: the figure lunges at
  you like a fake zombie. When it touches you or you hit it, it falls apart and your friend appears where they really are.
- **They don't notice any of it**: they don't see the disguise, don't hear the groans and don't know when it breaks free.
- With PvP on (the *players seen as zombies too always* setting) it still turns, raises its arms and groans, but never breaks free.

All of this is **local**: the hallucinations, the fake zombies, the double and their sounds are seen, heard and sent only to you, also
in multiplayer. The real sounds of the implant and the doses are still heard by those nearby.

**Crises:** now and then a crisis announces itself 20–40 seconds ahead: growing tinnitus, tunnel vision, glitching text and the monitor
naming what is coming, **paranoia** (many more fake threats for about a minute) or **dissociation** (time stutters, the screen and text
glitch). With the hallucinations add-on and the isometric camera, during the episode the world loses its color, wobbles and doubles,
and with the slow sound add-on nearby sounds go slightly out of tune. Blackouts, fury, overload and jump scares shake the camera. Take an **antidepressant** or **sit down (or sleep) with no zombies within 10 tiles for 8 seconds** to stop it. Once the episode
starts it runs its course, but it does no harm by itself.

**Neural cascade:** from neural load 97 with the implant on, the monitor warns of a neural cascade for 20–30 seconds. **Switch the
implant off** in that time and you avoid the overload (the load stays at 99). If you don't, the overload comes.

**Neural overload (100):** the implant shuts down and you are knocked out for 8–15 seconds, with a nosebleed, pain and a scream
that draws zombies. Afterwards the load drops to 85. With cyberpsychosis and a working implant there is a 30 % chance of a **total
fury** instead: 15 seconds with the implant locked on and even stronger attacks, then a crash (no stamina, a short knockout, Heat
at the cap, and a thermal scar of 15).

**Hallucinated awakening:** when you come back from an overload (or the short knockout at the end of total fury), if cyberpsychosis is
still active you get **60 to 90 seconds of a paranoia peak**: your double standing beside you, one or two fake zombies, nearby zombies
seen as people and much more broken text. You don't know what is real just when you are at your weakest.

**Neural scar:** every overload leaves **2 scar points** (up to 10). Each point lowers **all** neural thresholds by 1: the stages, the
start of cyberpsychosis and the hallucination one. At 10 points stage 1 can start at 50, cyberpsychosis at 70 and stage 3 at 85. The
cascade (97) and the 100 cap do not change. It recovers **1 point per game day with the implant off**.

**Black box:** the Implant tab shows the **last incident** (how long ago and what it was: overload, fury, avoided cascade, cut warning,
episode, blackout or night terror) and **how many there were in 24 hours**.

### Remission

Remove the implant and live **5 in-game days without any implant**. The first 2 days are withdrawal: stress and fatigue slowly climb
(antidepressants halve it). After that, cyberpsychosis ends and your neural load is at most 50. It leaves a scar: from then on any
implant adds neural load 25 % faster. On the Brutal preset there is no remission.

When remission completes, the monitor says **HUMANITY RESTORED** and the clone appears far away, waves and fades slowly, without a
glitch. If you use an implant again and relapse, it comes back at stage 3.

## Antidepressants

Vanilla antidepressants help (right-click → *Take antidepressant*, or take them the normal way). Each dose lasts 12 hours (stacking
up to 48). While it lasts, neural load falls 1.5 times faster, symptoms come half as often (hallucinations, glitches, screams,
spontaneous nosebleeds) and an overload knockout is shorter. They **don't cure** cyberpsychosis.

## Black Lace (Kerenzikov)

A combat drug, separate from the implant. Each unit has 3 doses.

| | Autoinjector (military) | Homemade |
|---|---|---|
| Duration | 5 minutes | 2.5 minutes |
| Afterwards | nothing | comedown: fatigue jumps to 65 % and stamina drops to 30 % |

Durations are in real time and don't run while the game is paused.

**While it lasts:** no pain, no panic or stress, no sleepiness (it comes back afterwards), actions cost half the stamina, a stamina
boost on injection plus regeneration every minute, +20 % attack speed, and a 25 % chance that a zombie lunging at you from close
range stumbles back before it grabs you.

**With the Sandevistan:** Heat rises 20 % slower. The implant's own bonuses replace the drug's while it is on. Don't collapse an
Overdrive under Black Lace: it knocks you out, adds 1.5 times the neural load and damages your heart.

**Tolerance:** each extra dose within 24 hours lasts 25 % less (down to half).

**How to take it:** from the inventory menu, or **attach it to your belt** and press its hotbar key. You can inject while walking.
Running cancels it.
