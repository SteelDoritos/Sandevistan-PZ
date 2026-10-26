package sandevistan.psychosis;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * Enganches de la cyberpsicosis en el juego (ZombieBuddy los aplica por nombre de clase y metodo). El cuerpo de cada uno se copia dentro del
 * metodo del juego, asi que solo llama a Puppets, TextGlitch, MoodleGlitch o Disguise: la logica y el manejo de errores estan alla.
 * (152) Salieron de SandevistanFX (27 §11.3).
 */
public final class Patches {
    private Patches() {}

    /** (138) zombie.iso.fboRenderChunk.FBORenderCell.renderMovingObjects(): el pase de los personajes de cada vista; ahi se encolan los titeres. */
    @Patch(className = "zombie.iso.fboRenderChunk.FBORenderCell", methodName = "renderMovingObjects")
    public static final class PuppetDraw {
        @Patch.OnEnter
        public static void enter() {
            Puppets.render();
        }
    }

    /** (138) zombie.core.fonts.AngelCodeFont.render(String text, int start, int end): todo texto de la fuente; en un episodio de texto corrupto se cambia. */
    @Patch(className = "zombie.core.fonts.AngelCodeFont", methodName = "render")
    public static final class TextRender {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(value = 0, readOnly = false) String text,
                                 @Patch.Argument(1) int start, @Patch.Argument(2) int end) {
            text = TextGlitch.text(self, text, start, end);
        }
    }

    /**
     * (149) zombie.ui.UIElement.DrawTexture(Texture, x, y, alpha): con el glitch de moodles, lo que dibuja MoodlesUI va corrido, con copias de
     * color y a veces desgarrado (MoodleGlitch). Engancha todas las versiones de DrawTexture (sus cuatro primeros argumentos son del mismo tipo),
     * pero MoodleGlitch solo toca las llamadas de MoodlesUI, y esa usa la de cuatro.
     */
    @Patch(className = "zombie.ui.UIElement", methodName = "DrawTexture")
    public static final class MoodleTexture {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(0) Object tex, @Patch.Argument(value = 1, readOnly = false) double x,
                                 @Patch.Argument(value = 2, readOnly = false) double y, @Patch.Argument(value = 3, readOnly = false) double a) {
            MoodleGlitch.texture(self, tex, x, y, a);
            x = MoodleGlitch.outX;
            y = MoodleGlitch.outY;
            a = MoodleGlitch.outA;
        }
    }

    /** (149) zombie.ui.UIElement.DrawTextureCol(Texture, x, y, Color): el fondo y el borde de cada moodle, igual que arriba. */
    @Patch(className = "zombie.ui.UIElement", methodName = "DrawTextureCol")
    public static final class MoodleTextureCol {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(0) Object tex, @Patch.Argument(value = 1, readOnly = false) double x,
                                 @Patch.Argument(value = 2, readOnly = false) double y, @Patch.Argument(value = 3, readOnly = false) zombie.core.Color col) {
            MoodleGlitch.textureCol(self, tex, x, y, col);
            x = MoodleGlitch.outX;
            y = MoodleGlitch.outY;
            col = MoodleGlitch.outCol;
        }
    }

    /** (147) zombie.core.skinnedmodel.visual.HumanVisual.getSkinTexture(): la piel del cuerpo; a los disfrazados de este cliente se les cambia. */
    @Patch(className = "zombie.core.skinnedmodel.visual.HumanVisual", methodName = "getSkinTexture")
    public static final class SkinTexture {
        @Patch.OnExit
        public static void exit(@Patch.This Object self, @Patch.Return(readOnly = false) String skin) {
            skin = Disguise.skin(self, skin);
        }
    }

    /**
     * (174) zombie.characters.IsoPlayer.render(...): disfraz nivel B. Mientras un titere zombi lo reemplaza, este cliente no dibuja al jugador real
     * (el juego hace lo mismo con el jugador local cuando no se muestra su modelo). Disguise.hidden decide; ante un error devuelve false.
     */
    @Patch(className = "zombie.characters.IsoPlayer", methodName = "render")
    public static final class HidePlayer {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Object self) {
            return Disguise.hidden(self);
        }
    }

    /** (174) zombie.characters.IsoGameCharacter.renderShadow(x, y, z): la sombra del real tampoco (el titere pone la suya). */
    @Patch(className = "zombie.characters.IsoGameCharacter", methodName = "renderShadow")
    public static final class HideShadow {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Object self) {
            return Disguise.hidden(self);
        }
    }

    /** (174) zombie.characters.IsoPlayer.renderlast(): el nombre y el globo de chat sobre la cabeza del real tampoco. */
    @Patch(className = "zombie.characters.IsoPlayer", methodName = "renderlast")
    public static final class HideName {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Object self) {
            return Disguise.hidden(self);
        }
    }

    /**
     * (181) C13.3 zombie.core.textures.Texture.rendershader2(x, y, w, h, ...): la sacudida. (183) Solo la pasada del mundo a la pantalla
     * (MultiTextureFBO2.render, ver ScreenOverlay) va corrida; Shake decide y cualquier otra llamada sigue igual. Los enganches de la 181
     * (PlayerCamera.update) y de la 182 (IsoCamera$FrameState.set) se sacaron: no movian la imagen entera.
     */
    @Patch(className = "zombie.core.textures.Texture", methodName = "rendershader2")
    public static final class WorldBlit {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(value = 0, readOnly = false) float x,
                                 @Patch.Argument(value = 1, readOnly = false) float y, @Patch.Argument(value = 2, readOnly = false) float w,
                                 @Patch.Argument(value = 3, readOnly = false) float h) {
            Shake.world(self, x, y, w, h);
            x = Shake.outX;
            y = Shake.outY;
            w = Shake.outW;
            h = Shake.outH;
        }
    }

    /** (181) C13.5 zombie.iso.weather.WeatherShader.startMainThread(TextureDraw, int vista): desaturacion, ondulacion y desenfoque del episodio. */
    @Patch(className = "zombie.iso.weather.WeatherShader", methodName = "startMainThread")
    public static final class ScreenShader {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Object td, @Patch.Argument(1) int view) {
            Screen.shaderVars(td, view);
        }
    }

    /**
     * (181) C13.5 zombie.core.textures.MultiTextureFBO2.render(): el mundo ya paso a la pantalla; encima, la separacion de color y el desgarro.
     * (183) Ademas marca cuando se esta pasando el mundo, para la sacudida (WorldBlit).
     */
    @Patch(className = "zombie.core.textures.MultiTextureFBO2", methodName = "render")
    public static final class ScreenOverlay {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self) {
            Shake.worldBegin(self);
        }

        @Patch.OnExit
        public static void exit(@Patch.This Object self) {
            Shake.worldEnd();
            Screen.overlay(self);
        }
    }
}
