package sandevistan.psychosis;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

import zombie.core.fonts.AngelCodeFont;

/**
 * (138) Texto corrupto de la cyberpsicosis: durante un episodio (lo pide Lua: SandevistanPsy.textGlitch), las letras de todo el texto que dibuja el juego
 * se cambian por simbolos al azar, distintos cada ~90 ms. Engancha AngelCodeFont.render(String, int, int) (privado: lo llaman todos los drawString
 * de la fuente, con el tramo start..end del texto) y le pasa otro texto del mismo largo, asi los indices y el ancho medido antes siguen valiendo.
 * Con la cache de listas de dibujo de la fuente encendida no toca nada (el texto corrupto quedaria guardado con la clave del original).
 */
public final class TextGlitch {
    private TextGlitch() {}

    static final String GLYPHS = "#$%&@*?!/\\|<>=+~^01";
    public static volatile long untilMs = 0;
    public static volatile float intensity = 0f;
    public static volatile String[] messages = new String[0];
    public static volatile String messageSource = null;      // texto exacto donde cayo la frase
    public static volatile String messagePhrase = null;      // frase fija del episodio
    public static volatile int messageStart = -1, messageEnd = -2, messageWindow = -1;
    public static String problem = "";
    public static long changed = 0, episodes = 0;

    private static final VarHandle CACHING;
    static {
        VarHandle h = null;
        try {
            h = MethodHandles.privateLookupIn(AngelCodeFont.class, MethodHandles.lookup()).findVarHandle(AngelCodeFont.class, "displayListCaching", boolean.class);
        } catch (Throwable t) {
            problem = "AngelCodeFont.displayListCaching no esta: " + t;
        }
        CACHING = h;
    }

    public static void start(float amount, long ms) { start(amount, ms, null); }

    /** (192) Episodio con una lista de frases (separadas por \n) para incrustar en un texto existente. */
    public static void start(float amount, long ms, String phrases) {
        intensity = Math.max(0f, Math.min(1f, amount));
        untilMs = System.currentTimeMillis() + Math.max(0L, Math.min(10_000L, ms));
        messages = (phrases == null || phrases.isEmpty()) ? new String[0] : phrases.split("\n", -1);
        messageSource = null;
        messagePhrase = null;
        messageStart = -1;
        messageEnd = -2;
        messageWindow = -1;
        episodes++;
    }

    public static boolean active() { return System.currentTimeMillis() < untilMs && intensity > 0f; }

    /** Desde el enganche: el texto a dibujar (el mismo si no hay episodio). */
    public static String text(Object font, String text, int start, int end) {
        if (text == null || System.currentTimeMillis() >= untilMs || CACHING == null) return text;
        try {
            if (!(font instanceof AngelCodeFont f) || (boolean) CACHING.get(f)) return text;
            long tick = System.currentTimeMillis() / 90;
            if (messagePhrase != null) {
                // La frase queda fija todo el episodio; el resto del mismo texto cambia con el tick.
                if (text.equals(messageSource) && start == messageStart && end == messageEnd) {
                    return embedAt(text, start, end, messageWindow, messagePhrase, intensity, tick, f.chars);
                }
            } else if (messages.length > 0) {
                Embedded chosen = embedChoice(text, start, end, messages, intensity, tick, f.chars);
                if (chosen != null) {
                    messageSource = text;
                    messageStart = start;
                    messageEnd = end;
                    messageWindow = chosen.window;
                    messagePhrase = chosen.phrase;
                    changed++;
                    return chosen.output;
                }
            }
            return corrupt(text, start, end, intensity, tick, f.chars);
        } catch (Throwable t) {
            problem = "texto corrupto: " + t;
            untilMs = 0;
            return text;
        }
    }

    /**
     * (192) Incrusta una frase coherente en una ventana del texto y corrompe el resto. Mismo largo que el original.
     * Devuelve null si el texto no es elegible (muy corto, sin espacio, pocas letras) o si ninguna frase entra.
     * Se usa para la prueba; en juego, `text` guarda la ventana y llama a `embedAt` en cada cuadro.
     */
    public static String embed(String text, int start, int end, String[] phrases, float amount, long tick, Object[] chars) {
        Embedded e = embedChoice(text, start, end, phrases, amount, tick, chars);
        return e == null ? null : e.output;
    }

    private static Embedded embedChoice(String text, int start, int end, String[] phrases, float amount, long tick, Object[] chars) {
        if (text == null || phrases == null || phrases.length == 0) return null;
        int a = Math.max(0, start), b = Math.min(text.length() - 1, end);
        if (a > b) return null;
        int letters = 0, spaces = 0;
        for (int i = a; i <= b; i++) {
            char c = text.charAt(i);
            if (Character.isLetter(c)) letters++;
            if (c == ' ') spaces++;
        }
        if (letters < 8 || spaces < 1) return null;              // etiquetas de una palabra y numeros: no
        int visible = b - a + 1;
        long seed = tick * 0x9E3779B97F4A7C15L ^ text.hashCode();
        for (int k = 0; k < phrases.length; k++) {
            String phrase = phrases[(int) Math.floorMod((seed >>> 17) + k, (long) phrases.length)];
            if (!validPhrase(phrase, chars)) continue;
            int len = phrase.length();
            if (len > visible) continue;
            int w = chooseWindow(text, a, b, len);
            if (w < 0) continue;
            String output = embedAt(text, a, b, w, phrase, amount, tick, chars);
            if (output != null) return new Embedded(output, w, phrase);
        }
        return null;
    }

    /** Reescribe la ventana con la frase fija y corrompe el resto con el tick actual. */
    public static String embedAt(String text, int start, int end, int w, String phrase, float amount, long tick, Object[] chars) {
        if (text == null || phrase == null || phrase.isEmpty()) return null;
        int a = Math.max(0, start), b = Math.min(text.length() - 1, end);
        int len = phrase.length();
        if (a > b || w < a || w + len - 1 > b) return null;
        char[] out = text.toCharArray();
        long s = tick * 0x9E3779B97F4A7C15L ^ text.hashCode() ^ (w * 0x2545F4914F6CDD1DL);
        for (int i = a; i <= b; i++) {
            if (i >= w && i < w + len) {
                out[i] = phrase.charAt(i - w);
                continue;
            }
            char c = out[i];
            if (!Character.isLetterOrDigit(c)) continue;
            s = s * 6364136223846793005L + 1442695040888963407L;
            float r = ((s >>> 40) & 0xFFFF) / 65536f;
            if (r >= amount) continue;
            char g = GLYPHS.charAt((int) ((s >>> 20) & 0x7FFF) % GLYPHS.length());
            if (chars != null && (g >= chars.length || chars[g] == null)) continue;
            out[i] = g;
        }
        return new String(out);
    }

    private static final class Embedded {
        final String output;
        final int window;
        final String phrase;
        Embedded(String output, int window, String phrase) {
            this.output = output;
            this.window = window;
            this.phrase = phrase;
        }
    }

    private static boolean validPhrase(String phrase, Object[] chars) {
        if (phrase == null || phrase.isEmpty()) return false;
        for (int i = 0; i < phrase.length(); i++) {
            char c = phrase.charAt(i);
            if (c == '\n' || c == '\r') return false;
            if (c == ' ') continue;
            if (chars != null && (c >= chars.length || chars[c] == null)) return false;
        }
        return true;
    }

    /** Busca una ventana que empiece y termine en un borde de palabra; si no, la centra. */
    private static int chooseWindow(String text, int a, int b, int len) {
        for (int w = a; w + len - 1 <= b; w++) {
            boolean left = w == a || !Character.isLetterOrDigit(text.charAt(w - 1));
            boolean right = w + len > b || !Character.isLetterOrDigit(text.charAt(w + len));
            if (left && right) return w;
        }
        return a + Math.max(0, (b - a + 1 - len) / 2);
    }

    /** Cambia letras y numeros del tramo por simbolos que la fuente tenga (chars nulo: cualquiera). Mismo largo; espacios y saltos quedan. */
    public static String corrupt(String text, int start, int end, float amount, long tick, Object[] chars) {
        int a = Math.max(0, start), b = Math.min(text.length() - 1, end);
        if (a > b || amount <= 0f) return text;
        char[] out = null;
        long seed = tick * 0x9E3779B97F4A7C15L ^ text.hashCode();
        for (int i = a; i <= b; i++) {
            char c = text.charAt(i);
            if (!Character.isLetterOrDigit(c)) continue;
            seed = seed * 6364136223846793005L + 1442695040888963407L;
            float r = ((seed >>> 40) & 0xFFFF) / 65536f;
            if (r >= amount) continue;
            char g = GLYPHS.charAt((int) ((seed >>> 20) & 0x7FFF) % GLYPHS.length());
            if (chars != null && (g >= chars.length || chars[g] == null)) continue;
            if (out == null) out = text.toCharArray();
            out[i] = g;
        }
        if (out == null) return text;
        changed++;
        return new String(out);
    }
}
