package sandevistan.fx;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

import zombie.iso.weather.fx.RainParticle;
import zombie.iso.weather.fx.SnowParticle;

/**
 * Lluvia y nieve isometricas congeladas. RainParticle.update(delta) y SnowParticle.update(delta) avanzan la gota velocidad x delta y le restan 1 a su
 * vida en cada cuadro (al llegar a 0 renace en otro lugar). El enganche multiplica delta por factor() y devuelve a la vida la parte que no debio
 * gastar (1 - factor), asi la gota queda quieta en el aire en vez de quieta y renaciendo. factor() va de un valor al otro en rampMs (suave).
 */
public final class Rain {                   // publica: su enganche se copia dentro de RainParticle y SnowParticle (otro paquete)
    static volatile float rampMs = 350f;
    static long frozen;                 // actualizaciones de gotas frenadas (para status)
    static String problem = "";

    private static volatile float target = 1f;
    private static volatile float from = 1f;
    private static volatile long changedNs;
    private static VarHandle rainLife, snowLife;

    static {
        try {
            rainLife = MethodHandles.privateLookupIn(RainParticle.class, MethodHandles.lookup()).findVarHandle(RainParticle.class, "life", float.class);
            snowLife = MethodHandles.privateLookupIn(SnowParticle.class, MethodHandles.lookup()).findVarHandle(SnowParticle.class, "life", float.class);
        } catch (Throwable e) {
            problem = "vida de las gotas: " + e + " (frenan igual, pero renacen)";
        }
    }

    private Rain() {}

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

    /** Enganche: delta para esta gota (y su vida devuelta). */
    public static float particle(Object p, float delta) {
        float f = factor();
        if (f >= 0.999f) return delta;
        try {
            VarHandle life = p instanceof RainParticle ? rainLife : p instanceof SnowParticle ? snowLife : null;
            if (life != null) life.set(p, (float) life.get(p) + (1f - f));
        } catch (Throwable e) {
            problem = "vida de las gotas: " + e;
            rainLife = snowLife = null;
        }
        frozen++;
        return delta * f;
    }
}
