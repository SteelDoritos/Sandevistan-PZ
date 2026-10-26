package sandevistan.psychosis;

import me.zed_0xff.zombie_buddy.Exposer;

/**
 * (152) Lo que ve Lua del mod opcional SandevistanPsychosis (global SandevistanPsy, expuesta por ZombieBuddy con el nombre simple de la clase;
 * no SandevistanPsychosis porque esa global ya es la tabla de Psychosis.lua). La usa SandevistanPsychosis/Bridge.lua; los numeros llegan como
 * double. Antes estaba dentro de SandevistanFX (138..151): mismas funciones, mismos nombres.
 */
@Exposer.LuaClass
public final class SandevistanPsy {
    private SandevistanPsy() {}

    // (138) Titeres (Puppets): zombis que dibuja solo este cliente. Los usa Sandevistan/FakeZombies.lua por SandevistanPsychosis/Bridge.lua.

    public static boolean puppetsAvailable() { return Puppets.ok(); }

    /** Nace el titere id con el atuendo outfit (nombre de clothing.xml) en x, y, z, visto por el jugador local playerNum. */
    public static boolean puppetSpawn(double id, String outfit, Object female, double x, double y, double z, double playerNum) {
        return Puppets.spawn((long) id, outfit, Boolean.TRUE.equals(female), (float) x, (float) y, (float) z, (int) playerNum);
    }

    /** (148) El clon: un titere con la visual y la ropa del personaje (character), animado como persona (idle, walk, run, ext). */
    public static boolean puppetSpawnClone(double id, Object character, double x, double y, double z, double playerNum) {
        return Puppets.spawnClone((long) id, character, (float) x, (float) y, (float) z, (int) playerNum);
    }

    public static void puppetSetState(double id, String state) { Puppets.setState((long) id, state); }

    /** Posicion, velocidad (casillas por segundo, para seguir entre ticks) y hacia donde mira. */
    public static void puppetMove(double id, double x, double y, double z, double vx, double vy, double fx, double fy) {
        Puppets.move((long) id, (float) x, (float) y, (float) z, (float) vx, (float) vy, (float) fx, (float) fy);
    }

    /** Variable de animacion del grupo "zombie" (bMoving, bLunge, zombieWalkType, bAttack...): "true"/"false", numero o texto; nil la borra. */
    public static void puppetVar(double id, String name, String value) { Puppets.var((long) id, name, value); }

    public static void puppetLook(double id, double alpha, double r, double g, double b) {
        Puppets.look((long) id, (float) alpha, (float) r, (float) g, (float) b);
    }

    public static String puppetState(double id) { return Puppets.state((long) id); }

    /** (138e) Paso de la animacion del titere (casillas por segundo de juego), -1 si todavia no se midio. */
    public static double puppetSpeed(double id) { return Puppets.speed((long) id); }

    /** (142) 0..1 mientras el titere se deshace: separacion de color cian/magenta (lo decide FakeZombies.lua). */
    public static void puppetGlitch(double id, double amount) { Puppets.glitch((long) id, (float) amount); }

    /** (141) Contorno rojo como el de un zombi real: el jugador lo tiene como blanco melee (esto lo decide FakeZombies.lua). */
    public static void puppetOutline(double id, Object on) { Puppets.outline((long) id, Boolean.TRUE.equals(on)); }

    public static void puppetRemove(double id) { Puppets.remove((long) id); }

    public static void puppetClear() { Puppets.clear(); }

    public static double puppetCount() { return Puppets.count(); }

    public static String puppetStats() {
        return Puppets.stats() + String.format(" | texto corrupto: %d episodios, %d textos cambiados", TextGlitch.episodes, TextGlitch.changed);
    }

    /** (149) Glitch de los moodles vanilla durante ms (amount 0..1): copias de color, temblor y desgarro, como el panel del mod. */
    public static void moodleGlitch(double amount, double ms) { MoodleGlitch.start((float) amount, (long) ms); }

    public static String moodleGlitchStats() { return MoodleGlitch.stats(); }

    /** (147) Disfraz (prueba, 22 §6.2.1): 0 nada, 1 persona, 2..4 zombi con podredumbre 1..3. Solo lo ve este cliente. */
    public static boolean disguise(Object character, double mode) { return Disguise.set(character, (int) mode); }

    public static double disguiseMode(Object character) { return Disguise.mode(character); }

    public static void disguiseClear() { Disguise.clear(); }

    /**
     * (174) Disfraz nivel B (29 §4.1): este cliente deja de dibujar al jugador character (cuerpo, sombra y nombre) y en su lugar va el titere
     * puppetId, un zombi con su ropa y podredumbre rot (1..3) que lo sigue. Solo jugadores. false si no se pudo (entonces no se oculta nada).
     */
    public static boolean disguiseHide(Object character, double puppetId, double playerNum, double rot) {
        return Disguise.hide(character, (long) puppetId, (int) playerNum, (int) rot);
    }

    /** (174) Vuelve el real y se va su titere. */
    public static void disguiseUnhide(Object character) { Disguise.unhide(character); }

    /** (174) true si el real esta oculto ahora mismo (su titere se esta dibujando en su lugar). */
    public static boolean disguiseHidden(Object character) { return Disguise.isHidden(character); }

    /**
     * (188) El titere del disfrazado character se suelta y queda como titere suelto (Lua lo mueve como un zombi falso); el real sigue oculto
     * hasta disguiseUnhide o, como tope, holdMs. Devuelve el id del titere, o -1 si no se pudo.
     */
    public static double disguiseDetach(Object character, double holdMs) { return Disguise.detach(character, (long) holdMs); }

    /** (188) El titere del disfraz mira hacia (x, y) girando degPerSec grados por segundo (on), o vuelve a mirar como el jugador (off). */
    public static void puppetFace(double id, Object on, double x, double y, double degPerSec) {
        Puppets.face((long) id, Boolean.TRUE.equals(on), (float) x, (float) y, (float) degPerSec);
    }

    public static String disguiseStats() { return Disguise.stats(); }

    /** (138) Episodio de texto corrupto: amount (0..1) de las letras cambiadas, durante ms. */
    public static void textGlitch(double amount, double ms) { TextGlitch.start((float) amount, (long) ms); }

    /** (192) Igual, pero con una lista de frases (separadas por \n) para incrustar en un texto existente. */
    public static void textGlitch(double amount, double ms, String phrases) { TextGlitch.start((float) amount, (long) ms, phrases); }

    public static boolean textGlitchAvailable() { return TextGlitch.problem.isEmpty(); }

    /** (181) C13.3 Sacudida de camara de la vista del jugador local view: px pixeles de pantalla (tope Shake.maxPx), durante ms. Solo isometrico. */
    public static void shake(double view, double px, double ms) { Shake.start((int) view, (float) px, (long) ms); }

    public static void shakeStop(double view) { Shake.stop((int) view); }

    /**
     * (181) C13.5 Efecto de pantalla de un episodio en la vista view, cada valor 0..1: desaturacion, ondulacion (la de la borrachera), desenfoque,
     * separacion de color y desgarro, durante ms (entra y sale con fundido). Solo isometrico.
     */
    public static void screenFx(double view, double desat, double wobble, double blur, double split, double tear, double ms) {
        Screen.start((int) view, (float) desat, (float) wobble, (float) blur, (float) split, (float) tear, (long) ms);
    }

    public static void screenFxStop(double view) { Screen.stop((int) view); }

    public static boolean screenFxActive(double view) { return Screen.active((int) view); }

    public static String fxStats() { return Shake.stats() + " | " + Screen.stats(); }

    public static String status() {
        return (Puppets.disabled ? "titeres apagados: " + Puppets.lastError : "titeres ok")
                + (TextGlitch.problem.isEmpty() ? "" : " | " + TextGlitch.problem)
                + (Disguise.problem.isEmpty() ? "" : " | disfraz: " + Disguise.problem)
                + (Disguise.problemB.isEmpty() ? "" : " | disfraz nivel B: " + Disguise.problemB)
                + (MoodleGlitch.problem.isEmpty() ? "" : " | moodles: " + MoodleGlitch.problem)
                + (Shake.problem.isEmpty() ? "" : " | sacudida: " + Shake.problem)
                + (Screen.problem.isEmpty() ? "" : " | pantalla: " + Screen.problem)
                + " | jar " + Main.VERSION;
    }
}
