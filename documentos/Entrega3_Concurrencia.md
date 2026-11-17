# TurismoUQ · Entrega 3 · Documento del escenario de concurrencia

Bases de Datos II · Proyecto integrador. Oracle AI Database 26ai Free, PDB `FREEPDB1`,
esquema `TURISMOUQ`. Scripts: `scripts/13_concurrencia_preparacion.sql` y
`13a` a `13e`. Evidencia: `evidencias/e3_13*.log`.

## 1. Objetivo

Mostrar qué ocurre cuando **dos sesiones intentan reservar la misma habitación al mismo
tiempo**, evidenciar el bloqueo real y comparar el comportamiento **antes** (sin bloqueo) y
**después** (con `SELECT ... FOR UPDATE`).

## 2. Montaje

| Elemento | Detalle |
|---|---|
| Habitación | `ZZ-CONC`, creada solo para el experimento (con tarifa en todas las temporadas), para no tocar datos reales y garantizar que está libre |
| Estadía | 10 al 13 de diciembre de 2026 (noches 10, 11 y 12) |
| Sesión A | Ventana 1, `13a_sesion_A.sql` (SID 193 en la ejecución registrada) |
| Sesión B | Ventana 2, `13b_sesion_B.sql`, **otra conexión** del mismo esquema, con cliente distinto (SID 212) |
| Observador | Ventana 3, `13c_monitor_bloqueos.sql` |
| Procedimiento «antes» | `PKG_TURISMO.SP_CREAR_RESERVA` (Entrega 2) |
| Procedimiento «después» | `SP_CREAR_RESERVA_SEGURA` (script 12): hace `SELECT id FROM habitacion WHERE id = :h FOR UPDATE WAIT 60` y luego llama a `SP_CREAR_RESERVA` |

Ninguna sesión usa autocommit: cada transacción termina solo con el `COMMIT` explícito.

## 3. Fase 1: ANTES (sin bloqueo)

| Paso | Sesión | Acción | Qué se observó |
|---|---|---|---|
| A1 | A | `sp_crear_reserva` de `ZZ-CONC`, 10–13 dic, **sin `COMMIT`** | Reserva 25526 creada |
| B1 | B | `sp_crear_reserva` de la **misma** habitación y fechas | Reserva 25527 creada. **No hubo bloqueo ni error** |
| A2 | A | `COMMIT` | |
| B2 | B | `COMMIT` | |

Resultado (consulta de la sesión A):

```text
ID_RESERVA FECHA_CHE FECHA_CHE ESTADO
---------- --------- --------- ------------
     25526 10-DEC-26 13-DEC-26 PENDIENTE
     25527 10-DEC-26 13-DEC-26 PENDIENTE

NOCHE      RESERVAS_ESA_NOCHE PROBLEMA
---------- ------------------ ----------------
10-DEC-26                   2 << DOBLE RESERVA
11-DEC-26                   2 << DOBLE RESERVA
12-DEC-26                   2 << DOBLE RESERVA
```

**Explicación.** `fn_habitacion_disponible` comprueba y después se inserta. Oracle aísla las
transacciones: cada sesión solo ve lo que otras ya **confirmaron**. Cuando B comprobó, la
reserva de A seguía sin `COMMIT`, así que B la vio «libre». `TRG_RH_NO_SOLAPE` (Entrega 2) no
lo evitó por la misma razón: también lee solo datos confirmados. Es la anomalía de
*comprobar y luego actuar* sin serializar, y deja **la misma habitación vendida dos veces**.

## 4. Fase 2: DESPUÉS (con `SELECT ... FOR UPDATE`)

Entre fases, `13d_limpieza_reservas_prueba.sql` borra las reservas de la fase 1 (2 borradas).

| Paso | Sesión | Acción | Qué se observó |
|---|---|---|---|
| A3 | A | `sp_crear_reserva_segura` (sin `COMMIT`) | Reserva 25528 creada; **A retiene el bloqueo** de la fila de `HABITACION` |
| B3 | B | `sp_crear_reserva_segura` de la misma habitación | **B queda esperando**: el prompt no vuelve |
| — | Ventana 3 | `13c_monitor_bloqueos.sql` | Ver 4.1 |
| A4 | A | `COMMIT` | Se libera el bloqueo; B continúa |
| B3 (fin) | B | | `ORA-20005: La habitacion ... no esta disponible entre el 2026-12-10 y el 2026-12-13` |

### 4.1 El bloqueo visto desde el observador

```text
=== 1. Quien espera a quien (V$SESSION) ===
   SID USUARIO   ESTADO  EVENTO                              BLOQUEADA_POR SEG_ESPERANDO SQL_TEXTO
   193 TURISMOUQ ACTIVE  PL/SQL lock timer                                             11 BEGIN DBMS_SESSION.SLEEP(13); END;
   212 TURISMOUQ ACTIVE  enq: TX - row lock contention                 193             7 SELECT id FROM habitacion WHERE id = :1 FOR UPDATE WAIT 60

=== 2. Bloqueos de fila (TX) y de tabla (TM) ===
   SID TIPO  MODO_RETENIDO  MODO_PEDIDO    OBJETO
   212 TX    ninguno        exclusive (X)
   193 TX    exclusive (X)  ninguno
   193 TM    row-X (RX)     ninguno        HABITACION / RESERVA / RESERVA_HABITACION
   212 TM    row-X (RX)     ninguno        HABITACION
```

(La fila de A en el evento `PL/SQL lock timer` es una pausa de la automatización usada para
registrar la evidencia; en la ejecución manual, A simplemente espera el ENTER del `PAUSE`.)

Lectura: la sesión **212 (B)** espera con el evento `enq: TX - row lock contention` y su
columna `bloqueada_por` apunta a la **193 (A)**, que retiene el bloqueo exclusivo de
transacción (`TX`, modo X) sobre la fila de la habitación. B pide un `TX` en modo exclusivo
que no se le concede mientras A no termine.

### 4.2 Resultado final de la fase 2

```text
ID_RESERVA FECHA_CHE FECHA_CHE ESTADO
     25528 10-DEC-26 13-DEC-26 PENDIENTE

NOCHE      RESERVAS_ESA_NOCHE
10-DEC-26                   1
11-DEC-26                   1
12-DEC-26                   1
```

Una sola reserva y una por noche. Para B: `RESERVAS_DE_B_EN_LA_HABITACION = 0`. B esperó a A
**≈ 9 s** (tiempo transcurrido en B3, `Elapsed: 00:00:09.01`) y, al liberarse el bloqueo, ya
veía la reserva confirmada y se rechazó correctamente.

## 5. Comparación antes y después

| | Antes (`sp_crear_reserva`) | Después (`sp_crear_reserva_segura`) |
|---|---|---|
| ¿B se bloquea? | No | Sí, hasta el `COMMIT` de A (≈ 9 s) |
| Reservas activas de la misma habitación y fechas | **2** (doble reserva) | **1** |
| Resultado para B | Éxito silencioso (error de negocio) | `ORA-20005` habitación no disponible |
| Evento de espera | Ninguno | `enq: TX - row lock contention` |
| Integridad | Se viola la regla «una habitación, una reserva por noche» | Se respeta |

## 6. Por qué la solución funciona y qué cuesta

- **Qué se bloquea.** Solo la fila de `HABITACION` de esa habitación. Dos sesiones que
  reserven habitaciones **distintas** no se estorban; solo se serializan quienes compiten por
  la misma.
- **Cuándo se libera.** En el `COMMIT` o `ROLLBACK` de la transacción que reserva. Por eso los
  procedimientos de reserva no hacen `COMMIT` internamente: quien los llama decide, y debe
  confirmar pronto para no retener el bloqueo.
- **Por qué B ahora ve la reserva.** Al obtener el bloqueo, B vuelve a leer la
  disponibilidad **después** del `COMMIT` de A, y Oracle le muestra los datos ya confirmados.
- **Espera acotada.** `FOR UPDATE WAIT 60` evita esperar eternamente: pasados 60 s responde
  `-20040` (la habitación está siendo reservada por otra sesión).
- **Costo.** Se pierde algo de concurrencia (las reservas de la misma habitación son
  secuenciales), que es justo lo que el negocio necesita.
- **Alcance.** Protege a quien reserva por `SP_CREAR_RESERVA_SEGURA` (y por
  `SP_RESERVAR_Y_PAGAR`, que la usa). Quien llame directamente a `SP_CREAR_RESERVA` o inserte a
  mano en `RESERVA_HABITACION` no pasa por el bloqueo.

## 7. Cómo repetir el experimento

1. Ejecutar `13_concurrencia_preparacion.sql` (requiere el script 12).
2. Abrir tres ventanas de SQL*Plus conectadas como `TURISMOUQ`: ejecutar `13a_sesion_A.sql` en
   la primera y `13b_sesion_B.sql` en la segunda. Los `PAUSE` indican cuándo pasar a la otra.
3. Cuando B quede esperando (paso B3), ejecutar `13c_monitor_bloqueos.sql` en la tercera.
4. Al terminar, `13e_limpieza_total.sql` borra la habitación de prueba y sus reservas.

**Capturas sugeridas:** (1) A tras A1 y B tras B1 (ambas crean la reserva); (2) la tabla
`<< DOBLE RESERVA`; (3) el observador con B en `enq: TX - row lock contention`; (4) B con
`ORA-20005` y el tiempo transcurrido; (5) la tabla final con una reserva por noche.
