package sandevistan.viewpoint;

import java.lang.reflect.Field;
import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

import org.lwjgl.util.vector.Matrix4f;
import zombie.core.Core;
import zombie.core.SpriteRenderer;
import zombie.core.math.PZMath;
import zombie.core.opengl.CharacterModelCamera;
import zombie.core.rendering.RenderList;
import zombie.core.rendering.ShaderParameter;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel.AnimatedModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelInstanceTextureCreator;
import zombie.core.skinnedmodel.model.ModelSlotRenderData;
import zombie.core.skinnedmodel.ModelCamera;
import zombie.core.skinnedmodel.shader.Shader;
import zombie.core.textures.TextureDraw;
import zombie.characters.IsoGameCharacter;
import zombie.iso.IsoCamera;
import zombie.iso.IsoDepthHelper;
import zombie.iso.sprite.IsoSprite;

/**
 * (136) Estelas con pose real en la camara isometrica normal: el mismo jar, sin Viewpoint (que queda solo para la camara 3D).
 * La version isometrica del mod es un extra opcional: sin el mod opcional, las estelas siguen siendo las siluetas 2D de siempre.
 *
 * Como dibuja el juego a un personaje (42.21): IsoGameCharacter.render -> IsoSprite.renderActiveModel -> SpriteRenderer.drawModel
 * arma un ModelSlotRenderData (alloc + initModel(slot) + init(slot)) con la posicion del momento y, por pieza (cuerpo, ropa, pelo),
 * una copia del esqueleto posado en coordenadas de mundo (ModelInstanceRenderData.matrixPalette, 16 floats por hueso). Cuando la
 * cola de sprites corre, TextureDraw.DrawQueued(rd) encola cada pieza con RenderList.DrawQueued; mas tarde RenderList.RenderOpaque
 * las dibuja y RenderList.Reset limpia las colas.
 *
 * (138c) EL DIBUJO DE ARRIBA ESTABA MAL ENTENDIDO y por eso las estelas isometricas nunca se vieron: en isometrico el juego NO dibuja a
 * los personajes por la cola de RenderList. IsoSprite.renderActiveModel encola dos cosas por personaje: un ModelCameraRenderData (al
 * correr pone ModelCamera.instance = CharacterModelCamera con x/y/z y el angulo del personaje) y el ModelSlotRenderData (TextureDraw
 * de tipo DrawModel: su render() -> performRenderCharacter -> CharacterModelCameraBegin -> DoPushIsoStuff en esa posicion -> por
 * pieza RenderCharacter -> Model.DrawChar -> DrawSolid -> startCharacter con inst.matrixPalette + ModelMesh.Draw). RenderList.RenderOpaque
 * solo dibuja lo que se encola con TextureDraw.DrawQueued, que no usa nadie en el juego normal y se dibuja sin la camara del personaje:
 * nuestras piezas "se dibujaban" (el log lo decia) fuera de lugar.
 *
 * Ahora cada estela se dibuja igual que un personaje: al entrar a FBORenderCell.renderMovingObjects (el pase de los personajes, donde
 * tambien se dibujan los titeres de SandevistanPsychosis, que si se ven) se arma una ranura propia (new, reutilizada) con initModel + init de la
 * ranura viva, se le pisan posicion, angulo, alfa, luz y profundidad de la casilla, cada pieza recibe la pose guardada (o se saca si no
 * estaba al guardar) y se encola un GenericDrawer que en el hilo de dibujo pone la camara en la estela y llama a rd.render(). Su
 * postRender suelta las piezas (no el postRender del juego: ese toca la lista readyModelData del personaje vivo). El color va en la luz
 * ambiente (RenderCharacter pisa el tinte de la pieza con el del modelo vivo).
 *
 * (138h) POR QUE LAS ESTELAS APARECIAN Y DESAPARECIAN (diagnostico con las trazas de la 138f en el juego real, 0.7 138f):
 *  1. Un pedido se consumia aunque la captura no guardara nada. init() corre para todos los personajes, y hay cuadros en que
 *     initModel deja modelData vacia (modelo o animacion sin terminar de armar: la columna que cambia de prenda al encender el Sandi,
 *     la ropa con texturas a medio hacer). El pedido se borraba igual y Lua seguia mostrando esa estela toda su vida: nunca se dibujaba.
 *     La traza lo delataba: "sin captura al mostrar" crecia el doble que "capturas". Ahora el pedido queda pendiente y se reintenta en
 *     los cuadros siguientes (hasta captureBudgetMs); si no se logra, se cuenta como perdido.
 *  2. valid() tiraba la estela cuando ModelManager.ModelSlot.remove estaba en true, y remove se pone en true cuando el juego saca al
 *     personaje del model manager (setSceneCulled), aunque sea por un instante. Se perdian TODAS las estelas vivas de golpe (la traza
 *     mostraba "invalidas=6" en un mismo cuadro). Ahora la ranura se vuelve a buscar en el personaje (legsSprite.modelSlot) y, mientras
 *     no haya una ranura usable, la estela se conserva sin dibujarse: solo vence por edad.
 *  3. Se guardaba readyModelData cuando tenia piezas: son las de un cuadro anterior (las que el juego dibuja mientras arma texturas).
 *     Para una estela la pose buena es la del momento, asi que se prefiere modelData y readyModelData queda de respaldo.
 *  4. Lua manda la posicion donde nacio la estela: si la captura se reintenta un cuadro despues, la estela no se corre del lugar.
 *
 * Los enganches (Patches.Iso*) son metodos publicos: su cuerpo se copia dentro de clases del juego.
 */
public final class IsoGhosts {
    // aspecto (Lua lo cambia con SandevistanVP.look, junto con las estelas 3D)
    static float tintScale = 1.5f;      // color de la estela x esto (queda sobre el color de la ropa, igual que en 3D)
    static float glow = 1.0f;           // luz minima: la estela se ve aunque este a oscuras
    static float alphaScale = 1.35f;    // (138f) opacidad x esto (tope 1): con el alfa de Lua tal cual, la estela isometrica casi no se veia
    static int maxDraws = 700;          // tope de piezas agregadas por cuadro
    static long showTimeoutMs = 300;    // una estela que Lua no muestra hace mas que esto no se dibuja
    static long maxAgeMs = 5000;        // y una que no se usa hace mas que esto se descarta (por si Lua no llama a drop)
    static long captureBudgetMs = 120;  // (138h) cuanto puede esperar un pedido a que el personaje se dibuje con piezas (unos 7 cuadros)
    static final int MAX_PENDING = 8;   // pedidos por personaje sin capturar (si no se lo dibuja, no se acumulan)

    private static final Object LOCK = new Object();

    /** Un pedido de Lua: id de la estela, posicion donde nacio (NaN si Lua no la mando) y cuando se pidio. */
    private static final class Req {
        final long id;
        final float x, y, z;
        final long ms;

        Req(long id, float x, float y, float z, long ms) {
            this.id = id;
            this.x = x;
            this.y = y;
            this.z = z;
            this.ms = ms;
        }

        boolean hasPos() { return !Float.isNaN(x) && !Float.isNaN(y) && !Float.isNaN(z); }
    }

    /** Pedidos de Lua para un personaje, a la espera de que el juego lo dibuje una vez. */
    private static final class Track {
        final ArrayList<Req> pending = new ArrayList<>();

        Req find(long id) {
            for (int i = 0; i < pending.size(); i++) if (pending.get(i).id == id) return pending.get(i);
            return null;
        }
    }

    /**
     * Una pieza de la pose guardada: identidad (para reconocerla cuadros despues), su malla y los huesos del momento.
     * (138) La malla sirve cuando el juego rearma el modelo (resetModel: la columna del Sandevistan cambia de prenda al encenderse):
     * las piezas nuevas son otras instancias de las mismas mallas, con el mismo esqueleto.
     */
    private static final class Piece {
        final ModelInstance instance;
        final Object mesh;
        final float[] palette;

        Piece(ModelInstance instance, Object mesh, float[] palette) {
            this.instance = instance;
            this.mesh = mesh;
            this.palette = palette;
        }
    }

    /** Una pose guardada. */
    private static final class Ghost {
        final long id;
        final Object character;
        ModelManager.ModelSlot slot;            // la ranura del personaje al guardar; se vuelve a buscar si el juego la recicla (138h)
        final ModelInstance body;               // el cuerpo al guardar: si cambia (otro modelo, otra ropa base), la estela ya no vale
        final ArrayList<Piece> pieces = new ArrayList<>();
        float x, y, z, angle;
        float depth;                            // targetDepth del cuerpo al guardar (sesgo de profundidad del shader)
        float ambR, ambG, ambB;
        boolean outside;
        float r = 1f, g = 1f, b = 1f, a;
        long shownMs, usedMs;
        boolean counted;                        // (138e) piezas perdidas: se cuentan una vez por estela
        final Drawer[] drawers = new Drawer[3];  // uno por estado del SpriteRenderer (como los maniquies), con su ranura propia

        Ghost(long id, Object character, ModelManager.ModelSlot slot) {
            this.id = id;
            this.character = character;
            this.slot = slot;
            this.body = slot == null ? null : slot.model;
        }

        Drawer drawer(int state) {
            if (drawers[state] == null) drawers[state] = new Drawer();
            return drawers[state];
        }
    }

    /**
     * Lo que el juego encola por personaje, en uno: la camara (ModelCameraRenderData.render) y el modelo (ModelSlotRenderData.render).
     * render() corre en el hilo de dibujo; postRender() cuando el juego termino con ese estado del SpriteRenderer.
     */
    static final class Drawer extends TextureDraw.GenericDrawer {
        final ModelSlotRenderData rd = new ModelSlotRenderData();   // propia (new) y reutilizada: nunca vuelve al pool del juego
        float x, y, z, angle;
        volatile boolean busy;                                       // encolada y sin postRender todavia

        @Override
        public void render() {
            try {
                ModelCamera cam = CharacterModelCamera.instance;
                cam.useAngle = angle;
                cam.useWorldIso = true;
                cam.x = x;
                cam.y = y;
                cam.z = z;
                cam.inVehicle = false;
                // (138f) Sin escribir profundidad: es translucida. Con profundidad tapaba lo que se dibuja despues (las sombras van despues
                // de los personajes, el pasto alrededor del jugador): se veia un hueco con la forma de la estela y un borde negro en el pasto.
                cam.depthMask = false;
                ModelCamera.instance = cam;
                // (138e) No rd.render(): su renderCharacter pasa por checkReady, que con una textura de la ropa a medio armar (sangre, suciedad,
                // la columna al encenderse) da "no lista" y, sin readyModelData, no dibuja la estela entera; y despues le pasa nuestra ranura a
                // ModelOutlines como si fuera la del jugador. Se dibuja directo, como hace renderCharacter cuando esta lista.
                fReadyFlag.setBoolean(rd, true);
                mPerform.invoke(rd);
            } catch (Throwable e) {
                renderError = e;                // en el hilo de dibujo no se toca nada mas: el proximo cuadro apaga el modo
            }
        }

        @Override
        public void postRender() {
            try {
                synchronized (LOCK) {
                    release(rd);
                }
            } catch (Throwable e) {
                note("limpieza isometrica", e);
            } finally {
                busy = false;
            }
        }
    }

    private static final IdentityHashMap<Object, Track> tracks = new IdentityHashMap<>();
    private static final LinkedHashMap<Long, Ghost> ghosts = new LinkedHashMap<>();
    /** (138h) ids con pedido vivo: para saber si un show que no encuentra la estela esta esperando captura o ya se perdio. */
    private static final java.util.HashSet<Long> pendingIds = new java.util.HashSet<>();
    /**
     * (138) Soltar una estela no libera piezas: las piezas son de sus Drawer y las suelta el postRender de cada uno, cuando el juego ya
     * no las dibuja. (Liberarlas desde Lua dejaba piezas con model=null en una cola del hilo de dibujo: el error se repetia en cada
     * cuadro y la pantalla quedaba congelada.)
     */
    private static volatile Throwable renderError;
    /** Mientras armamos una ranura propia (init) no se captura: el enganche de init es para los personajes del juego. */
    private static boolean building;
    private static Field fOutline, fFixX, fFixY, fReadyFlag, fLegsSprite, fCharSlot;
    private static java.lang.reflect.Method mPerform;

    // estado y REPORTE
    static long captures, framesDrawn;
    // (138d) diagnostico de "aparecen y al segundo muchas desaparecen": por que no se dibujo cada estela, en el log cada 2 s (tope 40 lineas)
    static long showMisses, showPending, skipHidden, skipFaded, skipBusy, skipCap, skipEmpty, skipNoSlot, expired, piecesLost, incomplete, capturedPieces;
    // (138h) pedidos de Lua: hechos, reintentados, perdidos (no se capturo a tiempo) y tirados por el tope
    static long stamps, stampsRetried, stampsLost, stampsDropped;
    private static long traceMs;
    private static int traceLines;
    static int lastGhosts, lastDraws, errors;
    static String lastError = "";
    static volatile boolean disabled;
    private static long frameNs, lastFrameNs, peakNs;

    private static volatile Boolean checked;
    static String problem = "sin comprobar";

    // trazas de una sola vez (diagnostico 136: captura/dibujo en el juego real)
    private static volatile boolean logHook, logStamp, logCapture, logShow, logShowMiss, logDrop, logDraw, logDrawHook, logNoPieces, logShader;

    /** readyModelData es privada: initModel la llena con copias para las texturas diferidas; nosotros dibujamos ya y las soltamos. */
    private static Field fReady;

    private IsoGhosts() {}

    /** true si las clases del juego que usamos siguen siendo las que conocemos y no hubo errores. */
    static boolean active() { return !disabled && check(); }

    /**
     * Comprueba una sola vez lo que usamos del juego (por reflexion): si el juego cambia algo, el modo isometrico se apaga solo y
     * status() dice por que, en vez de romper el dibujo (mismo blindaje que Access para Viewpoint).
     */
    static synchronized boolean check() {
        if (checked != null) return checked;
        try {
            Class<?> rd = ModelSlotRenderData.class;
            rd.getConstructor();                    // ranura propia (new), fuera del pool del juego: alloc trae la lista modelData sucia
            rd.getMethod("initModel", ModelManager.ModelSlot.class);
            rd.getMethod("init", ModelManager.ModelSlot.class);
            for (String f : new String[] { "character", "modelSlot", "modelData", "textureCreator", "x", "y", "z", "alpha",
                    "animPlayerAngle", "ambientR", "ambientG", "ambientB", "outside" }) rd.getField(f);
            ModelInstanceRenderData.class.getMethod("release", ModelInstanceRenderData.class);
            ModelInstanceRenderData.class.getMethod("init");
            ModelInstanceRenderData.class.getMethod("UpdateCharacter", Shader.class);
            for (String f : new String[] { "matrixPalette", "tintR", "tintG", "tintB", "hue", "properties", "parent" }) {
                ModelInstanceRenderData.class.getField(f);
            }
            fReady = ModelSlotRenderData.class.getDeclaredField("readyModelData");
            fReady.setAccessible(true);
            fOutline = ModelSlotRenderData.class.getDeclaredField("characterOutline");
            fOutline.setAccessible(true);
            fFixX = ModelSlotRenderData.class.getDeclaredField("fixJigglyModelsSquareX");
            fFixX.setAccessible(true);
            fFixY = ModelSlotRenderData.class.getDeclaredField("fixJigglyModelsSquareY");
            fFixY.setAccessible(true);
            fReadyFlag = ModelSlotRenderData.class.getDeclaredField("ready");
            fReadyFlag.setAccessible(true);
            // (138h) para volver a encontrar la ranura del personaje cuando el juego la saca y la vuelve a poner (setSceneCulled)
            fLegsSprite = IsoGameCharacter.class.getField("legsSprite");
            fCharSlot = IsoSprite.class.getField("modelSlot");
            mPerform = ModelSlotRenderData.class.getDeclaredMethod("performRenderCharacter");
            mPerform.setAccessible(true);
            ModelCamera.class.getField("depthMask");
            ModelSlotRenderData.class.getField("squareDepth");
            for (String f : new String[] { "useAngle", "useWorldIso", "x", "y", "z", "inVehicle" }) ModelCamera.class.getField(f);
            ModelCamera.class.getField("instance");
            CharacterModelCamera.class.getField("instance");
            IsoDepthHelper.class.getMethod("getSquareDepthData", int.class, int.class, float.class, float.class, float.class);
            ModelInstanceTextureCreator.class.getField("renderRefCount");
            checked = Boolean.TRUE;
            problem = "";
        } catch (Throwable e) {
            checked = Boolean.FALSE;
            problem = "el juego cambio lo que usan las estelas isometricas: " + e;
        }
        return checked;
    }

    private static void fail(String where, Throwable e) {
        lastError = where + ": " + e;
        errors++;
        System.err.println("[SandevistanVP] " + lastError);
        disabled = true;
        try {
            synchronized (LOCK) {
                ghosts.clear();                     // las piezas en vuelo las suelta el postRender de cada Drawer
                tracks.clear();
                pendingIds.clear();
            }
        } catch (Throwable ignored) {
            // la limpieza no puede volver a tumbar el cuadro del juego: el modo ya quedo apagado
        }
    }

    // --- lo que llama Lua (via SandevistanVP) ----------------------------------------------------------------------

    /** Pide guardar la pose de `character` en la proxima vez que el juego lo dibuje, como la estela `id`. */
    static void stamp(Object character, long id) {
        stamp(character, id, Float.NaN, Float.NaN, Float.NaN);
    }

    /**
     * (138h) Igual, pero con la posicion donde Lua grabo la estela: si la captura se reintenta uno o dos cuadros despues, la estela
     * queda donde nacio. Los NaN de la variante sin posicion hacen que se use la del personaje al capturar (comportamiento anterior).
     */
    static void stamp(Object character, long id, float x, float y, float z) {
        if (character == null || !active()) return;
        long now = System.currentTimeMillis();
        synchronized (LOCK) {
            Track t = tracks.get(character);
            if (t == null) {
                t = new Track();
                tracks.put(character, t);
            }
            if (t.pending.size() >= MAX_PENDING) {
                stampsDropped++;                    // el personaje no se dibuja: no se acumulan pedidos sin fin
            } else {
                t.pending.add(new Req(id, x, y, z, now));
                pendingIds.add(id);
                stamps++;
            }
        }
        if (!logStamp) {
            logStamp = true;
            System.out.println("[SandevistanVP] iso: primer pedido de estela (id=" + id + ")");
        }
    }

    /** La estela `id` se dibuja este cuadro con ese color y esa opacidad (0..1). */
    static void show(long id, float r, float g, float b, float a, long now) {
        synchronized (LOCK) {
            Ghost gh = ghosts.get(id);
            if (gh == null) {
                // (138h) distinguir "todavia no se capturo" (normal: el pedido se reintenta) de "ya no esta" (se solto o nunca existio)
                if (pendingIds.contains(id)) {
                    showPending++;
                } else {
                    showMisses++;
                }
                if (!logShowMiss) {
                    logShowMiss = true;
                    System.out.println("[SandevistanVP] iso: Lua muestra la estela " + id + " y todavia no esta guardada (pedidos="
                            + pendingIds.size() + ")");
                }
                return;
            }
            gh.r = r; gh.g = g; gh.b = b; gh.a = a;
            gh.shownMs = now; gh.usedMs = now;
            if (!logShow) {
                logShow = true;
                System.out.println("[SandevistanVP] iso: primer show (id=" + id + ", alfa=" + a + ")");
            }
        }
    }

    static void drop(long id) {
        synchronized (LOCK) {
            ghosts.remove(id);                      // sus piezas en vuelo las suelta el postRender de cada Drawer
            pendingIds.remove(id);
            for (Iterator<Map.Entry<Object, Track>> it = tracks.entrySet().iterator(); it.hasNext();) {
                Track t = it.next().getValue();     // (138h) un pedido que Lua ya no va a mostrar no se captura despues
                Req r = t.find(id);
                if (r != null) t.pending.remove(r);
                if (t.pending.isEmpty()) it.remove();   // y no queda una pista vacia por cada personaje para siempre
            }
        }
    }

    static void clear() {
        synchronized (LOCK) {
            ghosts.clear();
            tracks.clear();
            pendingIds.clear();
        }
    }

    // --- enganches (Patches.Iso*) ----------------------------------------------------------------------------------

    /** Al salir de ModelSlotRenderData.init(slot) (initModel + init): si el personaje tiene poses pedidas, las guarda. */
    public static void captureEnter(Object self) {
        if (building || disabled || !active()) return;
        if (!logHook) {
            logHook = true;
            System.out.println("[SandevistanVP] iso: enganche de captura activo (init)");
        }
        long t0 = System.nanoTime();
        try {
            ModelSlotRenderData rd = (ModelSlotRenderData) self;
            Object character = rd.character;
            if (character == null) return;
            long now = System.currentTimeMillis();
            int kept = 0;
            synchronized (LOCK) {
                Track t = tracks.get(character);
                if (t == null || t.pending.isEmpty()) return;
                for (Iterator<Req> it = t.pending.iterator(); it.hasNext();) {
                    Req req = it.next();
                    Ghost gh = keep(rd, character, req);
                    if (gh != null) {
                        it.remove();
                        pendingIds.remove(req.id);
                        ghosts.put(gh.id, gh);
                        kept++;
                        capturedPieces += gh.pieces.size();
                        if (!logCapture) {
                            logCapture = true;
                            System.out.println("[SandevistanVP] iso: primera captura (id=" + gh.id + ", piezas="
                                    + gh.pieces.size() + ")");
                        }
                    } else if (now - req.ms > captureBudgetMs) {
                        // (138h) no se logro: el personaje no se dibujo con piezas en todo el margen. Se pierde, pero se cuenta.
                        it.remove();
                        pendingIds.remove(req.id);
                        stampsLost++;
                    } else {
                        // (138h) ESTE era el bug: antes el pedido se borraba aunque no se guardara nada, y la estela nunca se dibujaba.
                        stampsRetried++;
                    }
                }
                if (t.pending.isEmpty()) tracks.remove(character);
                captures += kept;
            }
        } catch (Throwable e) {
            fail("captura isometrica", e);
        } finally {
            frameNs += System.nanoTime() - t0;
        }
    }

    /** Copia la pose del momento y la luz de la cuadra. La posicion es la que mando Lua (la de la estela), si vino. */
    private static Ghost keep(ModelSlotRenderData rd, Object character, Req req) {
        ModelManager.ModelSlot slot = rd.modelSlot;
        if (slot == null || slot.model == null) return null;   // sin ranura no se puede rearmar despues
        Ghost gh = new Ghost(req.id, character, slot);
        if (req.hasPos()) {                                     // (138h) la estela queda donde nacio, aunque la captura se demore
            gh.x = req.x; gh.y = req.y; gh.z = req.z;
        } else {
            gh.x = rd.x; gh.y = rd.y; gh.z = rd.z;
        }
        gh.angle = rd.animPlayerAngle;
        gh.depth = slot.model.targetDepth;
        gh.ambR = rd.ambientR; gh.ambG = rd.ambientG; gh.ambB = rd.ambientB;
        gh.outside = rd.outside;
        // (138h) La pose buena es la del cuadro (modelData). readyModelData son las copias de un cuadro anterior que el juego usa
        // mientras arma texturas: sirven de respaldo, pero guardarlas siempre atrasaba la pose de la estela.
        java.util.List<ModelInstanceRenderData> src = rd.modelData;
        if (src.isEmpty()) {
            java.util.List<ModelInstanceRenderData> ready = readyList(rd);
            if (ready != null) src = ready;
        }
        for (ModelInstanceRenderData inst : src) {
            if (inst.modelInstance == null || inst.model == null) continue;
            // (142) SOLO EL CUERPO: las piezas colgadas de un hueso (arma en la mano, objeto en la espalda) no se guardan. No usan la
            // paleta guardada: las rigidas van por Model.xfrm, que UpdateCharacter arma con makeBoneTransform sobre el animPlayer VIVO
            // del personaje, asi que la estela salia con el arma y las manos de AHORA (y el palo estirado entre la estela y el personaje).
            if (inst.model.isStatic) continue;                                        // modelo rigido (arma, objeto)
            if (inst.modelInstance.attachmentNameSelf != null
                    || inst.modelInstance.attachmentNameParent != null
                    || inst.modelInstance.parentBoneName != null) continue;           // colgada de un hueso
            float[] palette = copy(inst.matrixPalette);
            if (palette == null) continue;          // pieza rigida (anteojos sueltos): tampoco
            gh.pieces.add(new Piece(inst.modelInstance, inst.model, palette));
        }
        gh.usedMs = System.currentTimeMillis();
        return gh.pieces.isEmpty() ? null : gh;
    }

    /** Al entrar a FBORenderCell.renderMovingObjects (hilo principal, el pase de los personajes): encola las estelas vivas. */
    public static void drawFrame() {
        if (disabled || !active()) return;
        Throwable re = renderError;
        if (re != null) {
            renderError = null;
            fail("dibujo isometrico (hilo de dibujo)", re);
            return;
        }
        if (!logDrawHook) {
            logDrawHook = true;
            System.out.println("[SandevistanVP] iso: enganche de dibujo activo (renderMovingObjects)");
        }
        long now = System.currentTimeMillis();
        long t0 = System.nanoTime();
        try {
            int shown = 0, added = 0, state = -1;
            synchronized (LOCK) {
                for (Iterator<Map.Entry<Long, Ghost>> it = ghosts.entrySet().iterator(); it.hasNext();) {
                    Ghost gh = it.next().getValue();
                    if (now - gh.usedMs > maxAgeMs) {
                        expired++;
                        it.remove();
                        continue;
                    }
                    // (138h) La ranura del juego se recicla o se saca por un cuadro (setSceneCulled -> remove=true). Antes la estela se
                    // tiraba; ahora se vuelve a buscar la ranura del personaje y, si no hay, la estela espera (no se dibuja).
                    if (!usable(gh)) { skipNoSlot++; continue; }
                    if (now - gh.shownMs > showTimeoutMs) { skipHidden++; continue; }
                    if (gh.a <= 0.004f) { skipFaded++; continue; }
                    if (added + gh.pieces.size() > maxDraws) { skipCap++; break; }
                    if (state < 0) state = SpriteRenderer.instance.getMainStateIndex();
                    Drawer d = gh.drawer(state);
                    if (d.busy) { skipBusy++; continue; }   // ese estado todavia no termino de dibujarse
                    int before = gh.pieces.size();
                    int n = build(gh, d);
                    if (!gh.counted && n > 0) {
                        gh.counted = true;
                        if (n < before) { piecesLost += before - n; incomplete++; }
                    }
                    if (n <= 0) {
                        skipEmpty++;
                        release(d.rd);
                        if (!logNoPieces) {
                            logNoPieces = true;
                            System.out.println("[SandevistanVP] iso: estela sin piezas dibujables (capturadas=" + gh.pieces.size() + ")");
                        }
                        continue;
                    }
                    d.busy = true;
                    SpriteRenderer.instance.drawGeneric(d);
                    added += n;
                    shown++;
                }
            }
            lastGhosts = shown;
            lastDraws = added;
            trace(now, shown, added);
            if (added > 0) {
                framesDrawn++;
                if (!logDraw) {
                    logDraw = true;
                    System.out.println("[SandevistanVP] iso: primer dibujo (" + shown + " estelas, " + added + " piezas)");
                }
            }
        } catch (Throwable e) {
            fail("dibujo isometrico", e);
        } finally {
            frameNs += System.nanoTime() - t0;
            lastFrameNs = frameNs;
            if (frameNs > peakNs) peakNs = frameNs;
            frameNs = 0;
        }
    }

    /**
     * (138h) Ranura con la que se puede armar la estela: la guardada si el juego no la reciclo, o la que el personaje tenga ahora
     * (legsSprite.modelSlot) si se la sacaron y volvieron a poner. Si no hay ninguna, la estela se conserva y se reintenta el cuadro
     * siguiente: solo vence por edad. El cuerpo puede ser otro (resetModel): find lo reconoce por la malla.
     */
    private static boolean usable(Ghost gh) {
        ModelManager.ModelSlot slot = gh.slot;
        if (slot != null && slot.character == gh.character && !slot.remove && slot.model != null) return true;
        slot = currentSlot(gh.character);
        if (slot != null && slot.character == gh.character && !slot.remove && slot.model != null) {
            gh.slot = slot;
            return true;
        }
        if (!logDrop) {
            logDrop = true;
            System.out.println("[SandevistanVP] iso: estela a la espera de ranura (guardada=" + (gh.slot == null ? "null" : "ok")
                    + ", la del personaje=" + (slot == null ? "null" : "ok") + ")");
        }
        return false;
    }

    /** La ranura que el personaje tiene en este momento, sin pedirle una nueva a ModelManager (esa ruta crea ranuras y no se devuelven). */
    private static ModelManager.ModelSlot currentSlot(Object character) {
        if (fLegsSprite == null || fCharSlot == null || !(character instanceof IsoGameCharacter)) return null;
        try {
            Object sprite = fLegsSprite.get(character);
            return sprite instanceof IsoSprite ? (ModelManager.ModelSlot) fCharSlot.get(sprite) : null;
        } catch (Throwable e) {
            return null;
        }
    }

    /**
     * Arma la ranura del Drawer como el juego arma la de un personaje (initModel + init de la ranura viva) y le pone lo guardado:
     * posicion, angulo, alfa, luz (con el color de la estela), profundidad de la casilla y, por pieza, la pose. Devuelve las piezas.
     */
    private static int build(Ghost gh, Drawer d) throws Exception {
        ModelSlotRenderData rd = d.rd;
        release(rd);                                // por si un cuadro quedo sin postRender
        ModelManager.ModelSlot slot = gh.slot;
        building = true;
        try {
            rd.initModel(slot);
            rd.init(slot);
        } finally {
            building = false;
        }
        releaseReady(rd);                           // sin texturas listas no se dibuja (las copias diferidas traen la pose viva)
        rd.x = gh.x; rd.y = gh.y; rd.z = gh.z;
        rd.animPlayerAngle = gh.angle;
        rd.alpha = Math.max(0f, Math.min(1f, gh.a * alphaScale));
        float lit = light((gh.ambR + gh.ambG + gh.ambB) / 3f);
        rd.ambientR = gh.r * tintScale * lit;       // el color de la estela va en la luz: RenderCharacter pisa el tinte de la pieza
        rd.ambientG = gh.g * tintScale * lit;
        rd.ambientB = gh.b * tintScale * lit;
        rd.outside = gh.outside;
        fOutline.setBoolean(rd, false);             // sin contorno del jugador (ModelOutlines miraria esta ranura)
        rd.squareDepth = IsoDepthHelper.getSquareDepthData(PZMath.fastfloor(IsoCamera.frameState.camCharacterX),
                PZMath.fastfloor(IsoCamera.frameState.camCharacterY), gh.x + fFixX.getFloat(rd), gh.y + fFixY.getFloat(rd), gh.z).depthStart;
        int added = 0;
        used.clear();
        for (int i = rd.modelData.size() - 1; i >= 0; i--) {
            ModelInstanceRenderData inst = rd.modelData.get(i);
            Piece p = inst.model == null ? null : find(gh, inst);   // una pieza sin modelo tumba el dibujo
            if (p == null || inst.matrixPalette == null || inst.matrixPalette.capacity() < p.palette.length) {
                rd.modelData.remove(i);             // pieza que no estaba al guardar (ropa nueva, arma en mano): no se dibuja
                if (inst.modelInstance != null) ModelInstanceRenderData.release(inst);
                continue;
            }
            prepare(rd, inst, p.palette, gh.depth, gh.r, gh.g, gh.b, null);
            if (!logShader) {
                logShader = true;
                System.out.println("[SandevistanVP] iso: shader de la estela="
                        + (inst.model.effect == null ? "null" : inst.model.effect.getName() + " instanciado=" + inst.model.effect.isInstanced()));
            }
            added++;
        }
        d.x = gh.x; d.y = gh.y; d.z = gh.z;
        d.angle = gh.angle;
        return added;
    }

    /**
     * Deja una pieza lista para el pase. En isometrico los personajes van por DrawList.Draw -> DrawSingular:
     * startCharacter() sube pose, luz, tinte y alfa, y enseguida PushUniforms(inst.properties) reinicia TODOS los
     * uniforms del shader y los vuelve a llenar solo con las properties de la pieza. Si la pieza no trae properties
     * (MatrixPalette, Alpha, TintColour, targetDepth, como las deja initRenderData -> init + UpdateCharacter), la
     * paleta vuelve a su valor por defecto y las piezas salen degeneradas: el juego informa que dibujo la estela pero
     * no se ve nada. El camino instanciado de debug (zombieRenderInstanced) lee lo mismo del buffer, mas mvp.
     */
    static void prepare(ModelSlotRenderData rd, ModelInstanceRenderData inst, float[] palette, float depth,
            float r, float g, float b, org.joml.Matrix4f mvp) {
        inst.matrixPalette.clear();
        inst.matrixPalette.put(palette);
        inst.matrixPalette.flip();
        inst.tintR = r * tintScale;
        inst.tintG = g * tintScale;
        inst.tintB = b * tintScale;
        inst.hue = 0f;
        inst.ignoreLighting = false;                // (138c) el color de la estela va en la luz ambiente de la ranura (con piso Glow)
        inst.UpdateCharacter(null);                 // transform, DepthBias, UVScale, tono y tinte (1,1,1)
        // Sin inst.init(): su unica copia util es MatrixPalette (la hace setPalette) y ademas dispara renderMain()
        // (texturas de la ropa) en medio del pase.
        setPalette(inst, palette);                  // la pose capturada, en properties (es lo que de verdad sube el pase)
        inst.transformToParent(inst.parent);        // como initRenderData para las piezas hijas (ropa, pelo)
        rd.UpdateCharacter(inst.properties, true);  // AmbientColour blanco, Alpha=rd.alpha y luces del slot
        inst.properties.SetVector3("TintColour", inst.tintR, inst.tintG, inst.tintB);   // el color de la estela, sobre el (1,1,1) del pase
        inst.properties.SetFloat("targetDepth", depth);
        if (mvp != null) inst.properties.SetMatrix4("mvp", mvp).transpose();   // solo lo lee el camino instanciado de debug
    }

    private static float light(float ambient) { return Math.max(0f, Math.min(4f, Math.max(ambient, glow))); }

    /** Copia la pose guardada a la matriz que sube el camino instanciado (properties.MatrixPalette). */
    private static void setPalette(ModelInstanceRenderData inst, float[] palette) {
        ShaderParameter sp = inst.properties.GetParameter("MatrixPalette");
        Matrix4f[] arr = sp == null ? null : sp.GetMatrix4Array();
        if (arr == null) {
            arr = new Matrix4f[60];
            for (int i = 0; i < arr.length; i++) arr[i] = new Matrix4f();
            inst.properties.SetMatrix4Array("MatrixPalette", arr);
        }
        int n = Math.min(arr.length, palette.length / 16);
        for (int i = 0; i < n; i++) arr[i].load(FloatBuffer.wrap(palette, i * 16, 16));
    }

    /** Piezas ya usadas en la estela que se esta armando (para no dar dos veces la misma pose por malla). */
    private static final ArrayList<Piece> used = new ArrayList<>();

    /** La pieza guardada de esta instancia; si el juego rearmo el modelo, la de la misma malla que no se uso todavia. */
    private static Piece find(Ghost gh, ModelInstanceRenderData inst) {
        ModelInstance instance = inst.modelInstance;
        if (instance == null) return null;
        Piece byMesh = null;
        for (int i = 0; i < gh.pieces.size(); i++) {
            Piece p = gh.pieces.get(i);
            if (p.instance == instance) {
                used.add(p);
                return p;
            }
            if (byMesh == null && p.mesh != null && p.mesh == inst.model && !used.contains(p)) byMesh = p;
        }
        if (byMesh != null) used.add(byMesh);
        return byMesh;
    }

    /** Devuelve las copias del cuadro al pool de ModelInstanceRenderData (balancea el initModel de build). */
    private static void release(ModelSlotRenderData rd) {
        if (rd == null) return;
        releaseReady(rd);                           // no dibujamos por texturas diferidas: no dejamos esas copias
        try {
            ModelInstanceTextureCreator tc = rd.textureCreator;   // initModel sube su refcount; nosotros no usamos el creador
            if (tc != null) {
                if (tc.renderRefCount > 0) tc.renderRefCount--;
                rd.textureCreator = null;
            }
        } catch (Throwable e) {
            note("limpieza isometrica (creador de texturas)", e);
        }
        try {
            for (int i = 0; i < rd.modelData.size(); i++) {
                ModelInstanceRenderData inst = rd.modelData.get(i);
                if (inst == null || inst.modelInstance == null) continue;
                try {
                    ModelInstanceRenderData.release(inst);
                } catch (Throwable e) {
                    note("limpieza isometrica (pieza)", e);   // una copia que no se pudo soltar no puede tumbar el dibujo
                }
            }
        } finally {
            rd.modelData.clear();
        }
    }

    private static void note(String where, Throwable e) {
        lastError = where + ": " + e;
        errors++;
        System.err.println("[SandevistanVP] " + lastError);
    }

    @SuppressWarnings("unchecked")
    private static java.util.List<ModelInstanceRenderData> readyList(ModelSlotRenderData rd) {
        if (fReady == null) return null;
        try {
            return (java.util.List<ModelInstanceRenderData>) fReady.get(rd);
        } catch (Throwable e) {
            return null;
        }
    }

    /** Suelta las copias de readyModelData (privada) si initModel las armo. */
    @SuppressWarnings({ "unchecked", "rawtypes" })
    private static void releaseReady(ModelSlotRenderData rd) {
        if (fReady == null) return;
        ArrayList list;
        try {
            list = (ArrayList) fReady.get(rd);
        } catch (Throwable e) {
            note("limpieza isometrica (texturas diferidas)", e);
            return;
        }
        if (list == null) return;
        try {
            for (int i = 0; i < list.size(); i++) {
                Object o = list.get(i);
                if (!(o instanceof ModelInstanceRenderData)) continue;
                ModelInstanceRenderData inst = (ModelInstanceRenderData) o;
                if (inst.modelInstance == null) continue;
                try {
                    ModelInstanceRenderData.release(inst);
                } catch (Throwable e) {
                    note("limpieza isometrica (textura diferida)", e);
                }
            }
        } finally {
            list.clear();
        }
    }

    private static float[] copy(FloatBuffer b) {
        if (b == null) return null;
        int n = b.remaining();
        if (n <= 0) return null;
        float[] out = new float[n];
        b.duplicate().get(out);                     // solo avanza el duplicado
        return out;
    }

    /** (138d) Una linea cada 2 s mientras haya estelas: vivas, dibujadas y lo que se salteo desde la anterior (acumulado). */
    private static void trace(long now, int shown, int added) {
        if (traceLines >= 40 || now - traceMs < 2000 || ghosts.isEmpty()) return;
        traceMs = now;
        traceLines++;
        System.out.println("[SandevistanVP] iso traza: " + ghosts.size() + " guardadas, " + shown + " dibujadas (" + added + " piezas) | "
                + diag());
    }

    static String diag() {
        return "pedidos=" + stamps + " (reintentados=" + stampsRetried + ", perdidos=" + stampsLost + ", sin lugar=" + stampsDropped + ")"
                + " capturas=" + captures + String.format(" (%.1f piezas c/u)", captures == 0 ? 0.0 : capturedPieces / (double) captures)
                + " show sin captura=" + (showPending + showMisses) + " (esperando=" + showPending + ", ya no esta=" + showMisses + ")"
                + " | salteadas: Lua no la muestra=" + skipHidden + " alfa 0=" + skipFaded + " ocupada=" + skipBusy + " tope=" + skipCap
                + " sin piezas=" + skipEmpty + " sin ranura=" + skipNoSlot + " vencidas=" + expired
                + " incompletas=" + incomplete + " (piezas perdidas=" + piecesLost + ")";
    }

    // --- REPORTE ---------------------------------------------------------------------------------------------------

    static String stats() {
        synchronized (LOCK) {
            return "iso: " + ghosts.size() + " estelas | ultimo cuadro: " + lastGhosts + " estelas, " + lastDraws
                    + " piezas | cuadros con estelas=" + framesDrawn + ", errores=" + errors + " | " + diag()
                    + (lastError.isEmpty() ? "" : " (" + lastError + ")");
        }
    }

    /** Medidor: microsegundos de CPU de los enganches en el ultimo cuadro y el pico (para el REPORTE y PerfTest). */
    static String perf() {
        return String.format("iso: %.0f us por cuadro en los enganches (pico %.0f), estelas %d, piezas %d, errores %d",
                lastFrameNs / 1000.0, peakNs / 1000.0, lastGhosts, lastDraws, errors);
    }
}
