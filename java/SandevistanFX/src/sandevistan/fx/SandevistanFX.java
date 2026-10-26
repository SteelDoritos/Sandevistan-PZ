package sandevistan.fx;

import me.zed_0xff.zombie_buddy.Exposer;

/**
 * Lo que ve Lua (global SandevistanFX, expuesta por ZombieBuddy). (152) La cyberpsicosis (titeres, texto corrupto, disfraz, moodles) se fue
 * a su propio mod, SandevistanPsychosis (clase SandevistanPsy). La usa SandevistanFX/Bridge.lua; los numeros llegan de Lua como double.
 * Sin `name` en la anotacion: ZombieBuddy la publica con el nombre simple de la clase (ver SandevistanVP).
 */
@Exposer.LuaClass
public final class SandevistanFX {
    private SandevistanFX() {}

    /** true si se puede cambiar el tono de los sonidos (FMOD cargado y los sonidos del personaje accesibles). */
    public static boolean pitchAvailable() { return Voices.ok && Fmod.ok(); }

    /** Tono de todos los sonidos del personaje (1 = normal y lo suelta). Devuelve cuantos eventos lo aceptaron, o -1 sin FMOD. */
    public static double pitch(Object character, double pitch) {
        return Voices.apply(character, (float) Math.max(0.25, Math.min(2.0, pitch)));
    }

    public static double releaseAll() { return Voices.releaseAll(); }

    /** Velocidad de la lluvia y la nieve isometricas (1 = normal); llega en rampMs. */
    public static void precip(double factor, double rampMs) {
        Rain.rampMs = (float) Math.max(0, Math.min(5000, rampMs));
        Rain.setTarget((float) factor, System.nanoTime());
    }

    public static double precipFactor() { return Rain.factor(); }

    /** (134b) Tono del ambiente del mundo (lluvia, viento): el buscado y en cuanto llega. */
    public static void ambience(double pitch, double rampMs) {
        Ambience.rampMs = (float) Math.max(0, Math.min(5000, rampMs));
        Ambience.setTarget((float) pitch, System.nanoTime());
    }

    /** Aplica la rampa del ambiente (Lua lo llama cada refresco). */
    public static double ambienceTick() { return Ambience.tick(); }

    /** Sonda de Debug: los eventos del personaje con su tono actual. */
    public static String probe(Object character) { return Voices.probe(character); }

    public static String status() {
        boolean f = Fmod.ok();
        return "FMOD " + (f ? "ok (" + Fmod.library + ")" : "NO: " + Fmod.problem)
                + " | sonidos " + (Voices.ok ? "ok" : "NO: " + Voices.problem)
                + (Rain.problem.isEmpty() ? "" : " | " + Rain.problem)
                + (Splash.problem.isEmpty() ? "" : " | " + Splash.problem)
                + (Ambience.problem.isEmpty() ? "" : " | " + Ambience.problem)
                + " | jar " + Main.VERSION;
    }

    public static String stats() {
        return String.format("tono: %d eventos (%d al nacer), %d llamadas, %d errores (ultimo %d), %d zombis | lluvia: factor %.3f, %d gotas frenadas"
                + " | salpicaduras: %d frenadas, %d retenidas, %d sin nacer | ambiente: tono %.2f, %d eventos", Voices.applied, Voices.started, Fmod.calls,
                Fmod.errors, Fmod.lastError, Voices.pitched.size(), Rain.factor(), Rain.frozen, Splash.slowed, Splash.held, Splash.blocked,
                Ambience.pitch(System.nanoTime()), Ambience.applied);
    }
}
