package sandevistan.psychosis;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Map;

import zombie.core.Color;
import zombie.core.textures.Texture;
import zombie.ui.MoodlesUI;
import zombie.ui.UIElement;

/**
 * (149) Glitch de los moodles vanilla (27 §12): el mismo que el panel del mod y los moodles de Moodle Framework (HUD.glitchUI), pero en Java,
 * porque a los vanilla los dibuja MoodlesUI.render(). Mientras dura (lo pide Lua con SandevistanPsy.moodleGlitch al empezar cada glitch de
 * pantalla), cada textura que MoodlesUI dibuja con DrawTexture/DrawTextureCol (fondo, borde e icono de cada moodle):
 *  - lleva una copia cian y una magenta corridas a los costados (separacion de color),
 *  - se corre un poco entera (temblor),
 *  - y a veces se dibuja desgarrada en tres tiras corridas (la original se dibuja transparente).
 * Al empezar, todos los moodles tiemblan (MoodlesUI.wiggle, el temblor de cuando suben de nivel: desde Lua no esta expuesto).
 * Los valores cambian cada TICK_NS, no en cada llamada: fondo, borde e icono de un moodle se mueven juntos dentro del mismo cuadro.
 */
public final class MoodleGlitch {
    private MoodleGlitch() {}

    static final long TICK_NS = 50_000_000L;
    static volatile long untilNs;
    static float amount = 1f;
    static boolean busy;
    public static String problem = "";
    public static long drawn, torn, episodes;

    // lo que cada enganche le pone a sus argumentos (todo en el hilo principal, al dibujar la interfaz)
    public static double outX, outY, outA;
    public static Color outCol;
    private static final Color CLEAR = new Color(0f, 0f, 0f, 0f);

    private static long bucket = -1;
    private static int jx, jy, sp;
    private static Field fState;

    /** Empieza (o alarga) un glitch de ms milisegundos; amount 0..1 lo hace mas o menos fuerte. */
    public static void start(float amount, long ms) {
        long until = System.nanoTime() + ms * 1_000_000L;
        if (until > untilNs) untilNs = until;
        MoodleGlitch.amount = Math.max(0f, Math.min(1f, amount));
        episodes++;
        wiggleAll();
    }

    public static boolean active() { return System.nanoTime() < untilNs; }

    private static void wiggleAll() {
        try {
            MoodlesUI ui = MoodlesUI.getInstance();
            if (ui == null) return;
            if (fState == null) {
                Field f = MoodlesUI.class.getDeclaredField("moodleUiState");
                f.setAccessible(true);
                fState = f;
            }
            Map<?, ?> state = (Map<?, ?>) fState.get(ui);
            if (state == null) return;
            for (Object t : new ArrayList<>(state.keySet())) ui.wiggle((zombie.scripting.objects.MoodleType) t);
        } catch (Throwable t) {
            problem = "temblor: " + t;
        }
    }

    private static void roll() {
        long b = System.nanoTime() / TICK_NS;
        if (b == bucket) return;
        bucket = b;
        java.util.concurrent.ThreadLocalRandom r = java.util.concurrent.ThreadLocalRandom.current();
        jx = Math.round((r.nextInt(5) - 2) * amount);
        jy = Math.round((r.nextInt(3) - 1) * amount);
        sp = 1 + r.nextInt(3);
    }

    /** El desgarro se decide por textura y por tick: el mismo moodle queda desgarrado todo el tick, no parpadea dentro del cuadro. */
    private static boolean tear(Texture tex) {
        long h = bucket * 0x9E3779B97F4A7C15L + System.identityHashCode(tex);
        h ^= h >>> 29;
        return (h & 3) == 0 && amount > 0.3f;
    }

    /** Enganche de UIElement.DrawTexture(Texture, x, y, alpha): deja en outX/outY/outA los argumentos para la pasada original. */
    public static void texture(Object self, Object tex, double x, double y, double a) {
        outX = x;
        outY = y;
        outA = a;
        if (busy || !(self instanceof MoodlesUI) || !(tex instanceof Texture) || !active()) return;
        draw((UIElement) self, (Texture) tex, x, y, 1, 1, 1, a);
        outX = x + jx;
        outY = y + jy;
        if (tear((Texture) tex)) outA = 0;
    }

    /** Enganche de UIElement.DrawTextureCol(Texture, x, y, Color): igual, con el color del fondo. */
    public static void textureCol(Object self, Object tex, double x, double y, Color col) {
        outX = x;
        outY = y;
        outCol = col;
        if (busy || !(self instanceof MoodlesUI) || !(tex instanceof Texture) || col == null || !active()) return;
        draw((UIElement) self, (Texture) tex, x, y, col.r, col.g, col.b, col.a);
        outX = x + jx;
        outY = y + jy;
        if (tear((Texture) tex)) outCol = CLEAR;
    }

    private static void draw(UIElement ui, Texture tex, double x, double y, float r, float g, float b, double a) {
        busy = true;
        try {
            roll();
            ui.DrawTextureColor(tex, x + jx + sp, y + jy, 0.2, 1, 1, a * 0.5);
            ui.DrawTextureColor(tex, x + jx - sp, y + jy, 1, 0.15, 0.85, a * 0.5);
            if (tear(tex)) {
                int tw = tex.getWidth(), th = tex.getHeight();
                java.util.concurrent.ThreadLocalRandom rnd = java.util.concurrent.ThreadLocalRandom.current();
                for (int i = 0; i < 3; i++) {
                    double dx = (rnd.nextInt(7) - 3) * amount;
                    ui.DrawSubTextureRGBA(tex, 0, th * i / 3.0, tw, th / 3.0, x + jx + dx, y + jy + th * i / 3.0, tw, th / 3.0, r, g, b, a);
                }
                torn++;
            }
            drawn++;
        } catch (Throwable t) {
            problem = String.valueOf(t);
            untilNs = 0;                                     // si algo falla, se corta el glitch; el moodle se dibuja normal
        } finally {
            busy = false;
        }
    }

    static String stats() {
        return "moodles: " + episodes + " glitches, " + drawn + " dibujos, " + torn + " desgarros" + (problem.isEmpty() ? "" : " (" + problem + ")");
    }
}
