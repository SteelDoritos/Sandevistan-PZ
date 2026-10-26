package sandevistan.fx;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.ArrayList;
import java.util.List;

import fmod.fmod.FMODSoundEmitter;
import zombie.AmbientStreamManager;
import zombie.BaseAmbientStreamManager;
import zombie.audio.BaseSoundEmitter;

/**
 * (134b) Tono del ambiente del mundo. La lluvia no es un sonido aparte: el juego toca un solo evento de FMOD, World/Ambiance (sonido WorldAmbiance),
 * que mezcla lluvia, viento y fauna segun parametros (RainIntensity...). Esta en AmbientStreamManager.worldAmbienceEmitter (privado); los bucles
 * viejos (allAmbient) tienen su emisor publico. Bajarle el tono a esos eventos hace que la lluvia suene lenta (y el resto del ambiente tambien).
 * La rampa es la misma que la de la lluvia; tick() la aplica (Lua lo llama cada Config.FX.Pitch.RefreshMs).
 */
final class Ambience {
    static volatile float rampMs = 350f;
    static String problem = "";
    static long applied;

    private static volatile float target = 1f, from = 1f, last = 1f;
    private static volatile long changedNs;
    private static VarHandle worldEmitter;

    static {
        try {
            worldEmitter = MethodHandles.privateLookupIn(AmbientStreamManager.class, MethodHandles.lookup())
                    .findVarHandle(AmbientStreamManager.class, "worldAmbienceEmitter", BaseSoundEmitter.class);
        } catch (Throwable e) {
            problem = "ambiente: " + e;
        }
    }

    private Ambience() {}

    static synchronized void setTarget(float t, long nowNs) {
        t = Math.max(0.25f, Math.min(1f, t));
        if (t == target) return;
        from = pitch(nowNs);
        target = t;
        changedNs = nowNs;
    }

    static float pitch(long nowNs) {
        float t = target, f = from;
        if (f == t) return t;
        float k = (nowNs - changedNs) / (rampMs * 1e6f);
        if (k >= 1f || rampMs <= 0f) { from = t; return t; }
        if (k <= 0f) return f;
        k = k * k * (3f - 2f * k);
        return f + (t - f) * k;
    }

    /** Los emisores del ambiente que hay ahora. */
    static List<FMODSoundEmitter> emitters() {
        List<FMODSoundEmitter> out = new ArrayList<>();
        BaseAmbientStreamManager b = AmbientStreamManager.instance;
        if (!(b instanceof AmbientStreamManager m)) return out;
        if (worldEmitter != null && worldEmitter.get(m) instanceof FMODSoundEmitter f) out.add(f);
        for (AmbientStreamManager.AmbientLoop l : m.allAmbient) if (l != null && l.emitter != null) out.add(l.emitter);
        return out;
    }

    /** Aplica el tono de la rampa a los eventos del ambiente (mientras no este en 1, o al volver a 1). Devuelve cuantos eventos lo aceptaron. */
    static int tick() {
        float p = pitch(System.nanoTime());
        if (p >= 0.999f && last >= 0.999f) return 0;
        last = p;
        if (!Voices.ok || !Fmod.ok()) return -1;
        int n = 0;
        try {
            for (FMODSoundEmitter f : emitters())
                for (long e : Voices.events(f)) if (Fmod.setPitch(e, p) == Fmod.OK) n++;
        } catch (Throwable e) {
            problem = "ambiente: " + e;
        }
        applied += n;
        return n;
    }
}
