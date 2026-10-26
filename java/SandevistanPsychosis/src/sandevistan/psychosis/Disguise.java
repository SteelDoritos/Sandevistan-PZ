package sandevistan.psychosis;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Map;
import java.util.WeakHashMap;

import zombie.characters.IsoGameCharacter;
import zombie.characters.IsoPlayer;
import zombie.core.skinnedmodel.ModelManager;
import zombie.core.skinnedmodel.population.PopTemplateManager;
import zombie.core.skinnedmodel.visual.HumanVisual;
import zombie.core.skinnedmodel.visual.IHumanVisual;

/**
 * (147) Prueba del "disfraz" de la cyberpsicosis (22 §6.2.1, nivel A): este cliente ve a un personaje con la piel del otro bando.
 * Zombi -> persona: piel sana con su ropa y sus animaciones de zombi. Jugador -> zombi: piel podrida (etapa 1..3) con su ropa.
 *
 * Solo se cambia lo que devuelve HumanVisual.getSkinTexture() (Patches.SkinTexture, a la salida) para los personajes de la lista, y se
 * rearma el modelo con ModelManager.Reset. No se toca isZombie() ni el indice de piel guardado (ZombiePacket manda ese indice: si se
 * cambiara, el disfraz viajaria a los demas). Nada se guarda: la lista es de este cliente, con referencias debiles.
 *
 * (174) Nivel B (29 §4.1): otro jugador visto como un zombi entero. Este cliente no lo dibuja (Patches.HidePlayer, HideShadow y HideName saltean
 * su render, su sombra y su nombre) y en su lugar va un titere zombi con su ropa y piel podrida que lo sigue en cada cuadro (Puppets.spawnDisguise).
 * El real solo se oculta mientras el titere se esta dibujando de verdad (Puppets.standingIn): si el titere no nacio todavia, se fue, los titeres
 * se apagaron o la vista es la camara 3D, se ve el real. Ante cualquier error se apaga el nivel B y vuelve el real.
 *
 * (188) detach: el titere se suelta del jugador (Puppets.detach) y Lua lo maneja como un zombi falso; el real sigue oculto hasta unhide o, como
 * tope, holdMs (holdUntil), aunque el titere ya no este en su lugar.
 */
public final class Disguise {
    private Disguise() {}

    public static final int NONE = 0, HUMAN = 1, ZOMBIE1 = 2, ZOMBIE2 = 3, ZOMBIE3 = 4;

    private static final Map<Object, Integer> list = new WeakHashMap<>();
    private static Field fOwner;
    private static boolean failed;
    public static String problem = "";
    static long swapped, applied;

    // (174) nivel B: jugador -> id del titere que lo reemplaza; y las pieles podridas de esos titeres (su modelo es dueño de la visual copiada)
    private static final Map<Object, Long> hidden = new WeakHashMap<>();
    private static final Map<Object, Integer> puppetSkins = new WeakHashMap<>();
    // (188) jugador -> hasta cuando (nanoTime) sigue oculto aunque su titere ya no lo siga (se solto y va hacia el que lo ve como zombi falso)
    private static final Map<Object, Long> holdUntil = new WeakHashMap<>();
    static long detaches;
    private static volatile int hiddenCount;
    private static volatile boolean failedB;
    public static String problemB = "";
    static long hides, skips;

    /** Lo llama Lua (SandevistanPsy.disguise): mode NONE lo saca. Devuelve false si no se pudo. */
    static boolean set(Object character, int mode) {
        if (!(character instanceof IsoGameCharacter) || failed) return false;
        IsoGameCharacter chr = (IsoGameCharacter) character;
        try {
            synchronized (list) {
                if (mode <= NONE) {
                    if (list.remove(chr) == null) return true;
                } else {
                    list.put(chr, Math.min(ZOMBIE3, mode));
                }
            }
            ModelManager.instance.Reset(chr);              // rearma el modelo con la piel nueva (como al cambiar la ropa)
            applied++;
            return true;
        } catch (Throwable t) {
            fail(t);
            return false;
        }
    }

    static int mode(Object character) {
        synchronized (list) {
            Integer m = list.get(character);
            return m == null ? NONE : m;
        }
    }

    static int count() {
        synchronized (list) { return list.size(); }
    }

    /** Saca todos los disfraces y rearma esos modelos. (174) Tambien los del nivel B: vuelven los reales y se van sus titeres. */
    static void clear() {
        ArrayList<Long> ids;
        synchronized (list) {
            ids = new ArrayList<>(hidden.values());
            hidden.clear();
            holdUntil.clear();
            hiddenCount = 0;
        }
        for (Long id : ids) Puppets.remove(id);
        ArrayList<Object> all;
        synchronized (list) {
            all = new ArrayList<>(list.keySet());
            list.clear();
        }
        for (Object o : all) {
            try {
                ModelManager.instance.Reset((IsoGameCharacter) o);
            } catch (Throwable t) {
                fail(t);
            }
        }
    }

    /** Patches.SkinTexture: la piel que el juego eligio, o la del disfraz si el dueño esta en la lista. */
    public static String skin(Object visual, String chosen) {
        if (failed || !(visual instanceof HumanVisual)) return chosen;
        try {
            int mode;
            Object owner;
            synchronized (list) {
                if (list.isEmpty() && puppetSkins.isEmpty()) return chosen;
                owner = owner((HumanVisual) visual);
                Integer m = owner == null ? null : list.get(owner);
                if (m == null && owner != null) m = puppetSkins.get(owner);
                if (m == null) return chosen;
                mode = m;
            }
            HumanVisual v = (HumanVisual) visual;
            boolean female = ((IHumanVisual) owner).isFemale();
            PopTemplateManager pop = PopTemplateManager.instance;
            ArrayList<String> skins;
            String suffix = "";
            switch (mode) {
                case HUMAN:
                    skins = female ? pop.femaleSkins : pop.maleSkins;
                    if (!female && v.getBodyHairIndex() >= 0) suffix = "a";   // como el juego: hombre con vello
                    break;
                case ZOMBIE1: skins = female ? pop.femaleSkinsZombie1 : pop.maleSkinsZombie1; break;
                case ZOMBIE2: skins = female ? pop.femaleSkinsZombie2 : pop.maleSkinsZombie2; break;
                default:      skins = female ? pop.femaleSkinsZombie3 : pop.maleSkinsZombie3; break;
            }
            if (skins == null || skins.isEmpty()) return chosen;
            // el mismo indice de piel (tono) que ya tiene, sin escribirlo
            String s = skins.get(Math.floorMod(v.getSkinTextureIndex(), skins.size())) + suffix;
            swapped++;
            return s;
        } catch (Throwable t) {
            fail(t);
            return chosen;
        }
    }

    /**
     * (174) Nivel B: el titere puppetId (zombi con la ropa del jugador) reemplaza a character en este cliente. Solo jugadores (IsoPlayer).
     * rot = podredumbre 1..3. Devuelve false si no se pudo; en ese caso no se oculta nada.
     */
    static boolean hide(Object character, long puppetId, int owner, int rot) {
        if (!(character instanceof IsoPlayer) || failedB) return false;
        try {
            unhide(character);
            if (!Puppets.spawnDisguise(puppetId, character, owner, rot)) return false;
            synchronized (list) {
                hidden.put(character, puppetId);
                hiddenCount = hidden.size();
            }
            hides++;
            return true;
        } catch (Throwable t) {
            failB(t);
            Puppets.remove(puppetId);
            return false;
        }
    }

    /** (174) Vuelve el real y se va su titere, en el mismo cuadro (los dos cambios son en el hilo principal, antes del dibujo). */
    static void unhide(Object character) {
        Long id;
        synchronized (list) {
            id = hidden.remove(character);
            holdUntil.remove(character);
            hiddenCount = hidden.size();
        }
        if (id != null) Puppets.remove(id);
    }

    /**
     * (188) El titere de character se suelta (Puppets.detach) y Lua lo maneja como un zombi falso que va hacia el que lo ve. El real sigue
     * oculto hasta que Lua lo devuelva (unhide) o, como tope, holdMs: si Lua se cae, el real vuelve solo. Devuelve el id del titere, o -1.
     */
    static long detach(Object character, long holdMs) {
        if (failedB) return -1L;
        try {
            Long id;
            synchronized (list) { id = hidden.get(character); }
            if (id == null || !Puppets.detach(id)) return -1L;
            synchronized (list) { holdUntil.put(character, System.nanoTime() + Math.max(0L, holdMs) * 1_000_000L); }
            detaches++;
            return id;
        } catch (Throwable t) {
            failB(t);
            return -1L;
        }
    }

    /** (174) Para Lua: el real esta oculto ahora mismo (su titere se esta dibujando en su lugar). */
    static boolean isHidden(Object character) {
        return hidden(character);
    }

    /** (174) La piel podrida del titere del nivel B (Puppets.spawnDisguise, antes de copiar la visual); null la saca. */
    public static void puppetSkin(Object model, int mode) {
        synchronized (list) {
            if (mode <= NONE) puppetSkins.remove(model); else puppetSkins.put(model, Math.min(ZOMBIE3, mode));
        }
    }

    /**
     * (174) Patches.HidePlayer / HideShadow / HideName: true = este cliente no dibuja a ese personaje (el juego saltea el metodo).
     * Lo mas barato primero: corre por cada personaje en cada cuadro.
     */
    public static boolean hidden(Object self) {
        if (hiddenCount == 0 || failedB) return false;
        try {
            Long id, hold;
            synchronized (list) {
                id = hidden.get(self);
                hold = id == null ? null : holdUntil.get(self);
            }
            if (id == null) return false;
            if (hold != null) {                                // (188) soltado: oculto hasta que Lua lo devuelva o venza el tope
                if (System.nanoTime() >= hold) return false;
            } else if (!Puppets.standingIn(id)) return false;
            skips++;
            return true;
        } catch (Throwable t) {
            failB(t);
            return false;
        }
    }

    private static void failB(Throwable t) {
        failedB = true;
        problemB = String.valueOf(t);
        hiddenCount = 0;
        System.out.println("[SandevistanPsy] disfraz nivel B apagado: " + t);
    }

    private static Object owner(HumanVisual v) throws Exception {
        if (fOwner == null) {
            Field f = HumanVisual.class.getDeclaredField("owner");
            f.setAccessible(true);
            fOwner = f;
        }
        return fOwner.get(v);
    }

    private static void fail(Throwable t) {
        failed = true;
        problem = String.valueOf(t);
        System.out.println("[SandevistanPsy] disfraz apagado: " + t);
    }

    static String stats() {
        int b;
        synchronized (list) { b = hidden.size(); }
        return "disfraz: " + (failed ? "apagado (" + problem + ")" : count() + " en la lista, " + swapped + " pieles cambiadas, " + applied + " rearmados")
                + " | nivel B: " + (failedB ? "apagado (" + problemB + ")" : b + " ocultos, " + hides + " episodios, " + skips + " dibujos salteados"
                        + (detaches > 0 ? ", " + detaches + " soltados" : ""));
    }
}
