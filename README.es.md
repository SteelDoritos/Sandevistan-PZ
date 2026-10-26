# Sandevistan para Project Zomboid (Build 42)

[English](README.md)

Mod que agrega el implante espinal **Sandevistan** de *Cyberpunk 2077 / Edgerunners* como un sistema de riesgo y recompensa:
ralentizas el tiempo para el resto del mundo y lo pagas con calor, rechazo del implante, carga neuronal y, si abusas,
cyberpsicosis. No hay cura mágica: el cuerpo es el eslabón débil, no el chip.

- **Descarga:** [Steam Workshop (3816048725)](https://steamcommunity.com/sharedfiles/filedetails/?id=3816048725). Es la única
  forma de conseguir el mod jugable.
- **Versión:** 0.8 (build 201) · Project Zomboid Build 42 (probado en 42.21, `versionMin=42.20`)
- **Idiomas:** inglés, español latinoamericano, español rioplatense y ruso

## Qué es este repositorio

Es la casa pública de la **documentación y el código fuente** del mod: para leer cómo funciona, revisar qué le hace a una partida
o a un servidor y aprender del código. Contiene:

| Carpeta | Qué |
|---|---|
| [`docs/guide/`](docs/guide/README.md) | La **guía del jugador** (inglés y español): cada sistema, los números y dónde encontrar todo (con los spoilers marcados). |
| [`docs/how-it-works/`](docs/how-it-works/README.md) | **Cómo funciona por dentro** (en inglés): dónde corre cada parte del código, qué se guarda dónde, el ciclo de una activación, el multijugador y los add-ons Java. |
| `mod/` | El Lua, los scripts de ítems y recetas, las opciones de sandbox, los `mod.info` y las traducciones de los cuatro mods, igual que en el Workshop. |
| `java/` | El código fuente Java de los tres add-ons opcionales (se cargan con ZombieBuddy). |
| [`CHANGELOG.md`](CHANGELOG.md) | Qué cambió en la última actualización (en inglés). |

Lo que **no** contiene: modelos, texturas, íconos, sonidos, los `.jar` compilados ni los conjuntos de animación (derivan de
archivos vanilla). Por eso `mod/` no es una copia jugable: instala el mod desde el Workshop.

El desarrollo se hace en otro lugar y este repositorio se genera a partir de él en cada versión, así que no se edita a mano. Los
comentarios del código están en español y a veces nombran notas de diseño internas que no están publicadas aquí.

## Instalación

Desde el Workshop: suscríbete y activa **Sandevistan** en la pantalla de Mods antes de crear la partida o el servidor.

- **Opcional:** [Moodle Framework](https://steamcommunity.com/workshop/filedetails/?id=3396446795) muestra los estados del mod como
  moodles. Sin él todo funciona igual y los estados se ven en el panel flotante.
- **Add-ons Java opcionales** (se activan junto al mod base): *Slow sound and frozen rain* (`SandevistanFX`), *Cyberpsychosis
  hallucinations* (`SandevistanPsychosis`) y *Afterimages with real pose* (`SandevistanViewpoint`). Los tres necesitan
  [ZombieBuddy (3619862853)](https://steamcommunity.com/sharedfiles/filedetails/?id=3619862853). **Aprueba sus jars al arrancar
  el juego**, no después de cargar una partida con Viewpoint (se cierra el juego).
  [Viewpoint (3809306528)](https://steamcommunity.com/sharedfiles/filedetails/?id=3809306528) es opcional, para la cámara 3D.
- **Servidor dedicado:** solo hace falta `Sandevistan`; los add-ons son de cliente. Si el servidor los activa sin ZombieBuddy, no
  cargan y el mod base sigue funcionando.

## Reportar un problema

Reporta los errores en los **comentarios de la página del Workshop**, con:
- la versión del mod (está arriba del reporte),
- si es una partida individual, alojada o un servidor dedicado,
- el archivo `Zomboid/Lua/Sandevistan_report.txt` (activa el menú de depuración en las opciones del mod y luego *Debug →
  Pruebas e informes → REPORTE rápido*) y, si hay errores, `Zomboid/console.txt`.

En este repositorio las issues están desactivadas y no se aceptan pull requests: el código se genera desde el repositorio de
desarrollo en cada versión.

## Licencia

- **Código** (Lua y Java de `mod/` y `java/`): [MIT](LICENSE).
- **Documentación** y **assets propios** del mod: [CC BY-NC-SA 4.0](LICENSE-docs.md).
- Project Zomboid es de The Indie Stone; el material de terceros conserva su licencia. Ver [NOTICE](NOTICE.md) y
  [CREDITS](CREDITS.md).
