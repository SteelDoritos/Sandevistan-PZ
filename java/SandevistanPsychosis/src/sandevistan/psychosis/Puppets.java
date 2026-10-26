package sandevistan.psychosis;

import java.nio.FloatBuffer;
import java.util.ArrayList;
import java.util.HashMap;

import org.joml.Matrix4f;
import org.joml.Vector3f;
import org.lwjgl.opengl.GL11;

import zombie.GameTime;
import zombie.GameWindow;
import zombie.characters.IsoGameCharacter;
import zombie.core.Core;
import zombie.core.PerformanceSettings;
import zombie.core.SpriteRenderer;
import zombie.core.opengl.GLStateRenderThread;
import zombie.core.skinnedmodel.ModelCamera;
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel;
import zombie.core.skinnedmodel.advancedanimation.AnimatedModel.AnimatedModelInstanceRenderData;
import zombie.core.skinnedmodel.model.ModelOutlines;
import zombie.core.skinnedmodel.visual.HumanVisual;
import zombie.core.skinnedmodel.visual.ItemVisuals;
import zombie.core.textures.ColorInfo;
import zombie.core.textures.Texture;
import zombie.core.textures.TextureDraw;
import zombie.iso.IsoCamera;
import zombie.iso.IsoCell;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;
import zombie.iso.Vector2;
import zombie.iso.fboRenderChunk.FBORenderChunkManager;
import zombie.iso.fboRenderChunk.FBORenderShadows;
import zombie.iso.objects.ShadowParams;
import zombie.ui.UIManager;

/**
 * (138) Titeres: zombis que dibuja solo este cliente, sin entidad en el mundo (sin IA, sin red, sin partida guardada). Son las alucinaciones de la
 * cyberpsicosis (Sandevistan/FakeZombies.lua). Lua decide todo (donde nace, hacia donde va, que animacion, cuando se deshace); aca solo se dibujan.
 *
 * Mismo camino que un maniqui animado (IsoMannequin): un AnimatedModel con el AnimSet y el grupo de acciones "zombie" (las variables bMoving,
 * bLunge, bAttack... eligen la animacion como en un zombi de verdad), update() en el hilo principal, y un TextureDraw.GenericDrawer por estado del
 * SpriteRenderer que llama renderMain() al encolar y DoRenderToWorld() en el hilo de render. La camara de mundo del AnimatedModel calcula la
 * profundidad con IsoDepthHelper, asi que las paredes lo tapan como a cualquier personaje.
 *
 * Se dibujan al entrar a FBORenderCell.renderMovingObjects (el pase de los personajes, una vez por cuadro y por vista). Entre dos llamadas de Lua
 * la posicion avanza con la velocidad que mando Lua (hasta 250 ms), para que no salte con los ticks. Los modelos se reciclan (tope Max): cada uno
 * guarda instancias y texturas del juego, y crear uno por alucinacion las dejaria sueltas.
 */
public final class Puppets {
    private Puppets() {}

    public static int max = 6;
    public static volatile boolean disabled = false;
    /** (141) Contorno rojo como el de un zombi real (ModelOutlines): lo pide Lua cuando el jugador apunta y el titere esta entre sus blancos. */
    public static boolean outlines = true;
    public static String outlineError = "";
    static long outlinedFrames = 0;
    public static String problem = "";
    public static String lastError = "";
    public static long spawned = 0, drawnFrames = 0, drawn = 0, recycled = 0, renderCalls = 0, detached = 0;

    static final HashMap<Long, Puppet> live = new HashMap<>();
    static final ArrayList<Puppet> pool = new ArrayList<>();
    private static final Vector2 dir = new Vector2();

    /**
     * (138c) Variables que miran las transiciones del grupo de acciones "zombie" (media/actiongroups/zombie/*\/to_*.xml). Una condicion
     * isFalse sobre una variable que no existe NO pasa (CharacterVariableCondition: sin valor, false): un zombi real las tiene todas,
     * el titere no, y se quedaba en idle aunque bMoving fuera true (idle -> walktoward pide alerted, bPathfind, issitting, bClient... en false).
     */
    static final String[] FALSE_VARS = { "alerted", "bPathfind", "issitting", "bGetUpFromCrawl", "bClient", "bMoving", "bMovingNetwork",
            "bLunge", "bAttack", "bAttackVehicle", "isFacingTarget", "bKnockedDown", "bOnFloor", "hashitreaction", "bStaggerBack",
            "LastTargetSeen", "bStopLunging", "ZombieBiteDone", "bEatBodyTarget", "isRagdollFall", "bDead", "usePhysicHitReaction",
            "canRagdoll", "useRagdollVehicleCollision" };
    /** Persigue a alguien que ve: lunge no vuelve a idle/walktoward (bHasTarget false) y attack no vuelve a idle (bCanSeeTarget false). */
    static final String[] TRUE_VARS = { "bHasTarget", "bCanSeeTarget" };
    /** Aparece y desaparece con el cono de vision como un zombi (por segundo). */
    static float fadePerSecond = 5f;
    private static final ColorInfo ambient = new ColorInfo();
    /** (138d) Sombra como la de un zombi (IsoGameCharacter.renderShadow): se apaga sola si el juego cambia algo, sin apagar los titeres. */
    static boolean shadows = true;
    static String shadowError = "";
    private static final ShadowParams shadow = new ShadowParams(0.45f, 1.4f, 1.125f);
    private static final Vector3f forward = new Vector3f();

    static final class Puppet {
        final AnimatedModel model = new AnimatedModel();
        final Drawer[] drawers = new Drawer[3];
        final TexDrawer[] texDrawers = new TexDrawer[3];   // (150) camara 3D: arma la textura del cuerpo en el hilo de render
        long id;
        int owner;
        float x, y, z, vx, vy, fx = 1f, fy = 0f;
        long movedNs;
        float alpha = 1f, tr = 1f, tg = 1f, tb = 1f;
        float vis = 0f;                                 // (138c) 0 fuera del cono de vision, 1 a la vista
        long visNs;
        volatile boolean outline;                       // (141) el jugador lo tiene como blanco melee: se dibuja con borde rojo
        volatile float glitch;                          // (142) 0..1: se esta deshaciendo; se dibuja con separacion de color
        volatile float glitchOff;                       // (147) corrimiento de la separacion de color en este cuadro (quieto en pausa)
        // (138e) paso de la animacion (root motion, como avanza un zombi de verdad), en casillas por segundo de juego; -1 hasta medirlo
        float animSpeed = -1f;
        long animNs;
        long freedFrame = -10;
        final String animSet;                          // (148) "zombie" (zombis falsos) o "player-avatar" (el clon): no cambia al reciclar
        // (174) disfraz nivel B: el jugador que reemplaza (sigue su posicion y su rumbo en cada cuadro); cuadros procesados y el ultimo
        java.lang.ref.WeakReference<IsoGameCharacter> follow;
        int frames;
        volatile long seenNs;
        // (188) lleva la piel podrida del disfraz (tambien despues de soltarse del jugador: detach); y mirar hacia un punto girando de a poco
        boolean disguiseSkin;
        volatile boolean faceOn;
        volatile float faceX, faceY, turnRad;
        long faceNs;

        Puppet(String animSet) {
            this.animSet = animSet;
            for (int i = 0; i < drawers.length; i++) drawers[i] = new Drawer(this);
            for (int i = 0; i < texDrawers.length; i++) texDrawers[i] = new TexDrawer(this);
            model.setAnimSetName(animSet);
            model.setAnimate(true);
        }
    }

    /** Igual que IsoMannequin.Drawer: renderMain() al encolar (hilo principal), DoRenderToWorld() al dibujar (hilo de render). */
    static final class Drawer extends TextureDraw.GenericDrawer {
        final Puppet p;
        float x, y, z, angle;
        boolean rendered;

        Drawer(Puppet p) { this.p = p; }

        void init(float x, float y, float z) {
            this.x = x;
            this.y = y;
            this.z = z;
            rendered = false;
            p.model.renderMain();
            angle = p.model.getAnimationPlayer().getRenderedAngle();
        }

        @Override
        public void render() {
            if (p.outline) drawOutline(p, x, y, z, angle);     // (141) primero el contorno, como el juego
            float g = p.glitch;
            if (g > 0.01f) {
                // (142) glitch cyberpunk: tres pasadas del mismo modelo, cian a un lado y magenta al otro (separacion de color).
                // (146) Corridas en horizontal de la PANTALLA (en isometrico, el mundo (+1, -1)), con un largo distinto en cada cuadro y,
                // a veces, una pasada mas lejos: se lee como una imagen que se rompe y no como un modelo que tiembla en diagonal.
                float off = p.glitchOff;
                float sx = off * SCREEN_X, sy = -off * SCREEN_X;
                try {
                    p.model.setTint(0.15f, 1f, 1f);
                    p.model.DoRenderToWorld(x + sx, y + sy, z, angle);
                    p.model.setTint(1f, 0.15f, 0.85f);
                    p.model.DoRenderToWorld(x - sx, y - sy, z, angle);
                    p.model.setTint(p.tr, p.tg, p.tb);
                } catch (Throwable ignored) {
                    // un glitch que falla no puede tumbar el dibujo: la pasada normal va igual
                }
            }
            p.model.DoRenderToWorld(x, y, z, angle);
            rendered = true;
        }

        @Override
        public void postRender() {
            p.model.postRender(rendered);
        }
    }

    /**
     * (150) Con la camara 3D el titere no pasa por DoRender (lo dibuja Viewpoint), y DoRender es el que corre ModelInstanceTextureCreator.render():
     * la textura del cuerpo (piel + la ropa que el juego pinta encima: remeras, camisas, sangre). Sin eso el cuerpo quedaba sin textura y no se
     * veia (solo las piezas con textura propia: pantalon, mameluco, pelo, el implante), o se veia segun si antes habia llegado a pasar por el
     * isometrico. Este dibujo hace solo esa parte, en el hilo de render como DoRender, y al terminar cierra el modelo (postRender), igual que el
     * Drawer del isometrico.
     */
    static final class TexDrawer extends TextureDraw.GenericDrawer {
        final Puppet p;
        boolean rendered;

        TexDrawer(Puppet p) { this.p = p; }

        @Override
        public void render() {
            rendered = true;
            try {
                Object[] infos = (Object[]) fStates.get(p.model);
                int i = SpriteRenderer.instance.getRenderStateIndex();
                Object info = infos == null || i < 0 || i >= infos.length ? null : infos[i];
                zombie.core.skinnedmodel.model.ModelInstanceTextureCreator tc =
                        info == null ? null : (zombie.core.skinnedmodel.model.ModelInstanceTextureCreator) fTexCreator.get(info);
                if (tc != null && !tc.isRendered()) {
                    tc.render();
                    texRendered++;
                }
            } catch (Throwable t) {
                texError = String.valueOf(t);
            }
        }

        @Override
        public void postRender() {
            p.model.postRender(rendered);
            rendered = false;
        }
    }

    static long texRendered;
    static String texError = "";

    /** (146) Un paso en la horizontal de la pantalla isometrica, en casillas de mundo por eje (x +, y -). */
    static final float SCREEN_X = 0.7071f;

    /**
     * (146) Tartamudeo del glitch: mientras se deshace, algunos cuadros no avanza la animacion (queda la pose congelada y la siguiente
     * salta), como un video al que se le caen cuadros. g = 0..1 del glitch.
     */
    static boolean stutter(float g) {
        return g > 0.01f && java.util.concurrent.ThreadLocalRandom.current().nextFloat() < 0.45f * g;
    }

    /**
     * (147) Un cuadro del titere (isometrico o camara 3D): con el juego en pausa no avanza la animacion ni cambia el glitch, como un zombi de
     * verdad (antes seguia caminando en el lugar con el juego pausado). Al volver, el paso medido no cuenta el tiempo en pausa.
     */
    static void step(Puppet p, AnimatedModel m, long now) {
        if (GameTime.isGamePaused()) {
            p.animNs = now;
            return;
        }
        float g = p.glitch;
        if (g > 0.01f) {
            // (146) un largo distinto en cada cuadro y, a veces, una pasada mas lejos
            java.util.concurrent.ThreadLocalRandom r = java.util.concurrent.ThreadLocalRandom.current();
            float off = g * (0.04f + 0.10f * r.nextFloat());
            if (r.nextFloat() < 0.2f * g) off *= 2.5f;
            p.glitchOff = off;
        } else {
            p.glitchOff = 0f;
        }
        if (!stutter(g)) update(m);
        measure(p, m, now);
    }

    // (143) Camara 3D de Viewpoint: expone las piezas del titere para que el jar de Viewpoint las agregue a su escena.
    private static java.lang.reflect.Field fStates, fInstData, fTexCreator;
    private static boolean reflectReady, reflectFailed;
    private static boolean reflect() {
        if (reflectReady) return true;
        if (reflectFailed) return false;
        try {
            fStates = AnimatedModel.class.getDeclaredField("stateInfos");
            fStates.setAccessible(true);
            Class<?> info = Class.forName("zombie.core.skinnedmodel.advancedanimation.AnimatedModel$StateInfo");
            fInstData = info.getDeclaredField("instData");
            fInstData.setAccessible(true);
            fTexCreator = info.getDeclaredField("textureCreator");    // (150)
            fTexCreator.setAccessible(true);
            reflectReady = true;
            return true;
        } catch (Throwable t) {
            reflectFailed = true;
            outlineError = "3D: " + t;                       // se informa en stats()
            System.out.println("[SandevistanPsy] 3D: no se pudo leer el modelo del titere: " + t);
            return false;
        }
    }

    /**
     * (143) Una entrada por titere vivo de ese jugador, con lo que Viewpoint necesita para dibujarlo en la camara 3D:
     * { x, y, z, angulo, alfa, r, g, b, List de piezas, glitch 0..1, corrimiento del glitch }. Cada pieza: { ModelInstance, ModelMesh, Texture, float[] paleta,
     * Matrix4f xfrm, Integer cull, Boolean estatico }. La paleta y la matriz se copian porque el modelo las recicla para el
     * siguiente cuadro (y se cierra el modelo con postRender, como hace el dibujo isometrico, para que la textura del atuendo
     * termine de armarse).
     * (146) El modelo y la textura salen de la ModelInstance: AnimatedModel nunca llena los campos model y tex de sus datos de dibujo (DrawChar
     * usa modelInstance.model y modelInstance.tex, o model.tex si no hay), y por eso hasta la 145 se descartaban todas las piezas
     * ("sin piezas utiles").
     */
    public static java.util.List<Object[]> scene3D(int owner) {
        java.util.List<Object[]> out = new ArrayList<>();
        scene3DCalls++;
        scene3DNs = System.nanoTime();
        if (scene3DCalls == 1) {
            System.out.println("[SandevistanPsy] 3D: pedido de escena (jugador=" + owner + ", vivos=" + live.size()
                    + ", apagados=" + disabled + ", pase isometrico=" + renderCalls + " llamadas)");
        }
        if (disabled || live.isEmpty()) return out;
        if (!reflect()) return out;
        try {
            int state = SpriteRenderer.instance.getMainStateIndex();
            int others = 0;
            long now = System.nanoTime();
            for (Puppet p : live.values()) {
                if (p.owner != owner) { others++; continue; }
                // (186) disfraz nivel B con la camara 3D: el pase isometrico (render) no corre, asi que el titere sigue al jugador desde aca
                if (p.follow != null) follow(p, now);
                AnimatedModel m = p.model;
                if (m.getAnimationPlayer() == null) {
                    note("titere " + p.id + " sin animPlayer");
                    continue;
                }
                m.setAngle(dir.set(p.fx, p.fy));
                m.setAlpha(p.alpha);
                m.setTint(p.tr, p.tg, p.tb);
                m.setAmbient(ambient.set(1f, 1f, 1f, 1f), true, false);
                step(p, m, System.nanoTime());              // (146) el paso de la animacion tambien con la camara 3D (Lua lo usa como velocidad)
                m.renderMain();
                try {
                    Object[] infos = (Object[]) fStates.get(m);
                    if (infos == null || state < 0 || state >= infos.length || infos[state] == null) {
                        note("titere " + p.id + " sin estado " + state + " (estados=" + (infos == null ? -1 : infos.length) + ")");
                        continue;
                    }
                    @SuppressWarnings("unchecked")
                    ArrayList<AnimatedModelInstanceRenderData> list = (ArrayList<AnimatedModelInstanceRenderData>) fInstData.get(infos[state]);
                    if (list == null || list.isEmpty()) {
                        note("titere " + p.id + " sin piezas de render");
                        continue;
                    }
                    java.util.List<Object[]> pieces = new ArrayList<>();
                    for (AnimatedModelInstanceRenderData inst : list) {
                        if (inst == null || inst.modelInstance == null) continue;
                        zombie.core.skinnedmodel.model.Model model = inst.modelInstance.model;
                        if (model == null || model.mesh == null || !model.isReady()) continue;
                        zombie.core.textures.Texture tex = inst.modelInstance.tex != null ? inst.modelInstance.tex : model.tex;
                        int cull = inst.modelInstance.modelScript != null ? inst.modelInstance.modelScript.cullFace : 0;
                        boolean isStatic = model.isStatic;
                        float[] pal = null;
                        if (!isStatic && inst.matrixPalette != null) {
                            FloatBuffer b = inst.matrixPalette.duplicate();
                            b.rewind();
                            pal = new float[b.remaining()];
                            b.get(pal);
                        }
                        pieces.add(new Object[] { inst.modelInstance, model.mesh, tex, pal,
                                new Matrix4f(inst.xfrm), cull, isStatic });
                    }
                    if (pieces.isEmpty()) {
                        note("titere " + p.id + " sin piezas utiles (" + list.size() + ")");
                        continue;
                    }
                    float angle = m.getAnimationPlayer().getRenderedAngle();
                    out.add(new Object[] { p.x, p.y, p.z, angle, p.alpha, p.tr, p.tg, p.tb, pieces, p.glitch, p.glitchOff });
                    if (p.follow != null) {                     // (186) ya esta en el dibujo 3D: cuenta como parado en el lugar del jugador
                        p.seenNs = now;
                        p.frames++;
                    }
                } finally {
                    // (150) la textura del cuerpo se arma en el hilo de render (TexDrawer) y despues se cierra el modelo, como en el isometrico.
                    // Antes se cerraba aca mismo y la textura nunca se armaba.
                    try {
                        SpriteRenderer.instance.drawGeneric(p.texDrawers[state]);
                    } catch (Throwable t) {
                        m.postRender(true);
                    }
                }
            }
            if (out.size() != lastOut) {                    // (146) solo cuando cambia (antes alternaba con el estado y llenaba los 40 avisos)
                lastOut = out.size();
                note("vivos=" + live.size() + " mios=" + out.size() + (others > 0 ? " de otros=" + others : "") + " estado=" + state);
            }
        } catch (Throwable t) {
            out.clear();
            System.out.println("[SandevistanPsy] 3D: " + t);
        }
        return out;
    }

    // (144) Avisos de 3D para el console.txt: se dice que pasa, pero una sola vez por cambio y con un tope, para no llenar el log.
    private static long scene3DCalls;
    private static volatile long scene3DNs;
    private static int notes, lastOut = -1;
    private static String lastNote = "";
    private static void note(String s) {
        if (s.equals(lastNote) || notes >= 40) return;
        lastNote = s;
        notes++;
        System.out.println("[SandevistanPsy] 3D: " + s);
    }

    /** (142) Lua: 0..1 mientras el titere se deshace, para la separacion de color del glitch. */
    public static void glitch(long id, float amount) {
        Puppet p = live.get(id);
        if (p != null) p.glitch = Math.max(0f, Math.min(1f, amount));
    }

    /** (141) Lua: el titere es un blanco melee del jugador (contorno rojo como los zombis reales) o dejo de serlo. */
    public static void outline(long id, boolean on) {
        Puppet p = live.get(id);
        if (p != null) p.outline = on;
    }

    /**
     * (141) El borde rojo de los zombis cuando apuntas: el juego no dibuja a los personajes con un shader de contorno, los pinta en un FBO
     * (ModelOutlines.fboA) y al final del pase de personajes lo engrosa y lo mezcla (aim_outline_h/v/blit). Como el titere no es una entidad,
     * se hace lo mismo que ModelSlotRenderData.performRenderCharacterOutline: se pinta el modelo en ese FBO y el juego hace el resto, con el
     * mismo color (Core.getBadHighlitedColor) y la misma camara. Se copia tambien el estado de OpenGL que el juego deja como estaba
     * (atributos, textura, VBOs, profundidad) porque el pase normal del titere sigue despues.
     * Si algo falla se apaga solo (no rompe el dibujo ni los titeres).
     */
    static void drawOutline(Puppet p, float x, float y, float z, float angle) {
        if (!outlines) return;
        ModelOutlines mo = ModelOutlines.instance;
        ModelCamera cam = ModelCamera.instance;
        if (mo == null || mo.fboA == null) return;
        boolean depthMask = cam == null || cam.depthMask;
        try {
            if (cam != null) cam.depthMask = false;                     // como el juego: el contorno no escribe profundidad
            GL11.glPushClientAttrib(-1);
            GL11.glPushAttrib(1048575);
            GL11.glEnable(GL11.GL_BLEND);
            GL11.glBlendFunc(GL11.GL_SRC_ALPHA, GL11.GL_ONE_MINUS_SRC_ALPHA);
            GL11.glEnable(GL11.GL_ALPHA_TEST);
            GL11.glAlphaFunc(GL11.GL_GREATER, 0f);
            GL11.glEnable(GL11.GL_DEPTH_TEST);
            GL11.glDisable(GL11.GL_SCISSOR_TEST);
            ColorInfo col = Core.getInstance().getBadHighlitedColor();
            boolean started = mo.beginRenderOutline(col, false, false);
            mo.fboA.startDrawing(started, true);
            try {
                p.model.DoRenderToWorld(x, y, z, angle);
            } finally {
                mo.fboA.endDrawing();
            }
            outlinedFrames++;
        } catch (Throwable t) {
            outlines = false;
            outlineError = String.valueOf(t);
            System.out.println("[SandevistanPsy] contorno rojo apagado: " + t);
        } finally {
            try {
                GL11.glPopAttrib();
                GL11.glPopClientAttrib();
                Texture.lastTextureID = -1;
                GL11.glEnable(GL11.GL_TEXTURE_2D);
                if (SpriteRenderer.ringBuffer != null) SpriteRenderer.ringBuffer.restoreVbos = true;
                GL11.glDisable(GL11.GL_DEPTH_TEST);
                GL11.glEnable(GL11.GL_BLEND);
                GL11.glEnable(GL11.GL_ALPHA_TEST);
                GL11.glAlphaFunc(GL11.GL_GREATER, 0f);
                GLStateRenderThread.restore();
            } catch (Throwable t) {
                outlines = false;
                outlineError = String.valueOf(t);
            }
            if (cam != null) cam.depthMask = depthMask;
        }
    }

    public static boolean ok() { return !disabled; }

    private static void fail(String where, Throwable t) {
        disabled = true;
        lastError = where + ": " + t;
        System.out.println("[SandevistanPsy] titeres apagados por un error en " + where + ": " + t);
        t.printStackTrace(System.out);
    }

    static final String ZOMBIE = "zombie", AVATAR = "player-avatar";

    /**
     * (148) El titere id con ese AnimSet: el que ya esta vivo (si es del mismo tipo), uno de la reserva o uno nuevo. Los de la reserva se
     * reciclan solo dentro de su tipo (el grupo de acciones es otro); si la reserva esta llena de otro tipo, se suelta uno viejo.
     */
    private static Puppet obtain(long id, String animSet) {
        Puppet p = live.get(id);
        if (p != null && !p.animSet.equals(animSet)) { remove(id); p = null; }
        if (p != null) return p;
        if (live.size() >= max) return null;
        long frame = IsoCamera.frameState.frameCount;
        for (int i = 0; i < pool.size(); i++) {
            Puppet q = pool.get(i);
            if (q.animSet.equals(animSet) && frame - q.freedFrame > 3) { p = pool.remove(i); recycled++; break; }   // el hilo de render ya no lo usa
        }
        if (p == null && live.size() + pool.size() >= max) {
            for (int i = 0; i < pool.size(); i++) {
                if (frame - pool.get(i).freedFrame > 3) { pool.remove(i); break; }
            }
        }
        if (p == null) {
            if (live.size() + pool.size() >= max) return null;
            p = new Puppet(animSet);
        }
        live.put(id, p);
        return p;
    }

    private static void reset(Puppet p, long id, int owner, float x, float y, float z) {
        p.id = id;
        p.owner = owner;
        p.x = x;
        p.y = y;
        p.z = z;
        p.vx = 0f;
        p.vy = 0f;
        p.movedNs = System.nanoTime();
        p.alpha = 1f;
        p.tr = p.tg = p.tb = 1f;
        p.vis = 0f;
        p.visNs = 0L;
        p.animSpeed = -1f;
        p.animNs = 0L;
        p.outline = false;
        p.glitch = 0f;
        p.glitchOff = 0f;
        p.follow = null;
        p.frames = 0;
        p.seenNs = 0L;
        p.disguiseSkin = false;
        p.faceOn = false;
        p.turnRad = 0f;
        p.faceNs = 0L;
    }

    /**
     * (148) El clon de la cyberpsicosis (26 §7): un titere con la piel, el pelo y la ropa del personaje (copiados, como el maniqui de la
     * creacion de personaje: AnimatedModel.setModelData copia la visual) y el AnimSet "player-avatar" (estados idle, walk, run, ext).
     * Sin arma en la mano ni objetos colgados. Empieza quieto (idle); Lua cambia el estado con puppetSetState.
     */
    public static boolean spawnClone(long id, Object character, float x, float y, float z, int owner) {
        if (disabled || !(character instanceof IsoGameCharacter)) return false;
        try {
            IsoGameCharacter chr = (IsoGameCharacter) character;
            if (!(chr instanceof zombie.core.skinnedmodel.visual.IHumanVisual)) return false;
            Puppet p = obtain(id, AVATAR);
            if (p == null) return false;
            reset(p, id, owner, x, y, z);
            AnimatedModel m = p.model;
            m.clearVariables();
            ItemVisuals items = new ItemVisuals();
            chr.getItemVisuals(items);
            m.setModelData(((zombie.core.skinnedmodel.visual.IHumanVisual) chr).getHumanVisual(), items);
            m.setState("idle");
            spawned++;
            if (scene3DCalls > 0) System.out.println("[SandevistanPsy] 3D: clon " + id + " nace (jugador=" + owner + ")");
            return true;
        } catch (Throwable t) {
            fail("spawnClone", t);
            return false;
        }
    }

    /**
     * (148) Cambia el estado de animacion del titere (el clon: idle, walk, run, ext, sdvwave).
     * (150) AnimatedModel.setState solo guarda el nombre: con el grupo de acciones "player-avatar" la animacion la elige el grupo, que solo
     * cambia con eventos (EventWalk...), y el clon caminaba en idle. Se le pide el estado directo al animador (como hace el grupo al cambiar);
     * el grupo no lo pisa porque nunca le llega un evento. Asi tambien anda "sdvwave" (el saludo, estado que agrega el mod al AnimSet).
     */
    public static void setState(long id, String state) {
        Puppet p = live.get(id);
        if (p == null || state == null) return;
        try {
            p.model.setState(state);
            zombie.core.skinnedmodel.advancedanimation.AdvancedAnimator a = p.model.getAdvancedAnimator();
            if (a != null && a.containsState(state) && !state.equals(a.getCurrentStateName())) a.setState(state);
        } catch (Throwable t) {
            fail("setState", t);
        }
    }

    /**
     * (174) Disfraz nivel B (29 §4.1): un titere zombi con la ropa, el pelo y el cuerpo del jugador (setModelData copia la visual, como el clon)
     * y piel podrida (Disguise.puppetSkin: el mismo enganche de getSkinTexture, sobre el modelo del titere, que es dueño de la visual copiada).
     * AnimSet "zombie": Lua le pone las variables (bMoving, zombieWalkType, shouldSprint, bAttack) segun lo que hace el jugador. La posicion y el
     * rumbo los toma del jugador en cada cuadro (follow), sin esperar a Lua.
     */
    public static boolean spawnDisguise(long id, Object character, int owner, int rot) {
        if (disabled || !(character instanceof IsoGameCharacter) || !(character instanceof zombie.core.skinnedmodel.visual.IHumanVisual)) return false;
        try {
            IsoGameCharacter chr = (IsoGameCharacter) character;
            zombie.core.skinnedmodel.visual.IHumanVisual hv = (zombie.core.skinnedmodel.visual.IHumanVisual) character;
            Puppet p = obtain(id, ZOMBIE);
            if (p == null) return false;
            reset(p, id, owner, chr.getX(), chr.getY(), chr.getZ());
            AnimatedModel m = p.model;
            m.clearVariables();
            for (String v : FALSE_VARS) m.setVariable(v, false);
            for (String v : TRUE_VARS) m.setVariable(v, true);
            m.setVariable("Female", hv.isFemale());
            m.setVariable("zombieWalkType", "1");
            m.setState("idle");
            if (m.getActionContext().getGroup() != null) m.getActionContext().setGroup(m.getActionContext().getGroup());
            Disguise.puppetSkin(m, Disguise.ZOMBIE1 + Math.max(0, Math.min(2, rot - 1)));
            p.disguiseSkin = true;
            ItemVisuals items = new ItemVisuals();
            chr.getItemVisuals(items);
            m.setModelData(hv.getHumanVisual(), items);
            p.follow = new java.lang.ref.WeakReference<>(chr);
            follow(p, System.nanoTime());
            spawned++;
            return true;
        } catch (Throwable t) {
            fail("spawnDisguise", t);
            return false;
        }
    }

    private static final Vector2 followDir = new Vector2();

    /**
     * (174) El titere del nivel B se pone donde esta el jugador y mira hacia donde mira su animacion.
     * (188) Con face(): mira hacia ese punto (el que lo ve) girando como mucho turnRad por segundo; al soltarlo vuelve a girar de a poco hacia
     * donde mira el jugador y, ya alineado, lo copia de nuevo cuadro a cuadro.
     */
    static void follow(Puppet p, long now) {
        IsoGameCharacter chr = p.follow == null ? null : p.follow.get();
        if (chr == null) return;
        p.x = chr.getX();
        p.y = chr.getY();
        p.z = chr.getZ();
        p.vx = 0f;
        p.vy = 0f;
        float wx = 0f, wy = 0f;
        if (p.faceOn) {
            wx = p.faceX - p.x;
            wy = p.faceY - p.y;
        } else {
            Vector2 f = chr.getAnimForwardDirection(followDir);
            if (f != null) { wx = f.x; wy = f.y; }
        }
        if (wx != 0f || wy != 0f) {
            float len = (float) Math.sqrt(wx * wx + wy * wy);
            wx /= len;
            wy /= len;
            if (p.turnRad > 0f) {
                float dt = p.faceNs == 0L ? 0f : Math.min(0.1f, (now - p.faceNs) / 1.0e9f);
                if (GameTime.isGamePaused()) dt = 0f;
                float[] r = turnToward(p.fx, p.fy, wx, wy, p.turnRad * dt);
                p.fx = r[0];
                p.fy = r[1];
                if (!p.faceOn && r[2] < 0.05f) p.turnRad = 0f;   // ya mira hacia donde mira el jugador: vuelve a copiarlo
            } else {
                p.fx = wx;
                p.fy = wy;
            }
        }
        p.faceNs = now;
        p.movedNs = now;
    }

    /** (188) Gira (fx, fy) hacia (wx, wy), los dos de largo 1, como mucho maxRad. Devuelve { x, y, angulo que faltaba antes de girar }. */
    public static float[] turnToward(float fx, float fy, float wx, float wy, float maxRad) {
        float a = (float) Math.atan2(fy, fx);
        float b = (float) Math.atan2(wy, wx);
        float d = b - a;
        while (d > (float) Math.PI) d -= 2f * (float) Math.PI;
        while (d < -(float) Math.PI) d += 2f * (float) Math.PI;
        float gap = Math.abs(d);
        if (gap <= maxRad) return new float[] { wx, wy, gap };
        float n = a + Math.copySign(maxRad, d);
        return new float[] { (float) Math.cos(n), (float) Math.sin(n), gap };
    }

    /**
     * (188) Disfraz nivel B: el titere mira hacia (x, y) girando degPerSec grados por segundo (on), o vuelve a mirar hacia donde mira el jugador
     * (off, girando igual de a poco). Solo para titeres que siguen a un jugador.
     */
    public static void face(long id, boolean on, float x, float y, float degPerSec) {
        Puppet p = live.get(id);
        if (p == null || p.follow == null) return;
        p.faceX = x;
        p.faceY = y;
        if (degPerSec > 0f) p.turnRad = (float) Math.toRadians(degPerSec);
        p.faceOn = on;
    }

    /**
     * (188) El titere del disfraz deja de seguir a su jugador y queda como un titere suelto (con su ropa y su piel podrida) que Lua mueve como
     * un zombi falso. Devuelve false si no existe o no seguia a nadie.
     */
    public static boolean detach(long id) {
        Puppet p = live.get(id);
        if (p == null || p.follow == null) return false;
        p.follow = null;
        p.faceOn = false;
        p.turnRad = 0f;
        p.vx = 0f;
        p.vy = 0f;
        p.movedNs = System.nanoTime();
        detached++;
        return true;
    }

    /**
     * (174) El titere id esta reemplazando a su jugador ahora mismo: vivo, siguiendolo, procesado por el dibujo isometrico (186: o el 3D) en los ultimos 300 ms
     * y con al menos SwapFrames cuadros (el primero arma el modelo y las texturas: asi no hay un cuadro sin nadie). Si no, se dibuja el real.
     */
    public static int swapFrames = 6;
    public static boolean standingIn(long id) {
        if (disabled) return false;
        Puppet p = live.get(id);
        if (p == null || p.follow == null || p.follow.get() == null || p.frames < swapFrames) return false;
        return System.nanoTime() - p.seenNs < 300_000_000L;
    }

    /** Nace (o renace) el titere id con un atuendo de zombi; owner = numero del jugador local que lo ve. */
    public static boolean spawn(long id, String outfit, boolean female, float x, float y, float z, int owner) {
        if (disabled) return false;
        try {
            Puppet p = obtain(id, ZOMBIE);
            if (p == null) return false;
            reset(p, id, owner, x, y, z);
            AnimatedModel m = p.model;
            m.clearVariables();
            for (String v : FALSE_VARS) m.setVariable(v, false);
            for (String v : TRUE_VARS) m.setVariable(v, true);
            m.setVariable("Female", female);
            m.setVariable("zombieWalkType", "1");
            m.setState("idle");
            // (138d) Reciclado: setModelData solo cambia el grupo de acciones si es otro, y el titere seguia en el estado del anterior
            // (attack o staggerback al deshacerse), donde las variables de persecucion no lo sacan: quedaba quieto. setGroup vuelve al inicial.
            if (m.getActionContext().getGroup() != null) m.getActionContext().setGroup(m.getActionContext().getGroup());
            // (138b) un AnimatedModel nuevo no trae visual: initOutfit viste baseVisual y daba NullPointerException (los maniquies pasan antes
            // por setModelData). Un HumanVisual nuevo con el modelo de dueño (getHumanVisual() solo castea baseVisual), asi que es mujer/zombi segun setOutfitName.
            if (m.getVisual() == null) m.setVisual(new HumanVisual(m));
            m.setOutfitName(outfit, female, true);          // initOutfit en el proximo update: viste, arma el modelo y el grupo de acciones
            spawned++;
            if (scene3DCalls > 0) System.out.println("[SandevistanPsy] 3D: titere " + id + " nace (jugador=" + owner + ", vivos=" + live.size() + ")");
            return true;
        } catch (Throwable t) {
            fail("spawn", t);
            return false;
        }
    }

    public static void move(long id, float x, float y, float z, float vx, float vy, float fx, float fy) {
        Puppet p = live.get(id);
        if (p == null) return;
        p.x = x;
        p.y = y;
        p.z = z;
        p.vx = vx;
        p.vy = vy;
        if (fx != 0f || fy != 0f) {
            float len = (float) Math.sqrt(fx * fx + fy * fy);
            p.fx = fx / len;
            p.fy = fy / len;
        }
        p.movedNs = System.nanoTime();
    }

    /**
     * Variable de animacion: "true"/"false" -> booleana, si no, texto. (138b) Sin numeros: zombieWalkType "1".."5" es una condicion de
     * texto en los AnimSets (walktoward1.xml: STRING "1"); como float valia "1.0", ninguna caminata coincidia y el titere se deslizaba quieto.
     */
    public static void var(long id, String name, String value) {
        Puppet p = live.get(id);
        if (p == null || name == null) return;
        try {
            AnimatedModel m = p.model;
            if (value == null) { m.clearVariable(name); return; }
            if ("true".equals(value) || "false".equals(value)) { m.setVariable(name, Boolean.parseBoolean(value)); return; }
            m.setVariable(name, value);
        } catch (Throwable t) {
            fail("var", t);
        }
    }

    public static void look(long id, float alpha, float r, float g, float b) {
        Puppet p = live.get(id);
        if (p == null) return;
        p.alpha = Math.max(0f, Math.min(1f, alpha));
        p.tr = r;
        p.tg = g;
        p.tb = b;
    }

    public static String state(long id) {
        Puppet p = live.get(id);
        if (p == null) return "";
        try {
            return String.valueOf(p.model.getAdvancedAnimator().getCurrentStateName());
        } catch (Throwable t) {
            return "?";
        }
    }

    public static void remove(long id) {
        Puppet p = live.remove(id);
        if (p == null) return;
        p.outline = false;
        // (174) el modelo vuelve a la reserva sin la piel del disfraz; (188) tambien si ya se habia soltado del jugador
        if (p.follow != null || p.disguiseSkin) Disguise.puppetSkin(p.model, Disguise.NONE);
        p.follow = null;
        p.disguiseSkin = false;
        p.freedFrame = IsoCamera.frameState.frameCount;
        pool.add(p);
        if (scene3DCalls > 0) System.out.println("[SandevistanPsy] 3D: titere " + id + " se va (quedan " + live.size() + ")");
    }

    public static void clear() {
        for (Long id : new ArrayList<>(live.keySet())) remove(id);
    }

    public static int count() { return live.size(); }

    /** Para las pruebas: el valor de una variable de animacion como texto (null si no existe el titere). */
    public static String varOf(long id, String name) {
        Puppet p = live.get(id);
        return p == null ? null : p.model.getVariableString(name);
    }

    /** Para las pruebas: el visual del titere (null si no existe). */
    public static Object visualOf(long id) {
        Puppet p = live.get(id);
        return p == null ? null : p.model.getVisual();
    }

    /** Al entrar a FBORenderCell.renderMovingObjects: actualiza y encola los titeres de la vista que se esta dibujando. */
    public static void render() {
        renderCalls++;
        if (disabled || live.isEmpty()) return;
        // (145) si la camara 3D acaba de pedir la escena, el titere ya lo dibuja Viewpoint: no se toca el modelo otra vez
        // (renderMain/postRender no son seguros desde dos hilos a la vez, y el pase isometrico no se ve en la camara 3D).
        if (System.nanoTime() - scene3DNs < 250_000_000L) return;
        try {
            int view = IsoCamera.frameState.playerIndex;
            int state = SpriteRenderer.instance.getMainStateIndex();
            long now = System.nanoTime();
            IsoCell cell = IsoWorld.instance == null ? null : IsoWorld.instance.currentCell;
            boolean any = false;
            for (Puppet p : live.values()) {
                if (p.owner != view) continue;
                if (p.follow != null) {                         // (174) disfraz nivel B: donde esta el jugador, en este cuadro
                    follow(p, now);
                    p.seenNs = now;
                }
                if (GameTime.isGamePaused()) p.movedNs = now;   // (147) en pausa no se adelanta la posicion
                float dt = Math.min(0.25f, (now - p.movedNs) / 1.0e9f);
                float x = p.x + p.vx * dt;
                float y = p.y + p.vy * dt;
                AnimatedModel m = p.model;
                IsoGridSquare sq = cell == null ? null : cell.getGridSquare((int) Math.floor(x), (int) Math.floor(y), (int) Math.floor(p.z));
                // (138c) como un zombi: fuera del cono de vision (o en una casilla sin cargar) no se ve; aparece y se va con un fundido corto
                float target = sq != null && sq.isCanSee(view) ? 1f : 0f;
                float step = p.visNs == 0L ? 1f : Math.min(1f, (now - p.visNs) / 1.0e9f * fadePerSecond);
                p.visNs = now;
                p.vis = target > p.vis ? Math.min(target, p.vis + step) : Math.max(target, p.vis - step);
                if (p.follow != null && p.frames == 0) p.vis = target;   // (174) el disfraz aparece de una (el real ya se estaba viendo)
                p.frames++;
                if (sq != null) {
                    ColorInfo li = sq.getLightInfo(view);
                    if (li != null) ambient.set(li.r, li.g, li.b, 1f); else ambient.set(1f, 1f, 1f, 1f);
                    m.setAmbient(ambient, sq.isOutside(), sq.getRoom() != null);
                }
                m.setAngle(dir.set(p.fx, p.fy));
                m.setAlpha(p.alpha * p.vis);
                m.setTint(p.tr, p.tg, p.tb);
                step(p, m, now);                                // sigue animando aunque no se vea (al aparecer ya esta caminando); (146) tartamudeo
                if (p.vis <= 0.004f) continue;
                if (shadows && sq != null) shadow(p, m, x, y, sq, view);
                Drawer d = p.drawers[state];
                d.init(x, y, p.z);
                SpriteRenderer.instance.drawGeneric(d);
                drawn++;
                any = true;
            }
            if (any) drawnFrames++;
        } catch (Throwable t) {
            fail("render", t);
        }
    }

    /**
     * (138d) AnimatedModel.update() es para la interfaz: pone el multiplicador del juego en 1 y, con la interfaz en su propio FBO, multiplica el
     * tiempo por FPS / FPS de la interfaz (a 60 FPS con la interfaz a 20, tres veces mas rapido). Se compensa para que el titere anime con el
     * mismo paso que un zombi de verdad, incluida la camara lenta del juego (GameTime.setMultiplier).
     */
    static void update(AnimatedModel m) {
        GameTime gt = GameTime.getInstance();
        float fps = gt.fpsMultiplier;
        float k = uiScale();
        float per = gt.perObjectMultiplier;
        float game = per > 0f ? gt.getTrueMultiplier() / per : 1f;
        gt.fpsMultiplier = fps * game / k;
        try {
            m.update();
        } finally {
            gt.fpsMultiplier = fps;
        }
    }

    private static final Vector2 motion = new Vector2();
    /** Suavizado del paso medido (por cuadro): sigue los cambios de caminar a embestir en unos 10 cuadros sin temblar con cada pisada. */
    static float speedSmoothing = 0.15f;

    /**
     * (138e) Cuanto avanzo el cuerpo con la animacion en este cuadro (el desplazamiento que un zombi de verdad aplica en doDeferredMovement),
     * en casillas por segundo de juego. Lua lo usa como velocidad: los pies no patinan y cada forma de caminar alcanza como la de un zombi real.
     */
    static void measure(Puppet p, AnimatedModel m, long now) {
        if (m.getAnimationPlayer() == null) return;
        m.getAnimationPlayer().getDeferredMovement(motion, true);
        float len = motion.getLength();
        if (p.animNs == 0L) { p.animNs = now; return; }
        float dt = (now - p.animNs) / 1.0e9f;
        p.animNs = now;
        if (dt <= 0f || dt > 0.5f) return;
        float game = GameTime.getInstance().getTrueMultiplier();
        float v = len / dt / Math.max(0.05f, game);
        if (v > 8f) return;                              // un salto (reciclado, cambio de modelo): no es un paso
        if (p.animSpeed < 0f) { if (len > 0f) p.animSpeed = v; return; }
        p.animSpeed += (v - p.animSpeed) * speedSmoothing;
    }

    /** Paso de la animacion del titere en casillas por segundo de juego; -1 si todavia no se midio (Lua usa el de la configuracion). */
    public static float speed(long id) {
        Puppet p = live.get(id);
        return p == null ? -1f : p.animSpeed;
    }

    /** Lo que update() le agrega al tiempo (UIManager.useUiFbo: FPS promedio / FPS de la interfaz); 1 si no hay o no se puede saber. */
    public static float uiScale() {
        if (!UIManager.useUiFbo) return 1f;
        int ui = Core.getInstance().getOptionUIRenderFPS();
        float avg = GameWindow.averageFPS;
        if (ui <= 0 || avg < 1f) return 1f;
        return avg / ui;
    }

    /** Sombra en el piso, con el largo y el sentido de la pose (como un zombi; el mismo pase de sombras que los maniquies). */
    private static void shadow(Puppet p, AnimatedModel m, float x, float y, IsoGridSquare sq, int view) {
        try {
            if (!PerformanceSettings.fboRenderChunk || FBORenderChunkManager.instance.isCaching()) return;
            IsoGameCharacter.calculateShadowParams(m.getAnimationPlayer(), 1f, false, shadow);
            ColorInfo li = sq.getLightInfo(view);
            float r = li == null ? 1f : li.r, g = li == null ? 1f : li.g, b = li == null ? 1f : li.b;
            forward.set(p.fx, p.fy, 0f);
            FBORenderShadows.getInstance().addShadow(x, y, p.z, forward, shadow.w, shadow.fm, shadow.bm, r, g, b, p.alpha * p.vis, false);
        } catch (Throwable t) {
            shadows = false;
            shadowError = String.valueOf(t);
            System.out.println("[SandevistanPsy] titeres sin sombra: " + t);
        }
    }

    public static String stats() {
        StringBuilder each = new StringBuilder();
        for (Puppet p : live.values()) each.append(" | ").append(p.id).append(": ").append(animInfo(p));
        return String.format("titeres: %d vivos, %d en reserva, %d nacidos (%d reciclados), %d dibujados en %d cuadros%s%s", live.size(), pool.size(),
                spawned, recycled, drawn, drawnFrames, disabled ? " | APAGADOS: " + lastError : "", each)
                + String.format(" | texturas 3D: %d%s", texRendered, texError.isEmpty() ? "" : " (" + texError + ")")
                + (shadows ? "" : " | sin sombra: " + shadowError)
                + (outlines ? String.format(" | contornos: %d cuadros", outlinedFrames) : " | sin contorno: " + outlineError)
                + String.format(" | ritmo UI x%.2f", uiScale())
                + (detached > 0 ? " | disfraces soltados: " + detached : "");
    }

    /** (138c) Para el REPORTE: estado del grupo de acciones, del animador y las pistas que suenan (si camina, dice walktoward y Zombie_Walk...). */
    static String animInfo(Puppet p) {
        try {
            AnimatedModel m = p.model;
            StringBuilder t = new StringBuilder();
            if (m.getAnimationPlayer() != null && m.getAnimationPlayer().getMultiTrack() != null) {
                for (zombie.core.skinnedmodel.animation.AnimationTrack tr : m.getAnimationPlayer().getMultiTrack().getTracks()) {
                    if (t.length() > 0) t.append(", ");
                    t.append(tr.getName()).append(String.format(" %.1f/%.1f", tr.getCurrentTrackTime(), tr.getDuration()));
                }
            }
            return "accion=" + m.getActionContext().getCurrentStateName() + " anim=" + m.getAdvancedAnimator().getCurrentStateName()
                    + " pistas=[" + t + "] vis=" + String.format("%.2f paso=%.2f", p.vis, p.animSpeed);
        } catch (Throwable e) {
            return "? (" + e + ")";
        }
    }
}
