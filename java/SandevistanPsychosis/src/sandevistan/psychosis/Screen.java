package sandevistan.psychosis;

import zombie.IndieGL;
import zombie.characters.IsoPlayer;
import zombie.core.textures.MultiTextureFBO2;
import zombie.core.textures.Texture;
import zombie.core.textures.TextureDraw;
import zombie.iso.IsoCamera;

/**
 * (181) C13.5 Efectos de pantalla de los episodios (31 §10.2), sin reemplazar ningun shader del juego:
 *
 *  - Desaturacion, ondulacion y desenfoque: el mundo pasa a la pantalla con el shader del clima (WeatherShader, media/shaders/screen.frag) y ese
 *    shader ya trae DesaturationVal, DrunkFactor (la ondulacion y el borde borroso de la borrachera, 0..1 = intoxicacion / 100) y BlurFactor.
 *    WeatherShader.startMainThread(TextureDraw, vista) carga esos valores en TextureDraw.vars (4 = desaturacion, 22 = borrachera,
 *    23 = desenfoque); a la salida se suben al maximo entre el del juego y el del episodio. Se dibuja igual que siempre.
 *  - Separacion de color y desgarro: a la salida de MultiTextureFBO2.render() (donde el mundo ya se paso a la pantalla, antes de la interfaz)
 *    se dibuja la misma imagen del mundo otra vez: dos copias corridas a los costados, cian y magenta, casi transparentes, y a veces tiras
 *    horizontales corridas. Son dibujos comunes (Texture.rendershader2, el mismo que usa el juego para esa pasada) con el shader de siempre.
 *
 * Por vista de jugador local. Lua pide los valores y cuanto dura (con fundido de entrada y de salida); si algo falla, se apaga solo.
 */
public final class Screen {
    private Screen() {}

    static final int VIEWS = 4;
    static final float[] desat = new float[VIEWS], wobble = new float[VIEWS], blur = new float[VIEWS], split = new float[VIEWS], tear = new float[VIEWS];
    public static final long[] startNs = new long[VIEWS], endNs = new long[VIEWS];
    public static long fadeInNs = 250_000_000L, fadeOutNs = 700_000_000L;
    /** (183) Fundidos de cada vista: los de arriba como tope, y en un efecto corto una parte de lo que dura (ver start). */
    static final long[] fadeIn = new long[VIEWS], fadeOut = new long[VIEWS];
    /** Corrimiento maximo de las copias de color y de las tiras (pixeles de pantalla, con split / tear en 1). */
    public static float splitPx = 12f, tearPx = 46f;
    public static float splitAlpha = 0.22f;
    static final long TICK_NS = 60_000_000L;
    public static String problem = "";
    public static long episodes, shaded, overlays, torn;
    static boolean overlayOff;

    /** Empieza un efecto en la vista view (valores 0..1) durante ms. Pisa al anterior de esa vista. */
    public static void start(int view, float d, float w, float b, float s, float t, long ms) {
        if (view < 0 || view >= VIEWS || ms <= 0L) return;
        long now = System.nanoTime();
        boolean running = now < endNs[view];
        desat[view] = clamp(d);
        wobble[view] = clamp(w);
        blur[view] = clamp(b);
        split[view] = clamp(s);
        tear[view] = clamp(t);
        long dur = ms * 1_000_000L;
        // (183) con fundidos fijos un golpe corto (300-900 ms) no llegaba a pleno: entra en un quinto y sale en un tercio de lo que dura
        if (!running) {                            // si ya habia uno, no vuelve a entrar de a poco
            startNs[view] = now;
            fadeIn[view] = Math.min(fadeInNs, dur / 5);
        }
        fadeOut[view] = Math.min(fadeOutNs, dur / 3);
        endNs[view] = now + dur;
        episodes++;
    }

    /** Termina con el fundido de salida (no de golpe). */
    public static void stop(int view) {
        if (view < 0 || view >= VIEWS) return;
        long now = System.nanoTime();
        if (endNs[view] > now + fadeOut[view]) endNs[view] = now + fadeOut[view];
    }

    public static boolean active(int view) { return view >= 0 && view < VIEWS && System.nanoTime() < endNs[view]; }

    static float clamp(float v) { return v < 0f ? 0f : (v > 1f ? 1f : v); }

    /** 0..1: entra en fadeIn y sale en los ultimos fadeOut de la vista. */
    static float envelope(int view, long now) {
        long end = endNs[view], start = startNs[view];
        if (now >= end) return 0f;
        long fi = fadeIn[view], fo = fadeOut[view];
        float in = fi <= 0 ? 1f : Math.min(1f, (now - start) / (float) fi);
        float out = fo <= 0 ? 1f : Math.min(1f, (end - now) / (float) fo);
        return Math.max(0f, Math.min(in, out));
    }

    /** Enganche a la salida de WeatherShader.startMainThread(TextureDraw, vista): sube los valores del shader del clima de esa vista. */
    public static void shaderVars(Object td, int view) {
        if (view < 0 || view >= VIEWS || !(td instanceof TextureDraw draw)) return;
        long now = System.nanoTime();
        if (now >= endNs[view]) return;
        try {
            float[] v = draw.vars;
            if (v == null || v.length < 24) return;
            float e = envelope(view, now);
            v[4] = Math.max(v[4], desat[view] * e);
            v[22] = Math.max(v[22], wobble[view] * e);
            v[23] = Math.max(v[23], blur[view] * e);
            shaded++;
        } catch (Throwable t) {
            problem = "shader: " + t;
            endNs[view] = 0L;
        }
    }

    private static long bucket = -1;
    private static final float[] jitter = new float[VIEWS];
    private static final int[][] bands = new int[VIEWS][9];        // hasta 3 tiras: { y (0..1000), alto (pixeles), corrimiento (pixeles) }
    private static final int[] bandCount = new int[VIEWS];

    /** Cada TICK_NS cambian el largo de la separacion y las tiras (no en cada cuadro: se lee como una imagen que falla, no como ruido). */
    private static void roll(long now) {
        long b = now / TICK_NS;
        if (b == bucket) return;
        bucket = b;
        java.util.concurrent.ThreadLocalRandom r = java.util.concurrent.ThreadLocalRandom.current();
        for (int i = 0; i < VIEWS; i++) {
            jitter[i] = 0.55f + 0.45f * r.nextFloat();
            if (r.nextFloat() < 0.12f) jitter[i] *= 2.2f;              // a veces una pasada mas lejos
            int n = 0;
            if (tear[i] > 0f && r.nextFloat() < 0.55f * tear[i]) n = 1 + r.nextInt(3);
            bandCount[i] = n;
            for (int k = 0; k < n; k++) {
                bands[i][k * 3] = r.nextInt(1000);
                bands[i][k * 3 + 1] = 4 + r.nextInt(36);
                bands[i][k * 3 + 2] = (r.nextBoolean() ? 1 : -1) * (6 + r.nextInt(Math.max(1, Math.round(tearPx * tear[i]))));
            }
        }
    }

    /** Enganche a la salida de MultiTextureFBO2.render(): la separacion de color y el desgarro encima del mundo de cada vista con efecto. */
    public static void overlay(Object self) {
        if (overlayOff || !(self instanceof MultiTextureFBO2 fbo) || fbo.current == null) return;
        long now = System.nanoTime();
        boolean any = false;
        for (int i = 0; i < VIEWS; i++) if (now < endNs[i] && (split[i] > 0f || tear[i] > 0f)) any = true;
        if (!any) return;
        // (182) Core.RenderOffScreenBuffer apaga la mezcla antes de render() (disableBlend ... enableBlend): sin prenderla aca las copias salian
        // opacas (todo el mundo magenta). Se prende solo para estos dibujos (se encolan en orden) y se deja como estaba.
        boolean blend = false;
        try {
            Object it = fbo.current.getTexture();
            if (!(it instanceof Texture tex)) return;
            roll(now);
            IndieGL.enableBlend();
            IndieGL.glBlendFunc(770, 771);                           // GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA
            blend = true;
            for (int i = 0; i < VIEWS; i++) {
                if (now >= endNs[i] || IsoPlayer.players[i] == null) continue;
                float e = envelope(i, now);
                if (e <= 0f) continue;
                int l = IsoCamera.getScreenLeft(i), t = IsoCamera.getScreenTop(i), w = IsoCamera.getScreenWidth(i), h = IsoCamera.getScreenHeight(i);
                if (w <= 0 || h <= 0) continue;
                if (split[i] > 0f) {
                    float dx = Math.max(1f, splitPx * split[i] * e * jitter[i]);
                    float a = splitAlpha * split[i] * e;
                    // (183) sumadas (no tapando): la copia es la imagen sin el shader del clima, y tapando devolvia el color y la nitidez
                    // (en el video de la 182, el golpe encima de la disociacion le sacaba la desaturacion, y el golpe solo no se notaba)
                    IndieGL.glBlendFunc(770, 1);                     // GL_SRC_ALPHA, GL_ONE
                    tex.rendershader2(l + dx, t, w, h, l, t, w, h, 0f, 0.85f, 1f, a);
                    tex.rendershader2(l - dx, t, w, h, l, t, w, h, 1f, 0f, 0.85f, a);
                    IndieGL.glBlendFunc(770, 771);
                }
                for (int k = 0; k < bandCount[i]; k++) {
                    int by = t + bands[i][k * 3] * h / 1000;
                    int bh = Math.min(bands[i][k * 3 + 1], t + h - by);
                    if (bh <= 0) continue;
                    float sx = bands[i][k * 3 + 2] * e;
                    tex.rendershader2(l + sx, by, w, bh, l, by, w, bh, 1f, 1f, 1f, 1f);
                    torn++;
                }
                overlays++;
            }
        } catch (Throwable t) {
            problem = "copias: " + t;
            overlayOff = true;                                       // el resto (desaturacion, ondulacion) sigue
            System.out.println("[SandevistanPsy] efectos de pantalla: sin separacion de color ni desgarro: " + t);
        } finally {
            if (blend) IndieGL.disableBlend();
        }
    }

    static String stats() {
        return String.format("pantalla: %d efectos, %d pasadas del shader, %d cuadros con copias, %d tiras%s", episodes, shaded, overlays, torn,
                problem.isEmpty() ? "" : " (" + problem + ")");
    }
}
