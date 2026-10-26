package sandevistan.viewpoint;

import me.zed_0xff.zombie_buddy.Patch;

/**
 * Enganches de ZombieBuddy (los aplica por nombre de clase y metodo). El cuerpo de cada uno se copia dentro del metodo
 * enganchado, asi que solo llama a Ghosts, Rain3D o IsoGhosts: toda la logica y el manejo de errores estan alla.
 * Los de Viewpoint van con los argumentos como Object porque las clases de Viewpoint que los declaran no son publicas.
 * Los Iso* (136) son del juego y valen sin Viewpoint: son el modo isometrico, que dibuja las estelas con el mismo pipeline
 * de siempre y solo hace algo cuando Lua pidio estelas.
 */
public final class Patches {
    private Patches() {}

    /**
     * viewpoint.models.ModelCapture.capture(Frame, ModelSlotRenderData, IsoGameCharacter, ...): agrega las piezas de un personaje. (186) Si el
     * disfraz nivel B lo esconde (Hide3D), no se captura (devuelve false sin agregar nada; Characters.snapshot no usa lo que devuelve).
     */
    @Patch(className = "viewpoint.models.ModelCapture", methodName = "capture")
    public static final class Capture {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.Argument(0) Object frame, @Patch.Argument(2) Object character) {
            Ghosts.captureEnter(frame, character);
            return Hide3D.hidden(character);
        }

        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Object frame, @Patch.Argument(2) Object character, @Patch.Return boolean drawn) {
            Ghosts.captureExit(frame, character, drawn);
        }
    }

    /** viewpoint.models.Characters.snapshot(Frame, IsoCell, IsoGameCharacter): captura a todos los personajes del cuadro. */
    @Patch(className = "viewpoint.models.Characters", methodName = "snapshot")
    public static final class Snapshot {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Object frame) {
            Ghosts.afterCharacters(frame);
        }
    }

    /** (134) viewpoint.render.FrameUniforms.one(GlProgram, String, float): uniformes comunes; uRainClock pasa por el reloj de Rain3D. */
    @Patch(className = "viewpoint.render.FrameUniforms", methodName = "one")
    public static final class Uniform {
        @Patch.OnEnter
        public static void enter(@Patch.Argument(1) String name, @Patch.Argument(value = 2, readOnly = false) float value) {
            if ("uRainClock".equals(name)) value = Rain3D.clock(value);
        }
    }

    /** (134) viewpoint.render.WeatherPass.air(GlProgram, SceneData): carga uRainClock por su cuenta (lluvia y nieve); se vuelve a cargar al salir. */
    @Patch(className = "viewpoint.render.WeatherPass", methodName = "air")
    public static final class Air {
        @Patch.OnExit
        public static void exit(@Patch.Argument(0) Object program, @Patch.Argument(1) Object scene) {
            Rain3D.air(program, scene);
        }
    }

    /** (134) viewpoint.render.WeatherPass.uniforms(FrameContext): ahi lee Tuning.rainExposure (largo del trazo de cada gota). */
    @Patch(className = "viewpoint.render.WeatherPass", methodName = "uniforms")
    public static final class Exposure {
        @Patch.OnEnter
        public static void enter() {
            Rain3D.exposureEnter();
        }

        @Patch.OnExit
        public static void exit() {
            Rain3D.exposureExit();
        }
    }

    // (136) Estelas con pose real en la camara isometrica: el mismo jar, sin Viewpoint. Estos dos son del juego y corren
    // siempre; sin pedidos ni estelas guardadas no hacen nada (un puñado de comparaciones por cuadro).

    /**
     * zombie.core.skinnedmodel.model.ModelSlotRenderData.init(ModelSlot): al salir ya tiene el personaje, la ranura y la pose
     * del cuadro (lo arma IsoSprite.renderActiveModel -> SpriteRenderer.drawModel antes de encolarla).
     */
    @Patch(className = "zombie.core.skinnedmodel.model.ModelSlotRenderData", methodName = "init")
    public static final class IsoCapture {
        @Patch.OnExit
        public static void exit(@Patch.This Object self) {
            IsoGhosts.captureEnter(self);
        }
    }

    /**
     * (138c) zombie.iso.fboRenderChunk.FBORenderCell.renderMovingObjects(): el pase de los personajes. Al entrar se encolan las estelas,
     * cada una con su camara y su ranura, como el juego encola a un personaje (antes iba en RenderList.RenderOpaque, que en isometrico
     * no se dibuja con la camara del personaje: las estelas nunca se vieron).
     */
    @Patch(className = "zombie.iso.fboRenderChunk.FBORenderCell", methodName = "renderMovingObjects")
    public static final class IsoDraw {
        @Patch.OnEnter
        public static void enter() {
            IsoGhosts.drawFrame();
        }
    }
}
