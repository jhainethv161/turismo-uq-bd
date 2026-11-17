# TurismoUQ · Entrega 3 · Transacciones, concurrencia, índices y seguridad

Documento de soporte de la Entrega 3 del proyecto integrador de Bases de Datos II.
Explica qué hace cada script, en qué orden se ejecuta, qué decisiones se tomaron y qué
resultados se obtuvieron sobre una base Oracle real (**Oracle AI Database 26ai Free**,
PDB `FREEPDB1`, esquema `TURISMOUQ`).

La Entrega 3 **no modifica** las Entregas 1 y 2: agrega un procedimiento, un par de objetos
de prueba, índices, vistas, roles, un perfil y usuarios de demostración.

---

## 1. Orden de ejecución

Se ejecutan **después** de los scripts `01` a `10` (ver `README_Entrega2.md`).

| # | Script | Conectado como | Qué hace |
|---|--------|----------------|----------|
| 11 | `11_privilegios_entrega3.sql` | **DBA** en la PDB | Concede al dueño la lectura de vistas `V$` (para medir y observar bloqueos) |
| 12 | `12_transaccion_reserva_pago.sql` | dueño | `SP_CREAR_RESERVA_SEGURA` (`FOR UPDATE`), `SP_RESERVAR_Y_PAGAR` (SAVEPOINT) y demostración D1–D3 |
| 13 | `13_concurrencia_preparacion.sql` | dueño | Habitación de prueba `ZZ-CONC` para el experimento |
| 13a/13b/13c | `13a_sesion_A.sql`, `13b_sesion_B.sql`, `13c_monitor_bloqueos.sql` | dueño, **3 ventanas** | Experimento de dos sesiones (manual, con pausas guiadas) |
| 13d/13e | `13d_limpieza_reservas_prueba.sql`, `13e_limpieza_total.sql` | dueño | Limpieza entre fases / al final |
| 14 | `14_indices.sql` | dueño | 3 consultas lentas, planes antes/después, caso donde el índice no ayuda |
| 15 | `15_vistas_seguridad.sql` | dueño | 14 vistas de seguridad (una familia por rol) |
| 16 | `16_roles_usuarios_perfil.sql` | **DBA** en la PDB | 4 roles, perfil con límites y usuarios de demostración |
| 17 | `17_pruebas_seguridad.sql` | dueño | 44 pruebas `OK`/`FALLA` conectándose como cada usuario |
| 17b | `17b_pruebas_perfil.sql` | **DBA** en la PDB | Bloqueo por claves erróneas y límite de sesiones |

Los scripts `11`, `12`, `13`, `14`, `15` y `16` corren de arriba abajo en una base limpia y se
pueden repetir sin error. `13a/13b/13c` son interactivos (dos sesiones a la vez) y no hacen
parte de la corrida lineal; `17` y `17b` piden la clave de los usuarios de demostración por
pantalla (no se guarda ninguna clave en el repositorio).

```text
-- DBA, en la PDB
@scripts/11_privilegios_entrega3.sql

-- Dueño (TURISMOUQ)
@scripts/12_transaccion_reserva_pago.sql
@scripts/13_concurrencia_preparacion.sql
@scripts/14_indices.sql
@scripts/15_vistas_seguridad.sql

-- DBA, en la PDB
@scripts/16_roles_usuarios_perfil.sql

-- Dueño, luego DBA
@scripts/17_pruebas_seguridad.sql
@scripts/17b_pruebas_perfil.sql
```

Evidencia de la ejecución real en `evidencias/e3_*.log`.

---

## 2. Qué pide el enunciado y dónde está

| Componente (peso) | Entregable | Dónde |
|---|---|---|
| Transacción atómica reserva + pago con SAVEPOINT (20 %) | `SP_RESERVAR_Y_PAGAR` + demostración de rollback parcial | `12` · `e3_12_transaccion.log` |
| Concurrencia con dos sesiones y `FOR UPDATE` (15 %) | Experimento antes/después con bloqueo visible | `13*` · `e3_13*.log` |
| Índices: 3 consultas, plan antes/después, compuesto y de función (25 %) | `C1`, `C2`, `C3` | `14` · `e3_14_indices.log` |
| Caso donde el índice no ayuda (15 %) | `C4` / `C4b` (y `C5`) | `14` |
| Seguridad: 4 roles, vistas para recepción, perfil (25 %) | Roles, vistas, perfil, usuarios y pruebas | `15`, `16`, `17`, `17b` |

---

## 3. Transacción atómica (script 12)

`SP_RESERVAR_Y_PAGAR` registra la reserva y el pago como una sola unidad de trabajo. Reserva con
`SP_CREAR_RESERVA_SEGURA` (bloqueo de la habitación, ver sección 4). No hace `COMMIT` (lo decide
quien lo llama, igual que `PKG_TURISMO`).

```text
SAVEPOINT sp_rp_inicio
   sp_crear_reserva(...)          cabecera + línea + noches + PAGO_TOTAL
SAVEPOINT sp_rp_reserva_ok
   INSERT en PAGO
   validar que no se pague de más
   recalcular PAGO_TOTAL; si queda pagado -> reserva CONFIRMADA
```

El modo lo da `p_rollback_total`:

| Modo | Si falla el pago | Qué queda |
|---|---|---|
| `'S'` (por defecto) | `ROLLBACK TO sp_rp_inicio` y se relanza el error | Nada: ni reserva, ni línea, ni noches, ni pago |
| `'N'` | `ROLLBACK TO sp_rp_reserva_ok`, sin relanzar | La reserva en `PENDIENTE` (aparta la habitación mientras el cliente reintenta) |

El pago se **inserta primero y se valida después**, a propósito: así, cuando la validación
falla, hay una fila ya escrita que el rollback parcial deshace de verdad. Códigos propios:
`-20030` método de pago inexistente, `-20031` el pago excede lo que se debe, `-20032` monto
inválido.

Resultado de la ejecución (`e3_12_transaccion.log`):

| Escenario | Qué prueba | Resultado |
|---|---|---|
| D1 | Pago por el total exacto | `OK`: reserva `CONFIRMADA`, `PAGO_TOTAL` `PAGADO`, 1 pago |
| D2 | Pago del doble, modo `'N'` | `OK`: la traza muestra `pagos visibles = 1` y después del rollback parcial `pagos = 0`; la reserva sigue `PENDIENTE` |
| D3 | Método de pago inexistente, modo `'S'` | `OK`: error `-20030` y no queda ninguna línea nueva |

---

## 4. Concurrencia (scripts 13)

### 4.1 El problema

`SP_CREAR_RESERVA` (Entrega 2) comprueba la disponibilidad y después inserta. Oracle solo
muestra a una sesión lo que otras ya **confirmaron**. Si A y B comprueban al mismo tiempo,
ninguna ve la reserva sin confirmar de la otra, las dos concluyen "libre" y las dos insertan.
`TRG_RH_NO_SOLAPE` no lo evita: también lee solo lo confirmado. Es la anomalía de
*comprobar y luego actuar* sin serializar.

### 4.2 La solución

`SP_CREAR_RESERVA_SEGURA` (creado en el script 12) ejecuta `SELECT ... FROM habitacion WHERE id = :h FOR UPDATE WAIT n`
antes de llamar a `SP_CREAR_RESERVA`. El bloqueo de la fila de la habitación dura hasta el
`COMMIT` o `ROLLBACK`. Dos sesiones que reserven **la misma** habitación se serializan;
habitaciones distintas no se estorban. Cuando la primera confirma, la segunda obtiene el
bloqueo, vuelve a leer, **ahora sí ve la reserva confirmada** y se rechaza con `-20005`. Si
la espera supera `p_espera_seg` (60 s por defecto) responde `-20040`.

### 4.3 Procedimiento del experimento

Preparar una vez `13_concurrencia_preparacion.sql` (requiere el script 12). Abrir tres ventanas de SQL*Plus
conectadas como el dueño: **A** (`13a_sesion_A.sql`), **B** (`13b_sesion_B.sql`) y el
observador (`13c_monitor_bloqueos.sql`, se ejecuta cuando B está esperando). Los scripts
avisan con `PAUSE` cuándo pasar a la otra ventana.

| Paso | Sesión | Acción | Resultado esperado |
|---|---|---|---|
| A1 | A | `sp_crear_reserva` de `ZZ-CONC`, 10–13 dic 2026, sin `COMMIT` | Reserva creada |
| B1 | B | `sp_crear_reserva` de la **misma** habitación y fechas | Se crea también: **no hay bloqueo ni error** |
| A2 / B2 | A, B | `COMMIT` en cada una | |
| — | A | Consulta de resultado | **Doble reserva**: 2 reservas activas, 2 por noche |
| A3 | A | `sp_crear_reserva_segura` (sin `COMMIT`) | Reserva creada, A retiene el bloqueo |
| B3 | B | `sp_crear_reserva_segura` | **B queda esperando** |
| — | 3.ª ventana | `13c_monitor_bloqueos.sql` | B en `enq: TX - row lock contention`, `bloqueada_por` = SID de A |
| A4 | A | `COMMIT` | B se libera y recibe `ORA-20005` |
| — | A | Consulta de resultado | **1 reserva**, 1 por noche |

Resultado obtenido (`e3_13a_sesionA.log`, `e3_13b_sesionB.log`, `e3_13c_monitor.log`):

| | Antes (`sp_crear_reserva`) | Después (`sp_crear_reserva_segura`) |
|---|---|---|
| Bloqueo entre sesiones | Ninguno | B espera a A (≈ 9 s en la ejecución registrada) |
| Reservas activas de la misma habitación y fechas | **2** (doble reserva) | **1** |
| Resultado para B | Reserva creada (error de negocio no detectado) | `ORA-20005` habitación no disponible |
| Evento de espera en `V$SESSION` | — | `enq: TX - row lock contention` |

**Capturas para el documento (Word/PDF):** (1) salida de A tras A1 y de B tras B1; (2) tabla
"DOBLE RESERVA" de la fase antes; (3) `13c_monitor_bloqueos.sql` con B bloqueada; (4) mensaje
`ORA-20005` en B y tabla final de la fase después. Al terminar, `13e_limpieza_total.sql`
deja la base como estaba.

---

## 5. Índices (script 14)

Las tres consultas salen de operaciones reales de la plataforma y se midieron con
**lecturas lógicas** (`session logical reads`, repetibles) y el tiempo promedio de 20
ejecuciones. Antes de medir se recolectan estadísticas. Los parámetros se toman de los datos
(alojamiento y habitación con más reservas, un apellido poco frecuente): no hay ids fijos.
`EXPLAIN PLAN` de cada consulta antes y después sale en `e3_14_indices.log`.

| Consulta | Índice | Antes | Después | Mejora |
|---|---|---|---|---|
| **C1** reservas de un alojamiento en una semana (agenda del encargado) | **Compuesto** `(id_alojamiento, fecha_check_in)` | 206 lecturas · `TABLE ACCESS FULL` + `SORT ORDER BY` | 44 lecturas · `INDEX RANGE SCAN`, sin `SORT` | 4,7 veces |
| **C2** cliente por `UPPER(apellidos)` (recepción) | **Basado en función** `UPPER(apellidos)` | 46 lecturas · `TABLE ACCESS FULL` | 20 lecturas · `INDEX RANGE SCAN` | 2,3 veces |
| **C3** disponibilidad de una habitación (el `SELECT` de `FN_HABITACION_DISPONIBLE` y `TRG_RH_NO_SOLAPE`) | **Compuesto** `(id_habitacion, fecha_check_in, fecha_check_out)` | 253 lecturas · `TABLE ACCESS FULL` de `RESERVA_HABITACION` | 8 lecturas · `INDEX RANGE SCAN` | 31,6 veces |

Por qué ese orden de columnas: la igualdad va primero y el rango después, de modo que el
rango recorre un tramo contiguo del índice. En C1 además las filas ya salen ordenadas por
fecha y desaparece el `SORT`. C3 es la consulta más importante porque se ejecuta en **cada**
reserva nueva. C2 mejora poco en términos absolutos porque `CLIENTE` es pequeña (3.000
filas); el índice basado en función es indispensable por otra razón: un índice normal sobre
`apellidos` **no** sirve para `WHERE UPPER(apellidos) = ...`, porque guarda el valor original
y no el resultado de `UPPER`.

### 5.1 El caso donde el índice no ayuda (C4)

`RESERVA.ID_ESTADO_RESERVA` tiene 4 valores y el estado *completada* concentra el **76 %** de
las filas (19.370 de 25.500).

| Variante | Plan | Lecturas lógicas | Tiempo |
|---|---|---|---|
| C4 sin índice | `TABLE ACCESS FULL` | 19.456 | ≈ 171 ms |
| C4 con el índice creado (el optimizador decide) | **`TABLE ACCESS FULL`**: descarta el índice | 19.456 | ≈ 165 ms |
| C4b forzando `INDEX(r idx_reserva_estado)` | `INDEX RANGE SCAN` + acceso por `ROWID` | **38.741** | ≈ 181 ms |

Explicación: para leer una fila por el índice Oracle debe recorrer el índice **y además** ir
a la tabla una vez por fila (lecturas de bloque al azar). Cuando la consulta necesita casi
toda la tabla, leerla de corrido (lecturas multibloque) cuesta menos; por eso el
optimizador elige el recorrido completo, y al forzar el índice las lecturas **se duplican**.
Un índice B-tree ayuda cuando el predicado devuelve una fracción pequeña de la tabla (del
orden de 5 % o menos), no cuando devuelve la mayoría. Además cada índice extra ocupa
espacio y encarece `INSERT`, `UPDATE` y `DELETE`.

**Caso adicional (C5):** con el índice `UPPER(apellidos)` ya creado, la búsqueda
`WHERE apellidos = ...` (sin `UPPER`) sigue haciendo `TABLE ACCESS FULL`: un índice de
función solo se usa si la consulta contiene la misma expresión.

---

## 6. Seguridad (scripts 15, 16, 17, 17b)

### 6.1 Diseño

- **Mínimo privilegio:** cada rol recibe solo lo que su trabajo exige; ningún rol tiene
  privilegios de sistema salvo `CREATE SESSION`.
- **Nadie recibe privilegios sobre tablas.** El script 16 termina con una comprobación que debe
  devolver 0 filas (privilegios sobre tablas concedidos a los roles).
- **Seguridad por fila para los encargados:** `V_MI_ALOJAMIENTO` toma el usuario de la sesión
  (`SYS_CONTEXT('USERENV','SESSION_USER')`) y lo busca en `USUARIO_SISTEMA` de la Entrega 1. El
  usuario de Oracle es el `username` con el punto cambiado por guion bajo (`enc.ospina` →
  `ENC_OSPINA`). Un encargado inactivo (`activo = 'N'`) no ve nada.

### 6.2 Matriz de privilegios

| Rol | Privilegios | Qué puede hacer |
|---|---|---|
| `ROL_RECEPCION` | `SELECT` en `V_REC_CLIENTES`, `V_REC_HABITACIONES`, `V_REC_RESERVAS`; `EXECUTE` en `SP_RESERVAR_Y_PAGAR` | Consultar clientes, habitaciones y reservas **solo por vistas** (sin datos de pago) y registrar reserva + pago de forma atómica. **Cero acceso a tablas.** |
| `ROL_ADMIN_ALOJAMIENTO` | `SELECT` en `V_ADM_HABITACIONES`, `V_ADM_RESERVAS`, `V_ADM_RESENAS`, `V_ADM_TARIFAS`; `UPDATE (valor_noche)` en `V_ADM_TARIFAS` | Ver y ajustar las tarifas **solo de su alojamiento** |
| `ROL_GERENTE` | `SELECT` en `V_GER_OCUPACION`, `V_GER_INGRESOS`, `V_GER_CALIFICACIONES` | Indicadores agregados de toda la plataforma, solo lectura |
| `ROL_AUDITOR` | `SELECT` en `V_AUD_AUDITORIA_TARIFA`, `V_AUD_PAGOS`, `V_AUD_RESERVAS` | Lectura de la auditoría y de los movimientos de dinero; no puede modificar ni borrar nada |

Recepción ejecuta `SP_RESERVAR_Y_PAGAR` y no `PKG_TURISMO` completo: el paquete también
cancela, archiva y liquida, y eso no es trabajo de recepción.

### 6.3 Perfil `PERFIL_TURISMO`

| Límite | Valor | Efecto |
|---|---|---|
| `SESSIONS_PER_USER` | 2 | La tercera sesión simultánea falla con `ORA-02391` (verificado) |
| `CONNECT_TIME` | 480 min | Una sesión dura como máximo 8 horas |
| `IDLE_TIME` | 30 min | Se cierra tras 30 minutos sin actividad |
| `CPU_PER_CALL` | 6000 (60 s) | Corta una llamada fuera de control |
| `LOGICAL_READS_PER_CALL` | 5.000.000 | Evita un `SELECT` sin filtro sobre toda la base |
| `FAILED_LOGIN_ATTEMPTS` / `PASSWORD_LOCK_TIME` | 3 / 1 hora | 3 claves erróneas bloquean la cuenta (`ORA-28000`, verificado) |
| `PASSWORD_LIFE_TIME` / `GRACE_TIME` / `REUSE_TIME` | 90 / 7 / 180 días | Caducidad, aviso y no reutilización de claves |

### 6.4 Resultado de las pruebas

`17_pruebas_seguridad.sql` se conecta como cada usuario y comprueba que lo permitido
funciona y lo prohibido falla con el error esperado: **44 pruebas, 0 `FALLA`**
(`e3_17_pruebas_seguridad.log`). Casos destacados:

- Recepción: `SELECT` sobre las tablas `reserva`, `cliente`, `pago`, `tarifa` y
  `auditoria_tarifa` → `ORA-00942`; `INSERT`/`DELETE` sobre tablas → `ORA-00942`; la vista de
  clientes no admite `UPDATE`; `SP_RESERVAR_Y_PAGAR` se ejecuta (falla por lógica, `ORA-20006`).
- Encargado `ENC_OSPINA`: ve 5 de las 535 habitaciones (las suyas); actualiza una tarifa propia;
  una tarifa ajena afecta **0 filas**; no puede cambiar la habitación de una tarifa, ni
  insertar, ni borrar.
- `ENC_RESTREPO` ve 4 habitaciones, otro conjunto; `ENC_MARIN` (inactivo) ve 0.
- Gerente y auditor: acceso solo a sus vistas; el auditor no puede borrar la auditoría.

> En Oracle 23ai/26ai una operación DML no concedida sobre un objeto visible puede salir como
> `ORA-41900` en lugar de `ORA-01031`; las pruebas aceptan ambos.

---

## 7. Re-ejecución y limpieza

- `11`, `12`, `14`, `15`, `16` son re-ejecutables. `14` borra y recrea sus índices y tablas
  auxiliares (`IDX_CONSULTA`, `IDX_RESULTADO`). `16` borra y recrea usuarios, roles y perfil.
- `12` no deja datos: hace `ROLLBACK` al final.
- `13_concurrencia_preparacion.sql` recrea la habitación de prueba; `13e_limpieza_total.sql`
  la elimina junto con sus reservas, tarifas y filas de auditoría. Las dos fases del
  experimento usan `13d_limpieza_reservas_prueba.sql` entre una y otra.
- Para quitar los usuarios, roles y perfil: volver a ejecutar `16` y borrarlos, o
  `DROP USER ... CASCADE`, `DROP ROLE ...`, `DROP PROFILE perfil_turismo CASCADE`.

---

## 8. Limitaciones conocidas

1. `SP_RESERVAR_Y_PAGAR` registra **un** pago. Un abono parcial es válido (queda `ABONADO` y la
   reserva `PENDIENTE`), pero los pagos posteriores se registrarían por otro procedimiento que
   esta entrega no incluye.
2. El bloqueo de `SP_CREAR_RESERVA_SEGURA` lo toma quien use ese procedimiento
   (`SP_RESERVAR_Y_PAGAR`, y por tanto recepción, sí lo usa). Quien llame directamente a
   `PKG_TURISMO.SP_CREAR_RESERVA` o inserte en `RESERVA_HABITACION` a mano no pasa por el
   bloqueo; por eso a recepción solo se le concede `EXECUTE` sobre `SP_RESERVAR_Y_PAGAR`.
3. Las mejoras de C1 y C2 son moderadas porque las tablas tienen decenas de miles de filas;
   con el crecimiento real de la plataforma la diferencia aumenta.
4. La prueba de `SESSIONS_PER_USER` es manual (necesita tres ventanas); el procedimiento está en
   `17b_pruebas_perfil.sql`.
5. No se definió `PASSWORD_VERIFY_FUNCTION` para no complicar las claves de demostración; en
   producción conviene activarla.

---

## 9. Archivos de la entrega

```text
scripts/11_privilegios_entrega3.sql
scripts/12_transaccion_reserva_pago.sql
scripts/13_concurrencia_preparacion.sql
scripts/13a_sesion_A.sql
scripts/13b_sesion_B.sql
scripts/13c_monitor_bloqueos.sql
scripts/13d_limpieza_reservas_prueba.sql
scripts/13e_limpieza_total.sql
scripts/14_indices.sql
scripts/15_vistas_seguridad.sql
scripts/16_roles_usuarios_perfil.sql
scripts/17_pruebas_seguridad.sql
scripts/17b_pruebas_perfil.sql
evidencias/e3_*.log
README_Entrega3.md
```
