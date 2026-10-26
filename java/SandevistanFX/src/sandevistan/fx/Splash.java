package sandevistan.fx;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

import zombie.iso.IsoGridSquare;
import zombie.iso.IsoPuddles;

/**
 * (137) Salpicaduras de la lluvia en el piso exterior (lo que se ve "gotear" en veredas, techos bajos y bordes de las casas). No son RainParticle:
 * las dibuja IsoGridSquare.renderRainSplash(playerIndex, color), que en cada cuadro de render (no de juego) hace avanzar splashFrame
 * 0,08 x 30/lockFPS; al llegar a 1 la salpicadura termina (-1) y renace en otro punto de la casilla (splashX/Y al azar); con -1, cada cuadro
 * tira un dado para empezar otra. Por eso seguian a velocidad normal con la lluvia congelada.
 * El enganche guarda el estado al entrar y, al salir, escala lo que avanzo por Rain.factor(): el avance se multiplica por el factor, una que
 * iba a terminar sigue en su lugar si con el avance escalado no llego a 1, y una nueva nace solo con probabilidad = factor. Con el factor en 0
 * cada salpicadura queda congelada en su cuadro. El render de las casillas corre en el hilo principal y no se anida: alcanza con estaticos.
 * Tambien los charcos: IsoPuddles.update suma a puddlesTime (el reloj de las ondas del shader) 0,0166 x el multiplicador del juego, que el Sandi
 * no frena; el enganche escala ese avance por el mismo factor.
 */
public final class Splash {                 // publica: su enganche se copia dentro de IsoGridSquare (otro paquete)
    static long slowed, held, blocked;      // avances escalados, finales retenidos, nacimientos frenados (para status)
    static String problem = "";

    private static VarHandle frame, sx, sy, puddleTime;
    private static float puddleBefore = Float.NaN;
    private static boolean saved;
    private static float before, beforeX, beforeY;

    static {
        try {
            MethodHandles.Lookup l = MethodHandles.privateLookupIn(IsoGridSquare.class, MethodHandles.lookup());
            frame = l.findVarHandle(IsoGridSquare.class, "splashFrame", float.class);
            sx = l.findVarHandle(IsoGridSquare.class, "splashX", float.class);
            sy = l.findVarHandle(IsoGridSquare.class, "splashY", float.class);
        } catch (Throwable e) {
            problem = "salpicaduras: " + e + " (siguen a velocidad normal)";
            frame = null;
        }
        try {
            puddleTime = MethodHandles.privateLookupIn(IsoPuddles.class, MethodHandles.lookup()).findVarHandle(IsoPuddles.class, "puddlesTime", float.class);
        } catch (Throwable e) {
            problem = (problem.isEmpty() ? "" : problem + "; ") + "charcos: " + e;
            puddleTime = null;
        }
    }

    /** Enganche al entrar a IsoPuddles.update. */
    public static void puddlesEnter(Object puddles) {
        puddleBefore = Float.NaN;
        if (puddleTime == null || Rain.factor() >= 0.999f) return;
        try {
            puddleBefore = (float) puddleTime.get(puddles);
        } catch (Throwable e) {
            problem = "charcos: " + e;
            puddleTime = null;
        }
    }

    /** Enganche al salir: el reloj de las ondas avanza solo factor x lo que avanzo. */
    public static void puddlesExit(Object puddles) {
        float b = puddleBefore;
        puddleBefore = Float.NaN;
        if (Float.isNaN(b) || puddleTime == null) return;
        try {
            float after = (float) puddleTime.get(puddles);
            if (after > b) puddleTime.set(puddles, b + (after - b) * Rain.factor());
        } catch (Throwable e) {
            problem = "charcos: " + e;
            puddleTime = null;
        }
    }

    private Splash() {}

    /** Enganche al entrar a renderRainSplash. */
    public static void enter(Object square) {
        saved = false;
        if (frame == null || Rain.factor() >= 0.999f) return;
        try {
            before = (float) frame.get(square);
            beforeX = (float) sx.get(square);
            beforeY = (float) sy.get(square);
            saved = true;
        } catch (Throwable e) {
            fail(e);
        }
    }

    /** Enganche al salir: escala lo que la salpicadura avanzo en este cuadro. */
    public static void exit(Object square) {
        if (!saved) return;
        saved = false;
        try {
            adjust(square, Rain.factor(), (float) Math.random());
        } catch (Throwable e) {
            fail(e);
        }
    }

    /** La cuenta, aparte para probarla: f = factor de la lluvia, dice = numero al azar en [0, 1). */
    static void adjust(Object square, float f, float dice) {
        float after = (float) frame.get(square);
        if (after == before) return;
        if (before < 0f) {                                  // nacio una nueva en este cuadro
            if (after >= 0f && dice >= f) {
                frame.set(square, -1f);
                blocked++;
            }
            return;
        }
        if (after > before) {                               // avanzo
            frame.set(square, before + (after - before) * f);
            slowed++;
        } else if (after < 0f) {                            // termino: avanzo hasta 1 y volvio a -1 con otra posicion
            float step = 0.08f * 30f / lockFps();
            float next = before + step * f;
            if (next < 1f) {
                frame.set(square, next);
                sx.set(square, beforeX);
                sy.set(square, beforeY);
                held++;
            }
        }
    }

    private static float lockFps() {
        try {
            int fps = zombie.core.PerformanceSettings.getLockFPS();
            return fps > 0 ? fps : 60f;
        } catch (Throwable e) {
            return 60f;
        }
    }

    private static void fail(Throwable e) {
        problem = "salpicaduras: " + e;
        frame = null;                                       // se apaga solo: vuelven a la velocidad del juego
    }
}
