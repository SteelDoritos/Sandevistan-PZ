package sandevistan.fx;

import fmod.fmod.FMODSoundEmitter;
import me.zed_0xff.zombie_buddy.Patch;

/**
 * Enganches en el juego (ZombieBuddy los aplica por nombre de clase y metodo). El cuerpo de cada uno se copia dentro del metodo del juego, asi que
 * solo llama a Rain o Voices: la logica y el manejo de errores estan alla.
 */
public final class Patches {
    private Patches() {}

    /** zombie.iso.weather.fx.RainParticle.update(float delta): cada gota de lluvia isometrica, cada cuadro. */
    @Patch(className = "zombie.iso.weather.fx.RainParticle", methodName = "update")
    public static final class RainUpdate {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(value = 0, readOnly = false) float delta) {
            delta = Rain.particle(self, delta);
        }
    }

    /** zombie.iso.weather.fx.SnowParticle.update(float delta): cada copo. */
    @Patch(className = "zombie.iso.weather.fx.SnowParticle", methodName = "update")
    public static final class SnowUpdate {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self, @Patch.Argument(value = 0, readOnly = false) float delta) {
            delta = Rain.particle(self, delta);
        }
    }

    /** (137) zombie.iso.IsoGridSquare.renderRainSplash(int playerIndex, ColorInfo): la salpicadura de la lluvia de cada casilla exterior. */
    @Patch(className = "zombie.iso.IsoGridSquare", methodName = "renderRainSplash")
    public static final class RainSplash {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self) {
            Splash.enter(self);
        }

        @Patch.OnExit
        public static void exit(@Patch.This Object self) {
            Splash.exit(self);
        }
    }

    /** (137) zombie.iso.IsoPuddles.update(ClimateManager): el reloj de las ondas de los charcos. */
    @Patch(className = "zombie.iso.IsoPuddles", methodName = "update")
    public static final class PuddlesUpdate {
        @Patch.OnEnter
        public static void enter(@Patch.This Object self) {
            Splash.puddlesEnter(self);
        }

        @Patch.OnExit
        public static void exit(@Patch.This Object self) {
            Splash.puddlesExit(self);
        }
    }

    /** fmod.fmod.FMODSoundEmitter.startEvent(long eventInstance, GameSoundClip, boolean): un evento de FMOD que empieza a sonar. */
    @Patch(className = "fmod.fmod.FMODSoundEmitter", methodName = "startEvent")
    public static final class StartEvent {
        @Patch.OnExit
        public static void exit(@Patch.This FMODSoundEmitter self, @Patch.Argument(0) long instance) {
            Voices.started(self, instance);
        }
    }
}
