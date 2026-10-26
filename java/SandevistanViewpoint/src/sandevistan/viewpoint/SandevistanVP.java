package sandevistan.viewpoint;

import me.zed_0xff.zombie_buddy.Exposer;

/**
 * Lo que ve Lua (global SandevistanVP, expuesta por ZombieBuddy). La usa
 * SandevistanViewpoint/Bridge.lua; los numeros llegan de Lua como double.
 *
 * Sin `name`: ZombieBuddy la publica con el nombre simple de la clase. En la 2.3.4, un `name` sin punto igual al nombre de la
 * clase la borra (Exposer.exposeClassNow copia la global al nombre nuevo y despues pone nil en el viejo, que es el mismo).
 *
 * (136) El jar sirve para los dos modos y la camara decide cual: con la camara 3D de Viewpoint las dibuja Ghosts (poses dentro
 * de esa camara); en la isometrica normal las dibuja IsoGhosts con el pipeline del juego. Viewpoint pasa a ser opcional.
 */
@Exposer.LuaClass
public final class SandevistanVP {
    private SandevistanVP() {}

    /** true si el jar puede dibujar en el modo de camara actual: 3D (Viewpoint) o isometrico (el juego). */
    public static boolean available() { return is3D() ? Ghosts.active() : IsoGhosts.active(); }

    /** La camara 3D de Viewpoint esta encendida (dato exacto, sin el heuristico de Viewport.lua); false si no esta instalado. */
    public static boolean is3D() { return Access.viewEnabled(); }

    public static boolean thirdPerson() { return Access.viewThirdPerson(); }

    /** Pide guardar la pose de `character` en la proxima captura, como la estela `id` (el modo lo decide la camara). */
    public static void stamp(Object character, double id) {
        stamp(character, id, Double.NaN, Double.NaN, Double.NaN);
    }

    /**
     * (138h) Igual, con la posicion donde Lua grabo la estela. En isometrico, si la captura se reintenta un cuadro despues, la pose
     * es la nueva pero la estela queda en el lugar donde nacio. En 3D la posicion sale del cuadro de Viewpoint: se ignora.
     */
    public static void stamp(Object character, double id, double x, double y, double z) {
        long uid = (long) id;
        if (is3D()) Ghosts.stamp(character, uid); else IsoGhosts.stamp(character, uid, (float) x, (float) y, (float) z);
    }

    /** Muestra la estela `id` este cuadro con ese color y esa opacidad (0..1). */
    public static void show(double id, double r, double g, double b, double a) {
        long uid = (long) id;
        long now = System.currentTimeMillis();
        if (is3D()) Ghosts.show(uid, (float) r, (float) g, (float) b, (float) a, now);
        else IsoGhosts.show(uid, (float) r, (float) g, (float) b, (float) a, now);
    }

    public static void drop(double id) {
        long uid = (long) id;
        if (is3D()) Ghosts.drop(uid); else IsoGhosts.drop(uid);
    }

    public static void clear() {
        Ghosts.clear();
        IsoGhosts.clear();
    }

    /** Aspecto: multiplicador del color, luz minima y tope de piezas agregadas por cuadro (igual para los dos modos). */
    public static void look(double tint, double glow, double maxDraws) {
        float t = (float) Math.max(0.1, Math.min(4.0, tint));
        float l = (float) Math.max(0.0, Math.min(4.0, glow));
        int m = (int) Math.max(0, Math.min(5000, maxDraws));
        Ghosts.tintScale = t;
        Ghosts.glow = l;
        Ghosts.maxDraws = m;
        IsoGhosts.tintScale = t;
        IsoGhosts.glow = l;
        IsoGhosts.maxDraws = m;
    }

    /** Version de Viewpoint (opcional), y el estado de cada modo, con el motivo si algo no anda. */
    public static String status() {
        boolean ok = Access.ok();
        return (ok ? "Viewpoint " + Access.version + " compatible" : Access.problem())
                + (Ghosts.disabled ? " | 3D apagado por un error: " + Ghosts.lastError : "")
                + " | jar " + Main.VERSION
                + " | isometrico: " + (IsoGhosts.active() ? "listo" : "NO disponible (" + IsoGhosts.problem + ")");
    }

    public static String stats() {
        if (is3D()) {
            return Ghosts.stats() + String.format(" | lluvia 3D: factor %.3f, %d cuadros frenados%s", Rain3D.factor(), Rain3D.frames,
                    Rain3D.problem.isEmpty() ? "" : " (" + Rain3D.problem + ")") + " | " + Puppet3D.stats() + " | " + Hide3D.stats();
        }
        return IsoGhosts.stats();
    }

    /** (134) Velocidad de la lluvia 3D (1 = normal), en cuanto tiempo llega y el trazo minimo de cada gota. */
    public static void precip(double factor, double rampMs, double streak) {
        if (!Access.ok()) return;                     // sin Viewpoint no hay lluvia 3D que frenar
        Rain3D.rampMs = (float) Math.max(0, Math.min(5000, rampMs));
        Rain3D.streak = (float) Math.max(0.01, Math.min(1, streak));
        Rain3D.setTarget((float) factor, System.nanoTime());
    }

    /** Medidor de rendimiento: en 3D son los cuadros de Viewpoint; en isometrico, los us de CPU de los enganches. */
    public static String perf() { return is3D() ? Ghosts.perf() : IsoGhosts.perf(); }

    /** Vuelve a cero el pico y los FPS con y sin estelas, para medir desde ahora. */
    public static void resetStats() { Ghosts.resetStats(); }
}
