package sandevistan.fx;

import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

import fmod.fmod.FMODSoundEmitter;
import zombie.characters.BaseCharacterSoundEmitter;
import zombie.characters.CharacterSoundEmitter;
import zombie.characters.IsoGameCharacter;

/**
 * Los sonidos de un personaje: CharacterSoundEmitter tiene tres emisores (voz, pasos, extra) y cada uno su lista de sonidos sonando; los que son
 * eventos de FMOD Studio (EventSound) guardan el puntero del evento. Todo eso es privado o de paquete en 42.21: se lee con VarHandle. Si algo no
 * esta como lo conocemos, ok queda en false y problem dice que.
 *
 * pitched recuerda el tono pedido por personaje, para que un sonido que empieza entre dos refrescos de Lua nazca ya con ese tono (enganche en
 * FMODSoundEmitter.startEvent). Las claves son debiles: un zombi que el juego descarta no queda retenido.
 */
public final class Voices {                 // publica: su enganche se copia dentro de fmod.fmod.FMODSoundEmitter (otro paquete)
    static final Map<Object, Float> pitched = Collections.synchronizedMap(new WeakHashMap<>());
    static boolean ok;
    static String problem = "sin comprobar";
    static long applied, started;

    private static VarHandle vocals, footsteps, extra, instances, toStart, eventInstance;
    private static Class<?> eventSound;

    static {
        try {
            MethodHandles.Lookup cse = MethodHandles.privateLookupIn(CharacterSoundEmitter.class, MethodHandles.lookup());
            vocals = cse.findVarHandle(CharacterSoundEmitter.class, "vocals", FMODSoundEmitter.class);
            footsteps = cse.findVarHandle(CharacterSoundEmitter.class, "footsteps", FMODSoundEmitter.class);
            extra = cse.findVarHandle(CharacterSoundEmitter.class, "extra", FMODSoundEmitter.class);
            MethodHandles.Lookup fse = MethodHandles.privateLookupIn(FMODSoundEmitter.class, MethodHandles.lookup());
            instances = fse.findVarHandle(FMODSoundEmitter.class, "instances", ArrayList.class);
            toStart = fse.findVarHandle(FMODSoundEmitter.class, "toStart", ArrayList.class);
            eventSound = Class.forName("fmod.fmod.FMODSoundEmitter$EventSound");
            eventInstance = MethodHandles.privateLookupIn(eventSound, MethodHandles.lookup()).findVarHandle(eventSound, "eventInstance", long.class);
            ok = true;
            problem = "";
        } catch (Throwable e) {
            problem = "sonidos del personaje: " + e;
        }
    }

    private Voices() {}

    /** Los emisores de FMOD del personaje (vacio si no es un personaje con CharacterSoundEmitter, p. ej. en el servidor). */
    static List<FMODSoundEmitter> emitters(Object character) {
        List<FMODSoundEmitter> out = new ArrayList<>(3);
        if (!ok || !(character instanceof IsoGameCharacter c)) return out;
        BaseCharacterSoundEmitter e = c.getEmitter();
        if (!(e instanceof CharacterSoundEmitter cse)) return out;
        for (VarHandle h : new VarHandle[] { vocals, footsteps, extra }) {
            FMODSoundEmitter f = (FMODSoundEmitter) h.get(cse);
            if (f != null) out.add(f);
        }
        return out;
    }

    /** Punteros de los eventos que suenan (o estan por empezar) en ese emisor. */
    static List<Long> events(FMODSoundEmitter f) {
        List<Long> out = new ArrayList<>();
        for (VarHandle list : new VarHandle[] { instances, toStart }) {
            ArrayList<?> l = (ArrayList<?>) list.get(f);
            if (l == null) continue;
            for (int i = 0; i < l.size(); i++) {
                Object s = l.get(i);
                if (eventSound.isInstance(s)) {
                    long p = (long) eventInstance.get(s);
                    if (p != 0) out.add(p);
                }
            }
        }
        return out;
    }

    /** Pone ese tono a todos los eventos del personaje y lo recuerda (1 = lo suelta). Devuelve cuantos eventos lo aceptaron, o -1 sin FMOD. */
    static int apply(Object character, float pitch) {
        if (!ok || !Fmod.ok()) return -1;
        boolean release = pitch >= 0.999f;
        if (release) pitched.remove(character); else pitched.put(character, pitch);
        int n = 0;
        for (FMODSoundEmitter f : emitters(character)) {
            for (long p : events(f)) {
                if (Fmod.setPitch(p, release ? 1f : pitch) == Fmod.OK) n++;
            }
        }
        applied += n;
        return n;
    }

    /** Suelta a todos los personajes con tono cambiado. */
    static int releaseAll() {
        List<Object> keys;
        synchronized (pitched) { keys = new ArrayList<>(pitched.keySet()); }
        int n = 0;
        for (Object k : keys) n += Math.max(0, apply(k, 1f));
        pitched.clear();
        return n;
    }

    /** Enganche de FMODSoundEmitter.startEvent: un sonido nuevo de un personaje con tono cambiado nace con ese tono. */
    public static void started(FMODSoundEmitter emitter, long instance) {
        if (instance == 0 || pitched.isEmpty() || emitter == null) return;
        try {
            Float p = pitched.get(emitter.parent);
            if (p != null && Fmod.setPitch(instance, p) == Fmod.OK) started++;
        } catch (Throwable e) {
            problem = "startEvent: " + e;
        }
    }

    /** Para la sonda de Debug: cada evento del personaje con su tono actual. */
    static String probe(Object character) {
        if (!ok) return problem;
        StringBuilder sb = new StringBuilder();
        String[] names = { "voz", "pasos", "extra" };
        List<FMODSoundEmitter> em = emitters(character);
        if (em.isEmpty()) return "sin CharacterSoundEmitter";
        for (int i = 0; i < em.size(); i++) {
            sb.append(i < names.length ? names[i] : "?").append(':');
            for (long p : events(em.get(i))) sb.append(String.format(" %x=%.2f", p, Fmod.getPitch(p)));
            sb.append(i + 1 < em.size() ? " | " : "");
        }
        return sb.toString();
    }
}
