package sandevistan.viewpoint;

import java.util.ArrayList;
import java.util.IdentityHashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;

import org.joml.Matrix4f;
import viewpoint.core.Frame;
import viewpoint.render.ModelDraws;
import zombie.core.skinnedmodel.model.ModelMesh;

/**
 * Estelas 3D: poses guardadas de un personaje que se vuelven a dibujar en los cuadros siguientes.
 *
 * Reparto: Lua (Afterimages.lua del Sandevistan) decide cuando nace cada estela, cuanto vive y de que color, igual que en
 * isometrico; aca solo se guarda la pose y se dibuja. Flujo por cuadro de Viewpoint (hilo principal, IsoCell.render):
 *  1. ModelCapture.capture(personaje) agrega sus piezas a frame.scene.models. Si ese personaje tiene estelas, se anota
 *     el tramo de piezas y de huesos que agrego (captureEnter/captureExit); si Lua pidio una estela nueva (stamp), se copia.
 *  2. Al terminar Characters.snapshot (afterCharacters) se agrega cada estela visible como piezas nuevas: la malla, la
 *     instancia y la textura son las del personaje en ESTE cuadro (nunca se guardan referencias a instancias viejas, que el
 *     juego recicla); la pose (huesos) y la posicion son las guardadas. Va al final de la lista a proposito: despues de
 *     capturar a cada personaje Viewpoint marca todo el tramo final (own/whole), y no queremos que nos marque.
 *
 * Detalles del registro (ver Access): la matriz, la esfera de recorte y el punto de apoyo son relativos a la camara del
 * cuadro, asi que se corren por lo que se movio la camara. En primera persona Viewpoint colapsa los huesos de la cabeza
 * en la paleta principal; la de la sombra (shadowPalette) tiene la pose completa, y es la que se copia.
 */
public final class Ghosts {
    // aspecto (Lua lo puede cambiar con SandevistanVP.look)
    static float tintScale = 1.5f;      // material = color x esto (el albedo es textura x material: >1 aclara la ropa oscura)
    static float glow = 1.0f;           // luz minima de la estela (se ve aunque este a oscuras)
    static int maxDraws = 700;          // tope de piezas agregadas por cuadro
    static long showTimeoutMs = 300;    // una estela que Lua no muestra hace mas que esto no se dibuja
    static long maxAgeMs = 5000;        // y una que no se usa hace mas que esto se descarta (por si Lua no llama a drop)
    static final int MAX_PENDING = 8;   // stamps pendientes por personaje (si no se lo captura, no se acumulan)

    static final Object LOCK = new Object();

    /** Personaje con estelas: tramo que ocupo en el ultimo cuadro capturado y estelas pedidas por Lua. */
    static final class Track {
        long frame = -1;
        int c0, c1, b0, b1;
        final ArrayList<Long> pending = new ArrayList<>();
    }

    /** Una pose guardada. */
    static final class Ghost {
        final long id;
        final Object character;
        int n;                  // piezas
        ModelMesh[] meshes;     // solo para comparar con las del cuadro actual (si cambio la ropa o el arma, se descarta)
        float[] values;         // n registros de Access.VALUES floats, tal como estaban al guardar
        int[] pal;              // por pieza: hueso inicial relativo a bones, -1 = sin huesos (rigida), -2 = no se dibuja
        float[] bones;          // huesos de la pose, Access.BONE_FLOATS por hueso
        int boneCount;
        float camX, camY, camZ; // camara del cuadro en que se guardo
        float r = 1, g = 1, b = 1, a;
        long shownMs, usedMs;

        Ghost(long id, Object character) { this.id = id; this.character = character; }
    }

    static final IdentityHashMap<Object, Track> tracks = new IdentityHashMap<>();
    static final LinkedHashMap<Long, Ghost> ghosts = new LinkedHashMap<>();

    // estado de la captura en curso (no es reentrante: Viewpoint captura un personaje por vez)
    private static Object capChar;
    private static int capCount, capBones;
    private static final Matrix4f tmp = new Matrix4f();

    // estadisticas para el REPORTE
    static long captures, snapshots, framesDrawn;
    static int lastGhosts, lastDraws, errors;
    static String lastError = "";
    static volatile boolean disabled;   // se apaga solo ante el primer error en el dibujo

    // medidor (REPORTE). "Propio" = tiempo de CPU en los tres enganches por cuadro de Viewpoint; el costo de GPU de las piezas
    // agregadas no entra ahi (lo dibuja Viewpoint despues), pero si en el tiempo entre cuadros, que se lleva aparte con y sin estelas.
    private static long frameNs;                                    // propio del cuadro en curso (las capturas van antes del snapshot)
    private static long lastFrameEndNs;
    private static long winStartNs, winNs, winMaxNs, winFrames;     // ventana de un segundo en curso
    static double secFps, secAvgUs, secMaxUs;                       // ultima ventana completa
    static long peakNs; static int peakDraws;                       // desde el ultimo resetStats
    static long gapWithNs, framesWith, gapWithoutNs, framesWithout; // tiempo entre cuadros con y sin estelas dibujadas

    private Ghosts() {}

    static boolean active() { return !disabled && Access.ok(); }

    static void fail(String where, Throwable e) {
        errors++;
        lastError = where + ": " + e;
        disabled = true;
        synchronized (LOCK) { ghosts.clear(); tracks.clear(); }
        System.out.println("[SandevistanVP] estelas 3D apagadas por un error en " + where + ": " + e);
        e.printStackTrace(System.out);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Llamadas desde Lua (SandevistanVP)

    static void stamp(Object character, long id) {
        if (character == null || !active()) return;
        synchronized (LOCK) {
            Track t = tracks.get(character);
            if (t == null) { t = new Track(); tracks.put(character, t); }
            if (t.pending.size() < MAX_PENDING) t.pending.add(id);
        }
    }

    static void show(long id, float r, float g, float b, float a, long now) {
        synchronized (LOCK) {
            Ghost gh = ghosts.get(id);
            if (gh == null) return;
            gh.r = r; gh.g = g; gh.b = b; gh.a = a;
            gh.shownMs = now;
            gh.usedMs = now;
        }
    }

    static void drop(long id) {
        synchronized (LOCK) {
            ghosts.remove(id);
            for (Track t : tracks.values()) t.pending.remove(Long.valueOf(id));
        }
    }

    static void clear() {
        synchronized (LOCK) { ghosts.clear(); tracks.clear(); }
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Enganches (Patches)

    /** Antes de ModelCapture.capture. */
    public static void captureEnter(Object frame, Object character) {
        if (disabled) return;
        long t0 = System.nanoTime();
        captures++;
        try {
            synchronized (LOCK) {
                capChar = null;
                if (tracks.isEmpty() || !tracks.containsKey(character) || !Access.ok()) return;
                ModelDraws d = Access.models(frame);
                capChar = character;
                capCount = Access.count(d);
                capBones = Access.bones(d);
            }
        } catch (Throwable e) {
            fail("captureEnter", e);
        } finally {
            frameNs += System.nanoTime() - t0;
        }
    }

    /** Despues de ModelCapture.capture (drawn = lo que devolvio: false si no agrego nada). */
    public static void captureExit(Object frame, Object character, boolean drawn) {
        if (disabled) return;
        long t0 = System.nanoTime();
        try {
            synchronized (LOCK) {
                if (capChar == null || capChar != character) return;
                capChar = null;
                Track t = tracks.get(character);
                if (t == null) return;
                ModelDraws d = Access.models(frame);
                int c1 = Access.count(d), b1 = Access.bones(d);
                if (!drawn || c1 <= capCount) return;
                t.frame = ((Frame) frame).number;
                t.c0 = capCount; t.c1 = c1; t.b0 = capBones; t.b1 = b1;
                long now = System.currentTimeMillis();
                while (!t.pending.isEmpty()) {
                    long id = t.pending.remove(0);
                    Ghost gh = keep(frame, d, t, id, character, now);
                    if (gh != null) ghosts.put(id, gh);
                }
            }
        } catch (Throwable e) {
            fail("captureExit", e);
        } finally {
            frameNs += System.nanoTime() - t0;
        }
    }

    /** Despues de Characters.snapshot: agrega las estelas visibles al final de la lista de dibujo. */
    public static void afterCharacters(Object frame) {
        // (143) los titeres van aparte de las estelas: se dibujan aunque no haya ninguna (parado, sin correr) y aunque el motor de
        // estelas se haya apagado por un error. Puppet3D maneja sus propias fallas y nunca lanza.
        try {
            Puppet3D.draw((Frame) frame);
        } catch (Throwable ignored) {
            // un cuadro raro (otro tipo de argumento en las pruebas) no puede tumbar el dibujo
        }
        if (disabled) return;
        long t0 = System.nanoTime();
        snapshots++;
        try {
            synchronized (LOCK) {
                try {
                    lastGhosts = 0;
                    lastDraws = 0;
                    if (ghosts.isEmpty()) { cleanTracks(); return; }
                    if (!Access.ok()) return;
                    draw(frame, System.currentTimeMillis());
                    cleanTracks();
                } finally {
                    endFrame(t0);
                }
            }
        } catch (Throwable e) {
            fail("afterCharacters", e);
        }
    }

    /** Cierra el cuadro en el medidor. */
    private static void endFrame(long t0) {
        long now = System.nanoTime();
        long spent = frameNs + (now - t0);
        frameNs = 0;
        if (lastFrameEndNs != 0) {
            long gap = now - lastFrameEndNs;
            if (gap < 500_000_000L) {                               // una pausa o una pantalla de carga no cuenta
                if (lastDraws > 0) { gapWithNs += gap; framesWith++; }
                else { gapWithoutNs += gap; framesWithout++; }
            }
        }
        lastFrameEndNs = now;
        if (spent > peakNs) peakNs = spent;
        if (lastDraws > peakDraws) peakDraws = lastDraws;
        if (winStartNs == 0) winStartNs = now;
        winNs += spent;
        winMaxNs = Math.max(winMaxNs, spent);
        winFrames++;
        if (now - winStartNs >= 1_000_000_000L) {
            secFps = winFrames * 1e9 / (now - winStartNs);
            secAvgUs = winNs / 1e3 / winFrames;
            secMaxUs = winMaxNs / 1e3;
            winStartNs = now; winNs = 0; winMaxNs = 0; winFrames = 0;
        }
    }

    static void resetStats() {
        synchronized (LOCK) {
            peakNs = 0; peakDraws = 0;
            gapWithNs = 0; framesWith = 0; gapWithoutNs = 0; framesWithout = 0;
        }
    }

    // ---------------------------------------------------------------------------------------------------------------

    /** Copia la pose del tramo [c0, c1) recien capturado. */
    private static Ghost keep(Object frame, ModelDraws d, Track t, long id, Object character, long now) throws IllegalAccessException {
        int n = t.c1 - t.c0;
        int boneCount = t.b1 - t.b0;
        Ghost gh = new Ghost(id, character);
        gh.n = n;
        gh.meshes = new ModelMesh[n];
        gh.values = new float[n * Access.VALUES];
        gh.pal = new int[n];
        ModelMesh[] meshes = Access.meshes(d);
        int[] palette = Access.palette(d), shadow = Access.shadowPalette(d), flags = Access.flags(d);
        System.arraycopy(meshes, t.c0, gh.meshes, 0, n);
        System.arraycopy(Access.values(d), t.c0 * Access.VALUES, gh.values, 0, n * Access.VALUES);
        int drawable = 0;
        for (int i = 0; i < n; i++) {
            int src = t.c0 + i;
            int p = shadow[src] >= 0 ? shadow[src] : palette[src];
            if (meshes[src] == null || (flags[src] & Access.GLASS) != 0) {
                gh.pal[i] = -2;                                  // vidrio (anteojos) o sin malla: la estela va sin eso
            } else if (p < 0) {
                gh.pal[i] = -1;                                  // pieza rigida (arma, objeto en la mano)
                drawable++;
            } else if (p >= t.b0 && p < t.b1) {
                gh.pal[i] = p - t.b0;
                drawable++;
            } else {
                gh.pal[i] = -2;                                  // huesos fuera del tramo del personaje: no se arriesga
            }
        }
        if (drawable == 0) return null;
        gh.boneCount = Math.max(0, boneCount);
        gh.bones = new float[gh.boneCount * Access.BONE_FLOATS];
        if (gh.boneCount > 0) System.arraycopy(Access.palettes(d), t.b0 * Access.BONE_FLOATS, gh.bones, 0, gh.bones.length);
        Frame f = (Frame) frame;
        gh.camX = f.camX; gh.camY = f.camY; gh.camZ = f.camZ;
        gh.usedMs = now;
        return gh;
    }

    private static void draw(Object frame, long now) throws IllegalAccessException {
        Frame f = (Frame) frame;
        ModelDraws d = f.scene.models;
        int added = 0, shown = 0;
        // Viewpoint borra lo que queda entre la camara y el pecho del jugador (camera_clear.glsl), salvo lo marcado SOLID, que es como
        // marca a los demas personajes (ModelDraws.whole). En tercera persona la estela queda justo ahi, detras del jugador: va SOLID.
        // En primera persona no: una estela pegada a la cara taparia la vista, y ese borrado cerca del ojo es lo que la saca.
        int flags = Access.COLOUR | (Access.viewThirdPerson() ? Access.SOLID : 0);
        Iterator<Map.Entry<Long, Ghost>> it = ghosts.entrySet().iterator();
        while (it.hasNext()) {
            Ghost gh = it.next().getValue();
            if (now - gh.usedMs > maxAgeMs) { it.remove(); continue; }
            if (now - gh.shownMs > showTimeoutMs || gh.a <= 0.004f) continue;
            Track t = tracks.get(gh.character);
            if (t == null || t.frame != f.number) continue;          // el personaje no se dibujo en este cuadro
            if (t.c1 - t.c0 != gh.n || !sameMeshes(d, t, gh)) { it.remove(); continue; }   // cambio la ropa o el arma
            if (added + gh.n > maxDraws) break;
            added += drawGhost(f, d, t, gh, flags);
            shown++;
        }
        lastGhosts = shown;
        lastDraws = added;
        if (added > 0) framesDrawn++;
    }

    private static boolean sameMeshes(ModelDraws d, Track t, Ghost gh) throws IllegalAccessException {
        ModelMesh[] meshes = Access.meshes(d);
        for (int i = 0; i < gh.n; i++) if (meshes[t.c0 + i] != gh.meshes[i]) return false;
        return true;
    }

    private static int drawGhost(Frame f, ModelDraws d, Track t, Ghost gh, int flags) throws IllegalAccessException {
        int base = gh.boneCount > 0 ? d.palette(gh.bones, gh.boneCount) : 0;
        float dx = f.camX - gh.camX;
        float dy = -(f.camZ - gh.camZ) * Access.FLOOR_UNITS;
        float dz = f.camY - gh.camY;
        int added = 0;
        for (int i = 0; i < gh.n; i++) {
            if (gh.pal[i] == -2) continue;
            int src = t.c0 + i, s = i * Access.VALUES;
            // las referencias se leen en cada vuelta: add agranda los arreglos
            ModelMesh mesh = Access.meshes(d)[src];
            zombie.core.skinnedmodel.model.ModelInstance inst = Access.instances(d)[src];
            zombie.core.textures.Texture tex = Access.textures(d)[src];
            int cull = Access.cull(d)[src];
            tmp.set(gh.values, s);
            tmp.m30(tmp.m30() + dx).m31(tmp.m31() + dy).m32(tmp.m32() + dz);
            int idx = d.add(mesh, inst, tex, tmp, gh.pal[i] >= 0 ? base + gh.pal[i] : -1, -1, cull, flags);
            float[] v = Access.values(d);
            int o = idx * Access.VALUES;
            // color: textura x material (sin rotar el tono)
            v[o + Access.MATERIAL] = gh.r * tintScale;
            v[o + Access.MATERIAL + 1] = gh.g * tintScale;
            v[o + Access.MATERIAL + 2] = gh.b * tintScale;
            v[o + Access.MATERIAL + 3] = 0f;
            // luz: la del cuadro en que se guardo, con un minimo para que brille
            v[o + Access.LIGHT] = Math.max(gh.values[s + Access.LIGHT], glow);
            v[o + Access.LIGHT + 1] = Math.max(gh.values[s + Access.LIGHT + 1], glow);
            v[o + Access.LIGHT + 2] = Math.max(gh.values[s + Access.LIGHT + 2], glow);
            v[o + Access.LIGHT + 3] = gh.values[s + Access.LIGHT + 3];
            // esfera de recorte (centro relativo a la camara) y coordenadas de textura (atlas de objetos)
            v[o + Access.SPHERE] = gh.values[s + Access.SPHERE] + dx;
            v[o + Access.SPHERE + 1] = gh.values[s + Access.SPHERE + 1] + dy;
            v[o + Access.SPHERE + 2] = gh.values[s + Access.SPHERE + 2] + dz;
            v[o + Access.SPHERE + 3] = gh.values[s + Access.SPHERE + 3];
            System.arraycopy(gh.values, s + Access.UV, v, o + Access.UV, 4);
            // sin contorno, y la matriz anterior igual a la actual (sin vector de movimiento: el TAA no la embarra)
            v[o + Access.OUTLINE + 3] = 0f;
            tmp.get(v, o + Access.PREVIOUS);
            // transparencia por tramado: se ve la fraccion a de los pixeles
            v[o + Access.FADE] = 0f;
            v[o + Access.FADE + 1] = Math.min(1f, Math.max(0f, gh.a));
            // punto de apoyo en el terreno (relieve): tambien relativo a la camara cuando se usa
            float mode = gh.values[s + Access.STAND + 3];
            v[o + Access.STAND] = gh.values[s + Access.STAND] + (mode != 0f ? dx : 0f);
            v[o + Access.STAND + 1] = gh.values[s + Access.STAND + 1] + (mode != 0f ? dy : 0f);
            v[o + Access.STAND + 2] = gh.values[s + Access.STAND + 2] + (mode != 0f ? dz : 0f);
            v[o + Access.STAND + 3] = mode;
            added++;
        }
        return added;
    }

    /** Saca los personajes que ya no tienen estelas ni pedidos. */
    private static void cleanTracks() {
        if (tracks.isEmpty()) return;
        IdentityHashMap<Object, Boolean> used = new IdentityHashMap<>();
        for (Ghost gh : ghosts.values()) used.put(gh.character, Boolean.TRUE);
        tracks.entrySet().removeIf(e -> e.getValue().pending.isEmpty() && !used.containsKey(e.getKey()));
    }

    static String stats() {
        synchronized (LOCK) {
            return "estelas guardadas=" + ghosts.size() + " | personajes=" + tracks.size()
                    + " | ultimo cuadro: " + lastGhosts + " estelas, " + lastDraws + " piezas"
                    + " | capturas=" + captures + " cuadros=" + snapshots + " con estelas=" + framesDrawn
                    + " | errores=" + errors + (lastError.isEmpty() ? "" : " (" + lastError + ")");
        }
    }

    private static String fps(long gapNs, long frames) {
        return frames == 0 ? "-" : String.format(java.util.Locale.ROOT, "%.0f (%d cuadros)", frames * 1e9 / gapNs, frames);
    }

    /** Medidor: ultimo segundo, pico y FPS de Viewpoint con y sin estelas dibujadas (desde resetStats). */
    static String perf() {
        synchronized (LOCK) {
            return String.format(java.util.Locale.ROOT,
                    "ultimo seg: %.0f fps, propio prom %.0f us, max %.0f us | pico %.0f us, %d piezas | fps con estelas %s, sin %s",
                    secFps, secAvgUs, secMaxUs, peakNs / 1e3, peakDraws, fps(gapWithNs, framesWith), fps(gapWithoutNs, framesWithout));
        }
    }
}
