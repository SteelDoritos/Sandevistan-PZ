package sandevistan.psychosis;

/** Punto de entrada que ZombieBuddy ejecuta al cargar el jar: solo deja constancia en la consola. */
public final class Main {
    public static final String VERSION = "7 (0.7 193)";

    private Main() {}

    public static void main(String[] args) {
        System.out.println("[SandevistanPsy] jar " + VERSION + " cargado: " + SandevistanPsy.status());
    }
}
