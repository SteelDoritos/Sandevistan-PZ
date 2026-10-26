# Usar el implante

[Volver al contenido](README.md) · [English](../en/using-the-implant.md) · [Русский](../ru/using-the-implant.md)

## Controles

| Acción | Cómo |
|---|---|
| Encender | Toca **Z** (se cambia en *Opciones → Mods → Sandevistan*). Necesitas al menos un cuarto de tu resistencia. |
| Apagar | Toca Z otra vez. Es gratis: el Heat queda donde estaba y puedes volver a encenderlo después de 1 segundo. |
| Armar el Overdrive | Con el implante encendido, **mantén** Z un momento. Cuando se llene la barra de Heat entras en Overdrive en vez de un corte térmico. |
| Terminar el Overdrive antes | Toca Z durante el Overdrive. Colapsas en el acto. |
| Mostrar u ocultar el panel flotante | Una segunda tecla en las opciones del mod (sin asignar por defecto). |
| Forzar el implante | Con el implante **apagado**, **mantén** Z 0,8 s cuando lo único que te frena es la **resistencia** o el **calor** (los avisos de siempre). Entra directo en Overdrive. |
| Desconectar / reconectar | En el menú del implante (**Desconectar el implante** / **Reconectar el implante**). Solo con el implante **apagado** y sin furia. |

Con cyberpsicosis el implante cuesta más de controlar: para armarlo hace falta un doble toque y después mantener, y el apagado
responde con un pequeño retraso.

**Forzar** siempre termina en un colapso y se paga:

- **Sin aire:** la resistencia baja a 0, quedas con fatiga y sin esprint 10 s. No puedes volver a forzarlo hasta recuperar la
  **mitad** de la resistencia.
- **Trabado por calor:** te quemas la espalda baja, el implante suma **+0,1×** de desgaste y te queda **cicatriz térmica** aunque el
  colapso del día fuera gratis. No puedes volver a forzarlo hasta que el Heat llegue a **0**.

No hay una espera fija: el bloqueo se levanta solo cuando te recuperas. Forzar es para emergencias, y se puede apagar en el sandbox.

### Desconectar el implante

Puedes **desconectar** el implante desde su menú (solo con el implante **apagado** y sin la furia). Mientras está desconectado queda inerte:

- no se puede encender y el firmware no corre;
- la **carga neuronal baja a la mitad** y la **remisión avanza a la mitad**;
- los síntomas del daño cerebral siguen **a la mitad** (×0,25 con antidepresivos): alucinaciones, apagones, terrores nocturnos, gritos,
  sangrado de nariz;
- lo que hace el implante desaparece: mensajes del monitor neural, marcas de peligro y el glitch de pantalla. El panel dice **DESCONECTADO**.

**Reconectar** cuesta **+8 de carga neuronal**, **20 segundos** sin poder encenderlo, algo de estrés y un glitch corto; si reconectas
antes de **10 minutos**, la carga neuronal cuesta el **doble**. Reconectar también reinicia la remisión.

## Dilatación del tiempo

![Dilatación encendida: las estelas quedan detrás de ti mientras los zombis de alrededor se mueven en cámara lenta.](../../img/afterimages-day.jpg)
*Dilatación encendida: las estelas quedan detrás de ti mientras los zombis de alrededor se mueven en cámara lenta.*

Con el implante encendido, los zombis a menos de **16 tiles** (opción de sandbox) caminan, giran, atacan, caen y se levantan en
cámara lenta. Tú te mueves más rápido y atacas más rápido. La fuerza depende de tu nivel de adaptación y del implante:

| Tramo | Nivel de adaptación | Velocidad de los zombis | Tu movimiento | Tu velocidad de ataque | Implantes |
|---|---|---|---|---|---|
| I | 0 a 4 | 30 % | +25 % | +50 % | todos |
| II | 5 a 7 | 25 % | +35 % | +75 % | todos |
| III | 8 o más | 20 % | +40 % | +100 % | solo militar |
| IV | maestría 15 | 18 % | +45 % | +110 % | militar, con el mod Beyond Ten |

Los implantes de laboratorio se quedan en el tramo II, porque su adaptación llega solo al nivel 5.

Otros efectos mientras está encendido:

- **Impulso:** cuanto más tiempo seguido lo usas, más ganas, hasta +10 % de movimiento y +25 % de ataque a los 15 segundos más o
  menos. Lo extra se pierde en alrededor de un minuto después de apagarlo.
- **Cuerpo a cuerpo:** el implante multiplica el daño de cada golpe, ajustado por arma (las livianas ganan más y las pesadas, menos).
  Con Fuerza 5 y nivel 0 en el arma, un bate mata a un zombi en unos 3 golpes. También tienes +15 % de probabilidad de crítico, +15 %
  de derribo y recuperas el 30 % de la resistencia de cada golpe. La velocidad de ataque tiene un tope de 2,5×, y lo que pasa del tope
  se convierte en daño extra.
- **Armas de fuego:** recargar, montar el cerrojo y cambiar cargadores se acelera tanto como tu movimiento (opción de sandbox).
- **Animaciones más rápidas:** caminar, correr, trepar vallas, paredes y ventanas, y las sogas. Con el implante encendido, las trepadas
  y los tropiezos por choque pueden no fallar, con una probabilidad igual a tu adaptación. Con la adaptación estable no fallan nunca.
- **Estelas:** un rastro de siluetas de color detrás de ti: celeste en laboratorio, ámbar en militar, rojo con cyberpsicosis. Hay una
  opción de estelas arcoíris en las opciones del mod.
- **Deuda de resistencia:** con el implante encendido, tu resistencia **no baja**. Lo que gastas se cobra cuando lo apagas: correr,
  esprintar, golpear, empujar, trepar y el propio desgaste del implante quedan anotados. Si la cuenta pasa en más de un 35 % la
  resistencia que tenías al encenderlo, el implante se corta solo y quedas con un tropiezo y sin esprint de 2 a 5 segundos. El moodle
  **Aliento prestado** muestra cuánto llevas. La opción de sandbox *Deuda de estamina* (Apagada / Normal / Suave) la apaga o deja
  solo el cobro.

En multijugador, los demás jugadores dentro de la burbuja también se frenan (los administradores nunca).

## Heat

El Heat sube cada segundo que el implante está encendido y baja cuando está apagado.

- En **100** el implante se corta solo (un **corte térmico**). Tropiezas un segundo y el implante queda **bloqueado** hasta que el Heat
  vuelve a 0. Un corte térmico suma de 2 a 4 de rechazo, y nada con la adaptación estable.
- Tiempos aproximados de 0 al corte: laboratorio nivel 0, unos **6 s**; laboratorio nivel 5, unos **10 s**; militar nivel 0, unos
  **8 s**; militar nivel 10, unos **18 s**.
- Enfriado desde lleno: laboratorio nivel 0, unos 30 s; laboratorio nivel 5, unos 20 s; militar nivel 10, unos 12 s.
- **Enfriamiento ambiental:** el frío, la ropa mojada y el viento al aire libre enfrían el implante hasta **×1,45** más rápido (×1,9 en
  *Fuerte*). El mismo bono hace que la barra de Heat suba un poco más lento mientras está encendido (unas ×1,15 con el bono completo),
  así que la ráfaga dura más. Solo ayuda: el calor nunca lo empeora. Usar el implante te seca. Opción de sandbox: *Enfriamiento
  ambiental* (Apagado / Normal / Fuerte).
- El Heat sube más rápido con el implante gastado (mira [Desgaste](#desgaste-y-calibración)), con carga neuronal alta, con el rasgo
  Edgerunner y justo después de cambiar el firmware. Sube más lento con Black Lace.
- Un sonido te avisa al llegar a 80 de Heat.

## Overdrive

El Overdrive es un empujón más allá del límite. Se arma manteniendo la tecla con el implante encendido. Cuando el Heat llega a 100
obtienes:

- una ventana de **2,5 s** a nivel 0, que sube hasta **4 s** (laboratorio a nivel 5) o **7 s** (militar a nivel 10);
- encima de tu tramo: +40 % de movimiento, +100 % de velocidad de ataque, zombis a la mitad de la velocidad que ya tenían y +50 % de
  daño cuerpo a cuerpo.

**Siempre termina en un colapso:**

- tropiezas, te arrastras un par de segundos, te da fiebre (38,5–39,5 °C) y recibes daño y dolor en el torso;
- +5 a 10 de carga neuronal y +10 a 18 de rechazo (la mitad con la adaptación estable);
- un ruido que atrae a los zombis cercanos;
- una **cicatriz térmica**: tu Heat máximo baja 5 (el primer colapso de cada día de juego es gratis). Se recupera 1 punto por hora con
  el implante apagado, y más rápido durmiendo. Una "furia total" (mira [cyberpsicosis](your-body.md#cyberpsicosis)) cuesta 15. El tope
  nunca baja de 50.

Con cyberpsicosis, un colapso de Overdrive tiene un **1 % de probabilidad de matarte** y un 20 % de dejarte un corte profundo en el
pecho. Con Black Lace, además te deja inconsciente de 5 a 10 segundos y te daña el corazón.

## Adaptación

**Sandevistan: Adaptación** es una habilidad. Sube mientras tienes el implante instalado:

- 2 XP por segundo de uso;
- 12 XP por zombi que matas con el implante encendido;
- 5 XP por hora de juego, solo por llevarlo, mientras el rechazo esté por debajo de 50.

Los niveles desbloquean tramos más fuertes, menos Heat, mejor enfriamiento, una ventana de Overdrive más larga, más estelas, menos
trepadas fallidas y menos carga neuronal por uso (hasta −25 %). Pasa el mouse por un cuadradito de nivel en la pestaña de habilidades
para ver exactamente qué da cada nivel.

La **adaptación estable** es el nivel 5 en los implantes de laboratorio y el 7 en los militares. Importa mucho: desde ahí el implante
**deja de subir el rechazo por sí solo** (mira [Rechazo](your-body.md#rechazo)).

**Maestría:** con el mod **Beyond Ten**, los implantes militares siguen mejorando del nivel 11 al 15. Cada nivel recorta Heat,
resistencia y carga neuronal, y suma tiempo de Overdrive. El nivel 15 desbloquea el tramo IV.

La adaptación es **tuya**, no del implante. Si cambias de implante la conservas entera (la mitad si el anterior estaba destruido).

## Los implantes

| | Laboratorio (Prototipo 05 / 06) | Militar (XM-1 / Mk. II) |
|---|---|---|
| Adaptación máxima | 5 | 10 (15 con Beyond Ten) |
| Mejor tramo | II | III (IV con maestría) |
| Ventana de Overdrive al máximo | 4 s | 7 s |
| Carga neuronal por uso | ×0,7 | ×1,0 |
| Heat base | más alto | más bajo |

Los de laboratorio son más fáciles de llevar. Los militares son más fuertes, pero cuestan más carga neuronal. El Prototipo 04 es una
unidad de laboratorio defectuosa que se puede reparar (mira [Reparar un Prototipo 04](surgery-and-crafting.md#reparar-un-prototipo-04)).

## Desgaste y calibración

Cada implante tiene un **desgaste**: un multiplicador del Heat, donde 1,0× es perfecto. Una extracción tosca, una cirugía fallida o
un estudio suman desgaste. El tooltip del ítem lo muestra. Un implante gastado se puede **calibrar** de vuelta a 1,0× (mira
[Calibración](surgery-and-crafting.md#calibración)), suelto o instalado. Un Prototipo 04 reparado no baja de 1,2×.

## El HUD

![El panel flotante del Prototipo 05: Heat, rechazo y carga neuronal.](../../img/hud-panel.jpg)
*El panel flotante del Prototipo 05: Heat, rechazo y carga neuronal.*

![La pestaña Implante en la ventana del personaje (capturada en una versión anterior; algunos números cambiaron).](../../img/implant-tab.jpg)
*La pestaña Implante en la ventana del personaje (capturada en una versión anterior; algunos números cambiaron).*

- **Panel flotante:** Heat, carga neuronal, rechazo, cobertura y adaptación. Se desvanece cuando no usas el implante. Cambia según el
  implante: una placa de circuito en el de laboratorio, fibra de carbono en el XM-1 y aluminio grabado en el Mk. II. Su tamaño se ajusta
  en las opciones del mod.
- **Pestaña Implante** en la ventana del personaje: todos los números, qué los sube o los baja, cuánto falta para que se pase cada cosa,
  tu firmware y un botón para la guía de campo.
- **Moodles** (con Moodle Framework): Heat, bloqueo, rechazo, carga neuronal, cyberpsicosis, toxicidad herbal, inmunodepresión, Black
  Lace y su bajón, cobertura, antidepresivos, abstinencia y recuperación, recalibrado. Los de Heat, carga neuronal, rechazo e
  inmunodepresión cambian de ícono en cada nivel.
- **El implante en tu espalda:** un modelo 3D que se ilumina al encenderlo y se pone rojo en Overdrive. Las chaquetas y los abrigos lo
  tapan.
