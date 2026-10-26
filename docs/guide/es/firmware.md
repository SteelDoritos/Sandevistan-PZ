# Firmware

[Volver al contenido](README.md) · [English](../en/firmware.md)

Los chips de firmware cambian cómo se comporta el implante. El implante tiene **dos ranuras**:

- **Sistema:** cómo maneja el Heat, el enfriamiento, la carga neuronal y el rechazo.
- **Habilidad:** qué te permite hacer.

Una ranura vacía es el comportamiento normal. El firmware es opcional, y una opción de sandbox lo puede apagar.

## Instalar y sacar chips

- **Instalar:** clic derecho sobre el chip en tu inventario (unos 10 segundos, con el implante **apagado**). No hace falta cirugía ni
  computadora.
- Cada cambio suma **3 de rechazo** y deja el implante **recalibrando** durante una hora de juego (el Heat sube un 10 % más rápido). Con
  rechazo 75 o más no se pueden cambiar chips.
- **Ver o sacar** los chips instalados: clic derecho en el suelo → *Firmware*. Si te explantan el implante, sus chips vuelven a tu
  inventario.

## Los programas

Los programas se aprenden subiendo la adaptación: cada uno "se te ocurre" en un nivel. La pestaña Implante muestra cuántos conoces y
cuándo llega el próximo. La opción de sandbox *Todos los programas de firmware conocidos* omite este paso.

| Programa | Ranura | Se aprende en | Qué hace | El costo |
|---|---|---|---|---|
| **Martillo** | Habilidad | nivel 3 | Para armas pesadas: golpes más lentos que pegan mucho más fuerte, más derribo y el doble de daño crítico. | Recuperas mucha menos resistencia por golpe; el arma se gasta más rápido. |
| **Compatibilidad** | Sistema | nivel 4 | El rechazo sube un cuarto más lento, los cortes y colapsos cuestan un cuarto menos de rechazo, la adaptación pasiva es 1,5 veces más rápida y la inmunodepresión es un cuarto menor. | Un poco más de Heat. |
| **Centinela** | Sistema | nivel 4 | El Heat depende de cuánto te mueves: quieto cuesta mucho menos, caminando es normal y corriendo cuesta más. Quieto también da la mitad de XP por uso. | La carga neuronal y la resistencia no cambian. |
| **Filtro** | Sistema | nivel 4 | Los zombis falsos, los ecos, el texto corrupto, el eco de tus ruidos, las marcas fantasma y las figuras al costado aparecen **cuatro veces menos**. | Te deja **sin sentido de peligro** (ni marcas reales ni fantasma) y sin el aviso de Heat por sonido. El clon y el disfraz no se filtran. |
| **Apogeo** | Habilidad | nivel 4 | Cada zombi que matas con el implante encendido baja el Heat 20 (como mucho 3 muertes cada 3 segundos) y da más XP de adaptación. | El Heat base sube un poco más rápido: sin matar, duras menos. |
| **Cámara criogénica** | Sistema | nivel 5 | Con el implante apagado enfría casi el doble de rápido. Es un diseño militar. | El Heat sube más rápido, el tope de Heat baja al 80 % y la ventana de Overdrive es más corta. |
| **Reactor** | Sistema | nivel 5 | La barra de Heat se llena como si fuera hasta 150, así que aguantas mucho más tiempo encendido, y el impulso sube más rápido y se pierde más lento. | Apagado enfría a la mitad: una barra llena tarda unas tres veces más en recuperarse. |
| **Overclock** | Habilidad | nivel 5 | Sin Overdrive, pero desde la mitad del tope de Heat tus bonos de movimiento y ataque suben y los zombis se frenan más, al máximo en el tope. | Un 50 % más de carga neuronal por segundo y síntomas más fuertes. |
| **Taller** | Habilidad | nivel 5 | La tecla enciende un **modo trabajo** en vez de la dilatación de combate: zombis un 25 % más lentos, fabricar, reparar y leer un 25 % más rápido, y muy poco Heat y carga neuronal (nada con la adaptación estable mientras sigas trabajando). | Sin bonos de combate, sin Overdrive ni furia. Se suspende si se te acerca un zombi, y no funciona con carga neuronal 60 o más ni con rechazo 50 o más. |

Todos los programas funcionan en implantes de laboratorio y militares.

## Escribir un programa

Necesitas:

- un **chip de firmware virgen** (se fabrica con Electricidad 4, mira [Recetas](surgery-and-crafting.md#recetas), o se encuentra de vez
  en cuando);
- una **computadora con corriente** o una **Terminal de grabación** (no se fabrica: solo se encuentra en lugares militares). La terminal
  gasta una batería por programa;
- para los diseños militares (Cámara criogénica), además un **Microchip de grado militar**.

Clic derecho sobre la computadora o la terminal → escribir el programa. Tarda **60 segundos** sin adaptación y baja hasta **25** con la
adaptación estable. No pide Electricidad, porque es código: lo que cuenta es la costumbre con el implante.

## Chips programados y decompilar

Los chips que vienen ya programados son muy raros (laboratorios, oficinas, depósitos del ejército y la base militar). Puedes:

- **instalarlo** enseguida; o
- **decompilarlo** en una computadora con corriente o con la terminal (la mitad del tiempo de escritura). Aprendes el programa aunque
  no te alcance el nivel, y el chip queda virgen para volver a usarlo.

Llevar **los dos expedientes militares completos** también te enseña **Compatibilidad** y **Cámara criogénica**.
