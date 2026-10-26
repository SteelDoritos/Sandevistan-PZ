package sandevistan.fx;

/** Punto de entrada que ZombieBuddy ejecuta al cargar el jar: solo deja constancia en la consola. */
public final class Main {
    public static final String VERSION = "17 (0.7 152)";

    private Main() {}

    public static void main(String[] args) {
        System.out.println("[SandevistanFX] jar " + VERSION + " cargado: " + SandevistanFX.status());
    }
}
