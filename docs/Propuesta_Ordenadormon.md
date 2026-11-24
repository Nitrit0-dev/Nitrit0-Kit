# Ordenadormon: el equipo como criatura que evoluciona

Borrador para decidir. Es la idea de Juan (2026-11-22): un juego tipo Pokémon donde cada ordenador sale como un bicho distinto según la opción elegida, cambia de aspecto con los resultados y, si se supera todo, acaba como un superordenadormon. Encaja con el menú por recorrido (Revisar, Probar, Arreglar, Entregar): cada paso hace crecer a la criatura.

Los dibujos son propios. Nada de copiar personajes ni nombres de Pokémon; solo la mecánica de «evoluciona según lo que haces».

## Cómo funciona

1. **Huevo.** Al abrir un equipo nuevo sale un huevo con forma de caja de ordenador. Todavía no se sabe qué es.
2. **Especie.** Al elegir la opción de entrada, el huevo eclosiona en una especie distinta:

| Opción elegida | Especie | Rasgo |
|---|---|---|
| Va lento | Lentín | Caracol con carcasa de torre; la velocidad se ve en lo que se arrastra |
| No arranca / pantalla | Apagón | Bicho de pantalla negra con luces que se encienden al reparar |
| Internet | Antenito | Antenas y cola de cable; el Wi-Fi son sus ondas |
| Ruidos / calor | Ventilón | Ventilador por cara; el humo y el color dicen la temperatura |
| Limpiar y acelerar | Brillín | Esponja de metal; cada GB liberado le quita polvo |
| Revisión completa | Todoterreno | Forma neutra, la que más puede cambiar |

3. **Cuerpo por piezas.** Cada comprobación es una parte del cuerpo y cambia con el resultado:

| Comprobación | Parte | Bien | Mal | Arreglado |
|---|---|---|---|---|
| Disco | Barriga | Llena y firme | Grietas | Remendada |
| Memoria | Ojos | Grandes y vivos | Entornados | Despiertos |
| Procesador | Corazón | Late rápido | Late flojo | Late estable |
| Temperatura | Aura | Fresca, azulada | Roja, con humo | Tibia |
| Red | Antenas | Rectas | Torcidas | Enderezadas |
| Pantalla | Cara | Nítida | Píxeles muertos | Sin cambios visibles |
| Teclado y ratón | Manos | Ágiles | Torpes | Reparadas |
| Sonido | Voz | Clara | Con ruido | Limpia |

4. **Etapas.** La criatura crece con el número de pasos completados, no solo con aprobar:
   - **Cría:** tras Revisar.
   - **Joven:** tras Probar.
   - **Adulta:** tras Arreglar.
   - **Superordenadormon:** solo si al entregar está todo en verde (nota de salud alta, sin pruebas pendientes y todo lo que falló, arreglado). Aspecto dorado, con las piezas brillando.
5. **Si algo no se puede arreglar** (un disco con sectores dañados, por ejemplo), no se oculta: la criatura llega a adulta con esa pieza marcada y la nota lo dice. Así no se regala el final.

## Qué ve la persona

- En **Inicio**, su criatura de hoy, con la última evolución y lo que le falta para la siguiente.
- En **Probar**, cada prueba superada ilumina su parte del cuerpo. Es el juego visual.
- En **Entregar**, una tarjeta de la criatura (imagen para compartir) con la especie, la etapa, el antes y el después y la nota. Es lo que se manda por WhatsApp.
- Colección: el equipo guarda las criaturas de cada revisión y se ve cómo ha mejorado con el tiempo.

## Qué hace falta

- Dibujos en SVG por capas: 6 especies, 8 piezas con 3 estados cada una y 4 etapas. Se pintan según los resultados, sin imágenes pesadas.
- Estado en `Datos\Pasaporte` (en pack público, en la caché del PC). Se alimenta de lo que ya produce RevisionTotal, Pruebas y Arreglar.
- Textos sin estilo de IA, cortos y con humor seco. Se revisan con las skills antislop y humanizer.

## Orden de trabajo propuesto

1. Una sola especie (Todoterreno) con las 8 piezas y las 4 etapas, conectada a la Revisión total. Capturas para aprobar el dibujo.
2. Las demás especies y la elección por opción de entrada.
3. Tarjeta para compartir y colección.
4. Logros ligados a la criatura (primera evolución, final dorado, cinco equipos seguidos).

## Lo que decide Juan

- **Nombre.** «Ordenadormon» recuerda mucho a Pokémon. Mejor uno propio que se pueda enseñar a clientes sin problemas (Nitrit0, «Bit», «Nitrito»…).
- **Estilo.** Decidido por Juan: pixel art. Se dibuja en rejilla pequeña (por ejemplo 32x32) y se escala sin suavizar (`image-rendering: pixelated`) para que no pierda el aspecto retro.
- **Modo sencillo.** Recomiendo que sea donde más se vea la criatura; en el modo técnico, un adorno pequeño en Inicio.
