package sandevistan.viewpoint;

/** Punto de entrada que ZombieBuddy ejecuta al cargar el jar: solo deja constancia en la consola. */
public final class Main {
    public static final String VERSION = "24 (0.7 186)";

    private Main() {}

    public static void main(String[] args) {
        // (136) Viewpoint es opcional: sin el, el jar dibuja las estelas en la camara isometrica normal. Puede cargarse
        // despues que este jar: si sus clases todavia no estan, Access.ok() lo vuelve a intentar la primera vez que se use
        // (desde Lua o desde un enganche), y el REPORTE del Sandevistan muestra el resultado de cada modo.
        try {
            Class.forName("viewpoint.render.ModelDraws");
            System.out.println("[SandevistanVP] jar " + VERSION + " cargado: " + SandevistanVP.status());
        } catch (Throwable e) {
            System.out.println("[SandevistanVP] jar " + VERSION + " cargado; Viewpoint no esta (opcional): " + SandevistanVP.status());
        }
    }
}
