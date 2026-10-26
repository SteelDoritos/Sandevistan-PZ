-- Sandevistan / Config
-- Fuente única de números. Refleja 01-descripcion.md. Nada del mod usa números mágicos.
-- Los valores marcados "SV" se sobreescriben con SandboxVars.Sandevistan en applySandbox().

SandevistanConfig = {
  Version = "0.8",                                  -- 0.8: fin de la cola del plan 31 (24/10/2026); 0.7: version publica (antes 0.1.30, entregas 1 a 111). Hoja de ruta en README.md
  Build = "0.8 (201)",                               -- entrega dentro de la versión (para saber qué copia del mod está cargada)
  Debug = false,                                    -- se activa con isDebugEnabled() o la opción de mod

  UseSpatialSlowInSP = true,                        -- SV. v0.1: B por defecto (A es experimental)
  SlowMethod = "damping",                           -- validado por autotest (speedMod no tiene efecto en B42)
  DampingGain = 1.33,                               -- calibración: media medida x0.40 con 1.67 y x0.18 con 1.0; objetivo x0.30
  PlayerBoostMethod = "nudge",                      -- "nudge" (validado x1.25) | "none". moveSpeed no tiene efecto en B42

  Variants = {
    lab = { baseHeat = 16, heatReductionPerLevel = 0.075, baseCool = 3,
            coolBonusPerLevel = 0.13, maxLevel = 5, stableLevel = 5,
            neuralLoadMultiplier = 0.7, maxDilationTier = 2, overdriveMax = 4, color = { 0.2, 0.9, 1.0 } },
    military = { baseHeat = 12, heatReductionPerLevel = 0.054, baseCool = 3,
                 coolBonusPerLevel = 0.17, maxLevel = 10, stableLevel = 7,     -- (194) antes 8: quien viene del lab entra en el 5
                 neuralLoadMultiplier = 1.0, maxDilationTier = 4, overdriveMax = 7, color = { 1.0, 0.7, 0.15 },
                 mastery = true },                -- (123) niveles 11-15 con Beyond Ten (CFG.Mastery); el tramo IV solo se alcanza con la maestria
  },

  DilationTiers = {
    { minLevel = 0, world = 0.30, comp = 3.33, zombieSpeed = 0.30, playerBoost = 0.25, attackBoost = 0.50 },
    { minLevel = 5, world = 0.25, comp = 4.00, zombieSpeed = 0.25, playerBoost = 0.35, attackBoost = 0.75 },
    { minLevel = 8, world = 0.20, comp = 5.00, zombieSpeed = 0.20, playerBoost = 0.40, attackBoost = 1.00 },
    { minLevel = 15, world = 0.18, comp = 5.56, zombieSpeed = 0.18, playerBoost = 0.45, attackBoost = 1.10 },   -- (123) tramo IV: maestria 15 (S.dilationTier suma la maestria al nivel)
  },
  -- (123) MAESTRIA: con el mod Beyond Ten (skills hasta el nivel 15) la adaptacion del implante militar sigue del 10 al 15. Sin Beyond Ten no existe.
  -- S.level sigue con techo 10 y nada de lo que da el nivel 10 cambia; cada nivel de maestria (S.mastery, 0..5) suma encima, sobre el valor del nivel 10:
  --   Heat generado -HeatPerRank, enfriamiento +CoolPerRank, ventana de Overdrive +WindowPerRank s, estamina -StaminaPerRank,
  --   carga neuronal por uso -NeuralUsePerRank (ademas del UseAdaptReduction), tropiezo/arrastre/KO tras el colapso -RecoveryPerRank (ademas del 50 %).
  -- Hitos: estelas x(AdaptMaxMultiplier + AfterimageExtra) desde AfterimageRank; tramo IV (DilationTiers[4]) en la 15.
  -- Table = XP de cada nivel 11..15: la formula de Beyond Ten (xp10 + (xp10 - xp9) por nivel), asi su barra y la del mod avanzan parejo.
  Mastery = {
    Table = { 15000, 18000, 21000, 24000, 27000 },
    HeatPerRank = 0.04, CoolPerRank = 0.04, WindowPerRank = 0.3, StaminaPerRank = 0.05,
    NeuralUsePerRank = 0.03, RecoveryPerRank = 0.04,
    AfterimageRank = 3, AfterimageExtra = 1,
  },
  SpatialSlow = { Radius = 16 },                    -- SV: SlowRadius (v0.1.30: 12 -> 16, la transición queda cerca del borde de la pantalla)
  -- v0.1.30 (62): nivel de detalle de la dilatación (Slowdown.tickLOD). Lo que más cuesta del mod son las lecturas/escrituras por zombi y por tick.
  --   Enabled     false = como antes de la (62): se mide y se amortigua a cada zombi en cada tick (sirve de linea base en la prueba de rendimiento).
  --   SelectMs    cada cuanto se vuelve a elegir quien esta dentro del radio (un solo recorrido de la lista de zombis, antes eran dos).
  --   NearTiles   los que estan a esta distancia o menos de una fuente se amortiguan en todos los ticks.
  --   FarMs       los de mas lejos, cada tanto (0 = todos los ticks). El desplazamiento se acumula entre pasadas, asi que la velocidad media no cambia;
  --               solo cambia que la imagen avanza a tirones mas largos. (63): 40 ms. La prueba progresiva (Debug, Sandevistan_lod.txt) dio Si hasta 90 ms
  --               y No desde 130; el costo de Slowdown.tick ya no baja de 40 ms en adelante (0.74 -> 0.27 ms con el camino nuevo y 0.14 con 40 ms).
  --   FarMaxJump  guarda de velocidad (0 = sin guarda): el tiron que se ve al reacomodar a un lejano es ~ (1 - factor) * velocidad del motor * FarMs; si pasaria
  --               de este valor (casillas; 0.015 ~ 1 px a zoom 1, la prueba dio Si con ~0.023) el zombi se trata como cercano. Protege a los corredores, que
  --               la prueba no cubrio (sus zombis iban a ~0.4 casillas/s).
  SlowLOD = { Enabled = true, SelectMs = 150, NearTiles = 8, FarMs = 40, FarMaxJump = 0.015 },
  -- v0.1.30 (64): salida gradual. Al apagar el implante, los zombis a Tiles casillas o menos del jugador no vuelven de golpe a su velocidad: el amortiguado se
  -- relaja de su factor a 1 en Ms milisegundos (la animacion lenta se suelta a la mitad). La activacion sigue siendo instantanea. No aplica al glitch ni al speedMod.
  SlowRelease = { Enabled = true, Ms = 500, Tiles = 6 },
  -- Giro en cámara lenta: el motor gira al zombi (cuerpo y torso hacia el objetivo) a turnDelta por frame, aparte de la animación y del amortiguado de
  -- posición, así que un zombi frenado igual te seguía con la mirada. Slowdown baja su turnDelta (IsoZombie:setTurnDelta) a orig * factor * Gain
  -- (con piso Min) y lo restaura al soltarlo. El motor lo reescribe al recalcular el andar del zombi: se vuelve a aplicar en cada refresco.
  -- Gain 0,5: el giro de PZ ya es rapido de por si; con 1,0 (mismo factor que el tramo) en el juego todavia se sentia que te seguian. Probado en juego.
  SlowTurning = { Enabled = true, Gain = 0.5, Min = 0.05 },
  -- Tiempo en el piso: el contador con el que un zombi derribado se levanta (reanimateTimer) baja a la velocidad del tramo (zombieSpeed), no a la normal.
  -- Las animaciones de caer, quedar en el piso y levantarse van en camara lenta por los nodos de SlowAnimations (gen_slow_animsets.py).
  SlowGround = { Enabled = true },
  -- v0.1.30: animación de los zombis en cámara lenta. media/AnimSets/zombie/*/Sandevistan_*.xml son copias de los nodos vanilla con una
  -- condición más (variable SandevistanSlow = true) y la velocidad x0.30 (tools/gen_slow_animsets.py; para otro factor, regenerar).
  -- Slowdown pone la variable en los zombis que frena y la quita al soltarlos. SV: SlowZombieAnimations.
  -- HoldStates: estados con animacion de una sola pasada; si el zombi esta en uno, la variable no cambia hasta que termine (si no, la animacion
  -- arranca de cero en el otro nodo). HoldMaxSeconds: tope por si el estado no termina. Con tramo 0,2 un ataque lento dura ~3 s.
  -- (134) La caida, la reaccion al golpe y la muerte tambien van lentas. Un zombi que muere frenado conserva la variable hasta que la caida termina
  -- (pasa a cadaver); DyingMaxSeconds es el tope por si el motor no lo saca del mundo.
  SlowAnimations = { Enabled = true, Variable = "SandevistanSlow", Factor = 0.30,
    HoldStates = { "AttackState", "AttackNetworkState", "StaggerBackState", "ZombieTurnAlerted", "ZombieFaceTargetState",
                   "ZombieGetUpState", "ZombieGetUpFromCrawlState", "ZombieGetDownState",
                   "ZombieHitReactionState", "ZombieFallDownState", "ZombieFallingState" }, HoldMaxSeconds = 8, DyingMaxSeconds = 12 },
  -- 0.7 (126): voces de los zombis mas bajas durante la dilatacion (client/SlowAudio.lua). Las voces son eventos de FMOD: no se les puede bajar el tono ni
  -- tocarlas de a una desde Lua (el handle no es legible), pero GameSound:setUserVolume las baja en vivo, a todas las de ese nombre (sonda de audio, probado
  -- en el juego). Volume = volumen con la dilatacion plena; FullAt = factor de zombis desde el que se aplica entero (tramo I = 0,30): con menos dilatacion
  -- (Taller, x0,75) se baja en proporcion. FadeInMs/FadeOutMs: rampas al encender y al apagar. Opcion de mod (cliente) "slowZombieVoices".
  SlowAudio = { Enabled = true, Volume = 0.25, FullAt = 0.30, FadeInMs = 250, FadeOutMs = 600, VoiceTag = "Voice", Category = "Zombie" },
  -- (134) Para los mods opcionales con Java (ZombieBuddy). SandevistanFX: el tono de los sonidos de cada zombi frenado baja a Min + (1 - Min) x su factor de
  -- velocidad (FMOD, por zombi: con el factor 0,30 del tramo I queda en 0,72) y la lluvia y la nieve isometricas caen a Precip.Factor de su velocidad.
  -- SandevistanViewpoint: la misma lluvia congelada en la camara 3D, con las gotas Precip.Streak veces mas cortas. RampMs = cuanto tarda en frenar y en volver.
  -- (134b) Pitch.Volume: con el tono bajado, las voces bajan solo a este volumen (no a SlowAudio.Volume). Ambience: el ambiente del mundo (evento
  -- World/Ambiance de FMOD: la lluvia, el viento, los grillos; el juego los mezcla en un solo evento) baja a este tono con la dilatacion.
  -- (134c) Min 0,35 -> 0,6 y ambiente 0,5 -> 0,75: tan graves daban miedo. Tramo I (factor 0,30): voces a 0,72.
  FX = { Pitch = { Enabled = true, Min = 0.6, RefreshMs = 100, Volume = 0.8 }, Precip = { Enabled = true, Factor = 0.03, RampMs = 350, Streak = 0.15 },
         Ambience = { Enabled = true, Pitch = 0.75 },
         -- (181) C13.4 pedido de tono generico (SandevistanFXBridge.pitchRequest): llega a los zombis a Radius casillas (hasta Max) y a los jugadores
         Request = { Radius = 18, Max = 40 } },
  -- Animación rápida del jugador (v0.1.30 (14); (44) suma trepar vallas, paredes, ventanas y sogas): nodos extra en media/AnimSets/player/{movement,run,sprint,
  -- climbfence,climbwall,climbwindow,climbrope,climbdownrope} (tools/gen_player_animsets.py)
  -- con la condición Flag; su m_SpeedScale es una variable SandevistanSpd<base*100> que Slowdown pone en base * (1 + playerBoost).
  -- Bases = las escalas vanilla de esos nodos (1.04 caminar/correr, 0.96 sprint, 0.92 correr agachado, 0.72 a 1.20 trepar/saltar, 1.00 resto).
  FastAnimations = { Enabled = true, Flag = "SandevistanFast", VarPrefix = "SandevistanSpd", Bases = { 0.72, 0.80, 0.88, 0.92, 0.96, 1.00, 1.04, 1.20 }, MaxMultiplier = 2.2,
    -- estados de trepada/vallada: si el implante se apaga (o enciende) en medio, la bandera no cambia hasta que termine el estado (si no, la animacion se reinicia en la otra version)
    HoldStates = { "ClimbOverFence", "ClimbThroughWindow", "ClimbOverWall", "ClimbSheetRope", "ClimbDownSheetRope" }, HoldMaxSeconds = 6 },
  Net = { HeartbeatMs = 1000, ExpireMs = 3500, LookHeartbeatMs = 10000, LookExpireMs = 30000,        -- MP: latido del estado activo y vencimiento en clientes remotos
          StatFlushMs = 250,           -- (114) cada cuanto se le mandan al servidor los cambios de stats (resistencia, fatiga, panico...) que hizo el mod
          SaveEveryMs = 15000 },       -- (114) cada cuanto se le manda al servidor el ModData del jugador (es el que guarda la partida)

  -- Estelas (after-images) estilo Edgerunners: siluetas tintadas en posiciones pasadas del jugador.
  -- Tamaños en píxeles a zoom 1 (calibrables desde Debug). Tiempos en ms reales.
  Afterimage = {
    IntervalMs = 70, MinMoveTiles = 0.22, LifetimeMs = 450, Max = 12, Alpha = 0.55,
    PoseIso = true,                       -- (138h) con SandevistanViewpoint: estelas con pose real tambien en isometrico (false = siluetas 2D; los ecos usan el motor igual)
    AdaptMaxMultiplier = 3,               -- con la adaptación estable (S.adaptFraction = 1): estelas x3 de duración y x3 de cantidad máxima
    HideNearPlayerTiles = 0.35,          -- no tapar al personaje con la estela recién creada
    Overdrive = { IntervalMs = 45, LifetimeMs = 650, Alpha = 0.7 },
    Width = 123, Height = 162, OffsetY = 12,  -- calibrado en juego (textura 96x128)
    -- Forma según la marcha (textura Sandevistan_Ghost_<gait>_<DIR>_<frame>): tiempos en ms reales.
    -- Detección: isSprinting / isRunning del jugador; si no existen, por velocidad (tiles/s).
    Gaits = {
      walk   = { IntervalMs = 80, LifetimeMs = 420 },
      run    = { IntervalMs = 65, LifetimeMs = 450 },
      sprint = { IntervalMs = 50, LifetimeMs = 520 },
      -- agachado: se avanza despacio, así que duran más (si no, se apagan antes de alejarse del personaje) y pueden verse más cerca
      crouch   = { IntervalMs = 140, LifetimeMs = 700 },
      sneak    = { IntervalMs = 100, LifetimeMs = 1000, HideTiles = 0.15 },
      sneakrun = { IntervalMs = 75,  LifetimeMs = 800,  HideTiles = 0.2 },
    },
    GaitSpeedFallback = { run = 2.6, sprint = 4.2, sneakRun = 1.6 },
    RainbowPeriodMs = 900, RainbowStep = 0.09,
    Palettes = {
      lab = { { 0.2, 0.95, 1.0 }, { 0.3, 1.0, 0.65 }, { 0.3, 0.55, 1.0 }, { 0.85, 0.35, 1.0 } },
      military = { { 1.0, 0.75, 0.15 }, { 1.0, 0.45, 0.1 }, { 1.0, 0.2, 0.25 }, { 1.0, 0.35, 0.7 } },
      cyberpsychosis = { { 1.0, 0.1, 0.15 }, { 0.85, 0.0, 0.35 }, { 1.0, 0.3, 0.1 } },
    },
  },

  Stamina = { BaseDrain = 0.022, ReductionPerLevel = 0.075, MinToActivate = 0.25,
              ExhaustionCutoff = 0.15, EncumbranceMultiplier = 1.5, EmergencyStaggerSeconds = 0.5,
              -- (139) Deuda de estamina (27 §2): con el implante encendido la resistencia NO baja. Todo lo que el cuerpo gasta
              -- (correr, esprintar, golpear, empujar, trepar, tropezar y el drenaje del implante) se anota como deuda y se cobra
              -- de golpe al apagar. La regeneracion natural del juego no sube la resistencia: paga deuda. Mismo gasto, movido de
              -- lugar: durante la rafaga no ves el agotamiento, al apagar lo recibis entero.
              --   Enabled    lo cambia la opcion de sandbox StaminaDebt (Apagada / Normal / Suave).
              --   Punish     tropiezo de sobregiro y bloqueo de esprint (Normal); Suave deja solo el pago.
              --   MaxOverdraft  cuanto puede pasar la deuda a la marca antes del corte de emergencia (0,35 = 35 % de la
              --              resistencia que habia al encender).
              --   MoodleSteps   umbrales del moodle "Aliento prestado" (deuda / resistencia congelada).
              Deferred = { Enabled = true, Punish = true, MaxOverdraft = 0.35,
                           OverdraftStaggerSeconds = 1.0, NoSprintSeconds = { 2.0, 5.0 },
                           MoodleSteps = { 0.25, 0.50, 0.75, 1.00 } } },

  -- (167) T13: mapas anotados (D8). Con el sistema de escondites vanilla: marcan una zona con círculo, cruz y texto a mano. El ítem
  -- reparte solo el juego segun AnnotatedMapChance; `bounds` es la vista del mapa (misma carpeta de datos que usa vanilla) y `texts` son
  -- claves de Stash.json con su posicion en coordenadas del mundo.
  AnnotatedMaps = { Enabled = true,   -- SV: AnnotatedMaps
    lsu   = { stash = "SandevistanStashLSU",   item = "Base.LouisvilleMap4", building = { x = 12406, y = 2149 },
              bounds = { 12290, 2000, 12530, 2260 }, color = { 0.16, 0.19, 0.49 },
              texts = { { "Stash_SandevistanLSU_Text1", 12345, 2050 }, { "Stash_SandevistanLSU_Text2", 12455, 2240 } } },
    ekron = { stash = "SandevistanStashEkron", item = "Base.RosewoodMap",    building = { x = 765, y = 9841 },
              bounds = { 690, 9760, 870, 9920 }, color = { 0.16, 0.19, 0.49 },
              texts = { { "Stash_SandevistanEkron_Text1", 700, 9790 }, { "Stash_SandevistanEkron_Text2", 860, 9895 } } },
    base  = { stash = "SandevistanStashBase",  item = "Base.RosewoodMap",    building = { x = 5574, y = 12482 },
              bounds = { 5400, 12320, 5950, 12660 }, color = { 0.65, 0.05, 0.05 },
              texts = { { "Stash_SandevistanBase_Text1", 5420, 12410 }, { "Stash_SandevistanBase_Text2", 5620, 12570 } } },
  },

  -- (165) T12: desconexión del implante (29 §4.5, 30 §3.8, D13-D15). El implante queda inerte hasta reconectar: la CN baja a la mitad,
  -- los síntomas del daño cerebral siguen a la mitad (lo que hace el implante no), la remisión avanza a la mitad y reconectar cuesta.
  Disconnect = { RemissionRate = 0.5, DecayMult = 0.5, SymptomMult = 0.5, ActionSeconds = 6,
                 Reconnect = { CN = 8, LockSeconds = 20, Stress = 0.15, QuickMinutes = 10, QuickMult = 2 } },

  -- (163) T11: Forzar el implante (30 §3.4). Mantener la tecla con el implante apagado saltea el seguro del aire o del calor y entra
  -- directo en Overdrive; siempre termina en colapso, con la cuenta extra de lo que forzaste. Sin espera fija: los bloqueos se levantan
  -- al recuperar la resistencia o al enfriarse del todo.
  Force = { Enabled = true,                                      -- SV: ImplantOverride
    HoldSeconds = 0.8,
    Stamina = { UnlockAt = 0.5, NoSprintSeconds = 10, Fatigue = 0.10 },
    Heat = { Wear = 0.1, BurnPart = "Torso_Lower", ScarAlways = true },
  },

  -- v0.1.30 (30): guia de campo (se entrega con el primer implante; SV FieldGuideOnInstall) y escena de instalacion (solo la ve quien recibe el implante)
  Guide = { Item = "Sandevistan.SandevistanFieldGuide", Pages = 8 },
  FieldGuideOnInstall = true,
  InstallScene = { Enabled = true, Seconds = 11, ExplantSeconds = 10, ShortSeconds = 3.5, FailSeconds = 3.5, SkipAfter = 2, TypeCharsPerSecond = 45 },
  -- v0.1.30 (33): recarga y cerrojo mas rapidos con el implante activo (Factor 1 = el mismo aumento que tu velocidad). SV: FirearmActionSpeed.
  Firearms = { Enabled = true, Factor = 1.0 },
  HeatRateMultiplier = 1.0,                       -- SV (v0.1.30 25): velocidad a la que sube el Heat
  -- (138i) Enfriamiento ambiental (27 §3): SOLO bonus. Frio, cuerpo mojado y viento al aire libre enfrían mas rapido; el calor no castiga
  -- (nunca baja de x1,00). Max lo cambia la opcion de sandbox AmbientCooling (Apagado / Normal / Fuerte = StrongMax). CombinedMax es el tope
  -- del producto con la Camara criogenica (x1,75 x x1,45 daria x2,5). Dry: cuanto seca el implante por unidad de Heat (cuerpo, 0..100).
  -- (138j) DurationShare: cuanto de ese bonus tambien frena la suba de Heat mientras esta encendido (alarga la rafaga en MENOR proporcion:
  -- con 0,35, x1,45 de enfriamiento da ~x1,15 de duracion). 0 = solo enfriamiento.
  AmbientCooling = { Enabled = true, Max = 1.45, StrongMax = 1.9, CombinedMax = 2.0, DurationShare = 0.35,
    Cold = { RefTemp = 18, PerDegree = 0.02 }, BodyWet = 0.25, Wind = 0.05,
    Dry = { BodyPerHeat = 0.5, EvapPerCool = 0.15 } },
  HeatZoneMultiplier = { safe = 1.0, risk = 1.1, critical = 1.2, cyberpsychosis = 1.2 },

  Input = { HoldToArmSeconds = 0.3, DoubleTapWindowSeconds = 0.4, DefaultKey = 44 }, -- 44 = Keyboard.KEY_Z (la V es el menú radial vanilla de animales y vehículo)

  Stagger = { MoveFactor = 0.25 },                   -- movimiento durante un tropiezo (Effects.stagger)

  -- El corte térmico es la salida SEGURA (evita el Overdrive): a la adaptación ideal no suma rechazo; a nivel 0 suma todo RejectionMin..Max.
  -- RejectionAdaptReduction = fracción que se descuenta a adaptación estable (1 = nada).
  ThermalCutoff = { StaggerSeconds = 1.0, RejectionMin = 2, RejectionMax = 4, RejectionAdaptReduction = 1.0 },
  ManualCutoff = { ReuseDelaySeconds = 1.0 },       -- corte manual: 1 s y el Heat sigue desde donde estaba

  Overdrive = {
    WindowSeconds = 2.5,      -- ventana a nivel 0; sube lineal hasta Variants.<v>.overdriveMax en el nivel maximo (lab L5 4 s, militar L10 7 s): S.overdriveWindow
    StaggerSeconds = 2.0, CoolingMultiplier = 2.0,
    MinTemp = 38.5, MaxTemp = 39.5,
    NeuralLoadMin = 5, NeuralLoadMax = 10,           -- CN que suma el colapso (x NeuralLoadMultiplier con Kerenzikov)
    RejectionMin = 10, RejectionMax = 18, RejectionAdaptReduction = 0.5,     -- el colapso cuesta la mitad a adaptación estable
    SoundRadius = 6, TorsoDamage = 15, TorsoPain = 40,
    -- v0.1.29: cicatriz térmica. Cada Overdrive que termina en colapso (PerCollapse) y cada furia total (PerFury) bajan el tope de
    -- Heat (100 -> Min). El tope se recupera despacio con el implante apagado (RecoverPerHour por hora de juego, x SleepMult durmiendo).
    -- El corte térmico y el manual no lo tocan: siguen siendo la salida segura. SV: OverdriveHeatCap.
    -- v0.1.30 (10): castiga el abuso, no el uso: el primer colapso de cada FreeEveryHours horas de juego no deja cicatriz; los siguientes
    -- restan PerCollapse (5). Se recupera a 1 por hora (una cicatriz de colapso ~5 h). La furia total marca siempre.
    HeatCap = { Enabled = true, PerCollapse = 5, PerFury = 15, Min = 50, RecoverPerHour = 1.0, SleepMult = 1.5, FreeEveryHours = 24 },
    ChestWoundChance = 0,                           -- SV. v0.8: 0, el colapso por uso normal no deja herida profunda (solo con cyberpsicosis)
    Cyberpsychosis = { DeathChance = 0.01,          -- SV (v0.1.26: 1 %)
                       ChestWoundChance = 0.20 },   -- corte profundo en el pecho
    Kerenzikov = { UnconsciousMinSeconds = 5, UnconsciousMaxSeconds = 10, UnconsciousAdaptReduction = 0.5,   -- v0.1.29: el KO se acorta hasta la mitad a adaptación estable
                   NeuralLoadMultiplier = 1.5, ArrhythmiaDamage = 10 },
    -- Mientras dura el Overdrive: bonos que se suman a los del tramo (salto grande de ventajas)
    Bonus = { PlayerBoost = 0.40, AttackBoost = 1.0, ZombieSpeedMult = 0.5, DamageBonus = 0.5 },
    -- Tras el colapso: el jugador se arrastra (movimiento x Factor) durante Seconds
    SlowAfter = { Seconds = 2.0, Factor = 0.15 },
    -- v0.1.30 (11): el tropiezo y el arrastre tras el colapso se acortan con la adaptación (hasta la mitad a la adaptación estable),
    -- como el KO con Kerenzikov.
    RecoveryAdaptReduction = 0.5,
  },

  -- Impulso: cuanto más tiempo seguido se usa, más sube la velocidad de carrera y de ataque.
  -- Sube con el tiempo activo y baja despacio al apagarlo (segundos reales para llegar de 0 a 1 y viceversa).
  Momentum = { RampSeconds = 15, DecaySeconds = 60, PlayerBoost = 0.10, AttackBoost = 0.25 },

  -- Panel flotante: transparencia cuando no se usa (Heat 0 e implante apagado) y velocidad de la transición (alpha por segundo)
  HUD = { IdleAlpha = 0.3, FadeOutPerSecond = 0.25, FadeInPerSecond = 3, HoverInPerSecond = 0.8,    -- HoverInPerSecond: con el mouse encima
          -- Resplandor suave alrededor de los leds encendidos del panel de laboratorio y militar. Apagado: asi se ve en el juego desde la (70),
          -- porque el codigo pedia una textura con otro nombre y nunca se dibujaba. Prendido, el halo es muy sutil (un dibujo mas por led encendido).
          LedGlow = false,
          -- (134d) tinte de pantalla al activar y rojo del Overdrive (opacidad). En la camara 3D de Viewpoint la escena es mas clara y contrastada y el
          -- tinte isometrico casi no se notaba: ahi va mas fuerte.
          Tint = 0.045, Tint3D = 0.13, OverdriveTint = 0.09, OverdriveTint3D = 0.18 },

  -- Moodles (Moodles.lua, vía Moodle Framework): umbrales de nivel de cada estado. Rechazo y toxicidad
  -- usan Rejection.Moodles / Immunosuppressant.HerbalToxicity.Moodles. Los textos están en Translate/*/Moodles.json.
  Moodles = {
    UpdateMs = 250,                          -- cada cuánto se envían los valores al framework
    Heat = { 25, 50, 75, 90 },               -- niveles 1..4 por Heat
    NeuralLoad = { 15, 30, 60, 75 },         -- niveles 1..4 por Carga Neuronal
    -- (66) recuperacion tras sacarse el implante con cyberpsicosis. Abstinencia (Bad): nivel 2 mientras queden mas de WithdrawalEasingHours de las Withdrawal.Hours; nivel 1 despues.
    -- Recuperacion (Good, tras la abstinencia): nivel 1..4 segun las horas que faltan para la remision (> 48, > 24, > 12, <= 12).
    WithdrawalEasingHours = 24, RecoveryHours = { 12, 24, 48 },
    Cyberpsychosis = { 60, 80, 95 },         -- niveles 2..4 por CN (nivel 1: remisión, CN bajo 60)
    CoverageHours = { 12, 36, 60 },          -- niveles 2..4 por horas de cobertura (nivel 1: menos de 12 h)
    Thresholds = { 0.1, 0.2, 0.3, 0.4, 0.6, 0.7, 0.8, 0.9 },   -- setThresholds: malo 4..1, bueno 1..4
    RetrySeconds = 2, MaxRetries = 60,       -- reintentos de registro si el framework aún no cargó
  },

  -- Implante visible en la espalda: modelo 3D (prenda que equipa el mod): tipos de ítem por variante y frecuencia de la comprobación.
  Spine = {
            Model = { lab = "Sandevistan.SandevistanSpineLab", military = "Sandevistan.SandevistanSpineMilitary",
                      destroyed = "Sandevistan.SandevistanSpineLab" },        -- apagado (reposo)
            -- v0.1.26: los LEDs solo se encienden con el implante activo; en rojo con Overdrive o cyberpsicosis activa
            ModelOn = { lab = "Sandevistan.SandevistanSpineLabOn", military = "Sandevistan.SandevistanSpineMilitaryOn" },
            ModelRed = { lab = "Sandevistan.SandevistanSpineLabRed", military = "Sandevistan.SandevistanSpineMilitaryRed" },     -- (105) un modelo por variante (antes uno solo, rojo)
            -- el implante no se ve bajo estas prendas (subcadenas de la ubicación de cuerpo): chaquetas, capas, abrigos
            HiddenUnder = { "jacket", "cloak", "coat", "poncho", "torsoextra", "torso_extra" },
            SyncSeconds = 2 },

  -- Cyberpsicosis por etapas (client/Sandevistan/Psychosis.lua, v0.1.28). Cada sistema se puede apagar (Enabled) y casi todos tienen
  -- opción de sandbox. Etapa 1: CN >= Stage1CN (tics: susurros, terrores nocturnos, avisos). Etapa 2: cyberpsicosis activa (CN >= 80:
  -- inestabilidad temporal, sentido de peligro, alucinaciones de audio completas). Etapa 3: CN >= Stage3CN
  -- (reflejo descontrolado, apagones, furia cibernética como recompensa).
  Psychosis = {
    Stage1CN = 60, Stage3CN = 95,
    -- Avisos estilo HUD de Cyberpunk ("NEURAL LINK UNSTABLE", "HUMANITY 42%"). Humanidad = 100 - CN. Opción de mod "neuralMonitor".
    Monitor = { Enabled = true, ToastSeconds = 3.5, RandomEverySeconds = { 45, 100 }, MaxToasts = 3 },
    -- Terrores nocturnos: tras MinSleepHours durmiendo, chance por minuto in-game (CN 60 -> 100); los antidepresivos la bajan.
    NightTerrors = { Enabled = true, MinSleepHours = 2, ChancePerMinute = { min = 0.02, max = 0.10 }, Panic = 45, Stress = 0.3 },
    -- Audio: solo lo oye el jugador (no atrae zombis). EverySeconds = pausa entre eventos (CN 60 -> CN 100; la mitad con cyberpsicosis).
    -- Sonidos por rol: candidates = nombres vanilla (elegidos del volcado de sonidos de 42.21; se usa uno al azar entre los que existan)
    -- y, si ninguno existe, fallback = sonido propio. (153) Los roles con vanilla ya no tienen propio (se borraron los placeholders): si una
    -- version del juego sacara esos sonidos, el rol queda mudo. Sin vanilla adecuado (verificado en el volcado):
    --   heartbeat: "HeartBeat" es el latido de pánico del juego (podría quedar en bucle si se lanza desde acá) -> se usa el propio.
    --   tinnitus / glitch*: no hay equivalentes (RadioStatic / TelevisionStatic son ruido en bucle) -> propios.
    -- "footstep" usa eventos "Combined" (con parámetro de superficie; probados en el juego con los zombis falsos, 140).
    Audio = { Enabled = true, MinCN = 60, EverySeconds = { 70, 22 }, Volume = 0.85,
      Roles = {
        footstep = { candidates = { "ZombieFootstepsCombined", "HumanFootstepsCombined" } },
        footstepHuman = { candidates = { "HumanFootstepsCombined" } },        -- (171) los pasos del clon en modo espejo
        groan    = { candidates = { "MaleZombieVoiceA", "MaleZombieVoiceB", "MaleZombieVoiceC",
                                    "FemaleZombieVoiceA", "FemaleZombieVoiceB", "FemaleZombieVoiceC" } },
        -- (140) el zombi falso que corre usa las voces de los corredores del juego y, al morder, las voces de mordida
        groanSprint = { candidates = { "MaleZombieSprinterVoiceA", "MaleZombieSprinterVoiceB",
                                       "FemaleZombieSprinterVoiceA", "FemaleZombieSprinterVoiceB" } },
        bite     = { candidates = { "MaleZombieBiteA", "MaleZombieBiteB", "MaleZombieBiteC",
                                    "FemaleZombieBiteA", "FemaleZombieBiteB", "FemaleZombieBiteC",
                                    "MaleZombieSprinterBiteA", "MaleZombieSprinterBiteB",
                                    "FemaleZombieSprinterBiteA", "FemaleZombieSprinterBiteB",
                                    "ZombieBite", "NeckBite" } },
        bang     = { candidates = { "ZombieThumpWood", "ZombieThumpGeneric", "ZombieThumpMetal", "ZombieThumpGarageDoor" } },
        glass    = { candidates = { "SmashWindow", "BreakGlassItem" } },
        whisper  = { candidates = { "VoiceMaleWhisperPsst", "VoiceFemaleWhisperPsst", "VoiceMaleWhisperHey", "VoiceFemaleWhisperHey" } },
        heartbeat = { candidates = {}, fallback = "SandevistanHeartbeat" },
        tinnitus  = { candidates = {}, fallback = "SandevistanTinnitus" },   -- clip a 0.5 en el script (el tono agudo lastimaba el oído)
        -- (153) glitch en tres familias (sonidos de Mixkit, tools/import_sounds.py, todos al mismo volumen percibido). Nunca sale dos veces
        -- seguidas el mismo y Pitch/VolumeJitter varian cada toque (+-, solo en los sonidos de archivo). glitch = tartamudeo temporal (el mas
        -- frecuente: cortos y secos); glitchVanish = una alucinacion que se deshace (doble, zombi falso); glitchSevere = falla grave (explante).
        glitch       = { candidates = {}, fallback = { "SandevistanGlitch1", "SandevistanGlitch2", "SandevistanGlitch3", "SandevistanGlitch4",
                                                       "SandevistanGlitch5", "SandevistanGlitch6", "SandevistanGlitch7" },
                         Pitch = 0.08, VolumeJitter = 0.15 },
        glitchVanish = { candidates = {}, fallback = { "SandevistanGlitchVanish1", "SandevistanGlitchVanish2", "SandevistanGlitchVanish3" },
                         Pitch = 0.08, VolumeJitter = 0.15 },
        glitchSevere = { candidates = {}, fallback = { "SandevistanGlitchSevere1", "SandevistanGlitchSevere2" } },
      } },
    -- Inestabilidad temporal: con el implante encendido y cyberpsicosis, la dilatación "tartamudea" (los zombis cercanos vuelven a
    -- velocidad normal) durante DurationMs. ChancePerSecond crece con la CN (80 -> 100).
    TimeGlitch = { Enabled = true, ChancePerSecond = { min = 0.04, max = 0.12 }, DurationMs = { 300, 800 }, CooldownSeconds = 2.5 },
    -- Sentido de peligro: marcos rojos tenues sobre los zombis reales cercanos del mismo piso que NO estás viendo (tras paredes o
    -- esquinas). El implante no es visual: se explica como percepción refleja, sin números. Opción de mod "threatVision".
    -- Phantoms (80): de a ratos, con cyberpsicosis, aparece un marco sobre alguien que no está (casi siempre a tu espalda): dura un par de segundos,
    -- parpadea y se disuelve si mirás hacia ahí. EverySeconds = { a CN 100, a CN 60 } (con antidepresivos se espacian); SoundChance = chance de que
    -- vaya con unos pasos lejanos. Se apagan con Phantoms.Enabled o con la opción de mod / de sandbox del sentido de peligro.
    ThreatVision = { Enabled = true, Range = 10, Max = 8, RefreshMs = 250,
                     Phantoms = { Enabled = true, EverySeconds = { 15, 45 }, Max = 2, LifeSeconds = { 0.9, 2.4 }, Radius = { 2.5, 6 }, BehindChance = 0.7, SoundChance = 0.3 } },
    -- Reflejo descontrolado: con CN crítica, si un zombi te ataca con el implante apagado puede dispararse solo unos segundos.
    Misfire = { Enabled = true, RadiusTiles = 1.6, ChancePerSecond = 0.35, Seconds = { 2, 3 }, RejectionCost = 3, CooldownSeconds = 25 },
    -- Apagones: visión de túnel + latidos y, a veces, unos instantes de negro (se puede caminar). Los antidepresivos espacian los episodios.
    Blackouts = { Enabled = true, CooldownSeconds = { 70, 160 }, TunnelSeconds = 4.5, BlackoutChance = 0.5, BlackoutSeconds = { 0.6, 1.3 } },
    -- Furia cibernética (recompensa): con cyberpsicosis y el implante encendido, más daño y velocidad de ataque melee, sin pánico y
    -- con menos dolor. (Los costos ya existen: Heat y CN suben más rápido con cyberpsicosis.)
    -- WeaponWearMult (64): en furia (cyberpsicosis o furia total) cada golpe melee gasta el arma esa cantidad de veces mas (1 = como vanilla): fuerza sin medir la estructura.
    Berserk = { Enabled = true, DamageBonus = 0.25, AttackBoost = 0.25, NoPanic = true, PainScale = 0.5, WeaponWearMult = 2.0 },
    -- Sobrecarga neural (v0.1.29): al llegar la CN al tope. Válvula de escape: apaga el implante, te deja inconsciente, sangrado, dolor y un
    -- grito que atrae zombis, y baja la CN a DropTo (con pausa de CooldownHours de juego). Con cyberpsicosis activa y el implante operativo hay
    -- FuryChance de "furia total" en vez del KO: Seconds con el implante trabado (no se puede apagar, sin corte térmico), más ataque y daño
    -- (AttackBoost/DamageBonus se suman a los de la furia) y al terminar un bajón (sin estamina, CrashSeconds inconsciente, Heat al tope).
    -- Los antidepresivos acortan el KO (AntidepKOMultiplier).
    Overload = { Enabled = true, CooldownHours = 6, DropTo = 85, KOSeconds = { 8, 15 }, AntidepKOMultiplier = 0.5, Pain = 40,
                 FuryChance = 0.30, Fury = { Seconds = 15, AttackBoost = 0.25, DamageBonus = 0.25, EnduranceFloor = 0.3, CrashSeconds = 5 },
                 -- (177) C05: la antesala de la sobrecarga (Crisis.lua, 29 §5.2.1). Desde FromCN con el implante encendido, Seconds de aviso
                 -- (tinnitus, latidos, tunel, texto y «CASCADA NEURAL INMINENTE»); la CN no pasa de HoldCN mientras dura. Apagar el implante la
                 -- evita: la CN queda en AvoidCN como mucho y no hay KO. Si no, la sobrecarga de siempre.
                 Cascade = { Enabled = true, FromCN = 97, Seconds = { 20, 30 }, HoldCN = 99.9, AvoidCN = 99 } },
    -- (138) Zombis falsos (FakeZombies.lua; los dibuja el mod opcional SandevistanPsychosis, sin el no hay): con cyberpsicosis activa (MinStage), de a ratos
    -- nace uno a SpawnDist casillas (casi siempre a tu espalda, fuera de la vista y con camino recto hasta vos), camina a WalkSpeed casillas/s (o
    -- corre con SprintChance) y a LungeDist embiste. Al tocarte (TouchDist) o al pegarle (alcance del arma + HitSlack) se deshace en FadeMs; el
    -- contacto suma Panic y Stress y Pain de dolor sin herida. Una pared o puerta cerrada en el camino lo deshace (no busca caminos). No se frena
    -- con el Sandevistan. EverySeconds = { a CN 100, a CN 60 } (los antidepresivos los espacian, como a las marcas fantasma).
    FakeZombies = { Enabled = true, MinStage = 2, Max = 1, FirstDelaySeconds = 25, EverySeconds = { 60, 240 },
                    SpawnDist = { 7, 12 }, BehindChance = 0.6, GroanChance = 0.5,
                    WalkSpeed = { 0.55, 0.9 }, SprintChance = 0.12,          -- (146) 0,2 -> 0,12: el corredor raro y callado es el Jumpscare
                    SprintSpeed = 2.6, LungeDist = 2.2, LungeSpeed = 1.3,
                    MaxAnimSpeed = 4,                   -- (138e) con SandevistanPsychosis el paso sale de la animacion (WalkSpeed/SprintSpeed/LungeSpeed quedan para sin jar); tope por las dudas
                    TouchDist = 0.65, HitSlack = 0.4, LifeSeconds = 20, FadeMs = 350,
                    Panic = 25, Stress = 0.12, Pain = 8, PainParts = { "Hand_L", "Hand_R", "ForeArm_L", "ForeArm_R", "UpperArm_L", "Neck" },
                    Alpha = 1.0, Tint = { 0.92, 0.92, 1.0 },
                    -- (140) Sonidos del zombi falso: pasos mientras camina, gruñidos cada tanto, uno al entrar en embestida, el mordisco al tocarte
                    -- y un gruñido al pegarle. Suenan en SU posicion (emisor del mundo: volumen, estereo y distancia del juego), solo los oye este
                    -- cliente y NO son ruido de mundo: los zombis reales no los escuchan. Voz del mismo sexo que el atuendo. Respeta
                    -- PsychosisAudio (sandbox) y Sound.Enabled. StepEvery = casillas recorridas por paso; GroanEvery = segundos.
                    -- (171) C02: el corredor con trancos largos (StepEverySprint, unos 3 pasos por segundo) y mas fuerte (StepVolumeSprint), como en
                    -- vanilla. Cada paso lleva el piso de su casilla y la velocidad (parametros de FMOD), y cada voz la distancia al jugador.
                    -- (172) La voz es UNA por zombi falso, continua, con el estado del juego (ZombieState: buscando, embestida, mordida, golpe), como
                    -- la de un zombi real; StartVolume/GroanVolume = su volumen, GroanEvery = espera para relanzarla si el evento termina solo,
                    -- VoiceLingerMs = cuanto sigue sonando despues del golpe o la mordida. LungeVolume y HitVolume ya no se usan (son estados de la voz).
                    Sound = { Enabled = true, StepEvery = { 0.65, 0.9 }, StepVolume = 0.5, StepEverySprint = { 1.05, 1.3 }, StepVolumeSprint = 1.0, VoiceLingerMs = 1500,
                              ScareLingerMs = 2500, VoiceFadeMs = 600,       -- (173) el susto suena mas despues del contacto; toda voz se apaga en VoiceFadeMs
                              GroanEvery = { 4.5, 11 }, GroanVolume = 0.75, StartVolume = 0.8,
                              LungeVolume = 1.0, BiteVolume = 1.0, HitVolume = 0.85 },
                    -- (141) Contorno rojo: mientras apuntas, el juego le pone un borde rojo a los zombis que podrias golpear. El titere no es
                    -- una entidad y no entra en esa lista, asi que se repite la misma cuenta y se le dibuja el mismo contorno (Range = 3
                    -- casillas y Dot 0,8 son los de CombatManager.calculateHitListWeapon; el color lo pone el juego).
                    Outline = { Enabled = true, Range = 3.0, Dot = 0.8 },
                    -- (142) Al deshacerse: glitch estilo cyberpunk, con tirones de posicion y colores cian/magenta/blanco alternados
                    -- durante FadeMs (encima del parpadeo de siempre).
                    Glitch = { Enabled = true, JitterTiles = 0.12, JitterChance = 0.35, ColorMs = 55,
                               -- (146) mientras camina, de vez en cuando un "salto" de un instante (parpadeo + color corrido): la pista de que
                               -- no existe. TellChance = probabilidad por segundo; TellMs = cuanto dura. 0 lo apaga.
                               TellChance = 0.08, TellMs = 110 },
                    -- (146) El susto: con Chance, el zombi falso es un CORREDOR que nace a tu espalda, fuera de la vista y callado (sin pasos
                    -- ni gruñidos) hasta ScreamDist casillas; ahi grita fuerte y embiste. Si te toca, el golpe psicosomatico es mas fuerte
                    -- (Panic, StressMult) y la pantalla se rompe un instante (ScreenGlitchMs) junto con el texto (TextGlitch).
                    -- Va aparte de SprintChance (los corredores comunes, que suenan como siempre).
                    Jumpscare = { Enabled = true, Chance = 0.07, MinStage = 2, SpawnDist = { 9, 13 }, ScreamDist = 4.5, ScreamVolume = 1.25,
                                  Panic = 45, StressMult = 1.5, ScreenGlitchMs = 650, TextGlitch = 0.8 },
                    -- atuendos de clothing.xml que existen para los dos sexos (los que tienen una sola version quedan afuera)
                    Outfits = { "Generic01", "Generic02", "Generic03", "Generic04", "Generic05", "Student", "Police", "Doctor",
                                "Farmer", "Bathrobe", "HospitalPatient", "Punk", "Redneck", "Fireman" } },
    -- (148) El clon (Doppelganger.lua, 26 §7; lo dibuja el mod opcional SandevistanPsychosis, sin el no hay): con cyberpsicosis en etapa MinStage, de a
    -- ratos aparece una copia tuya (tu piel, tu pelo y tu ropa, sin arma) a Dist casillas, casi siempre a tu espalda. Con MirrorChance copia
    -- tus pasos con MirrorDelayMs de atraso; si no, se queda quieta mirandote. Si la miras de frente (LookDot) durante LookMs, o te acercas a
    -- menos de TouchDist, se deshace con el glitch (FadeMs) y suma Stress; si no, se va sola a los LifeSeconds. No hace ruido (salvo pasos suaves en espejo, 171), no choca y no
    -- existe para nadie mas. EverySeconds = { a CN 100, a CN 60 }.
    Doppelganger = { Enabled = true, MinStage = 3, Max = 1, FirstDelaySeconds = 120, EverySeconds = { 360, 900 },
                     Dist = { 3, 6 }, LifeSeconds = { 8, 14 }, MirrorChance = 0.5, MirrorDelayMs = 1000,
                     WaveChance = 0.5,                 -- (150) quieto: con esta chance te saluda (el saludo vanilla, en bucle)
                     LookDot = 0.85, LookMs = 500, TouchDist = 1.3, FadeMs = 700,
                     Stress = 0.08, Panic = 10, TextGlitch = 0.35,
                     -- (171) C02: en modo espejo pisa muy suave, con el mismo atraso que sus pasos (29 §4.2). StepEvery = casillas por paso.
                     MirrorSteps = { Enabled = true, Volume = 0.18, StepEvery = { 0.7, 0.85 }, RunStepEvery = { 1.0, 1.2 } },
                     Alpha = 0.95, Tint = { 0.86, 0.88, 0.95 } },
    -- (138) Ecos (Echoes.lua; los dibuja el motor de estelas del mod opcional SandevistanViewpoint, sin el no hay): con cyberpsicosis activa, de a ratos
    -- hasta MaxZombies zombis reales que estas viendo (a Range casillas, mismo piso) dejan durante DurationMs una estela de su pose cada StampMs,
    -- alternando rojo y cian (vision doble), que se apaga en LifeMs. EverySeconds = { a CN 100, a CN 60 }.
    Echoes = { Enabled = true, MinStage = 2, FirstDelaySeconds = 20, EverySeconds = { 40, 120 }, Range = 10, MaxZombies = 2,
               -- (138e) menos poses por eco: antes 1600 y 110 (unas 14 por zombi), ahora unas 6
               DurationMs = 1200, StampMs = 190, LifeMs = 650, Alpha = 0.55, Colors = { { 0.3, 1.0, 1.0 }, { 1.0, 0.25, 0.3 } } },
    -- (181) C13.2 FIGURAS FANTASMA (PhantomFigures.lua; las dibuja el mod opcional SandevistanPsychosis, sin el no hay): con cyberpsicosis en
    -- etapa MinStage, de a ratos una figura (un titere zombi semitransparente: Alpha y Tint) se entrevé al costado de lo que ves: el rumbo
    -- girado SideDeg grados, a Dist casillas, solo en una casilla que estas viendo. Quieta mirandote, o caminando despacio de costado
    -- (WalkChance). Nunca embiste ni toca y no hace ruido (su pista). Si la miras de frente (LookDot) LookMs, o te acercas a menos de NearDist,
    -- se deshace (FadeMs); si no, se va sola a los LifeSeconds. Sin lugar a la vista prueba otra vez en RetrySeconds.
    -- EverySeconds = { a CN 100, a CN 60 }. Opcion de sandbox PsychosisPhantomFigures (necesita ademas «Alucinaciones»); el Filtro la espacia.
    PhantomFigures = { Enabled = true, MinStage = 2, Max = 1, FirstDelaySeconds = 60, EverySeconds = { 100, 300 }, RetrySeconds = 15,
                       Dist = { 8, 13 }, SideDeg = { 55, 100 }, LookDot = 0.93, LookMs = 250, NearDist = 5, LifeSeconds = { 5, 10 },
                       WalkChance = 0.5, WalkSpeed = 0.4, Alpha = 0.35, Tint = { 0.55, 0.58, 0.68 }, FadeMs = 450, Tries = 8 },
    -- (181) C13.3 / C13.4 / C13.5 (ScreenFX.lua). Sacudida de camara y efectos de pantalla: los hace el mod opcional SandevistanPsychosis y solo
    -- con la camara isometrica. Shake = { pixeles de pantalla, ms } por evento. Screen.<tipo> = lo que el episodio le hace a la imagen del mundo,
    -- 0..1: Desat (desaturacion), Wobble (la ondulacion de la borrachera del juego, con el borde borroso), Blur (desenfoque del borde), Split
    -- (copias cian y magenta corridas) y Tear (tiras horizontales corridas). Burst = el golpe corto de cada tartamudeo (disociacion y tiempo).
    -- Pitch = el tono de los sonidos reales cercanos durante el episodio, { tono, oscilacion } (Hz = su ritmo); lo hace el mod opcional
    -- SandevistanFX y se multiplica con el de la dilatacion. Con «menos destellos»: sin Split ni Tear, y Wobble y Shake por LessFlashes.
    -- (183) La sacudida corre la imagen del mundo entera (no la camara: el clic y el apuntado no se mueven).
    -- (185) In3D: tambien con la camara 3D de Viewpoint (su imagen pasa a la pantalla por el mismo camino que la isometrica; en prueba).
    -- Shake3DMult: la sacudida en 3D (en primera persona marea mas).
    ScreenFX = { Enabled = true, In3D = true, Shake3DMult = 0.5,
                 Shake = { Enabled = true, Blackout = { 7, 650 }, Fury = { 10, 700 }, Overload = { 14, 900 }, Scare = { 9, 500 }, Touch = { 4, 280 } },
                 Screen = { Enabled = true,
                            Paranoia = { Desat = 0.35, Wobble = 0.12, Blur = 0, Split = 0.2, Tear = 0 },
                            Dissociation = { Desat = 0.55, Wobble = 0.4, Blur = 0.12, Split = 0.45, Tear = 0.35 },
                            Burst = { Desat = 0.6, Wobble = 0.5, Blur = 0.2, Split = 1, Tear = 1 } },
                 Pitch = { Enabled = true, Paranoia = { 0.95, 0.025 }, Dissociation = { 0.9, 0.05 }, Hz = 0.3 } },
    -- (138) Texto corrupto (lo hace el mod opcional SandevistanPsychosis): con cyberpsicosis activa, de a ratos las letras de todo el texto del juego se
    -- cambian por simbolos durante Seconds. Amount = parte de las letras cambiadas { a CN 60, a CN 100 }. Tambien acompaña al tartamudeo del tiempo
    -- (OnTimeGlitch), al negro de un apagon (OnBlackout) y al contacto de un zombi falso (OnFakeZombie).
    TextGlitch = { Enabled = true, MinStage = 2, FirstDelaySeconds = 40, EverySeconds = { 70, 220 }, Seconds = { 0.5, 1.4 }, Amount = { 0.12, 0.45 },
                   OnTimeGlitch = 0.35, OnBlackout = 0.6, OnFakeZombie = 0.5 },
    -- (191) MENSAJES ALUCINADOS: de vez en cuando, en lugar de símbolos, el texto se "ordena" en una frase corta y coherente durante
    -- Seconds. Es local, no reemplaza la UI ni va al chat. Chance por episodio de texto, con cooldown; necesita el texto corrupto y
    -- «Alucinaciones». Las frases están en IGUI_Sandevistan_PsyMessage1..Count (EN/AR/ES/RU).
    Messages = { Enabled = true, MinStage = 2, FirstDelaySeconds = 120, Chance = 0.04, CooldownSeconds = 600, Seconds = 2.2, Count = 8 },
    -- (174) C03: el disfraz como episodio (Disguise.lua, lo dibuja el mod opcional SandevistanPsychosis; 29 §4.1 y §4.3). En etapa MinStage, raro: por
    -- Seconds, hasta MaxZombies zombis reales a la vista (a Range casillas y a mas de MinDist) se ven como personas, o hasta MaxPlayers jugadores se
    -- ven como zombis (con PlayerChance si hay alguno y Players lo permite: "never", "nopvp" = solo con el PvP del servidor apagado, "always";
    -- opcion de sandbox PsychosisDisguise). Jugadores: nivel B (LevelB: titere zombi en su lugar) o, si no se puede, nivel A (piel podrida Rot).
    -- EverySeconds = { a CN 100, a CN de la etapa 3 }; RetrySeconds sin nadie a la vista. TellChance/TellMs = el salto de imagen (la pista).
    -- MoveSpeed/RunSpeed (casillas por segundo) = cuando el titere camina o corre; si el juego dice que se mueve alcanza con MinSpeed (174b: sin
    -- desplazarse no camina, aunque el juego lo diga); MoveHoldMs = cuanto se sostiene. (187) RunSpeed solo de respaldo, si no se
    -- puede preguntar si corre. LevelBGraceMs = sin titere a la vista ese tiempo, pasa a nivel A. (186) LevelB3D: el nivel B tambien con la
    -- camara 3D de Viewpoint (necesita el mod SandevistanViewpoint, que esconde al real en su dibujo y pone el titere); sin el, a los
    -- LevelBGraceMs pasa a nivel A como siempre.
    Disguise = { Enabled = true, Players = "nopvp", MinStage = 3, FirstDelaySeconds = 300, EverySeconds = { 600, 1500 }, RetrySeconds = 30,
                 Seconds = { 20, 40 }, Range = 12, MinDist = 3, MaxZombies = 3, MaxPlayers = 2, PlayerChance = 0.5, Rot = { 1, 3 },
                 LevelB = true, LevelB3D = true, LevelBGraceMs = 1500, TellChance = 0.08, TellMs = 160, MoveSpeed = 0.3, RunSpeed = 3.2,
                 MinSpeed = 0.05, MoveHoldMs = 300,
                 -- (188) Nivel B, jugadores: el zombi actua como zombi. Con el jugador quieto, a TurnDist casillas gira hacia el que lo ve
                 -- (TurnDegPerSec) y a ArmsDist levanta los brazos (postura de embestida); con Voice, la voz de zombi del zombi falso todo el
                 -- episodio (quieto, buscando, objetivo fijado), solo para este cliente. Al levantar los brazos, DetachChance de soltarse: el
                 -- titere deja al jugador y va hacia vos como un zombi falso (te toca o le pegas y se deshace); el real sigue oculto hasta
                 -- entonces, como mucho HoldMs, y despues su disfraz termina. PvPOnly: soltarse solo con el PvP del servidor apagado.
                 Approach = { Enabled = true, TurnDist = 5, ArmsDist = 2.5, TurnDegPerSec = 90, Voice = true, DetachChance = 0.35,
                              HoldMs = 6000, PvPOnly = true } },
    -- (175): eco de tus propios ruidos (SelfEcho.lua, 27 §6). Desde la etapa MinStage, un ruido tuyo (golpe o disparo, puerta, corrida de
    -- RunSeconds) tiene Chance de repetirse DelaySeconds despues: Chance = { etapa 1, etapa 2-3 a CN 100 } (etapa 2-3 sube con la CN), por la
    -- intensidad, con tope MaxChance. Golpes y puertas a Dist casillas a tu espalda (Volume); disparos lejos, a FarDist y en cualquier direccion
    -- (FarVolume); la corrida, RunSteps pasos cada RunStepMs que se acercan desde atras (StepVolume). Uno a la vez por CooldownSeconds, hasta
    -- MaxPending esperando. DoorRefreshMs = cada cuanto se miran las puertas al lado del jugador.
    -- (175b) El golpe melee suena con el sonido del impacto (HitSound del arma), no con el zumbido del swing, que casi no se oia; mas cerca y mas
    -- fuerte. NearDist = la distancia del eco del Debug. LogFirst = cuantos ruidos anotados se escriben en la consola (los ecos sonados, siempre).
    SelfEcho = { Enabled = true, MinStage = 1, Chance = { 0.06, 0.25 }, MaxChance = 0.6, DelaySeconds = { 5, 20 }, CooldownSeconds = 45,
                 MaxPending = 2, Dist = { 2.5, 5 }, Volume = 1.0, FarDist = { 10, 16 }, FarVolume = 1.0, NearDist = { 2, 3 },
                 RunSeconds = 2, RunSteps = { 4, 7 }, RunStepMs = 330, StepVolume = 0.9, DoorRefreshMs = 250, LogFirst = 8 },
    -- (176) C05: PRESION psicotica (26 §3 con 27 §4.1). Un multiplicador de la frecuencia de las alucinaciones (audio, texto, apagones, marcas
    -- fantasma, zombis falsos, ecos, clon, disfraz, eco de tus ruidos, glitch de pantalla y alucinaciones de la CN) que sale del contexto, no
    -- de la CN (la CN ya entra por P.intensity). Solo factores que los episodios no tocan: cansancio (stat 0..1), zombis cerca (CrowdRadius
    -- casillas, CrowdMax = el tope; nunca jugadores) y dolor (stat 0..100). Heat = 0 hasta C06 (puente Heat <-> cyberpsicosis). Los pesos se
    -- renormalizan: con los factores al tope la presion es 1. Multiplicador = 1 + presion * Strength (x1,5 al tope). Se suaviza con SmoothSeconds
    -- (sube y baja de a poco) y se recalcula cada RefreshMs; no se guarda. Mid/High = los cortes de baja/media/alta (pestana Implante); al pasar
    -- a alta el monitor avisa (una vez cada ToastCooldownSeconds). Solo con la etapa 1 o mas.
    -- (177) C05: CRISIS (Crisis.lua; 26 §4 y §5 con 27 §4.2). Con cyberpsicosis en etapa MinStage, cada EverySeconds = { a CN 100, a CN 60 }
    -- (la primera a los FirstDelaySeconds; la presion y los antidepresivos la mueven) una ANTESALA de WarnSeconds avisa el tipo que viene. Se
    -- corta con un antidepresivo (AbortOnAntidep) o quedandose sentado o dormido sin zombis a AbortZombieRadius casillas por AbortRestSeconds
    -- (ReliefStress menos de estres; la proxima en AfterAbortSeconds). Si no, el EPISODIO: Mult = cuanto mas seguido llega cada cosa (las clases
    -- de P.freqMult). Paranoia: zombis falsos, marcas fantasma, audio, ecos. Disociacion: texto y pantalla, y cada StutterEverySeconds un
    -- tartamudeo de StutterMs (glitch de pantalla y texto, y el Sandi pierde la dilatacion un instante). WarnTunnel/CascadeTunnel = tunel al
    -- final del aviso; Tunnel = el de la disociacion. ToastEverySeconds = cada cuanto el monitor repite el aviso.
    Crisis = { Enabled = true, MinStage = 2, FirstDelaySeconds = 300, EverySeconds = { 900, 2400 }, WarnSeconds = { 20, 40 },
               AbortOnAntidep = true, AbortRestSeconds = 8, AbortZombieRadius = 10, ReliefStress = 0.05, AfterAbortSeconds = 600,
               ToastEverySeconds = 10, WarnTunnel = 0.4, CascadeTunnel = 0.6, Order = { "Paranoia", "Dissociation" },
               Types = {
                 Paranoia = { Enabled = true, MinStage = 2, Weight = 1, Seconds = { 45, 75 },
                              Mult = { FakeZombies = 4, Phantoms = 4, Audio = 3, SelfEcho = 3, Echoes = 2, PhantomFigures = 3 } },   -- (181) figuras
                 Dissociation = { Enabled = true, MinStage = 2, Weight = 1, Seconds = { 30, 50 }, Tunnel = 0.15,
                                  Mult = { TextGlitch = 4, ScreenGlitch = 3, Audio = 1.5 },
                                  StutterEverySeconds = { 5, 10 }, StutterMs = { 400, 900 }, StutterText = 0.3 } } },
    Pressure = { Enabled = true, Strength = 0.5, Weights = { Fatigue = 0.35, Crowd = 0.35, Pain = 0.15, Heat = 0.15 },
                 CrowdRadius = 10, CrowdMax = 12, RefreshMs = 1000, SmoothSeconds = 6, Mid = 0.33, High = 0.66, ToastCooldownSeconds = 300 },
    -- (180) C06: PUENTE HEAT <-> CYBERPSICOSIS (27 §10). El Heat entra en la presion desde el 70 % del tope y crece en linea recta hasta
    -- el tope (peso 0,15). Despues de un colapso de Overdrive o del fin de una furia, por Hours la proxima antesala espera
    -- CrisisWaitMult (solo etapa MinStage+). Si se siente castigo doble, CrisisWaitMult se sube a 1 y queda apagado.
    Vulnerable = { Enabled = true, MinStage = 2, Hours = 0.4, CrisisWaitMult = 0.5 },
    -- (179) C05: ANCLAS DE HUMANIDAD (29 §9.1, client/Anchors.lua). Dormir en una cama Minutes seguidos, leer un libro o una revista,
    -- comer algo bueno (UnhappyChange negativo) o estar cerca de otro jugador Seconds en MP: PressureCut de presion por Hours y la
    -- proxima antesala espera CrisisMult (o se empuja PushMinutes si ya estaba agendada). Cada ancla tiene su CooldownHours.
    Anchors = { Enabled = true, PressureCut = 0.3, Hours = 1.0, CrisisMult = 1.5, PushMinutes = 10,
                Sleep = { Enabled = true, Minutes = 60, CooldownHours = 6 },
                Read = { Enabled = true, CooldownHours = 4 },
                Eat = { Enabled = true, UnhappyChange = -5, CooldownHours = 4 },
                Company = { Enabled = true, Radius = 8, Seconds = 120, CooldownHours = 6 } },
    -- (178) C05: CAJA NEGRA (26 §8, 29 §5.2.4). El implante anota solo lo que el jugador recordaria: sobrecargas (KO o furia total),
    -- cascadas evitadas, antesalas cortadas, episodios de paranoia/disociacion, apagones con negro y terrores nocturnos. Nunca audio ni
    -- glitches. Anillo de MaxEntries en d.incidents (se guarda); la pestaña Implante muestra el ultimo y cuantos hubo en Hours24.
    BlackBox = { Enabled = true, MaxEntries = 15, Hours24 = 24 },
    -- (178) C05: DESPERTAR ALUCINADO (29 §5.2.2). Al volver del KO de la sobrecarga (o del bajon de la furia total), con cyberpsicosis
    -- activa, Seconds de pico: un episodio de paranoia forzado y, una vez al empezar, el clon mirandote, FakeZombies zombis falsos, los
    -- zombis cercanos vistos como personas (disfraz, si hay) y texto corrupto fuerte. Sin el jar de SandevistanPsychosis quedan el audio,
    -- las marcas y el texto que haya.
    Wake = { Enabled = true, Seconds = { 60, 90 }, Clone = true, FakeZombies = 2, Disguise = true, TextGlitch = 0.8, TextGlitchMs = 6000 },
  },

  -- (170) C01: opcion del mod "menos destellos" (S.lessFlashes, 29 §7.1). GlitchGapMs = espera minima entre dos glitches de pantalla (sin tiras
  -- y el doble de largos, asi no hay mas de un cambio por segundo); TellStretch = el "salto" del zombi falso dura eso mas y es un bajon suave;
  -- BlackFadeIn = segundos que tarda en entrar el negro del apagon (normal 0,15).
  LessFlashes = { GlitchGapMs = 1000, TellStretch = 4, BlackFadeIn = 0.5,
                  ShakeMult = 0.5, WobbleMult = 0.5 },        -- (181) C13: sacudida y ondulacion de la pantalla mas suaves (sin copias de color ni tiras)

  Combat = { AttackSpeedBoost = true,
             MaxCombatSpeed = 2.5,             -- (134: 2,5 segun el banco de golpes; en 3,0 fallaban 6 de 9 armas) (103) tope de la velocidad ABSOLUTA del golpe (el motor deja la base entre 0.8 y 1.6); por encima el juego no registra el impacto. nil = sin tope
             -- (111) empuje y pisoton: sus animaciones tienen velocidad fija (no usan CombatSpeed). Los nodos SandevistanShove_* (tools/gen_shove_animsets.py) se eligen con la
             -- bandera Flag y su velocidad sale de VarPrefix<base*100> = base x el mismo factor que el golpe (1 + bono de ataque, con el tope MaxCombatSpeed).
             ShoveAnim = { Enabled = true, Flag = "SandevistanShove", VarPrefix = "SandevistanShv", Bases = { 0.80, 1.28 } },
             MeleeDelayBoost = true,           -- la pausa entre golpes se divide por (1 + attackBoost)
             MPHitRateGuard = true,            -- SV (117). (116) MP: cerca del limite del anti-cheat de golpes del servidor (3 por 1,2 s con un arma de un blanco) el golpe va sin bono (Combat.rateLimited)
             AttackStaminaRefund = 0.30,       -- devuelve 30% de la stamina gastada por golpe
             -- (134) daño melee con el implante encendido: el golpe saca lo del motor + base x (Mult x (RefDamage / daño medio del arma) ^ WeaponExp
             -- (acotado a WeaponMin..WeaponMax) x (1 + firmware + furia) - 1), con base = la perdida del golpe medio a media distancia sin critico
             -- (Combat.sandiBase). Mult 11: el bate (0,8-1,1) con nivel 0 mata a un zombi normal (1,8-2,1) en 3 golpes (2 con un critico); como la base
             -- crece con el nivel del arma, de un golpe desde nivel ~6.
             -- Ver Combat.vanillaLoss y tools/tests/damage.lua (golpes para matar por arma).
             Damage = { Mult = 11, RefDamage = 0.95, WeaponExp = 0.5, WeaponMin = 0.35, WeaponMax = 2.0 },
             -- critico del Sandi: con MeleeCritBonus de chance el golpe (ya multiplicado) suma x(MeleeCritDamageMultiplier - 1) mas
             MeleeCritBonus = 0.15, MeleeCritDamageMultiplier = 1.5, MeleeKnockdownBonus = 0.15,
             -- (134e) la velocidad que el tope MaxCombatSpeed descarta se convierte en daño: si el tramo pedia base x (1 + bono) y la animacion quedo en
             -- el tope, el bono del Sandi se multiplica por (pedida / tope - 1) x Efficiency + 1, hasta Max. Con Efficiency 1 el daño por segundo queda
             -- como si el golpe fuera tan rapido como pedia el tramo.
             SpeedOverflowDamage = { Enabled = true, Efficiency = 1.0, Max = 2.0 },
             EvasiveReflexRadius = 1.5 },

  NeuralLoad = {
    Max = 100, PerSecondActive = 0.15,   -- solo el tiempo de uso suma CN (x multiplicador de variante); encender no suma nada
    CyberpsychosisUseMultiplier = 2,  -- con cyberpsicosis activa la CN sube al doble de ritmo mientras se usa (sin picos al encender)
    RestHoursBeforeDecay = 1,         -- (134d) horas de juego sin usar el implante para que la CN empiece a bajar (antes 2)
    Decay = { safe = 0.5, risk = 0.25, critical = 0.1, cyberpsychosis = 0.1 },
    UseAdaptReduction = 0.25,         -- (48) la CN por uso baja hasta un 25% con la adaptacion estable (lineal con S.adaptFraction: lab 5, militar 8); reemplaza al bono de recuperacion de (46)
    ImmunoDecayMultiplier = 2.0,
    Zones = { risk = 30, critical = 60, cyberpsychosis = 80 },
    RemissionFloor = 50, HallucinationThreshold = 60,
    -- (178) C05: CICATRIZ NEURAL ACUMULATIVA (29 §5.2.3). Cada sobrecarga suma PerOverload puntos (tope Max); cada punto baja TODOS los
    -- umbrales neurales (Stage1CN, Stage3CN, las zonas de S.cnZone y HallucinationThreshold). Se recupera RecoverPerDay punto por cada
    -- RecoverHours de juego con el implante apagado. La cascada (Overload.Cascade.FromCN) y el tope de 100 no cambian.
    NeuralScar = { Enabled = true, PerOverload = 2, Max = 10, RecoverPerDay = 1, RecoverHours = 24 },
    -- v0.1.29: remisión de la cyberpsicosis. Única salida: vivir HoursWithoutImplant horas de juego sin ningún implante instalado
    -- (hay que sacárselo). Al cumplirse, la cyberpsicosis se va, la CN queda como mucho en RemissionFloor y baja normal desde ahí. Deja
    -- una cicatriz: si vuelve a usar un implante, la CN por uso sube ScarUseMult veces más rápido (para siempre). SV: CyberpsychosisRemission.
    -- Withdrawal (64): abstinencia en las primeras Hours de la remision: el estres y la fatiga suben de a poco (hasta los topes; los antidepresivos lo reducen).
    Remission = { Enabled = true, HoursWithoutImplant = 120, ScarUseMult = 1.25,
                  Withdrawal = { Hours = 48, StressPerMinute = 0.0012, StressCap = 0.5, FatiguePerMinute = 0.0006, FatigueCap = 0.6, AntidepMult = 0.5 } },
    -- (180) C08: ABSTINENCIA LEVE (27 §7, D17). Con el implante puesto, funcionando y sin desconectar, CN >= MinCN y StartHours de
    -- juego sin usarlo: el estres y la infelicidad suben despacio hasta los topes y el monitor insiste. Se va sola a las EndHours
    -- aunque la CN siga alta (y con la CN bajo MinCN). Un uso de UseSeconds o mas reinicia la cuenta (en Taller cuenta WorkUseMult).
    -- El antidepresivo la reduce a la mitad. Nunca toca la CN ni tiene moodle propio.
    Craving = { Enabled = true, MinCN = 60, StartHours = 12, EndHours = 48,
                UseSeconds = 10, WorkUseMult = 0.5,
                StressPerMinute = 0.0006, StressCap = 0.15,
                UnhappyPerMinute = 0.02, UnhappyCap = 20,
                AntidepMult = 0.5, MonitorEveryMinutes = { 20, 40 } },
    PsychosomaticHealthFloor = 0.25, PsychosomaticDamage = 2,
    HallucinationChancePerMinute = { min = 0.02, max = 0.15 }, -- interpolado CN 60 -> 100
    Hallucinations = true,                          -- SV
    -- v0.1.15: síntomas nuevos
    Glitch = { MinCN = 60,                          -- glitches de pantalla/HUD desde CN 60 (más fuertes hacia 100)
               RatePerSecond = { min = 0.12, max = 0.8 },  -- episodios por segundo real, interpolado CN 60 -> 100
               DurationMs = { 80, 220 } },
    Nosebleed = { MinCN = 60,
                  OnDeactivateChance = 0.35,          -- al apagar el implante con CN >= 60
                  OnCollapse = true, OnCollapseMinCN = 60,   -- tras el colapso por Overdrive, solo con CN >= 60 (v0.1.30: síntoma neural)
                  ChancePerMinute = { min = 0.003, max = 0.01 }, -- espontáneo, CN 60 -> 100
                  Minutes = { 10, 20 },               -- duración in-game
                  DamagePerMinute = 0.25, HealthFloor = 0.25 },
    Scream = { MinCN = 80,
               ChancePerMinute = { min = 0.01, max = 0.04 },     -- CN 80 -> 100
               Radius = 25, Panic = 30, CooldownHours = 1 },
  },

  -- Antidepresivos vanilla como tratamiento de la CN (no curan la cyberpsicosis)
  Antidepressant = {
    DurationHours = 12, CapHours = 48,
    CNDecayMultiplier = 1.5,          -- se multiplica con el x2 del inmunosupresor
    SymptomMultiplier = 0.5,          -- alucinaciones, glitches, grito y sangrado espontáneo
  },

  Rejection = {
    BaseRate = 1.4, SleepMultiplier = 0.5,
    ChronicThreshold = 60, ChronicRate = 0.3, NaturalDecay = 0.5,
    -- v0.1.29: con el implante apagado y sin carga neuronal crónica (CN < 60) el rechazo baja solo cuando la adaptación se acerca a la
    -- ideal: nada por debajo de RecoveryFromAdapt (fracción de la adaptación estable) y todo el NaturalDecay a la adaptación estable.
    -- Durmiendo se recupera SleepDecayMultiplier veces más rápido. (Con cobertura de inmunosupresores baja al ritmo completo, como antes.)
    RecoveryFromAdapt = 0.6, SleepDecayMultiplier = 1.5,
    BlockActivationAt = 75, BlockSleepAt = 75, EmergencyWakeAt = 90, ShockDamagePerHour = 3,
    Moodles = { 25, 50, 75, 90 },
    -- (107) temperatura minima del cuerpo por RECHAZO (antes por nivel del moodle, desde 50): { desde, grados }. La febricula arranca en 35 para que la
    -- temperatura del pecho avise antes de la fiebre de verdad (50); bajo 35 nada, para no vivir con la espalda caliente en la adaptacion normal.
    Fever = { { 35, 37.4 }, { 50, 37.8 }, { 75, 38.3 }, { 90, 38.8 } },
    RateMultiplier = 1.0,                           -- SV
  },

  -- (162) T09: paliativos con pastillas vanilla (30 §3.3). Frenan un poco, no bajan nada de golpe, tienen tolerancia y un tope conjunto.
  -- Se enganchan SOLO al tomarlas (ISTakePillAction): las recetas y la cirugía también gastan analgésicos y eso no cuenta.
  Stopgaps = { Enabled = true,                                    -- SV: Stopgaps
    Painkiller = { Item = "Base.Pills", Hours = 6, RejectionMult = 0.85, FeverDrop = 0.3, Diminish = 0.5 },   -- cada dosis extra en 24 h rinde la mitad
    Sleeping   = { Item = "Base.PillsSleepingTablets", Hours = 12, SleepRejectionMult = 0.35, NoNightTerrors = true, AllowSleepUpTo = 89 },
    Beta       = { Item = "Base.PillsBeta", Hours = 6, CNUseMult = 0.9, ScreamMult = 0.5, TerrorMult = 0.5 },
    Caps = { RejectionMult = 0.8, CNUseMult = 0.85 },
  },

  Immunosuppressant = {
    DurationMultiplier = 1.0,                     -- SV (v0.1.30 25): escala las horas que cubre cada dosis
    CapHours = 72,
    -- v0.1.30 (15): cada unidad (clinico, casero, herbal) trae varias dosis, como un blister/frasco medico. Cada dosis gasta un uso
    -- (el item es drenable: el juego cuenta los usos). Los items del mundo bajaron de cantidad para no triplicar el suministro total.
    Uses = 3,
    -- v0.1.26: con cobertura activa la CN por uso sube menos (reduccion por nivel).
    -- (135) dosis de choque (21-plan-inmunodepresion): apilar dosis en las ultimas WindowHours SUBE la reduccion: tier x (1 + Stack[n]) con tope Cap
    -- (clinico 50 / 65 / 75 / 80 %). Con ShockDoses o mas, la CN baja ShockDecay veces mas rapido (encima de NeuralLoad.ImmunoDecayMultiplier).
    -- Tolerancia: cada dosis extra en la ventana cubre ToleranceStep menos (minimo ToleranceFloor). Antes cada dosis extra restaba potencia (Falloff).
    NeuralUse = { clinical = 0.50, crafted = 0.35, herbal = 0.15, WindowHours = 24, Stack = { 0, 0.30, 0.50, 0.60 }, Cap = 0.80,
                  ShockDoses = 2, ShockDecay = 1.5, ToleranceStep = 0.25, ToleranceFloor = 0.25 },
    -- (135) inmunodepresion (ID 0..100): sube con cada dosis, no baja del piso del tier mientras cubre y despues baja sola. Amplifica la infeccion de las
    -- heridas, la curacion, los resfrios y el malestar (efectos: partes 2 y 3 del plan). Level = opcion de sandbox (0 apagado, 0.5 leve, 1, 1.5 dura):
    -- escala los efectos y el rebote, no el valor. Decay por hora despierto/dormido; enfermo (herida infectada, resfrio o malestar >= SickMoodle) x Sick con
    -- minimo SickMin. Rebote: si la tanda llego a Rebound.Peak, al terminar la cobertura el rechazo sube x RejectionMult durante Hours.
    Immunodepression = {
      Level = 1.0,                                    -- SV
      Gain = { clinical = 45, crafted = 30, herbal = 10 },
      Floor = { clinical = 50, crafted = 30, herbal = 10 },
      DecayAwake = 4, DecayAsleep = 6, Resilient = 1.5, Prone = 0.5,
      Sick = 0.6, SickMin = 2, SickMoodle = 2, SickStat = 50,        -- SickStat: % del tope del stat (solo si falta MoodleType.SICK)
      Rebound = { Peak = 60, Hours = 6, RejectionMult = 1.5 },
      Moodles = { 20, 40, 60, 80 },
      -- fuerza de los efectos: k = ID/100 x Level x rasgo (tope MaxStrength); efecto = 1 + (Max - 1) x k
      TraitStrength = { Resilient = 0.5, Prone = 1.5 }, HealerStrength = { Fast = 0.75, Slow = 1.25 }, MaxStrength = 2,
      Max = { infectOnset = 2.0, infectGrowth = 2.0, healing = 1.6, coldCatch = 2.0, coldStrength = 2.0, coldRecovery = 1.5, sickness = 1.5 },
      -- la tirada de infeccion del juego (BodyPart.DamageUpdate, 42.21): Rand.Next(N) == 0 cada 1/30 s; N = Base menos lo que corresponda, minimo Min.
      -- La extra (Immunodep.lua) usa la misma N con (infectOnset - 1) veces mas tiradas.
      Onset = { Base = 40000, NoBandage = 10000, DirtyBandage = 35000, Scratch = 20000, Cut = 25000, Deep = 30000, Glass = 24000, Burn = 23000,
                BurnWash = 7000, DirtyClothing = 20000, BloodyClothing = 24000, Min = 5000 },
      -- topes por minuto de lo que se suma (tambien los aplica el servidor en N.body "immuno"): nivel de infeccion, temporizadores de curacion, resfrio
      Net = { InfLevel = 0.05, Timer = 0.5, Cold = 3 },
    },
    clinical = { durationHours = 48, rateMultiplier = 0 },
    crafted  = { instantReduction = 0.50, durationHours = 24, rateMultiplier = 0,
                 FailChance = 0.10, Nausea = 15 },
    herbal   = { instantReduction = 0.25, durationHours = 8, rateMultiplier = 0.25,
                 toxicityPerDose = 25 },
    HerbalToxicity = { DecayPerHour = 2.5, Moodles = { 25, 50, 75, 90 } },
    CraftedRecipeKnown = false,                     -- SV
  },

  Kerenzikov = {
    -- (108) como en Cyberpunk 2077: la duracion es en SEGUNDOS REALES (no corre en pausa) y mientras dura no hay NADA de dolor (PainFree; vuelve al terminar)
    military = { durationSeconds = 300 },
    -- (119) el bajon del casero pasa UNA vez, al terminar el efecto: el cansancio sube a crashFatigue y la estamina baja a crashEndurance; despues la
    -- estamina se recupera sola. crashHours = cuanto queda el moodle del bajon (solo aviso). HoldsFatigue: mientras dura, el sueño que tenias queda en 0 y vuelve al final.
    crafted  = { durationSeconds = 150, crashHours = 1, crashFatigue = 0.65, crashEndurance = 0.30 },
    HoldsFatigue = true,
    PainFree = true,
    -- Mientras dura: panico y estres en 0 (CalmMind; vuelven solos al terminar) y las acciones gastan StaminaCostMult de la resistencia normal (la mitad).
    -- El gasto propio del Sandevistan no cambia: se mide despues de que el implante descuenta lo suyo.
    CalmMind = true, StaminaCostMult = 0.5, StaminaMaxDropPerTick = 0.15,
    ToleranceStep = 0.25, ToleranceFloor = 0.50, ToleranceWindowHours = 24,
    -- v0.1.29: sinergia con el Sandevistan (el Heat sube HeatGainMult veces la velocidad normal). El pulso de reflejo que empujaba a los
    -- zombis se quitó por sobrado: los beneficios del fármaco ya alcanzan.
    HeatGainMult = 0.8,
    -- v0.1.26: al tomarlo sube la resistencia. (108) Mientras dura, cada minuto de juego recupera entre 5 y 10 % de resistencia (antes regeneraba en cada tick sin esfuerzo).
    StaminaBoost = 0.5, StaminaRegenPerMinute = { 0.05, 0.10 },
    -- (107) reflejos del Black Lace, por debajo del Sandevistan: golpes x(1 + AttackBoost) (el implante da +50 % o mas) sin reintegro de estamina, y cada
    -- zombi que EMPIEZA a atacarte a GrabDodgeRadius casillas o menos tiene GrabDodgeChance de ser frenado (tropieza hacia atras) antes de agarrarte.
    -- Con el Sandevistan encendido mandan los bonos del implante (no se suman).
    AttackBoost = 0.20, GrabDodgeChance = 0.25, GrabDodgeRadius = 1.3, GrabScanMs = 100,
  },

  -- v0.1.30 (82): FIRMWARE. Chips de software con dos slots tipados (Sistema y Habilidad) que cambian como se comporta el implante. Diseno en
  -- 14-catalogo-firmware.md, plan en 15-plan-firmware.md. La logica vive en shared/Firmware.lua (perfil) y client/FirmwareClient.lua (chips, flasheo, menus).
  --   Enabled        SV FirmwareEnabled: apagado, los chips no hacen nada y no se pueden instalar
  --   AllKnown       SV FirmwareAllKnown: todos los programas conocidos desde el inicio (si no, se aprenden con el nivel de adaptacion)
  --   FlashSeconds   instalar o sacar un chip (sin PC ni cirugia). FlashRejection = rechazo que suma cada cambio; BlockAt = con este rechazo o mas no se cambia
  --   Recalibrate    tras cambiar un chip el Heat sube HeatMult veces mas durante Hours horas de juego (sin moodle)
  --   TicksPerSecond segundos -> "tiempo" de las acciones temporizadas (la dosis de inmunosupresor dura 100 y suena ~2.7 s)
  --   Programs.<Id>  slot, code (3 letras de la etiqueta, tools/chip_art.py), level (nivel de adaptacion en que se aprende), only (nil | "lab" | "military"),
  --                  ready (false = el chip existe pero su logica todavia no: no se puede instalar) y profile (campos del perfil, ver shared/Firmware.lua)
  Firmware = {
    Enabled = true, AllKnown = false,
    FlashSeconds = 10, FlashRejection = 3, BlockAt = 75,
    Recalibrate = { Hours = 1, HeatMult = 1.10 },
    TicksPerSecond = 37,
    -- (83) Movimiento (Centinela y Camara criogenica): velocidad medida por el cambio de posicion, suavizada SmoothSeconds; por debajo de StillSpeed
    -- (tiles por segundo) cuenta como quieto (apuntar o girar sin desplazarte tambien). MaxSpeed acota los saltos (teletransporte).
    Motion = { StillSpeed = 0.3, SmoothSeconds = 1.0, MaxSpeed = 8 },
    -- (83) Apogeo: cada kill con el implante encendido baja el Heat; como mucho MaxKills bajas cada WindowSeconds (si no, una horda lo apaga solo)
    KillHeat = { MaxKills = 3, WindowSeconds = 3 },
    -- (85) Escribir un programa en un chip virgen, en una computadora con corriente o con el terminal portatil. Es CODIGO: no pide Electricidad. Lo que cuenta es la costumbre con el
    -- implante: Seconds = { segundos sin costumbre, segundos con la adaptacion estable } (lineal con S.adaptFraction). El chip virgen se fabrica (receta nativa
    -- BuildFirmwareChip); el terminal NO se fabrica: se encuentra en los lugares militares (88: botin del ejercito y base). Los programas solo militares piden ademas un microchip militar. Computer = como se reconoce una computadora del mundo (prefijos del
    -- sprite o palabras del nombre/grupo del objeto): verificar con la sonda 1 de Debug (Debug -> Firmware -> Sondas). Con el terminal no hace falta corriente: gasta BatteriesPerWrite baterias.
    Write = {
      Seconds = { 60, 25 },
      DecompileFraction = 0.5,                        -- (87) decompilar un chip programado lleva esta fraccion de lo que lleva escribir (30 s sin costumbre, 12,5 s con la adaptacion estable)
      Battery = "Base.Battery", BatteriesPerWrite = 1,         -- (el terminal gasta lo mismo al decompilar)
      MilitaryChip = "Sandevistan.MilSpecChip",
      Terminal = "Sandevistan.FwTerminal",
      Computer = { SpritePrefixes = { "appliances_com_01" }, Words = { "computer", "laptop", "workstation" } },
    },
    -- (86) Taller: MODO TRABAJO. En vez de la dilatacion de combate la tecla enciende un modo suave: el mundo a World (los zombis un 25 % mas lentos; los otros jugadores no se frenan: PlayerSlowBelow), sin bonos de movimiento ni de ataque, y
    -- Heat y CN por segundo x CostMult. La CN baja con la adaptacion hasta cero en el nivel estable MIENTRAS trabajas (una accion larga en curso) y con el flujo completo (FlowSeconds seguidos
    -- trabajando; sin una accion en curso se conserva FlowGraceSeconds y despues se pierde); sin trabajar paga CostMult x (1 - IdleAdaptReduction x adaptacion). Se enfria activo a
    -- ActiveCoolFraction del ritmo de reposo. Gasta estamina x el campo stamina del perfil (0,2: trabajo liviano). Las acciones de la lista (fabricar, reparar, leer) duran ActionMult veces lo normal (ActionsEnabled = false lo apaga).
    -- Candados: (1) un zombi que te ataca o te persigue a ThreatTiles o menos suspende el modo y lo bloquea ThreatLockSeconds; (3) sin XP de adaptacion por tiempo; (4) no se enciende ni sigue
    -- con CN >= MaxCN o rechazo >= MaxRejection. (108) Se quito el corte de la "fatiga mental" (cada 30 min de trabajo, 10 de pausa).
    -- La animacion lenta de los zombis solo se pone con un factor menor a AnimBelow y el choque jugador contra jugador se saltea con un factor de PlayerSlowBelow o mas.
    Work = {
      World = 0.75, CostMult = 0.15, IdleAdaptReduction = 0.5,                -- (108) mundo x0,75 (era 0,8), Heat y CN x0,15 (era 0,28)
      FlowSeconds = 60, FlowGraceSeconds = 8, ActiveCoolFraction = 0.5,
      ThreatTiles = 4, ThreatLockSeconds = 5, ThreatCheckSeconds = 0.5,
      MaxCN = 60, MaxRejection = 50,
      AnimBelow = 0.6, PlayerSlowBelow = 0.6,
      ActionMult = 0.75, ActionsEnabled = true,                               -- (108) era 0,8
      -- clases de acciones temporizadas de 42.x (las de la lista de Umbrella: crafteo, reparar, leer, investigar; vendar, coser, entablillar y desinfectar se probaron y se sacaron en la (91))
      Actions = { "ISHandcraftAction", "ISCraftAction", "ISFixAction", "ISRepairClothing", "ISReadABook", "ISResearchRecipe" },          -- (91) vendar y curar quedaron afuera (Taller es de trabajo manual: fabricar, reparar y leer)
    },
    Slots = { "sistema", "habilidad" },
    Order = { "Compatibilidad", "Centinela", "Filtro", "CamaraCriogenica", "Reactor", "Apogeo", "Martillo", "Overclock", "Taller" },
    -- Programs.<Id>: slot, code (la etiqueta del chip), level (nivel de adaptacion en que se aprende), ready, only (nil / "lab" / "military"), profile (lo que cambia) y, opcional,
    -- (111) origin = "military": funciona en cualquier implante pero es un diseno militar: escribirlo pide un microchip militar y como chip programado solo sale en el ejercito.
    -- dossiers = true: ademas se aprende llevando encima los expedientes militares completos (CFG.Prototype07.Dossiers; v0.1.30 (87)). Tambien se aprende decompilando su chip (87).
    -- (108) Se quitaron Rafaga, Austero, Supresor, Sin limitador, Tirador y Vigilia; los que quedan se reajustaron (14-catalogo-firmware.md). (114) Se quito Sostenido.
    Programs = {
      -- Sistema: como maneja sus recursos el implante (Heat, enfriamiento, CN, rechazo, niveles)
      -- (120) tambien la ensenan los expedientes militares: el investigador la escribio en el dorso de sus papeles (Nota 9) y se la grabo al 01 (Nota 10)
      Compatibilidad = { slot = "sistema", code = "CMP", level = 4, ready = true, dossiers = true, profile = { heat = 1.1, rej = 0.75, rejEvent = 0.75, immuno = 0.75, xpPassive = 1.5 } },
      Centinela = { slot = "sistema", code = "CEN", level = 4, ready = true, profile = { centinela = { still = 0.35, walk = 1.0, run = 1.3, xpStill = 0.5 } } },
      -- (180) C08: Filtro (FLT). Baja x0,25 las alucinaciones que dependen de la vista y del oido (zombis falsos, ecos, texto, eco de tus
      -- ruidos, marcas fantasma y las de la CN) pero deja sin sentido de peligro ni aviso de Heat por sonido. El clon y el disfraz NO se filtran.
      Filtro = { slot = "sistema", code = "FLT", level = 4, ready = true, profile = { hallu = 0.25, noSense = true } },
      -- (108) Camara criogenica: enfria x1,75 con el implante apagado (cool), a cambio de Heat x1,2, ventana de Overdrive x0,8 y tope de Heat x0,8 (maxHeat).
      -- (111) En los dos implantes y se aprende en el nivel 5; se sigue encontrando en la base militar y la siguen ensenando los expedientes militares
      CamaraCriogenica = { slot = "sistema", code = "CRI", level = 5, ready = true, origin = "military", dossiers = true, profile = { heat = 1.2, window = 0.8, cool = 1.75, maxHeat = 0.8 } },
      -- (110) Reactor: la contracara de la Camara criogenica ((111) en los dos implantes). Mucha masa termica (thermalMass): la barra sigue yendo de 0 a 100 pero todo el Heat
      -- (el de uso, el enfriado y lo que baja un kill) se mueve como si fuera de 0 a 150, o sea x1/1,5; ademas enfria x0,5 con el implante apagado (recuperarse lleva
      -- el triple). Extra, "inercia": el Impulso del uso continuo sube x1,5 mas rapido y se pierde x0,5 mas lento.
      Reactor = { slot = "sistema", code = "RCT", level = 5, ready = true, profile = { thermalMass = 1.5, cool = 0.5, momentumRamp = 1.5, momentumDecay = 0.5 } },
      -- Habilidad: que te permite hacer (estilo de combate, poder, utilidad)
      Apogeo   = { slot = "habilidad", code = "APO", level = 4, ready = true, profile = { heat = 1.1, xpKill = 1.25, killHeat = 20 } },          -- (108) cada kill baja 20 de Heat (eran 8)
      Martillo = { slot = "habilidad", code = "MAR", level = 3, ready = true, profile = { ab = 0.5, dmg = 0.30, knock = 0.30, critMult = 2.0, refund = 0.33, wear = 0.5 } },
      -- (109) Overclock (ex Pacto): el implante va pasado de vueltas (por eso no hay Overdrive). "Linea roja": desde From del tope de Heat los bonos suben en linea recta hasta
      -- el tope: movimiento +Move, ataque +Attack (en las mismas unidades que el bono del Overdrive: +0,40 / +1,0) y el factor de zombis x ZombieSpeed. CN y sintomas x1,5.
      Overclock = { slot = "habilidad", code = "OVC", level = 5, ready = true, profile = { cn = 1.5, symptoms = 1.5, noOverdrive = true,
                    overclock = { From = 0.5, Move = 0.25, Attack = 0.25, ZombieSpeed = 0.8 } } },
      -- Taller: mode = "work" (ver Work arriba); sin Overdrive ni furia. (108) La activacion gasta estamina x0,2
      Taller   = { slot = "habilidad", code = "TAL", level = 5, ready = true, profile = { mode = "work", noOverdrive = true, noBerserk = true, stamina = 0.2 } },
    },
  },

  XP = {
    Table = { 100, 250, 500, 1000, 1800, 3000, 4500, 6500, 9000, 12000 },
    PerKill = 12, PerSecondActive = 2, PassivePerHour = 5,
    PassiveMaxRejection = 50, FlushSeconds = 5,
    Multiplier = 1.0,                               -- SV
  },

  Surgery = {
    guided            = { minFA = 4, chance = { { 4, 0.75 }, { 6, 0.95 } }, time = 1200 },
    blind             = { minFA = 7, chance = { { 7, 0.65 } }, time = 1800 },
    assistedHarness   = { minFA = 2, chance = { { 2, 0.80 }, { 4, 0.95 } }, time = 1000 },
    assistedNoHarness = { minFA = 4, chance = { { 4, 0.70 }, { 6, 0.90 } }, time = 1400 },
    FailDegradationExtra = 0.1,                     -- el fallo nunca pierde el implante
    -- (195) con libros por debajo de minFA: chance del minimo - ChanceLossPerLevel por nivel, con piso BookGuide.ChanceFloor o el
    -- BookChanceFloor del metodo (p. ej. guided = { ..., BookChanceFloor = 0.40 }).
    PostOpPain = 30,
    -- (194) Coser la incision: la aguja de sutura o, como al coser una herida en vanilla (HStitch), una aguja de coser (etiqueta
    -- base:sewingneedle, no se gasta) y ThreadUses usos de hilo (etiqueta base:thread). La herida de vanilla gasta 1; la incision, mas.
    ThreadUses = 3,
    -- (125) el expediente del estudiante completo (notas 16-20) ENCIMA del cirujano es el paso a paso de Leo: para un implante de laboratorio cualquier
    -- metodo pide solo First Aid MinFA. Por debajo del minimo de siempre del metodo se paga: la probabilidad sube en linea recta desde
    -- ChanceAtMinFA[metodo] (con First Aid MinFA) hasta la de siempre en el minimo del metodo, y aunque salga bien queda una herida profunda leve
    -- en la espalda (SloppyWound: sangrado y dano, a coser y vendar). A ciegas (la unica autoinstalacion sin el arnes de la base): 35 % con FA 1,
    -- +5 % por nivel hasta 65 % con FA 7. Guiada: 50 / 58 / 67 % con FA 1 / 2 / 3.
    StudentDossier = { Dossier = "student", MinFA = 1, Variants = { lab = true },
                       ChanceAtMinFA = { guided = 0.50, blind = 0.35, assistedHarness = 0.72, assistedNoHarness = 0.50 },
                       SloppyWound = { part = "Torso_Lower", bleeding = 15, damage = 20 } },
  },

  Extraction = {
    MaxDegradation = 1.8, Time = 400,
    -- (49) La calidad de la extraccion depende solo del First Aid, sin azar: el desgaste (multiplicador de Heat) baja de forma lineal desde
    -- DegradationAtFA0 con First Aid 0 hasta 1.0 (perfecto) con First Aid PerfectFA o mas. Requisito: el bisturi (sin nivel minimo).
    DegradationAtFA0 = 1.6, PerfectFA = 4,
    RemovedCorpseDegradation = 1.5,
    -- v0.1.29: extraccion TOSCA (sin bisturi): cualquier cuchillo afilado. Nunca pierde el implante; sale con DegradationExtra mas de desgaste que
    -- la limpia (segun el First Aid), tarda el doble y hay CutChance de cortarse la mano.
    -- v0.1.29: cualquier cuchillo cuenta: la lista de tipos conocidos, las etiquetas del juego (Tags: nombres de ItemTag) o un tipo cuyo nombre
    -- contiene alguna de Words (sin las ExcludeWords). Debug -> Mundo -> "Volcar cuchillos" escribe los nombres reales de 42.21.
    Crude = { Tools = { "Base.KitchenKnife", "Base.HuntingKnife", "Base.Scissors" },
              Tags = { "SHARP_KNIFE", "SCISSORS" },
              Words = { "knife", "cleaver", "machete", "scissors", "dagger", "razor", "scalpel", "shiv" },
              ExcludeWords = { "butter", "plastic", "toy", "spork" },
              DegradationExtra = 0.2, TimeMult = 2, CutChance = 0.5 },
  },

  -- (129) Project A-Life (server/Sandevistan/ALife.lua): un NPC vestido con la espalda del Sandevistan (SandevistanSpine*) deja el implante en su
  -- cadaver, que se extrae como el de un ex-sujeto. Degradation = desgaste con el que queda en el cadaver (la extraccion solo puede empeorarlo segun
  -- el First Aid): el militar, de fabrica y mantenido; el de laboratorio, un prototipo usado en la calle (por debajo del aviso de desgaste, 1.3).
  ALife = { Enabled = true,                         -- SV: ALifeImplants
            Degradation = { military = 1.0, lab = 1.15 } },

  -- v0.1.29: expedientes de notas. Cada historia tiene su carpeta: las notas sueltas se archivan en ella (se consumen) y la carpeta se
  -- lee en orden con las páginas que faltan marcadas. `notes` = numeros de nota (SandevistanNoteNN) en orden de lectura; los numeros
  -- siguen el orden cronologico. `page` y `total` se calculan solos (abajo).
  Notes = {
    Stories = {
      { id = "researcher", notes = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, dossier = "SandevistanDossierResearcher" },
      { id = "depot",      notes = { 13, 14, 15 },                            dossier = "SandevistanDossierDepot" },
      { id = "student",    notes = { 16, 17, 18, 19, 20 },                    dossier = "SandevistanDossierStudent" },
    },
    Count = 20,                                     -- notas que existen (SandevistanNote01..20)
    FileTime = 20,                                  -- ticks de la acción de archivar
    -- (106) beneficio del expediente del investigador completo (una vez armado, para siempre: S.knowsDossier): el termino de adaptacion del rechazo x0,85
    ResearcherRejectionMult = 0.85,
  },

  -- (122) la chatarra va segun el desgaste que se saca: una por cada WearPerScrap (0,1x), con ScrapRequired de minimo. Antes era 1 fija.
  Calibration = { MinFA = 4, MinElectrical = 3, ScrapRequired = 1, WearPerScrap = 0.1, Time = 900 },

  -- Explantación (cambio lab <-> militar o retirar uno destruido). Nunca pierde el implante:
  -- el fallo deja todo como estaba, con un corte en la espalda.
  Explant = {
    MinFA = 6, MinFADestroyed = 7, Time = 1500,
    chance = { { 6, 0.70 }, { 8, 0.90 } },
    DegradationExtra = 0.2,           -- el implante retirado sale con +0.2x (tope 1.8x)
    KeepXPFraction = 1.0,             -- adaptación conservada para el próximo implante: (124) toda (antes la mitad)
    KeepXPFractionDestroyed = 0.5,    -- (124) al retirar uno destruido (falla catastrofica) se conserva la mitad: la perdida es por romperlo, no por cambiarlo
    RejectionSpike = 30,              -- rechazo inicial al instalar el siguiente
    -- (194) Con los libros por debajo del minimo, la chance no baja de aca: el explante es la salida (remision), y con First Aid 0 el fallo
    -- queda en 55 % como mucho (con el piso general de BookGuide, 75 %). Sin aguja de sutura: el implante sale, la incision queda abierta.
    BookChanceFloor = 0.45,
  },

  Prototype04 = {
    Enabled = true,                                 -- SV
    -- (95) Reparar ya no sale casi gratis (eran 2 chatarras): se reemplazan las piezas quemadas (Repair.Parts, de las de Prototype06.Parts) y se gasta el estabilizador
    -- (el compuesto sintetico), mas o menos la mitad de lo que cuesta armar un P06. Si falla se pierden el compuesto y la chatarra y las piezas vuelven con FailWear de desgaste
    -- de mas (como el armado del P06); el implante nunca se pierde.
    MinElectrical = 5, MinFA = 4, ScrapRequired = 2, Time = 2400,
    Repair = { Parts = { "board", "cell" }, CompoundRequired = 1, FailWear = 0.05 },
    chance = { { 5, 0.60 }, { 7, 0.85 } },
    RepairedDegradation = 1.2, DegradationFloor = 1.2,
  },

  -- Prototipo 06: réplica por ingeniería inversa. Rinde como un 05 (variante lab);
  -- sale algo degradado según Electrical y se calibra hasta 1.0 (sin piso).
  Prototype06 = {
    Enabled = true,                                 -- SV
    Study = { MinElectrical = 4, Time = 1200, DegradationExtra = 0.1 }, -- desarmar un implante suelto
    -- v0.1.30 (24): el P06 se ensambla con TRES PARTES (placa neural, regulador termico, celda de energia), cada una con su propia receta y su
    -- propia habilidad. La calidad de cada parte depende del nivel de quien la fabrico y se guarda en el item (md.partQuality, en degradacion:
    -- menor es mejor); el implante sale con el PROMEDIO. Las partes que se encuentran en el mundo no tienen marca: valen DefaultPartQuality.
    -- v0.1.30 (61): ESPECIALIDADES. Cada parte pide UNA sola habilidad (placa y celda: Electrical; regulador: Soldadura) y el ensamblado pide solo
    -- First Aid (el "ripperdoc" que integra y despues opera): en un servidor cada uno puede subir lo suyo y pasarse las partes. La tirada del
    -- ensamblado es por First Aid. El fallo ya no quema partes (podian ser de otro jugador): se pierden los conectores y el estabilizador
    -- (el compuesto) y las partes vuelven con FailWear de desgaste de mas.
    MinFA = 4, ScrapRequired = 2, CompoundRequired = 1, Time = 2400,   -- la chatarra que queda son los conectores
    chance = { { 4, 0.50 }, { 6, 0.75 }, { 8, 0.90 } },              -- por First Aid
    -- (106) el binder de estudiante completo (notas 16-20) encima: se necesita para estudiar el P06 (como el P07 pide los militares) y suma
    -- DossierChanceBonus a la tirada del ensamblado (tope 0,98)
    Dossiers = { "student" }, DossierChanceBonus = 0.10,
    FailWear = 0.05,
    Tag = "06",
    -- v0.1.30 (68): CINCO partes, cada una con su especialidad (la dificultad se reparte en vez de apilarse en Electrical): placa y celda (Electrical),
    -- regulador (Soldadura), chasis (la carcasa y los tornillos; desde la (122) sin habilidad) y arnes (Costura: el cableado flexible que va a la columna).
    PartOrder = { "board", "regulator", "cell", "chassis", "harness" },
    Parts = {
      board     = { item = "Sandevistan.NeuralInterfaceBoard", perk = "Electricity", bonus = 0 },
      regulator = { item = "Sandevistan.ThermalRegulator",     perk = "MetalWelding", bonus = 2 },   -- soldar sube mas lento: cada nivel vale como 1 mas dos
      cell      = { item = "Sandevistan.PowerCell",            perk = "Electricity", bonus = 0 },
      chassis   = { item = "Sandevistan.ImplantChassis",       fixed = 1.0 },   -- (122) sin habilidad (Mecanica es de autos): mas materiales; no empeora el implante (con partes perfectas sigue saliendo 1.0)
      harness   = { item = "Sandevistan.NeuralLinkHarness",    perk = "Tailoring",    bonus = 0 },
    },
    PartQuality = { { 0, 1.5 }, { 4, 1.4 }, { 5, 1.35 }, { 6, 1.25 }, { 8, 1.1 }, { 10, 1.0 } },   -- degradacion que aporta una parte segun el nivel (+bonus)
    DefaultPartQuality = 1.3,
    Grades = { { 1.05, "Fine" }, { 1.2, "Good" }, { 1.35, "Standard" }, { 9, "Crude" } },        -- hasta cada valor: nombre del grado (se muestra en el item)
  },

  -- v0.1.30 (61): PROTOTIPO 07, la replica del implante MILITAR. Se aprende estudiando un militar funcional (un solo estudio) y llevando encima los dos
  -- expedientes militares COMPLETOS (investigador 10/10 y guardia del deposito 2/2): los planos de la base. Sin piso de desgaste: con los planos
  -- completos y el implante en la mano, a nivel suficiente se replica perfecto (la calidad sale de las partes). Las partes usan materiales distintos
  -- (microchip militar y refrigerante criogenico, que solo hay en la base y en depositos del ejercito) y habilidades mas altas; el estabilizador son
  -- (122) una dosis del Black Lace militar o un casero lleno entero (antes dos dosis) (militar o casero: el casero se fabrica, asi la replica no depende de las tres unidades de la base). SV: Prototype07Enabled.
  -- Nombre de pantalla: "Mark II" (Mk. II). El implante es una linea aparte de los prototipos de laboratorio; internamente se llama 07 (marca, recetas, claves).
  ProtoLabels = { ["04"] = "P04", ["06"] = "P06", ["07"] = "Mk.II" },
  -- v0.1.30 (69): NOMBRE DE LA PLACA. Los implantes que arma el jugador (P06 y Mk. II) llevan una placa con nombre que se puede cambiar desde el menu del
  -- item (afuera del cuerpo) y pide una lapicera. El nombre viaja con el implante: item (md.plateName) <-> jugador (d.plateName) en instalacion, explantacion y
  -- cirugia remota. Solo letras, numeros y unos signos, en mayusculas (el HUD usa tipografia fija y el marco tiene ancho fijo).
  Plate = { Enabled = true, MaxLength = 16, Prototypes = { ["06"] = true, ["07"] = true } },
  Prototype07 = {
    Enabled = true,
    Study = { MinElectrical = 6, Time = 1800, DegradationExtra = 0.1 },
    Dossiers = { "researcher", "depot" },           -- ids de CFG.Notes.Stories que hay que llevar completos
    MinFA = 6, ScrapRequired = 2, Time = 3000,
    -- (196) antes 40/60/80 %: con el nivel justo fallaba mas de la mitad, y con libros FA 0-4 caian todos en el piso (25 %)
    chance = { { 6, 0.55 }, { 8, 0.75 }, { 10, 0.90 } },             -- por First Aid
    FailWear = 0.05,
    Tag = "07",
    PartOrder = { "board", "regulator", "cell", "chassis", "harness" },     -- v0.1.30 (68): cinco partes, como el P06 (el pico de Electrical baja de 8 a 7)
    Parts = {
      board     = { item = "Sandevistan.MilNeuralLattice",  perk = "Electricity",  bonus = 0 },
      regulator = { item = "Sandevistan.CryoRegulator",     perk = "MetalWelding", bonus = 2 },
      cell      = { item = "Sandevistan.HighDensityCell",   perk = "Electricity",  bonus = 0 },
      chassis   = { item = "Sandevistan.MilChassis",        fixed = 1.0 },   -- (122) idem
      harness   = { item = "Sandevistan.MilLinkHarness",    perk = "Tailoring",    bonus = 0 },
    },
    PartQuality = { { 0, 1.5 }, { 4, 1.4 }, { 5, 1.35 }, { 6, 1.25 }, { 8, 1.1 }, { 10, 1.0 } },
    DefaultPartQuality = 1.3,
  },

  Crafting = {
    Time = 300,
    HerbalMinForaging = 3,
    -- v0.1.30 (15): recetas NATIVAS (craftRecipe en scripts/Sandevistan_recipes.txt; aparecen en el menu de crafteo). Nombres completos:
    Recipes = { compound = "Sandevistan.MakeSyntheticCompound", crafted = "Sandevistan.MakeHomemadeImmunosuppressant",
                herbal = "Sandevistan.MakeHerbalImmunosuppressant", kerenzikov = "Sandevistan.MakeHomemadeKerenzikov",
                proto06 = "Sandevistan.BuildPrototype06",
                board = "Sandevistan.BuildNeuralBoard", regulator = "Sandevistan.BuildThermalRegulator", cell = "Sandevistan.BuildPowerCell",
                chassis = "Sandevistan.BuildImplantChassis", harness = "Sandevistan.BuildNeuralLinkHarness",
                -- v0.1.30 (61): Prototipo 07 (militar) y los planos (se redactan sabiendo el diseno; leerlos ensena las recetas)
                proto07 = "Sandevistan.BuildPrototype07", proto07h = "Sandevistan.BuildPrototype07Homemade", chip07 = "Sandevistan.BuildMilChip",
                board07 = "Sandevistan.BuildMilLattice", regulator07 = "Sandevistan.BuildCryoRegulator", cell07 = "Sandevistan.BuildHighDensityCell",
                chassis07 = "Sandevistan.BuildMilChassis", harness07 = "Sandevistan.BuildMilLinkHarness",
                plan06 = "Sandevistan.WriteBlueprint06", plan07 = "Sandevistan.WriteBlueprint07",
                -- v0.1.30 (85): chip de firmware virgen y terminal portatil (los sabe quien tiene un implante)
                fwchip = "Sandevistan.BuildFirmwareChip" },
    -- Costos (usos de pastillas, etc.). Los usa el respaldo por menu contextual (si las recetas nativas no cargan) y tools/check_recipes.py
    -- los compara con el script. Un inmunosupresor casero (3 dosis) sale con 3 + 2 pastillas: ~1,7 por dosis (antes 7 por dosis).
    Cost = { CompoundPills = 3, CraftedPills = 2, KerenzikovPills = 1, KerenzikovVitamins = 1, AlcoholFluid = 0.1 },
    -- IDs vanilla B42 (confirmados contra la API de 42.20, salvo marcados)
    Items = {
      Painkillers = "Base.Pills",
      Caffeine = "Base.PillsVitamins",            -- verificado en 42.21: existe y la receta del Kerenzikov casero lo acepta (en el juego son las "pastillas de cafeína")
      Disinfectant = "Base.Disinfectant",
      AlcoholWipes = "Base.AlcoholWipes",
      Whiskey = "Base.Whiskey",
      Coldpack = "Base.Coldpack",
      BakingSoda = "Base.BakingSoda",
      Mortar = "Base.MortarPestle",
      MortarCeramic = "Base.CeramicMortarandPestle",
      WildGarlic = "Base.WildGarlic2",
      BlackSage = "Base.BlackSage",
      Comfrey = "Base.Comfrey",
      Suture = "Base.SutureNeedle",
      Scalpel = "Base.Scalpel",
      Mirror = "Base.Mirror",
      Screwdriver = "Base.Screwdriver",
      ElectronicsScrap = "Base.ElectronicsScrap",
      Wire = "Base.Wire", ElectricWire = "Base.ElectricWire", SmallSheetMetal = "Base.SmallSheetMetal",     -- v0.1.30 (24): partes del P06 (IDs de 42.21)
      UnusableMetal = "Base.UnusableMetal", AluminumScrap = "Base.AluminumScrap", Battery = "Base.Battery",
      Screws = "Base.Screws", LeatherStrips = "Base.LeatherStrips", Twine = "Base.Twine",   -- v0.1.30 (68): chasis y arnes (IDs vistos en las recetas de 42.21; la aguja y el hilo van por etiqueta: base:sewingneedle / thread / heavythread / twine)
      Thread = "Base.Thread",                                                          -- (194) verificado en 42.21 (drenable, etiqueta base:thread): Debug
      Needle = "Base.Needle",                                                          -- (verificado en 42.21) solo lo usan el recorrido y el Debug para darle una aguja al jugador (la receta pide la etiqueta)
      LeoBag = "Base.Bag_Schoolbag",
      Pen = "Base.Pen", BluePen = "Base.BluePen", RedPen = "Base.RedPen", Pencil = "Base.Pencil", Paper = "Base.SheetPaper2",   -- (43) planos (IDs verificados en 42.21)
      AntiDep = "Base.PillsAntiDep",
    },
  },

  ExSubjects = {
    MilitaryCount = 3, CivilExSubjectChance = 0.60,   -- SV (107: cada campus tiene siempre un ex-sujeto; esta es la chance de un SEGUNDO, ver World.fixedWanted)
    FastShamblerChance = 1.0,                         -- SV
    FastShamblerWalkType = "2",                       -- (103) marcha de "fast shambler": la animacion Zombie_Walk2 (x1,04 contra x0,80 de la marcha comun); speedMod no mueve nada en 42.21
    Respawn = true,                                   -- SV
    RespawnChance = 0.05,                             -- SV (por chequeo)
    RespawnCheckHours = 24,
    RespawnMax = 3,                                   -- SV (por zona; 0 = sin tope)
    SpawnMinDistFromPlayers = 12, SpawnOffsetMin = 4, SpawnOffsetMax = 12,
    CorpseSearchRadius = 3,
    CampusContainerImplantChance = 0.5,             -- unidad de banco 1.2x en un contenedor del campus
    -- Los ex-sujetos llevan puesta la placa 3D de la espalda para reconocerlos: Lit = con LEDs encendidos. Se aplica con
    -- addBodyVisualFromItemType (solo lo ve quien tiene al zombi cargado desde el servidor/anfitrión); además queda el marcador 2D.
    Visual3D = { Enabled = true, Lit = true,
      -- (137) cada cliente pone la placa en los cadaveres con implante (el visual del servidor no llega a los clientes) y avisa al acercarse
      CorpseScan = { Enabled = true, EveryMs = 2000, Radius = 12, Hint = true, HintDist = 2.5 } },

    ReplaceUnidentifiedAfterLoad = true,            -- repone ex-sujetos que no se reconocen tras cargar
    -- (169) T16: ex-sujetos errantes. Muy de vez en cuando, uno lejos de los campus y de la base (se escapó y quedó vagando): se genera
    -- cerca de un jugador que esté a más de MinDistFromZone de todos los anclajes, a lo sumo Max por mundo, con una tirada cada CheckHours.
    Wander = { Enabled = true, Chance = 0.15, Max = 2, CheckHours = 12, MinDistFromZone = 250,
               RadiusMin = 14, RadiusMax = 40, MilitaryChance = 0.2 },
    Outfits = { military = "ArmyCamoGreen", lab = "Student" }, -- nombres verificados en clothing.xml de 42.21
  },

  -- (155) Guía con libros (31 §3.1, T06): sin el nivel de una skill, los libros vanilla de esa skill en el inventario guían. Hace falta el
  -- libro de cada nivel que falta (vol = ceil(nivel / 2)). Penalidad por nivel que falta (gap): más tiempo y chance de fallar.
  -- shared/Sandevistan/BookGuide.lua (BG.check / BG.checkAll / BG.timeMult / BG.failChance / BG.chanceBelow).
  BookGuide = { Enabled = true,                                     -- SV: BookGuide (enum de 4 valores; ver Levels)
    Books = { Doctor = "Base.BookFirstAid", Electricity = "Base.BookElectrician",
              MetalWelding = "Base.BookMetalWelding", Tailoring = "Base.BookTailoring" },     -- + número de volumen (1..5)
    TimePerLevel = 0.25,                        -- duración × (1 + TimePerLevel × gap); el del nivel es la referencia
    FailPerLevel = 0.10, FailMax = 0.60,        -- crafteos que hoy no fallan
    RefundShare = 0.5,                          -- al fallar, vuelve esta parte de cada material consumido (T07)
    ChanceLossPerLevel = 0.08, ChanceFloor = 0.25,   -- tiradas que ya existen, por debajo del mínimo
    -- (195) cada tirada puede tener su propio piso con BookChanceFloor en su tabla (Surgery.<metodo>, Explant, Prototype04/06/07); reemplaza a
    -- ChanceFloor (no cambia con el nivel de sandbox). Sin el, vale ChanceFloor. Los crafteos que no tenian tirada usan FailPerLevel/FailMax.
    SloppyWound = true,                         -- cirugía y explante por debajo del mínimo: la herida leve del expediente (125)
    CacheMs = 500,                              -- OnTest se llama por cada ítem candidato: el resultado se guarda este tiempo (T07)
    -- (156) T07: requisitos de las recetas nativas guiables (nombre pelado -> { perk = nivel }). El script de cada una lleva
    -- OnTest = SandevistanRecipeCode.guide_<nombre> y Tooltip = Tooltip_Sandevistan_BookGuide, sin SkillRequired.
    Recipes = {
      BuildNeuralBoard = { Electricity = 5 },
      BuildThermalRegulator = { MetalWelding = 4 },
      BuildPowerCell = { Electricity = 3 },
      BuildNeuralLinkHarness = { Tailoring = 3 },
      BuildPrototype06 = { Doctor = 4 },
      BuildMilChip = { Electricity = 7 },
      BuildMilLattice = { Electricity = 7 },
      BuildCryoRegulator = { MetalWelding = 5 },
      BuildHighDensityCell = { Electricity = 6 },
      BuildMilLinkHarness = { Tailoring = 5 },
      BuildPrototype07 = { Doctor = 6 },
      BuildPrototype07Homemade = { Doctor = 6 },
      BuildFirmwareChip = { Electricity = 4 },
    },
    -- (155) D12: cuatro valores en el sandbox (Apagada / Suave / Normal / Dura). Los números de arriba son los de Normal; applySandbox
    -- copia los del elegido. Ningún preset la apaga: es el camino del jugador solo.
    Levels = {
      Suave  = { TimePerLevel = 0.15, FailPerLevel = 0.06, FailMax = 0.40, ChanceLossPerLevel = 0.05, ChanceFloor = 0.35, RefundShare = 0.75 },
      Normal = { TimePerLevel = 0.25, FailPerLevel = 0.10, FailMax = 0.60, ChanceLossPerLevel = 0.08, ChanceFloor = 0.25, RefundShare = 0.50 },
      Dura   = { TimePerLevel = 0.35, FailPerLevel = 0.14, FailMax = 0.75, ChanceLossPerLevel = 0.10, ChanceFloor = 0.15, RefundShare = 0.25 },
    },
  },

  -- Rasgos (client/Sandevistan/Traits.lua). El kit del rasgo "Instalador de callejón" se entrega una sola vez.
  Traits = { SpecialLevels = 1, SpecialXPBonus = 0.25,   -- v0.1.30 (15): +1 nivel y +25 % de XP de adaptación (x1.25 como Fast Learner; antes x1.75). Cuesta 7 (antes 5)
              -- (154) D4: los rasgos negativos se suavizaron. Rechazo al cromo x1.5 (antes 2.0: el rechazo subía +100 %, ahora +50 %) y
              -- Propenso a la ciberpsicosis x1.25 (antes 1.5: +50 %, ahora +25 %). Neuralmente inestable da 4 (antes 3; ver TraitDefs).
              ChromeRejectionMult = 1.5, PsychoNeuralMult = 1.25,
              -- v0.1.30 (15). Edgerunner (cuesta 4): +10 % de velocidad y +15 % de ataque sobre el tramo; Heat x1.25 y rechazo de cortes/colapsos x1.5.
              EdgerunnerPlayerBoost = 0.10, EdgerunnerAttackBoost = 0.15, EdgerunnerHeatMult = 1.25, EdgerunnerEventRejectionMult = 1.5,
              -- "Neuralmente inestable" (da 4): la CN baja mas lento en reposo. Ex-corpo (cuesta 4): receta de Kerenzikov y un autoinyector casero.
              UnstableDecayMult = 0.7,
              ExCorpoKit = { "Sandevistan.KerenzikovCrafted" },
              -- (137) Multijugador: el cliente le pide al servidor los rasgos del mod que eligio al crear el personaje; el servidor los repone solo a
              -- un personaje con menos de estas horas de vida y una sola vez (en una partida alojada se perdian al aparecer).
              ServerRestoreMaxHours = 1,
              -- (154) T01: el Aprendiz de ripperdoc sabe las tres recetas civiles y empieza con los libros vol. 1 de First Aid y de Electricidad.
              RipperdocKit = { "Base.BookFirstAid1", "Base.BookElectrician1" },
              -- (161) T08: el rasgo Cromado arranca con el implante puesto, 24 h de cobertura y un pack casero; este es el kit que se entrega.
              ChromedKit = { "Sandevistan.ImmunosuppressantCraftedPack" },
              -- (154) T02: el Instalador de callejón trae con qué operarse dos veces (dos agujas) y desinfectante: toallitas con alcohol (5 usos).
             Kit = { "Sandevistan.SandevistanLab", "Sandevistan.SandevistanCryoBoxEmpty",
                     "Sandevistan.ImmunosuppressantCraftedPack",
                     "Base.SutureNeedle", "Base.SutureNeedle", "Base.AlcoholWipes" } },     -- v0.1.30 (17): 1 pack de 3 dosis (antes 2 unidades de 1 dosis)

  -- Pruebas atléticas: probabilidad de anular un tropiezo/caída = adaptación relativa x GuardScale (1 = nunca falla al tope).
  -- v0.1.29: EasyClimbing = activar la opción de sandbox del mismo nombre mientras el implante esté encendido y la tirada del trepado salga bien
  -- (paredes y sogas no fallan); InjuryShield = curar las heridas NUEVAS de un trepado con tirada superada (ShieldGraceMs: margen tras terminar).
  Athletic = { GuardScale = 1.0, EasyClimbing = true, EasyClimbingInMP = false, InjuryShield = true, ShieldGraceMs = 2500 },

  -- Sonidos placeholder (tools/gen_sounds.py). HeatWarnAt: Heat al que suena el aviso.
  Sound = { Enabled = true, HeatWarnAt = 80,
            NoOverlapSeconds = { SandevistanError = 3.9, SandevistanDoseImmuno = 2.7 } },   -- duración del .ogg: no se lanza otro hasta que termine el anterior

  -- Loot aleatorio en el mapa (server/Sandevistan/Loot.lua), ADEMÁS de los sets fijos de la base y los campus (World.lua): así no hace
  -- falta haber visto cada contenedor ni ir a un lugar concreto. Los pesos son los de las tablas de distribución de vanilla: la chance
  -- por tirada es peso/100 % (0.1 = muy raro; 0.25 = una vez cada ~400 tiradas). Lugares elegidos por coincidencia de nombre de la tabla.
  -- Los Sandevistan MILITARES no salen aquí: solo en las cajas criogénicas de la base y en sus ex-sujetos.
  Loot = {
    Enabled = true,
    -- (103) "Lab" a secas tambien entraba en las tablas del laboratorio de drogas (DrugLabGuns, DrugLabMoney, FridgeDrugLab...): ahora solo laboratorios de verdad.
    PartsMultiplier = 1.0,                        -- SV (v0.1.30 25): escala el peso de las partes del P06
    -- (120) Lugares medicos x8 (Black Lace y muestra): con 0.25 y 4 tiradas por estante salia en ~1 de cada 100 estantes y en las pruebas
    -- no aparecia nunca. El juego tira Rand(10000) < peso*100*multiplicadores: peso 2 seria ~8% por estante de hospital de 4 tiradas (vanilla AntibioticsBox 0.5).
    -- (120) Black Lace (3 dosis por unidad desde la 119): la mitad del peso de antes. Botin por probabilidad en lugares medicos de todo el mapa (no forzado).
    -- Los nombres se buscan como PEDAZO del nombre de la tabla: "Pharmacy" solo agarraba PharmacyCosmetics/PharmacyGlasses (el estante de remedios de la
    -- farmacia es StoreShelfMedical) y "Hospital" agarraba tachos, lavanderia y revisteros. tools/check_loot.py compara cada nombre con las tablas de 42.21.
    KerenzikovMilitary = { weight = 0.15, match = { "MedicalStorageDrugs", "MedicalClinicDrugs", "StoreShelfMedical", "HospitalRoomShelves", "HospitalRoomCounter",
                                                     "MedicalCabinet", "ArmyStorageMedical", "ArmyBunkerMedical" } },
    KerenzikovCrafted  = { weight = 0.5, match = { "MedicalStorageDrugs", "MedicalClinicDrugs", "StoreShelfMedical", "DrugShackDrugs", "DerelictHouseDrugs" } },
    KerenzikovHouse    = { weight = 0.03, match = { "BathroomCabinet", "BedroomSidetable" } },
    -- Prototipo 05 (el estudiante escondió más de uno): laboratorios y oficinas, y muy rara vez escuelas
    Implant            = { weight = 0.004, match = { "Laboratory", "SchoolLab", "TestingLab", "ClinicDrugs", "OfficeDesk", "CrateElectronics", "ElectronicStoreMisc" } },
    ImplantSchool      = { weight = 0.002, match = { "Classroom", "SchoolLocker", "Library" } },
    -- (120) El inmunosupresor ya no sale en el botin aleatorio: solo en los sets fijos de los edificios (World.lua) y por receta.
    -- Para que la receta casera no dependa de un solo edificio: muestra sintética, cuaderno de síntesis y hoja de Kerenzikov
    Compound           = { weight = 0.5, match = { "Laboratory", "SchoolLab", "TestingLab", "MedicalStorageDrugs", "MedicalClinicDrugs" } },
    -- Partes del Prototipo 06 (sin marca de calidad: valen DefaultPartQuality): electronica, laboratorios y oficinas
    Parts              = { weight = 0.03, match = { "CrateElectronics", "ElectronicStoreMisc", "Laboratory", "SchoolLab", "TestingLab", "OfficeDesk" } },
    -- v0.1.30 (61): materiales del Prototipo 07 (nombres de las tablas "Army*" verificados en 42.21)
    MilChip            = { weight = 0.006, match = { "ArmyStorageElectronics", "ArmyHangarTools", "ArmyBunkerStorage", "CrateElectronics" } },   -- muy rara: tambien se fabrica (BuildMilChip)
    -- (166) T14: el cuaderno de síntesis es el primer paso del camino solo; más común y también en los estantes de medicina
    Notebook           = { weight = 0.15, match = { "Laboratory", "SchoolLab", "TestingLab", "Classroom", "Library", "SchoolLocker",
                                                   "StoreShelfMedical", "MedicalClinicDrugs" } },
    -- (161) T10: libros de guía vanilla (First Aid y Electricista, vol. 1 y 2) en los lugares del mod: el camino del jugador solo.
    -- Ojo: el peso es por libro y por tirada; en las bibliotecas y escuelas del juego ya salen de por sí.
    Books              = { weight = 0.3, match = { "Laboratory", "SchoolLab", "TestingLab", "MedicalClinicDrugs", "OfficeDesk" },
                           items = { "Base.BookFirstAid1", "Base.BookFirstAid2", "Base.BookElectrician1", "Base.BookElectrician2" } },
    KerenzikovNotes    = { weight = 0.05, match = { "Laboratory", "SchoolLab", "TestingLab", "OfficeDesk", "MedicalStorageDrugs" } },
    -- Notas de lore: estudiantes (16-20) y militares (1-15)
    Notes              = { weight = 0.05, match = { "OfficeDesk", "DeskGeneric", "Locker", "ClassroomDesk", "Library" } },
    MilitaryNotes      = { weight = 0.03, match = { "OfficeDesk", "DeskGeneric", "Locker" } },
    -- (85) chip de firmware virgen: electronica, laboratorios y oficinas (muy poco; tambien se fabrica con Electricidad 4)
    FwBlank            = { weight = 0.02, match = { "CrateElectronics", "ElectronicStoreMisc", "Laboratory", "SchoolLab", "TestingLab", "OfficeDesk" } },
    -- (87) chips de firmware ya programados, un peso por programa (mas raros que el virgen en conjunto): laboratorios y oficinas traen los programas que corren en cualquier hardware o en el
    -- de laboratorio; los depositos del ejercito, los que corren en cualquier hardware o en el militar (los nombres "Army*" de 42.21 no estan verificados: el reporte cuenta las entradas)
    FwProgrammedCivil  = { weight = 0.0007, match = { "CrateElectronics", "ElectronicStoreMisc", "Laboratory", "SchoolLab", "TestingLab", "OfficeDesk" } },
    FwTerminal         = { weight = 0.02, match = { "ArmyStorageElectronics", "ArmyHangarTools", "ArmyBunkerStorage", "ArmyBunkerLockers" } },        -- (88) terminal de grabacion: solo en lugares militares
    FwProgrammedArmy   = { weight = 0.003,  match = { "ArmyStorageElectronics", "ArmyHangarTools", "ArmyBunkerStorage", "ArmyBunkerLockers" } },   -- nombres de 42.21 verificados con el REPORTE (la cocina y la enfermeria del bunker no)
  },

  World = {
    MilitaryCryoBoxCount = 2,                         -- SV (1–2)
    LabCampus = "all",                                -- SV: all | random | lsu | ekron
    SyntheticCompoundCount = { 3, 4 },                -- por campus (v0.1.30 (95): +1 a pedido del usuario; antes { 2, 3 })
    MilChipCount = 2,                              -- (43) microchips militares en la base (ademas del botin muy raro y de la receta BuildMilChip)
    -- (87) chips de firmware ya programados en la base militar: uno de cada programa de `fixed` (la Camara criogenica, al fondo junto a las cajas criogenicas) y `random.count`
    -- distintos sacados de `random.pool` (en cualquier oficina, laboratorio o deposito). Solo con el firmware prendido.
    FwBaseTerminals = 1,                            -- (88) terminales de grabacion de firmware en la base militar (el terminal no se fabrica)
    FwBaseChips = { fixed = { "CamaraCriogenica" }, random = { count = 2, pool = { "Centinela", "Martillo", "Apogeo", "Overclock", "Compatibilidad", "Reactor" } } },
    ClinicalCount = 5, KerenzikovMilitaryCount = 2,       -- inmunosupresores clinicos de 3 dosis en la base militar; v0.1.30 (95): 5 (antes 2: eran pocos para el tamano de la base)
                                                          -- (120) Black Lace: 2 autoinyectores de 3 dosis (antes 3 de una)
    BaseDeepMaxZ = -13,                               -- ala de investigación subterránea de la base: plantas <= -13 (notas 1-9 repartidas ahí)
    LeoBagImmunoCount = 2,                            -- inmunosupresores caseros en el bolso de Leo de cada campus (v0.1.30 (15): 1 unidad de 3 dosis = las 3 de antes)
  },

  -- Anclas de mapa (registradas en juego, 42.20). El contenido se reparte buscando
  -- habitaciones por nombre alrededor del ancla (scanRadius, niveles zMin..zMax).
  PlacementTriggerDistance = 30,    -- el set se coloca cuando un jugador está a esta distancia
  RoomKeywords = {
    lab = { "lab", "science", "research", "chem", "biology", "experiment" },
    medical = { "medic", "clinic", "infirm", "hospital", "doctor", "pharm", "nurse", "surgery", "firstaid" },
    storage = { "storage", "store", "warehouse", "janitor", "garage", "workshop", "mechanic",
                "maintenance", "utility", "tool", "supply", "boiler", "basement" },
    office = { "office", "admin", "class", "library", "study", "security", "reception", "meeting", "lecture" },
  },
  Locations = {
    base = { name = "Military Research Facility", anchor = { x = 5574, y = 12482, z = 0 },
             -- v0.1.29: la auditoría mostró el complejo cortado por el borde (oeste, norte y planta -15; luego este y norte con radio 70): caja ampliada
             scanRadius = 70, scanExtent = { w = 70, e = 120, n = 120, s = 70 }, zMin = -20, zMax = 2 },
  },
  Campuses = {
    lsu   = { name = "Louisville State University", anchor = { x = 12406, y = 2149, z = 0 },
              scanRadius = 40, scanExtent = { w = 80, e = 80 }, zMin = -3, zMax = 9,
              bagAt = { x = 12407, y = 2143, z = 5 } },   -- (94) casilla del bolso de Leo (dada por el usuario): con la regla de "la planta mas alta" caia en el aire
    ekron = { name = "Ekron Community College",  anchor = { x = 765, y = 9841, z = 0 },
              scanRadius = 40, scanExtent = { w = 80, e = 80, s = 80 }, zMin = -3, zMax = 6 },
  },
}

local CFG = SandevistanConfig

-- (120) por historia: page[n] = pagina de la nota n, total = paginas. Todo el codigo de los expedientes usa esto (no rangos).
for _, st in ipairs(CFG.Notes.Stories) do
  st.page, st.total = {}, #st.notes
  for i, n in ipairs(st.notes) do st.page[n] = i end
end

local function sv()
  return SandboxVars and SandboxVars.Sandevistan or nil
end

local LAB_CAMPUS_ENUM = { "all", "random", "lsu", "ekron" }

-- v0.1.30 (25): DIFICULTAD elegible en el sandbox (opcion enum Sandevistan.Preset). Indice 1 = Custom (se usan las opciones sueltas tal como estan);
-- del 2 al 6 el preset REEMPLAZA los valores de SandboxVars.Sandevistan que define (las mismas claves que sandbox-options.txt). Normal = los
-- valores de diseno. En multijugador lo decide el servidor (SandboxVars se sincroniza y applySandbox corre en todos).
SandevistanConfig.PresetNames = { "Custom", "Arcade", "Relaxed", "Normal", "Realistic", "Brutal" }
local PSY_ALL = { PsychosisAudio = true, PsychosisThreatVision = true, PsychosisTimeGlitch = true, PsychosisMisfire = true, PsychosisBlackouts = true,
                  PsychosisBerserk = true, PsychosisNightTerrors = true, PsychosisOverload = true,
                  PsychosisFakeZombies = true, PsychosisEchoes = true, PsychosisTextGlitch = true,       -- (138)
                  PsychosisMessages = true,                                                                  -- (191)
                  PsychosisPhantomFigures = true }                                                             -- (181) C13.2
local function preset(over, psy)
  local t = {}
  for k, v in pairs(PSY_ALL) do t[k] = v end
  for k, v in pairs(psy or {}) do t[k] = v end
  for k, v in pairs(over) do t[k] = v end
  return t
end
SandevistanConfig.Presets = {
  Arcade = preset({ CatastrophicFailureChance = 0, CyberpsychosisDeathChance = 0, RejectionRateMultiplier = 0.4, XPMultiplier = 2.0,
                    CyberpsychosisRemission = true, OverdriveHeatCap = false, Hallucinations = false, CraftedRecipeKnown = true,
                    ExSubjectRespawnChance = 0, MilitaryCryoBoxCount = 2, HeatRateMultiplier = 0.7, ImmunoDurationMultiplier = 1.5, Immunodepression = 1,
                    PartsLootMultiplier = 2.0, Prototype07Enabled = true, FirmwareAllKnown = true, BookGuide = 2 },
                  { PsychosisAudio = false, PsychosisTimeGlitch = false, PsychosisMisfire = false, PsychosisBlackouts = false,
                    PsychosisBerserk = false, PsychosisNightTerrors = false, PsychosisOverload = false }),   -- solo queda la vision de peligro
  Relaxed = preset({ CatastrophicFailureChance = 0, CyberpsychosisDeathChance = 0.005, RejectionRateMultiplier = 0.7, XPMultiplier = 1.5,
                     CyberpsychosisRemission = true, OverdriveHeatCap = true, Hallucinations = true, CraftedRecipeKnown = true,
                     ExSubjectRespawnChance = 0.03, MilitaryCryoBoxCount = 2, HeatRateMultiplier = 0.85, ImmunoDurationMultiplier = 1.25, Immunodepression = 3,
                     PartsLootMultiplier = 1.5, Prototype07Enabled = true, FirmwareAllKnown = false, BookGuide = 2 },
                   { PsychosisBlackouts = false, PsychosisMisfire = false }),
  Normal = preset({ CatastrophicFailureChance = 0, CyberpsychosisDeathChance = 0.01, RejectionRateMultiplier = 1.0, XPMultiplier = 1.0,
                    CyberpsychosisRemission = true, OverdriveHeatCap = true, Hallucinations = true, CraftedRecipeKnown = false,
                    ExSubjectRespawnChance = 0.05, MilitaryCryoBoxCount = 2, HeatRateMultiplier = 1.0, ImmunoDurationMultiplier = 1.0, Immunodepression = 3,
                    PartsLootMultiplier = 1.0, Prototype07Enabled = true, FirmwareAllKnown = false, BookGuide = 3 }),
  Realistic = preset({ CatastrophicFailureChance = 0, CyberpsychosisDeathChance = 0.03, RejectionRateMultiplier = 1.3, XPMultiplier = 0.8,
                       CyberpsychosisRemission = true, OverdriveHeatCap = true, Hallucinations = true, CraftedRecipeKnown = false,
                       ExSubjectRespawnChance = 0.08, MilitaryCryoBoxCount = 1, HeatRateMultiplier = 1.1, ImmunoDurationMultiplier = 0.85, Immunodepression = 3,
                       PartsLootMultiplier = 0.7, Prototype07Enabled = true, FirmwareAllKnown = false, BookGuide = 4 }),
  Brutal = preset({ CatastrophicFailureChance = 0, CyberpsychosisDeathChance = 0.08, RejectionRateMultiplier = 2.0, XPMultiplier = 0.6,
                    CyberpsychosisRemission = false, OverdriveHeatCap = true, Hallucinations = true, CraftedRecipeKnown = false,
                    ExSubjectRespawnChance = 0.12, MilitaryCryoBoxCount = 1, HeatRateMultiplier = 1.25, ImmunoDurationMultiplier = 0.7, Immunodepression = 4,
                    PartsLootMultiplier = 0.4, Prototype07Enabled = false, FirmwareAllKnown = false, BookGuide = 4 }),
}

-- (170) C01: INTENSIDAD de la cyberpsicosis (opcion enum Sandevistan.PsychosisIntensity, 29 §9.3). Una sola perilla para todos los sintomas,
-- aparte de la dificultad. Va ENCIMA de lo que dejaron la dificultad y las opciones sueltas: nunca prende algo que alguna de ellas apago.
--   Freq    = multiplica la frecuencia de todos los sintomas (entra en S.symptomMultiplier: zombis falsos, ecos, texto, clon, marcas fantasma,
--             apagones, terrores, audio, glitch de pantalla, alucinaciones de la CN). 0,5 = la mitad de seguido.
--   Off     = sistemas que apaga (claves de CFG.Psychosis; "Jumpscare" es el susto de los zombis falsos). AllOff = todos y las alucinaciones.
--   FakeMax = tope de zombis falsos a la vez (sin el, el de FakeZombies.Max). ScareMult = chance del susto.
-- La CN, sus costos y la sobrecarga como mecanica no cambian: Apagada saca los sintomas, no la carga. Normal = los numeros de diseno.
SandevistanConfig.PsychosisIntensityNames = { "Off", "Mild", "Normal", "Brutal" }
SandevistanConfig.PsychosisIntensity = {
  Off    = { Freq = 1, AllOff = true },
  Mild   = { Freq = 0.5, Off = { "Blackouts", "Misfire", "Jumpscare", "Disguise" }, FakeMax = 1 },
  Normal = { Freq = 1 },
  Brutal = { Freq = 1.5, FakeMax = 2, ScareMult = 2 },
}
local PSY_SYSTEMS = { "Audio", "ThreatVision", "TimeGlitch", "Misfire", "Blackouts", "Berserk", "NightTerrors", "Overload",
                      "FakeZombies", "Echoes", "TextGlitch", "Messages", "Doppelganger", "Disguise", "SelfEcho", "Pressure", "Crisis", "PhantomFigures" }
-- Los valores de diseno, tomados al cargar: lo que la intensidad apaga vuelve a esto si la opcion suelta no viene en el sandbox (o no existe,
-- como el clon y el susto), asi pasar de Leve a Normal restaura todo.
local PSY_BASE = { enabled = {}, hallu = CFG.NeuralLoad.Hallucinations, scare = CFG.Psychosis.FakeZombies.Jumpscare.Enabled,
                   scareChance = CFG.Psychosis.FakeZombies.Jumpscare.Chance, fakeMax = CFG.Psychosis.FakeZombies.Max }
for _, k in ipairs(PSY_SYSTEMS) do PSY_BASE.enabled[k] = CFG.Psychosis[k].Enabled end

function SandevistanConfig.psychosisIntensityName(idx)
  return SandevistanConfig.PsychosisIntensityNames[tonumber(idx) or 3] or "Normal"
end

-- s = el sandbox efectivo (puede ser nil): con su valor, cada sistema ya quedo como dice la opcion suelta; sin el, vuelve al de diseno.
function SandevistanConfig.applyPsychosisIntensity(idx, s)
  local P = CFG.Psychosis
  local J = P.FakeZombies.Jumpscare
  for _, k in ipairs(PSY_SYSTEMS) do
    if s == nil or s["Psychosis" .. k] == nil then P[k].Enabled = PSY_BASE.enabled[k] end
  end
  if s == nil or s.Hallucinations == nil then CFG.NeuralLoad.Hallucinations = PSY_BASE.hallu end
  J.Enabled, J.Chance, P.FakeZombies.Max = PSY_BASE.scare, PSY_BASE.scareChance, PSY_BASE.fakeMax
  local name = SandevistanConfig.psychosisIntensityName(idx)
  local lv = SandevistanConfig.PsychosisIntensity[name]
  P.Intensity, P.FreqMult = name, lv.Freq or 1
  if lv.AllOff then
    for _, k in ipairs(PSY_SYSTEMS) do P[k].Enabled = false end
    CFG.NeuralLoad.Hallucinations = false
  end
  for _, k in ipairs(lv.Off or {}) do
    local t = (k == "Jumpscare") and J or P[k]
    if t then t.Enabled = false end
  end
  if lv.FakeMax then P.FakeZombies.Max = lv.FakeMax end
  J.Chance = PSY_BASE.scareChance * (lv.ScareMult or 1)
end

-- Nombre del preset elegido en el sandbox ("Custom" si no hay sandbox o el indice es invalido).
function SandevistanConfig.presetName(s)
  s = s or sv()
  local idx = s and tonumber(s.Preset) or 1
  return SandevistanConfig.PresetNames[idx] or "Custom"
end

-- SandboxVars.Sandevistan efectivo: con un preset distinto de Custom, sus valores pisan a los sueltos (los que no define quedan como estan).
function SandevistanConfig.effectiveSandbox()
  local s = sv()
  if not s then return nil end
  local preset = SandevistanConfig.Presets[SandevistanConfig.presetName(s)]
  if not preset then return s end
  local merged = {}
  for k, v in pairs(s) do merged[k] = v end
  for k, v in pairs(preset) do merged[k] = v end
  return merged
end

function SandevistanConfig.applySandbox()
  local s = SandevistanConfig.effectiveSandbox()
  if not s then return end
  CFG.Preset = SandevistanConfig.presetName()
  local function pick(v, default) if v == nil then return default end return v end
  CFG.UseSpatialSlowInSP = pick(s.UseSpatialSlowInSP, CFG.UseSpatialSlowInSP)
  CFG.SlowAnimations.Enabled = pick(s.SlowZombieAnimations, CFG.SlowAnimations.Enabled)
  CFG.FastAnimations.Enabled = pick(s.FastPlayerAnimations, CFG.FastAnimations.Enabled)
  CFG.Combat.MPHitRateGuard = pick(s.MPHitRateGuard, CFG.Combat.MPHitRateGuard)            -- (117)
  CFG.ALife.Enabled = pick(s.ALifeImplants, CFG.ALife.Enabled)                              -- (129)
  local rad = tonumber(s.SlowRadius)
  if rad then CFG.SpatialSlow.Radius = math.max(8, math.min(30, rad)) end
  CFG.Overdrive.ChestWoundChance = pick(s.CatastrophicFailureChance, CFG.Overdrive.ChestWoundChance)
  CFG.Overdrive.Cyberpsychosis.DeathChance = pick(s.CyberpsychosisDeathChance, CFG.Overdrive.Cyberpsychosis.DeathChance)
  CFG.NeuralLoad.Hallucinations = pick(s.Hallucinations, CFG.NeuralLoad.Hallucinations)
  CFG.Rejection.RateMultiplier = pick(s.RejectionRateMultiplier, CFG.Rejection.RateMultiplier)
  CFG.Immunosuppressant.CraftedRecipeKnown = pick(s.CraftedRecipeKnown, CFG.Immunosuppressant.CraftedRecipeKnown)
  CFG.XP.Multiplier = pick(s.XPMultiplier, CFG.XP.Multiplier)
  CFG.ExSubjects.CivilExSubjectChance = pick(s.CivilExSubjectChance, CFG.ExSubjects.CivilExSubjectChance)
  CFG.ExSubjects.FastShamblerChance = pick(s.FastShamblerChance, CFG.ExSubjects.FastShamblerChance)
  CFG.ExSubjects.Respawn = pick(s.ExSubjectRespawn, CFG.ExSubjects.Respawn)
  CFG.ExSubjects.RespawnChance = pick(s.ExSubjectRespawnChance, CFG.ExSubjects.RespawnChance)
  CFG.ExSubjects.RespawnMax = pick(s.ExSubjectRespawnMax, CFG.ExSubjects.RespawnMax)
  CFG.World.MilitaryCryoBoxCount = pick(s.MilitaryCryoBoxCount, CFG.World.MilitaryCryoBoxCount)
  CFG.Prototype04.Enabled = pick(s.Prototype04Enabled, CFG.Prototype04.Enabled)
  CFG.Prototype06.Enabled = pick(s.Prototype06Enabled, CFG.Prototype06.Enabled)
  CFG.Prototype07.Enabled = pick(s.Prototype07Enabled, CFG.Prototype07.Enabled)
  local P = CFG.Psychosis
  P.Audio.Enabled = pick(s.PsychosisAudio, P.Audio.Enabled)
  P.ThreatVision.Enabled = pick(s.PsychosisThreatVision, P.ThreatVision.Enabled)
  P.TimeGlitch.Enabled = pick(s.PsychosisTimeGlitch, P.TimeGlitch.Enabled)
  P.Misfire.Enabled = pick(s.PsychosisMisfire, P.Misfire.Enabled)
  P.Blackouts.Enabled = pick(s.PsychosisBlackouts, P.Blackouts.Enabled)
  P.Berserk.Enabled = pick(s.PsychosisBerserk, P.Berserk.Enabled)
  P.Overload.Enabled = pick(s.PsychosisOverload, P.Overload.Enabled)
  CFG.Overdrive.HeatCap.Enabled = pick(s.OverdriveHeatCap, CFG.Overdrive.HeatCap.Enabled)
  CFG.NeuralLoad.Remission.Enabled = pick(s.CyberpsychosisRemission, CFG.NeuralLoad.Remission.Enabled)
  P.NightTerrors.Enabled = pick(s.PsychosisNightTerrors, P.NightTerrors.Enabled)
  P.FakeZombies.Enabled = pick(s.PsychosisFakeZombies, P.FakeZombies.Enabled)          -- (138) los tres necesitan ademas "Alucinaciones"
  P.Echoes.Enabled = pick(s.PsychosisEchoes, P.Echoes.Enabled)
  P.TextGlitch.Enabled = pick(s.PsychosisTextGlitch, P.TextGlitch.Enabled)
  P.Messages.Enabled = pick(s.PsychosisMessages, P.Messages.Enabled)                    -- (191)
  P.PhantomFigures.Enabled = pick(s.PsychosisPhantomFigures, P.PhantomFigures.Enabled)    -- (181) C13.2 (tambien pide "Alucinaciones")
  -- (174) C03: disfraz: Apagado / Solo zombis como personas / Tambien jugadores como zombis sin PvP / Tambien jugadores como zombis siempre.
  local DSV = { { false, "never" }, { true, "never" }, { true, "nopvp" }, { true, "always" } }
  local dsv = s.PsychosisDisguise and tonumber(s.PsychosisDisguise)
  if dsv and DSV[dsv] then P.Disguise.Enabled = DSV[dsv][1]; P.Disguise.Players = DSV[dsv][2] end
  SandevistanConfig.applyPsychosisIntensity(s.PsychosisIntensity, s)                  -- (170) C01: despues de las sueltas (solo apaga)
  CFG.Firearms.Enabled = pick(s.FirearmActionSpeed, CFG.Firearms.Enabled)
  CFG.Firmware.Enabled = pick(s.FirmwareEnabled, CFG.Firmware.Enabled)
  CFG.Firmware.AllKnown = pick(s.FirmwareAllKnown, CFG.Firmware.AllKnown)
  CFG.FieldGuideOnInstall = pick(s.FieldGuideOnInstall, CFG.FieldGuideOnInstall)
  CFG.HeatRateMultiplier = tonumber(s.HeatRateMultiplier) or CFG.HeatRateMultiplier
  -- (138i) Enfriamiento ambiental: Apagado / Normal / Fuerte (Fuerte sube el tope de x1,45 a x1,90; el tope conjunto no cambia).
  local ACV = { { false, 1.45 }, { true, 1.45 }, { true, 1.90 } }
  local acv = s.AmbientCooling and tonumber(s.AmbientCooling)
  if acv and ACV[acv] then CFG.AmbientCooling.Enabled = ACV[acv][1]; CFG.AmbientCooling.Max = ACV[acv][2] end
  -- (139) Deuda de estamina: Apagada / Normal (paga al apagar y castiga el sobregiro) / Suave (paga sin tropiezo ni bloqueo de esprint).
  local SDV = { { false, true }, { true, true }, { true, false } }
  local sdv = s.StaminaDebt and tonumber(s.StaminaDebt)
  if sdv and SDV[sdv] then CFG.Stamina.Deferred.Enabled = SDV[sdv][1]; CFG.Stamina.Deferred.Punish = SDV[sdv][2] end
  CFG.Stopgaps.Enabled = pick(s.Stopgaps, CFG.Stopgaps.Enabled)                                   -- (162) paliativos
  CFG.NeuralLoad.Craving.Enabled = pick(s.Craving, CFG.NeuralLoad.Craving.Enabled)                    -- (180) abstinencia leve
  CFG.Force.Enabled = pick(s.ImplantOverride, CFG.Force.Enabled)                                  -- (163) forzar el implante
  -- (155) Guía con libros: Apagada / Suave / Normal / Dura. Los números del nivel elegido pasan a los campos de BookGuide (los de arriba).
  local BGV = { false, "Suave", "Normal", "Dura" }
  local bgv = s.BookGuide and tonumber(s.BookGuide)
  if bgv and BGV[bgv] then
    CFG.BookGuide.Enabled = BGV[bgv] ~= false
    local lv = CFG.BookGuide.Levels[BGV[bgv] or "Normal"]
    if lv then for k, v in pairs(lv) do CFG.BookGuide[k] = v end end
  end
  CFG.Immunosuppressant.DurationMultiplier = tonumber(s.ImmunoDurationMultiplier) or CFG.Immunosuppressant.DurationMultiplier
  local IDLV = { 0, 0.5, 1.0, 1.5 }                                                          -- (135) Apagado / Leve / Normal / Dura
  if s.Immunodepression and IDLV[tonumber(s.Immunodepression)] then CFG.Immunosuppressant.Immunodepression.Level = IDLV[tonumber(s.Immunodepression)] end
  CFG.Loot.PartsMultiplier = tonumber(s.PartsLootMultiplier) or CFG.Loot.PartsMultiplier
  if s.LabCampus and LAB_CAMPUS_ENUM[s.LabCampus] then
    CFG.World.LabCampus = LAB_CAMPUS_ENUM[s.LabCampus]
  end
end

if Events and Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(function() SandevistanConfig.applySandbox() end) end
if Events and Events.OnGameStart then Events.OnGameStart.Add(function() SandevistanConfig.applySandbox() end) end

return SandevistanConfig
