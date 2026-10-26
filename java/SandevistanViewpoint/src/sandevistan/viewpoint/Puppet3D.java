package sandevistan.viewpoint;

import java.lang.reflect.Method;
import java.util.List;

import org.joml.Matrix4f;
import viewpoint.core.Frame;
import viewpoint.render.ModelDraws;
import zombie.core.skinnedmodel.model.ModelInstance;
import zombie.core.skinnedmodel.model.ModelMesh;
import zombie.core.textures.Texture;
import viewpoint.light.OwnedLight;
import zombie.iso.IsoCamera;
import zombie.iso.IsoGridSquare;
import zombie.iso.IsoWorld;

/**
 * (143) Zombis falsos (titeres de SandevistanPsychosis; hasta la 151, de SandevistanFX) en la camara 3D de Viewpoint.
 *
 * Viewpoint no dibuja personajes: arma una lista de piezas (ModelDraws) y las pinta con su camara. Las estelas entran por
 * ModelCapture; el titere no es un personaje, asi que se le piden sus piezas al jar de SandevistanPsychosis por reflexion
 * (Puppets.scene3D) y se agregan con la misma colocacion que usa ModelCapture.placed: traslacion relativa a la camara
 * (camX - x, (z - camZ) x FLOOR_UNITS, camY - y), escala (-1,5, 1,5, 1,5), giro angle + PI; por pieza, las rigidas
 * multiplican por xfrm traspuesta (como ModelCapture.add) y las esqueletadas usan su paleta viva.
 * (148) Luz y color como ModelCapture: tinte y tono de cada pieza (el pelo tiene su color en el tinte) y la luz de la casilla
 * (OwnedLight.modelLightAt / modelSky). Hasta la 147 iba con luz plena y tinte x1,5: de noche brillaba y el pelo salia blanco.
 * Si algo falla se apaga solo y no toca el resto del dibujo.
 */
final class Puppet3D {
    private static Method scene3D;
    private static boolean missing, failed, noView;
    private static String problem = "";
    private static long calls, frames, lastPieces, lastSeen;

    private Puppet3D() {}

    static void draw(Frame f) {
        calls++;
        if (f == null || f.scene == null) return;
        if (!Access.ok()) {
            if (!noView) {
                noView = true;
                System.out.println("[SandevistanVP] 3D: titeres sin dibujar: " + Access.problem());
            }
            return;
        }
        if (missing || failed) return;
        try {
            if (scene3D == null) {
                Class<?> fx = fxClass();
                if (fx == null) {
                    missing = true;
                    return;
                }
                scene3D = fx.getMethod("scene3D", int.class);
                System.out.println("[SandevistanVP] 3D: titeres enganchados al jar de SandevistanPsychosis");
            }
            Object r = scene3D.invoke(null, IsoCamera.frameState.playerIndex);
            if (!(r instanceof List)) return;
            List<?> puppets = (List<?>) r;
            int n = puppets.size();
            // avisar solo en los cambios: asi el console.txt dice si los hay, si desaparecen o si vuelven
            if (n != lastSeen) {
                System.out.println("[SandevistanVP] 3D: titeres " + (n == 0 ? "ninguno" : "visibles: " + n)
                        + " (cuadro " + calls + ")");
                lastSeen = n;
            }
            if (n > 0) add(f, puppets);
        } catch (Throwable t) {
            failed = true;
            problem = String.valueOf(t);
            System.out.println("[SandevistanVP] 3D: titeres apagados: " + t);
        }
    }

    private static Class<?> fxClass() {
        return psyClass("sandevistan.psychosis.Puppets");  // (152) se mudo de SandevistanFX
    }

    /** El jar de la cyberpsicosis puede estar en el mismo cargador o en uno propio, segun como lo monte ZombieBuddy: se prueban los tres. */
    static Class<?> psyClass(String name) {
        ClassLoader[] loaders = { Puppet3D.class.getClassLoader(), Thread.currentThread().getContextClassLoader() };
        for (ClassLoader cl : loaders) {
            try {
                if (cl != null) return Class.forName(name, true, cl);
            } catch (Throwable ignored) {
            }
        }
        try {
            return Class.forName(name);
        } catch (Throwable t) {
            System.out.println("[SandevistanVP] 3D: no se encontro " + name + " (" + t
                    + "): los titeres y el disfraz necesitan el mod SandevistanPsychosis");
            return null;
        }
    }

    private static void add(Frame f, List<?> puppets) throws Exception {
        ModelDraws d = f.scene.models;
        int flags = Access.COLOUR | (Access.viewThirdPerson() ? Access.SOLID : 0);
        Matrix4f place = new Matrix4f(), model = new Matrix4f(), xfrm = new Matrix4f();
        int added = 0;
        for (Object o : puppets) {
            Object[] g = (Object[]) o;
            float x = ((Number) g[0]).floatValue(), y = ((Number) g[1]).floatValue(), z = ((Number) g[2]).floatValue();
            float angle = ((Number) g[3]).floatValue(), alpha = ((Number) g[4]).floatValue();
            float r = ((Number) g[5]).floatValue(), gg = ((Number) g[6]).floatValue(), b = ((Number) g[7]).floatValue();
            List<?> pieces = (List<?>) g[8];
            light(x, y, z);
            float glitch = g.length > 9 ? ((Number) g[9]).floatValue() : 0f;
            float off = g.length > 10 ? ((Number) g[10]).floatValue() : 0f;     // (147) lo elige FX: el mismo que en isometrico, quieto en pausa
            // (146) glitch del deshacido. (149) En 3D, una copia cian y una magenta encimadas al modelo peleaban por la profundidad con el
            // modelo solido (las tres casi en el mismo lugar) y quedaban manchas de colores mezclados. Ahora es en el tiempo: algunos cuadros
            // el titere se dibuja UNA vez, corrido a un costado y de un solo color (cian o magenta), como una imagen que salta; el resto, normal.
            // La eleccion sale del corrimiento que manda FX (quieto en pausa), asi que en pausa tampoco parpadea.
            int pick = glitch > 0.01f && off > 0f ? Math.floorMod(Float.floatToIntBits(off) * 0x9E3779B1, 100) : 100;
            if (pick < 55 * glitch) {
                float vx = x - f.camX, vy = y - f.camY;
                float len = (float) Math.sqrt(vx * vx + vy * vy);
                float px = len > 1e-3f ? -vy / len : 1f, py = len > 1e-3f ? vx / len : 0f;
                boolean cyan = (pick & 1) == 0;
                float side = cyan ? 1f : -1f;
                float lr = lightR, lg = lightG, lb = lightB, sk = sky;
                lightR = lightG = lightB = 1f; sky = 0f;               // la copia de color no es de este mundo: sin la luz de la casilla
                added += pass(f, d, pieces, x + px * off * side, y + py * off * side, z, angle, alpha,
                        cyan ? 0.15f : 1f, cyan ? 1f : 0.15f, cyan ? 1f : 0.85f, flags, place, model, xfrm);
                lightR = lr; lightG = lg; lightB = lb; sky = sk;
            } else {
                added += pass(f, d, pieces, x, y, z, angle, alpha, r, gg, b, flags, place, model, xfrm);
            }
        }
        lastPieces = added;
        if (added > 0) {
            frames++;
            if (frames == 1) {
                Object[] g = (Object[]) puppets.get(0);
                System.out.println(String.format("[SandevistanVP] 3D: primer cuadro con titeres (%d piezas, en %.2f,%.2f,%.2f; camara %.2f,%.2f,%.2f)",
                        added, ((Number) g[0]).floatValue(), ((Number) g[1]).floatValue(), ((Number) g[2]).floatValue(),
                        f.camX, f.camY, f.camZ));
            }
        }
    }

    /** Una pasada del titere: todas sus piezas con la colocacion de ModelCapture.placed, el tinte y el alfa dados. Devuelve cuantas agrego. */
    private static int pass(Frame f, ModelDraws d, List<?> pieces, float x, float y, float z, float angle, float alpha,
                            float r, float gg, float b, int flags, Matrix4f place, Matrix4f model, Matrix4f xfrm) throws Exception {
        int added = 0;
        {
            place.identity()
                    .translation(f.camX - x, (z - f.camZ) * Access.FLOOR_UNITS, f.camY - y)
                    .scale(-1.5f, 1.5f, 1.5f)
                    .rotateY(angle + (float) Math.PI);
            for (Object po : pieces) {
                Object[] pc = (Object[]) po;
                ModelInstance inst = (ModelInstance) pc[0];
                ModelMesh mesh = (ModelMesh) pc[1];
                Texture tex = (Texture) pc[2];
                float[] pal = (float[]) pc[3];
                Matrix4f xf = (Matrix4f) pc[4];
                int cull = ((Number) pc[5]).intValue();
                boolean isStatic = Boolean.TRUE.equals(pc[6]);
                int base = -1;
                if (isStatic) {
                    model.set(place).mul(xfrm.set(xf).transpose());
                } else {
                    model.set(place);
                    // (147) la paleta del juego es 4x4 por hueso (16 floats) y ModelDraws.palette(float[], n) copia n huesos de 3x4: con
                    // pal.length como cantidad se salia del arreglo (ArrayIndexOutOfBounds) y apagaba los titeres en el primer cuadro.
                    // La version FloatBuffer es la que usa ModelCapture con matrixPalette: lee 16 por hueso y guarda 12.
                    if (pal != null && pal.length >= 16) base = d.palette(java.nio.FloatBuffer.wrap(pal), pal.length / 16);
                }
                int idx = d.add(mesh, inst, tex, model, base, -1, cull, flags);
                // (150) la esfera para el recorte, como ModelCapture (centro del personaje 0,9 arriba de los pies, radio 1,3). Sin esto cada pieza
                // quedaba con la esfera que hubiera dejado otro dibujo en esa ranura: segun la posicion, Viewpoint descartaba el torso, la cara
                // o todo el titere (se veian el pantalon y el pelo solos, o nada).
                d.bounds(idx, place.m30(), place.m31() + 0.9f, place.m32(), 1.3f);
                float[] v = Access.values(d);
                int o2 = idx * Access.VALUES;
                d.material(idx, inst.tintR * r, inst.tintG * gg, inst.tintB * b, inst.hue);
                d.light(idx, lightR, lightG, lightB, sky);
                v[o2 + Access.OUTLINE + 3] = 0f;
                model.get(v, o2 + Access.PREVIOUS);
                v[o2 + Access.FADE] = 0f;
                v[o2 + Access.FADE + 1] = Math.min(1f, Math.max(0f, alpha));
                added++;
            }
        }
        return added;
    }

    private static float lightR = 1f, lightG = 1f, lightB = 1f, sky = 0f;

    /** (148) La luz de la casilla del titere, como ModelCapture.capture/light: la de Viewpoint si la tiene, si no la del juego. */
    private static void light(float x, float y, float z) {
        lightR = lightG = lightB = 1f;
        sky = 0f;
        IsoGridSquare sq = IsoWorld.instance == null || IsoWorld.instance.currentCell == null ? null
                : IsoWorld.instance.currentCell.getGridSquare((int) Math.floor(x), (int) Math.floor(y), (int) Math.floor(z));
        if (sq == null) return;
        int packed = OwnedLight.modelLightAt(sq.x, sq.y, sq.z);
        if (packed >= 0) {
            lightR = (packed & 255) / 255f;
            lightG = (packed >> 8 & 255) / 255f;
            lightB = (packed >> 16 & 255) / 255f;
        } else {
            zombie.core.textures.ColorInfo li = sq.getLightInfo(IsoCamera.frameState.playerIndex);
            if (li != null) {
                lightR = Math.min(1f, li.r);
                lightG = Math.min(1f, li.g);
                lightB = Math.min(1f, li.b);
            }
        }
        sky = OwnedLight.modelSky(sq.x, sq.y, sq.z, sq.isOutside() && !sq.haveRoof);
    }

    static String stats() {
        if (missing) return "3D: SandevistanPsychosis no esta (los titeres necesitan el mod opcional)";
        if (failed) return "3D: titeres apagados (" + problem + ")";
        return "3D: " + frames + " cuadros, " + lastPieces + " piezas, " + lastSeen + " titeres, " + calls + " llamadas";
    }
}
