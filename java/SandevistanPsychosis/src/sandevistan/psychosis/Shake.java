package sandevistan.psychosis;

import zombie.iso.IsoCamera;

/**
 * (181) C13.3 Sacudida de camara (31 §10.2): un temblor corto en los apagones, al empezar la furia, en la sobrecarga y en el susto.
 *
 * (183) Se corre la IMAGEN del mundo, no la camara. MultiTextureFBO2.render() pasa el mundo ya dibujado a la pantalla con una sola llamada
 * (Texture.rendershader2 con el rectangulo de la vista y el shader del clima); mientras dura el temblor, esa llamada va corrida y un poco
 * agrandada (el borde que se corre no queda negro). Se mueve todo junto (piso, personajes, objetos) y la camara del juego, el clic y el
 * apuntado no se tocan. Antes: la 181 sumaba a PlayerCamera.offX y no se vio; la 182 sumaba a la copia del cuadro (IsoCamera$FrameState) y
 * solo se movieron algunos objetos (el piso y los personajes se dibujan con otra cuenta). Los dos se sacaron.
 *
 * El desplazamiento es una suma de dos senos por eje (frecuencias distintas, fases al azar en cada temblor), en pixeles de pantalla, y se
 * apaga con una curva (1 - t)^2.
 */
public final class Shake {
    private Shake() {}

    static final int VIEWS = 4;
    /** Tope de la amplitud que acepta (pixeles de pantalla): un pedido mas grande se recorta. */
    public static float maxPx = 24f;
    public static final float[] ampPx = new float[VIEWS];
    static final long[] startNs = new long[VIEWS], endNs = new long[VIEWS];
    static final float[] phase = new float[VIEWS * 4];
    public static String problem = "";
    public static long shakes, frameStates;

    /** Empieza (o refuerza) un temblor de px pixeles de pantalla durante ms en la vista del jugador local view. */
    public static void start(int view, float px, long ms) {
        if (view < 0 || view >= VIEWS || px <= 0f || ms <= 0L) return;
        long now = System.nanoTime();
        float amp = Math.min(maxPx, px);
        // si ya hay uno mas fuerte en curso, se queda ese (un pedido chico no corta uno grande)
        if (now < endNs[view] && current(view, now) >= amp) return;
        ampPx[view] = amp;
        startNs[view] = now;
        endNs[view] = now + ms * 1_000_000L;
        java.util.concurrent.ThreadLocalRandom r = java.util.concurrent.ThreadLocalRandom.current();
        for (int i = 0; i < 4; i++) phase[view * 4 + i] = r.nextFloat() * 6.2831855f;
        shakes++;
    }

    public static void stop(int view) {
        if (view >= 0 && view < VIEWS) endNs[view] = 0L;
    }

    public static boolean active(int view) { return view >= 0 && view < VIEWS && System.nanoTime() < endNs[view]; }

    /** Amplitud de ahora (pixeles de pantalla): baja con (1 - t)^2. */
    static float current(int view, long now) {
        long end = endNs[view], start = startNs[view];
        if (now >= end || end <= start) return 0f;
        float t = (now - start) / (float) (end - start);
        float k = 1f - t;
        return ampPx[view] * k * k;
    }

    /** Desplazamiento de la vista en ese instante, en pixeles de pantalla (x, y en out). */
    static void offset(int view, long now, float[] out) {
        float a = current(view, now);
        if (a <= 0f) { out[0] = 0f; out[1] = 0f; return; }
        float s = (now - startNs[view]) / 1.0e9f;
        int p = view * 4;
        out[0] = a * (0.65f * (float) Math.sin(s * 81.7f + phase[p]) + 0.35f * (float) Math.sin(s * 131.9f + phase[p + 1]));
        out[1] = a * 0.6f * (0.6f * (float) Math.sin(s * 97.4f + phase[p + 2]) + 0.4f * (float) Math.sin(s * 149.3f + phase[p + 3]));
    }

    private static final float[] tmp = new float[2];

    /** El mundo se esta pasando a la pantalla (entre la entrada y la salida de MultiTextureFBO2.render()), y con que textura. */
    static boolean inWorld;
    static Object worldTex;
    /** Lo que tiene que usar la llamada original de rendershader2 (Patches.WorldBlit los copia a sus argumentos). */
    public static float outX, outY, outW, outH;

    /** Entrada de MultiTextureFBO2.render(). */
    public static void worldBegin(Object fbo) {
        inWorld = false;
        worldTex = null;
        if (!(fbo instanceof zombie.core.textures.MultiTextureFBO2 m) || m.current == null) return;
        long now = System.nanoTime();
        boolean any = false;
        for (int i = 0; i < VIEWS; i++) if (now < endNs[i]) any = true;
        if (!any) return;
        try {
            worldTex = m.current.getTexture();
            inWorld = worldTex != null;
        } catch (Throwable t) {
            problem = String.valueOf(t);
        }
    }

    /** Salida de MultiTextureFBO2.render() (antes de las copias de color de Screen: esas no se corren). */
    public static void worldEnd() {
        inWorld = false;
        worldTex = null;
    }

    /**
     * Entrada de Texture.rendershader2(x, y, w, h, ...): si es el mundo pasando a la pantalla en una vista que tiembla, deja en outX..outH el
     * rectangulo corrido y agrandado; si no, los mismos valores.
     */
    public static void world(Object tex, float x, float y, float w, float h) {
        outX = x;
        outY = y;
        outW = w;
        outH = h;
        if (!inWorld || tex != worldTex) return;
        try {
            long now = System.nanoTime();
            for (int i = 0; i < VIEWS; i++) {
                if (now >= endNs[i] || x != IsoCamera.getScreenLeft(i) || y != IsoCamera.getScreenTop(i)) continue;
                float a = current(i, now);
                if (a <= 0f) return;
                offset(i, now, tmp);
                float mx = a, my = a * 0.6f;                         // lo maximo que se corre en cada eje: se agranda eso por lado
                outX = x + tmp[0] - mx;
                outY = y + tmp[1] - my;
                outW = w + 2f * mx;
                outH = h + 2f * my;
                frameStates++;
                return;
            }
        } catch (Throwable t) {
            problem = String.valueOf(t);
            inWorld = false;
        }
    }

    static String stats() {
        return "sacudida: " + shakes + " temblores, " + frameStates + " cuadros corridos" + (problem.isEmpty() ? "" : " (" + problem + ")");
    }
}
