package sandevistan.viewpoint;

import java.lang.reflect.Method;

/**
 * (186) Disfraz nivel B de la cyberpsicosis con la camara 3D de Viewpoint (jugadores vistos como zombis).
 *
 * En isometrico el jar de SandevistanPsychosis saltea el dibujo del jugador real (IsoPlayer.render, su sombra y su nombre) y pone en su lugar un
 * titere zombi que lo sigue. Viewpoint no pasa por esos metodos: arma sus piezas con ModelCapture.capture. El enganche de capture (Patches.Capture)
 * le pregunta aca si ese personaje esta oculto, y si lo esta no se capturan sus piezas (sin cuerpo ni sombra; el titere lo dibuja Puppet3D).
 * Quien decide es Disguise.hidden del otro jar (por reflexion, como Puppet3D): solo da true con el titere ya dibujandose en su lugar.
 * Si algo falla se apaga solo y el jugador se dibuja como siempre.
 */
public final class Hide3D {
    private static Method hidden;
    private static boolean missing, failed;
    private static String problem = "";
    private static long asked, skipped;

    private Hide3D() {}

    /** true = no capturar a este personaje en este cuadro. Corre por cada personaje en cada cuadro: lo barato primero. */
    public static boolean hidden(Object character) {
        if (missing || failed || character == null) return false;
        try {
            if (hidden == null) {
                Class<?> c = Puppet3D.psyClass("sandevistan.psychosis.Disguise");
                if (c == null) {
                    missing = true;
                    return false;
                }
                hidden = c.getMethod("hidden", Object.class);
                System.out.println("[SandevistanVP] 3D: disfraz nivel B enganchado al jar de SandevistanPsychosis");
            }
            asked++;
            if (!Boolean.TRUE.equals(hidden.invoke(null, character))) return false;
            skipped++;
            return true;
        } catch (Throwable t) {
            failed = true;
            problem = String.valueOf(t);
            System.out.println("[SandevistanVP] 3D: disfraz nivel B apagado: " + t);
            return false;
        }
    }

    static String stats() {
        return "disfraz 3D: " + (failed ? "apagado (" + problem + ")" : missing ? "sin el jar de SandevistanPsychosis"
                : asked + " consultas, " + skipped + " capturas salteadas");
    }
}
