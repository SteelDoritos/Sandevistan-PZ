# Changelog

The full player-facing notes of each update. Download the mod from the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3816048725).

## 0.8 (build 201)

The biggest update since the mod went public: the whole cyberpsychosis line with a new optional add-on, stamina debt, books as
guides, a surgery and balance pass and many fixes.

**Important:** all three Java add-ons changed. Restart the game and approve them in ZombieBuddy when it asks, at startup.
If you only used "Slow sound and frozen rain", fake zombies, the double and corrupted text now need the new
"Cyberpsychosis hallucinations" add-on enabled too.

### New optional add-on: Sandevistan - Cyberpsychosis hallucinations
- The Java side of cyberpsychosis, separate from Slow sound and frozen rain (both need ZombieBuddy).
- Fake zombies only you can see: they come from behind, sound like zombies and fall apart when they touch you or you hit them.
  The Sandevistan doesn't slow them down. Sometimes it's a silent runner that screams when it gets close.
- Your double: at stage 3 a copy of you shows up behind you. It stares, waves, or copies your steps one second late.
  Look at it or get close and it falls apart.
- The disguise: for 20 to 40 seconds, zombies in sight look like wounded people (they still really bite), or in multiplayer other
  players look like whole zombies that turn toward you, groan and sometimes lunge at you. They don't see or hear any of it.
- Figures at the edge of your view: dark, see-through silhouettes. Look at them or get close and they fall apart. They never attack.
- Corrupted text, and moodles that glitch and tear (vanilla and Moodle Framework).
- Camera shake and screen effects for blackouts, episodes and overload, also in Viewpoint's 3D camera. A "fewer flashes" mod
  option turns all the flicker off.

### Cyberpsychosis
- Intensity is one sandbox knob (Off / Mild / Normal / Brutal), and each symptom can be turned off on its own.
- Psychotic pressure: being tired, in pain, surrounded by zombies or hot makes hallucinations come more often, up to 1.5 times.
- Crises announce themselves 20 to 40 seconds ahead, then hit as paranoia or dissociation. An antidepressant, or sitting or sleeping
  with no zombies within 10 tiles for 8 seconds, contains them. Right after an Overdrive collapse or a fury, the next one comes sooner.
- Neural cascade from neural load 97: switch off in time and you avoid the overload.
- Black box in the Implant tab, hallucinated awakening after an overload, and a neural scar that lowers every threshold by 2 points
  per overload (1 recovers per day with the implant off).
- Humanity anchors (a bed, reading, a good meal, company) lower the pressure. Light withdrawal after 12 hours at neural load 60+
  without using the implant.
- Echoes: real zombies leave a red and cyan double-vision trail, and your own noises (a hit, a shot, a door, a run) repeat 5 to 20
  seconds later from somewhere else. They don't attract zombies.
- Real glitch sounds for time stutters, hallucinations falling apart and implant failures.
- Hallucinated messages: now and then, inside a text that is already glitching (a label, a tooltip, a chat line), a short
  coherent phrase stays fixed for about two seconds ("LOOK BEHIND YOU", "IT'S NOT YOURS", "WHO'S TALKING?"). Sandbox option.
- The Filter firmware chip cuts fake zombies, echoes, corrupted text and phantom marks to a quarter, at the cost of your danger
  sense and the Heat sound warning.
- Completing remission now has its ending: the monitor reads HUMANITY RESTORED and the double says goodbye far away.

### Implant and body
- Stamina debt: while the implant is on your endurance doesn't drop; it's charged when you switch it off. Go past the limit and the
  implant cuts out. New "Borrowed breath" moodle and sandbox option.
- Ambient cooling: cold, wet clothes and wind cool the implant faster. Bonus only, it never punishes you. Using the implant dries you.
- Force the implant: hold the key with it off to skip the air or heat safety and go straight into Overdrive. It always ends in a
  collapse, and you pay for it.
- Disconnect the implant from its menu: it stays inert until you reconnect. Neural load drops and remission advances at half
  speed, and reconnecting costs neural load, stress and a wait. Remission is now counted in accumulated hours.
- Stopgaps with vanilla pills: painkillers, sleeping pills and beta blockers soften rejection, night terrors and neural load.

### Surgery and balance
- Explanting no longer needs a suture needle: the incision stays open, so bandage it.
- Wherever a suture needle is needed, a sewing needle and 3 uses of thread also work, like vanilla stitching. The suture needle is
  used first if you have one; the sewing needle is not used up.
- The military implant reaches stable adaptation at level 7 (was 8). Your adaptation carries over, so coming from a lab implant
  you start the military one at level 5.
- Assembling the Mk. II: 55 / 75 / 90 % at First Aid 6 / 8 / 10 (was 40 / 60 / 80).
- Hallucinations are less dense, especially at stage 2; the paranoia bursts still stand out.
- Default key is Z (V is the vanilla radial menu). Neural load decays a little every 10 minutes instead of once per hour.

### Books, loot and world
- Books as guides: without the skill level you can still install, explant, calibrate, repair, study and craft, if you carry the
  vanilla books for the levels you're missing. It takes longer and can fail; at the required level there is no penalty. Explanting
  with the books never drops below 45 % success.
- The crafting panel says which skill the books cover, how many levels you're missing, the extra time and the real fail chance,
  or which books you still need. With the level, it says which skill the recipe asks for.
- To operate on yourself without the harness, standing in front of a mirror in the world is enough.
- Guide books now show up in labs, schools, clinics and offices, and in the campus labs.
- Three annotated maps mark the campuses and the base. Rare wandering ex-subjects carry an implant far from the campuses.
- The synthesis notebook is more common.

### Traits
- New: Chromed (12 points) starts you with a lab implant already installed.
- Ripperdoc's Apprentice (7 points) knows all three civilian recipes and starts with the First Aid and Electrical books, volume 1.
- Backstreet Installer (10 points) brings two suture needles and alcohol wipes, so you can operate on yourself twice.
- Softer negative traits: Chrome Rejection ×1.5 (was ×2), Cyberpsycho Prone ×1.25 (was ×1.5), Neurally Unstable gives 4 points.

### Multiplayer and fixes
- Fixed a kick on dedicated servers ("malformed packet or suspicious activity") when installing a Prototype 05. Update both the
  server and the clients to the same version.
- The 3D implant spine is created by the server: others see it, it no longer duplicates and it survives reconnecting.
- Surgery, kits, firmware chips and antidepressants save the character state immediately, so a disconnect doesn't lose them.
- The sounds of your cyberpsychosis are heard only by you. Real implant and dose sounds are still heard nearby.
- Fixed the mod's traits and starting kit in hosted games, the A-Life corpse spine, and admin-spawned spines deleting themselves.
- Slow sound and frozen rain: rain splashes and puddle ripples now slow down and freeze too.
- The double, fake zombies, figures and the disguise also work in Viewpoint's 3D camera.
- Crafting panel with books: assembling the Prototype 06 or the Mk. II showed the wrong fail chance, and "Time Required" overlapped
  "Quantity".
- Cyberpsychosis costs less performance while the implant is off.
- The console only shows warnings and errors; the detailed log and the internal debug tests are mod options.

Approve the Java add-ons right when the game starts: approving them after loading a game with Viewpoint closes the game.
