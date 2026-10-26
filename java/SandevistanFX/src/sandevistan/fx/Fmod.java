package sandevistan.fx;

import java.lang.foreign.Arena;
import java.lang.foreign.FunctionDescriptor;
import java.lang.foreign.Linker;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.SymbolLookup;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandle;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * El tono de un evento de FMOD Studio. javafmod (el puente del juego) no trae FMOD_Studio_EventInstance_SetPitch, pero la biblioteca que el juego
 * ya cargo (libfmodstudio.so / fmodstudio.dll / libfmodstudio.dylib) la exporta: se llama con la API de funciones externas de Java 25 (FFM).
 * Abrir la misma ruta devuelve la copia ya cargada (dlopen / LoadLibrary no cargan dos veces el mismo archivo), asi que los punteros de los
 * eventos del juego valen aca. FMOD Studio valida cada puntero (uno viejo devuelve FMOD_ERR_INVALID_HANDLE), pero un puntero NULO con FMOD sin
 * iniciar tira el proceso (FxTest lo encontro): nunca se manda 0, y en el juego solo se tocan los eventos vivos de la lista de cada emisor.
 */
@SuppressWarnings("restricted")       // FFM: el juego ya arranca con --enable-native-access=ALL-UNNAMED (ProjectZomboid64.json)
final class Fmod {
    static final int OK = 0, ERR_INVALID_HANDLE = 30;

    private static MethodHandle setPitch, getPitch;
    private static volatile Boolean state;      // null = sin cargar todavia
    static String problem = "sin cargar";
    static String library = "-";
    static long calls, errors;
    static int lastError;

    private Fmod() {}

    static boolean ok() {
        Boolean s = state;
        if (s == null) s = load();
        return s;
    }

    static synchronized boolean load() {
        if (state != null) return state;
        try {
            SymbolLookup lib = find();
            Linker linker = Linker.nativeLinker();
            setPitch = linker.downcallHandle(symbol(lib, "FMOD_Studio_EventInstance_SetPitch"),
                    FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.JAVA_FLOAT));
            getPitch = linker.downcallHandle(symbol(lib, "FMOD_Studio_EventInstance_GetPitch"),
                    FunctionDescriptor.of(ValueLayout.JAVA_INT, ValueLayout.ADDRESS, ValueLayout.ADDRESS, ValueLayout.ADDRESS));
            problem = "";
            state = Boolean.TRUE;
        } catch (Throwable e) {
            problem = "FMOD: " + e;
            state = Boolean.FALSE;
        }
        return state;
    }

    private static MemorySegment symbol(SymbolLookup lib, String name) {
        return lib.find(name).orElseThrow(() -> new IllegalStateException("la biblioteca no exporta " + name));
    }

    /** Nombres posibles de la biblioteca de FMOD Studio en este sistema. */
    static List<String> names() {
        String os = System.getProperty("os.name", "").toLowerCase();
        List<String> n = new ArrayList<>();
        if (os.contains("win")) { n.add("fmodstudio.dll"); n.add("fmodstudio64.dll"); }
        else if (os.contains("mac")) n.add("libfmodstudio.dylib");
        else { n.add("libfmodstudio.so"); n.add("libfmodstudio.so.13"); }
        return n;
    }

    /** Carpetas donde el juego busca sus bibliotecas (-Djava.library.path=natives/ en el lanzador) y la del juego. */
    static List<Path> dirs() {
        List<Path> d = new ArrayList<>();
        String user = System.getProperty("user.dir", ".");
        for (String s : System.getProperty("java.library.path", "").split(java.io.File.pathSeparator)) {
            if (s.isEmpty()) continue;
            Path p = Path.of(s);
            d.add(p.isAbsolute() ? p : Path.of(user).resolve(p));
        }
        d.add(Path.of(user, "natives"));
        d.add(Path.of(user));
        return d;
    }

    private static SymbolLookup find() {
        for (Path dir : dirs()) {
            for (String n : names()) {
                Path p = dir.resolve(n);
                if (Files.isRegularFile(p)) {
                    // primero el nucleo (libfmod.so: libfmodstudio pide libfmod.so.14 y en natives/ solo esta con el otro nombre). En el juego ya
                    // esta cargado y esto no hace nada; fuera del juego (la prueba) es lo que deja abrir la de Studio
                    String core = n.replace("fmodstudio", "fmod").replace(".so.13", ".so");
                    if (Files.isRegularFile(dir.resolve(core))) {
                        try { SymbolLookup.libraryLookup(dir.resolve(core), Arena.global()); } catch (IllegalArgumentException e) { /* la de Studio dira */ }
                    }
                    library = p.toString();
                    return SymbolLookup.libraryLookup(p, Arena.global());
                }
            }
        }
        for (String n : names()) {
            try {
                SymbolLookup l = SymbolLookup.libraryLookup(n, Arena.global());
                library = n;
                return l;
            } catch (IllegalArgumentException e) {
                // probar el siguiente nombre
            }
        }
        throw new IllegalStateException("no encontre " + names() + " en " + dirs());
    }

    /** Resultado de FMOD (0 = bien; -1 = sin biblioteca o error de la llamada). */
    static int setPitch(long instance, float pitch) {
        if (instance == 0 || !ok()) return -1;
        try {
            int r = (int) setPitch.invokeExact(MemorySegment.ofAddress(instance), pitch);
            calls++;
            if (r != OK) { errors++; lastError = r; }
            return r;
        } catch (Throwable e) {
            problem = "SetPitch: " + e;
            return -1;
        }
    }

    /** Tono pedido del evento, o -(codigo de error de FMOD) / -1000 sin biblioteca. */
    static float getPitch(long instance) {
        if (instance == 0 || !ok()) return -1000f;
        try (Arena a = Arena.ofConfined()) {
            MemorySegment pitch = a.allocate(ValueLayout.JAVA_FLOAT), fin = a.allocate(ValueLayout.JAVA_FLOAT);
            int r = (int) getPitch.invokeExact(MemorySegment.ofAddress(instance), pitch, fin);
            return r == OK ? pitch.get(ValueLayout.JAVA_FLOAT, 0) : -r;
        } catch (Throwable e) {
            problem = "GetPitch: " + e;
            return -1000f;
        }
    }
}
