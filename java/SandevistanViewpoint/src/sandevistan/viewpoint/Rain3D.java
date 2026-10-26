package sandevistan.viewpoint;

import viewpoint.platform.Gl;
import viewpoint.platform.GlProgram;
import viewpoint.platform.Tuning;
import viewpoint.render.SceneData;

/**
 * (134) Lluvia congelada en la camara 3D de Viewpoint. Las gotas, los copos y los anillos de los charcos salen del shader con un reloj, uRainClock
 * (SceneData.time mod 600, el periodo RAIN_PERIOD de lib/weather.glsl), que se carga en FrameUniforms.one y en WeatherPass.air. Aca ese reloj se
 * cambia por uno propio que avanza factor() veces mas lento: real - offset, con offset creciendo dt x (1 - factor). Al apagar el implante el offset
 * queda (el reloj sigue continuo, sin salto de las gotas). Ademas el largo del trazo de cada gota (Tuning.rainExposure, el "tiempo de exposicion"
 * del shader) se achica con el factor, hasta Streak: una gota quieta no deja estela.
 * (134b) De costado las gotas se mueven con uWindOffset = origen - viento acumulado (SceneData.windCarriedX/Z, que Viewpoint suma en tiempo real):
 * se frena igual, con un desfase propio que crece con lo que avanzo el viento x (1 - factor).
 */
public final class Rain3D {                 // publica: sus enganches se copian dentro de clases de Viewpoint (otro paquete)
    static final float PERIOD = 600f;
    static volatile float rampMs = 350f;
    static volatile float streak = 0.15f;
    static long frames;
    static volatile boolean off;        // se apaga sola ante un error (sin tocar las estelas)
    static String problem = "";

    private static volatile float target = 1f;
    private static volatile float from = 1f;
    private static volatile long changedNs;
    private static float lastRaw = Float.NaN;
    private static float offset;
    private static float savedExposure = Float.NaN;
    static final double WIND_WRAP = 12288.0;        // el mismo periodo que usa WeatherPass.air
    private static double lastWindX = Double.NaN, lastWindZ, windOffX, windOffZ;

    private Rain3D() {}

    static synchronized void setTarget(float t, long nowNs) {
        t = Math.max(0f, Math.min(1f, t));
        if (t == target) return;
        from = factor(nowNs);
        target = t;
        changedNs = nowNs;
    }

    static float target() { return target; }

    static float factor() { return factor(System.nanoTime()); }

    static float factor(long nowNs) {
        float t = target, f = from;
        if (f == t) return t;
        float k = (nowNs - changedNs) / (rampMs * 1e6f);
        if (k >= 1f || rampMs <= 0f) { from = t; return t; }
        if (k <= 0f) return f;
        k = k * k * (3f - 2f * k);
        return f + (t - f) * k;
    }

    /** El reloj de la lluvia para este valor real (mod 600). Varias llamadas con el mismo valor en un cuadro dan lo mismo. */
    static synchronized float clock(float raw, float f) {
        if (Float.isNaN(lastRaw)) lastRaw = raw;
        float dt = raw - lastRaw;
        if (dt < -PERIOD / 2) dt += PERIOD;          // el reloj real dio la vuelta
        if (dt < 0f || dt > 5f) dt = 0f;              // salto (cargar partida, pausa larga): no se arrastra
        lastRaw = raw;
        if (dt > 0f) {
            offset = (offset + dt * (1f - f)) % PERIOD;
            frames++;
        }
        float v = (raw - offset) % PERIOD;
        return v < 0f ? v + PERIOD : v;
    }

    public static float clock(float raw) {
        if (off) return raw;
        float f = factor();
        if (f >= 0.999f && offset == 0f) { lastRaw = raw; return raw; }
        return clock(raw, f);
    }

    /** Desfase del viento acumulado (x, z) para este valor de Viewpoint; varias llamadas en un cuadro dan lo mismo. */
    static synchronized double[] wind(double carriedX, double carriedZ, float f) {
        if (Double.isNaN(lastWindX)) { lastWindX = carriedX; lastWindZ = carriedZ; }
        double dx = carriedX - lastWindX, dz = carriedZ - lastWindZ;
        lastWindX = carriedX; lastWindZ = carriedZ;
        if (Math.abs(dx) > 50 || Math.abs(dz) > 50) { dx = 0; dz = 0; }      // salto (cargar partida): no se arrastra
        windOffX = (windOffX + dx * (1f - f)) % WIND_WRAP;
        windOffZ = (windOffZ + dz * (1f - f)) % WIND_WRAP;
        return new double[] { windOffX, windOffZ };
    }

    /** Enganche de WeatherPass.air(GlProgram, SceneData): vuelve a cargar uRainClock y uWindOffset con los relojes propios. */
    public static void air(Object program, Object scene) {
        try {
            if (off || !(program instanceof GlProgram p) || !(scene instanceof SceneData s)) return;
            float f = factor();
            double[] w = wind(s.windCarriedX, s.windCarriedZ, f);              // siempre: sigue el viento aunque no haga falta corregir
            if (offset == 0f && w[0] == 0 && w[1] == 0 && f >= 0.999f) return;
            if (p.has("uWindOffset"))
                p.set("uWindOffset", Gl.wrap(s.originX - s.windCarriedX + w[0], WIND_WRAP), Gl.wrap(s.originZ - s.windCarriedZ + w[1], WIND_WRAP));
            if (p.has("uRainClock")) p.set("uRainClock", clock(s.time % PERIOD));
        } catch (Throwable e) {
            off = true;
            problem = "lluvia 3D apagada: " + e;
            System.out.println("[SandevistanVP] " + problem);
        }
    }

    /** Enganches de WeatherPass.uniforms: el trazo de las gotas mas corto mientras dura, y el valor de Viewpoint de vuelta al salir. */
    public static void exposureEnter() {
        if (off) return;
        float f = factor();
        if (f >= 0.999f) return;
        savedExposure = Tuning.rainExposure;
        Tuning.rainExposure = savedExposure * Math.max(streak, f);
    }

    public static void exposureExit() {
        if (!Float.isNaN(savedExposure)) {
            Tuning.rainExposure = savedExposure;
            savedExposure = Float.NaN;
        }
    }
}
