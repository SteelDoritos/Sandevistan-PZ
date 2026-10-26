package sandevistan.viewpoint;

import java.io.InputStream;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.Properties;

import org.joml.Matrix4f;
import viewpoint.core.Frame;
import viewpoint.render.ModelDraws;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.textures.Texture;

/**
 * Acceso a las partes internas de Viewpoint que usan las estelas, y la verificacion al arrancar.
 *
 * Todo lo que no es publico en Viewpoint se lee por reflexion. Antes de usar nada, check() comprueba que las
 * clases, los metodos, los campos y las constantes del registro de dibujo (ModelDraws) sean los que conocemos:
 * si Viewpoint cambio algo, las estelas 3D se apagan solas y status() dice por que, en vez de romper el dibujo.
 */
final class Access {
    /** Versiones de Viewpoint probadas con este jar (una version distinta funciona si pasa check(), pero se avisa). */
    static final String[] TESTED = { "0.1.6.1" };

    // Registro de un dibujo de ModelDraws: 68 floats (offsets dentro del registro). check() los compara con los de Viewpoint.
    static final int VALUES = 68, MATERIAL = 16, LIGHT = 20, SPHERE = 24, UV = 28, OUTLINE = 32, PREVIOUS = 36,
            INDICES = 52, FADE = 56, STAND = 60, EDGE = 64;
    static final int BONE_FLOATS = 12;          // una matriz 3x4 por hueso
    static final int COLOUR = 1, SHADOW = 2, SOLID = 128, GLASS = 1024;
    static final float FLOOR_UNITS = 2.4494896f; // un piso del mundo en unidades de escena de Viewpoint (ModelCapture.placed)

    static String version = "?";
    static boolean tested;
    private static volatile Boolean result;     // null = sin comprobar todavia
    private static String problem = "sin comprobar";

    private static Field fValues, fPalette, fShadow, fCull, fFlags, fMeshes, fInstances, fTextures, fPalettes, fBones, fCount;
    private static Field fViewEnabled, fViewThird;

    private Access() {}

    /** true si todo lo que usamos de Viewpoint esta y es como lo conocemos. Se comprueba una sola vez. */
    static boolean ok() {
        Boolean r = result;
        if (r == null) r = check();
        return r;
    }

    static String problem() { return problem; }

    static synchronized boolean check() {
        if (result != null) return result;
        try {
            readVersion();
            Class<?> draws = ModelDraws.class;
            fValues = field(draws, "values", float[].class);
            fPalette = field(draws, "palette", int[].class);
            fShadow = field(draws, "shadowPalette", int[].class);
            fCull = field(draws, "cull", int[].class);
            fFlags = field(draws, "flags", int[].class);
            fMeshes = field(draws, "meshes", ModelMesh[].class);
            fInstances = field(draws, "instances", ModelInstance[].class);
            fTextures = field(draws, "textures", Texture[].class);
            fPalettes = field(draws, "palettes", float[].class);
            fBones = field(draws, "bones", int.class);
            fCount = field(draws, "count", int.class);
            constant(draws, "VALUES", VALUES);
            constant(draws, "MATERIAL", MATERIAL);
            constant(draws, "LIGHT", LIGHT);
            constant(draws, "SPHERE", SPHERE);
            constant(draws, "UV", UV);
            constant(draws, "OUTLINE", OUTLINE);
            constant(draws, "PREVIOUS", PREVIOUS);
            constant(draws, "INDICES", INDICES);
            constant(draws, "FADE", FADE);
            constant(draws, "STAND", STAND);
            constant(draws, "EDGE", EDGE);
            constant(draws, "BONE_FLOATS", BONE_FLOATS);
            constant(draws, "COLOUR", COLOUR);
            constant(draws, "SHADOW", SHADOW);
            constant(draws, "SOLID", SOLID);
            constant(draws, "GLASS", GLASS);
            method(draws, "add", int.class, ModelMesh.class, ModelInstance.class, Texture.class, Matrix4f.class,
                    int.class, int.class, int.class, int.class);
            method(draws, "palette", int.class, float[].class, int.class);
            method(draws, "count", int.class);

            Class<?> frame = Frame.class;
            field(frame, "scene", viewpoint.render.SceneData.class);
            field(frame, "camX", float.class);
            field(frame, "camY", float.class);
            field(frame, "camZ", float.class);
            field(frame, "number", long.class);
            field(viewpoint.render.SceneData.class, "models", ModelDraws.class);

            Class<?> view = Class.forName("viewpoint.core.View");
            fViewEnabled = field(view, "enabled", boolean.class);
            fViewThird = field(view, "thirdPerson", boolean.class);

            // los dos metodos que enganchamos (Patches): si cambian de forma, los enganches no se aplican
            Class<?> capture = Class.forName("viewpoint.models.ModelCapture");
            Method cap = null;
            for (Method m : capture.getDeclaredMethods()) {
                if (m.getName().equals("capture") && m.getParameterCount() == 10 && m.getReturnType() == boolean.class
                        && m.getParameterTypes()[0] == frame
                        && m.getParameterTypes()[2] == zombie.characters.IsoGameCharacter.class) cap = m;
            }
            if (cap == null) throw new IllegalStateException("ModelCapture.capture cambio de forma");
            Class<?> characters = Class.forName("viewpoint.models.Characters");
            method(characters, "snapshot", void.class, frame, zombie.iso.IsoCell.class, zombie.characters.IsoGameCharacter.class);

            problem = tested ? "" : "Viewpoint " + version + " no probado con este jar (funciona, pero avisá si ves algo raro)";
            result = Boolean.TRUE;
        } catch (NoClassDefFoundError e) {
            problem = "Viewpoint no esta instalado (o todavia no cargo)";     // (136) es opcional: el modo isometrico igual anda
            result = Boolean.FALSE;
        } catch (Throwable e) {
            problem = "Viewpoint " + version + " no compatible: " + e;
            result = Boolean.FALSE;
        }
        return result;
    }

    private static void readVersion() {
        try (InputStream in = ModelDraws.class.getClassLoader().getResourceAsStream("viewpoint/build.properties")) {
            if (in == null) return;
            Properties p = new Properties();
            p.load(in);
            version = p.getProperty("version", "?");
            for (String t : TESTED) if (t.equals(version)) tested = true;
        } catch (Throwable ignored) {
        }
    }

    private static Field field(Class<?> c, String name, Class<?> type) throws Exception {
        Field f = c.getDeclaredField(name);
        if (f.getType() != type) throw new IllegalStateException(c.getSimpleName() + "." + name + " es " + f.getType().getSimpleName());
        f.setAccessible(true);
        return f;
    }

    private static void constant(Class<?> c, String name, int expected) throws Exception {
        Field f = c.getDeclaredField(name);
        if (!Modifier.isStatic(f.getModifiers())) throw new IllegalStateException(name + " no es estatico");
        f.setAccessible(true);
        int v = f.getInt(null);
        if (v != expected) throw new IllegalStateException("ModelDraws." + name + " = " + v + " (esperaba " + expected + ")");
    }

    private static void method(Class<?> c, String name, Class<?> ret, Class<?>... params) throws Exception {
        Method m = c.getDeclaredMethod(name, params);
        if (m.getReturnType() != ret) throw new IllegalStateException(c.getSimpleName() + "." + name + " devuelve " + m.getReturnType());
    }

    // --- lectura de ModelDraws (los arreglos se piden de nuevo despues de cada add: add los agranda) ---

    static float[] values(ModelDraws d) throws IllegalAccessException { return (float[]) fValues.get(d); }
    static int[] palette(ModelDraws d) throws IllegalAccessException { return (int[]) fPalette.get(d); }
    static int[] shadowPalette(ModelDraws d) throws IllegalAccessException { return (int[]) fShadow.get(d); }
    static int[] cull(ModelDraws d) throws IllegalAccessException { return (int[]) fCull.get(d); }
    static int[] flags(ModelDraws d) throws IllegalAccessException { return (int[]) fFlags.get(d); }
    static ModelMesh[] meshes(ModelDraws d) throws IllegalAccessException { return (ModelMesh[]) fMeshes.get(d); }
    static ModelInstance[] instances(ModelDraws d) throws IllegalAccessException { return (ModelInstance[]) fInstances.get(d); }
    static Texture[] textures(ModelDraws d) throws IllegalAccessException { return (Texture[]) fTextures.get(d); }
    static float[] palettes(ModelDraws d) throws IllegalAccessException { return (float[]) fPalettes.get(d); }
    static int bones(ModelDraws d) throws IllegalAccessException { return fBones.getInt(d); }
    static int count(ModelDraws d) throws IllegalAccessException { return fCount.getInt(d); }

    static ModelDraws models(Object frame) { return ((Frame) frame).scene.models; }

    static boolean viewEnabled() {
        try { return ok() && fViewEnabled.getBoolean(null); } catch (Throwable e) { return false; }
    }

    static boolean viewThirdPerson() {
        try { return ok() && fViewThird.getBoolean(null); } catch (Throwable e) { return false; }
    }
}
