# TurismoUQ · Entrega 2 · Capa PL/SQL

Documento de soporte de la Entrega 2 del proyecto integrador de Bases de Datos II.
Explica qué hace cada script, en qué orden se ejecuta, qué decisiones de negocio se
tomaron y cómo se comprobó su funcionamiento sobre una base Oracle real.

La Entrega 1 (scripts `01`, `02` y `03`) se ejecuta **antes** de todos los scripts de
esta entrega. La Entrega 2 no modifica el DDL ni la carga de la Entrega 1: agrega
objetos de programa, tablas de soporte, disparadores y una vista materializada.

---

## 1. Requisitos

- Oracle Database 21c o superior. La validación final se hizo en **Oracle AI Database
  26ai Free**, PDB `FREEPDB1`, esquema `TURISMOUQ`.
- SQL*Plus o SQL Developer, con salida de `DBMS_OUTPUT` habilitada.
- La Entrega 1 cargada en el mismo esquema (tablas `RESERVA`, `PAGO`, `TARIFA`,
  `TEMPORADA`, etc. con datos).
- Para el script `05`: conexión con privilegios de DBA (`SYSTEM` o `SYS`) a la PDB
  donde vive el esquema. Los demás scripts se ejecutan como dueño del esquema.

---

## 2. Orden de ejecución

| # | Script | Conectado como | Qué hace |
|---|--------|----------------|----------|
| 01 | `01_ddl_turismouq.sql` | dueño | DDL de la Entrega 1 |
| 02 | `02_carga_turismouq.sql` | dueño | Carga de datos de la Entrega 1 |
| 03 | `03_consultas_turismouq.sql` | dueño | Consultas de la Entrega 1 (evidencia) |
| 05 | `05_privilegios_y_tablespace.sql` | **DBA** (`SYSTEM`/`SYS`) en la PDB | Privilegios, tablespace `TS_TURISMOUQ_HIST` y cuota |
| 06 | `06_tablas_soporte.sql` | dueño | `AUDITORIA_TARIFA`, `LIQUIDACION_MENSUAL`, `RESERVA_HISTORICO` |
| 07 | `07_paquete_pkg_turismo.sql` | dueño | Paquete `PKG_TURISMO` (funciones, procedimientos y cursor) |
| 08 | `08_disparadores.sql` | dueño | Los 5 disparadores |
| 09 | `09_vista_materializada.sql` | dueño | `MV_OCUPACION_MENSUAL` y el job de refresco |
| 10 | `10_pruebas_entrega2.sql` | dueño | Evidencia: pruebas T1–T17 con salida `OK`/`FALLA` |

La numeración de la Entrega 2 empieza en `05` porque ese script agrupa en un solo paso
los privilegios y el tablespace; no hay un script `04` independiente.

**Regla importante:** el script `08` se ejecuta **después** de la carga de la Entrega 1.
Si los disparadores existieran antes de `02`, el `INSERT ... SELECT` masivo sobre
`RESERVA_HABITACION` fallaría con `ORA-04091` (tabla mutante).

### 2.1 Conexión

```text
sqlplus turismouq/TurismoUQ2026@localhost:1521/FREEPDB1
```

Si se entra como `SYS` a la CDB, primero hay que cambiar de contenedor:

```sql
ALTER SESSION SET CONTAINER = FREEPDB1;
```

### 2.2 Ejecución completa

```text
-- Entrega 1, como TURISMOUQ
@scripts/01_ddl_turismouq.sql
@scripts/02_carga_turismouq.sql
@scripts/03_consultas_turismouq.sql

-- Script 05, como SYSTEM/SYS en FREEPDB1
@scripts/05_privilegios_y_tablespace.sql

-- Entrega 2, como TURISMOUQ
@scripts/06_tablas_soporte.sql
@scripts/07_paquete_pkg_turismo.sql
@scripts/08_disparadores.sql
@scripts/09_vista_materializada.sql
@scripts/10_pruebas_entrega2.sql
```

---

## 3. Qué pide el enunciado y dónde está

| Entregable | Objeto | Script |
|---|---|---|
| Función de valor de estadía | `PKG_TURISMO.FN_VALOR_ESTADIA` | 07 |
| Procedimiento de creación de reserva con excepciones propias | `PKG_TURISMO.SP_CREAR_RESERVA` | 07 |
| Cursor explícito **con parámetros** para liquidación mensual | `C_LIQUIDACION(P_DESDE, P_HASTA)` dentro de `SP_LIQUIDACION_MENSUAL` | 07 |
| Todo lo anterior dentro de un paquete | `PKG_TURISMO` (especificación + cuerpo) | 07 |
| Disparador de **sentencia** para auditar `TARIFA` | `TRG_AUDITORIA_TARIFA` (`COMPOUND TRIGGER`) | 08 |
| Disparador de **fila** contra solapes | `TRG_RH_NO_SOLAPE` (`BEFORE INSERT FOR EACH ROW`) | 08 |
| Tablespace propio para el histórico, con justificación | `TS_TURISMOUQ_HIST` + `RESERVA_HISTORICO` | 05 y 06 |
| Vista materializada de ocupación mensual y política de refresco justificada | `MV_OCUPACION_MENSUAL` + `JOB_REFRESCO_MV_OCUPACION` | 09 |
| Evidencia de prueba de cada componente | Pruebas T1–T17 y logs | 10 y `evidencias/` |

Además de lo pedido, el paquete incluye `SP_AGREGAR_HABITACION`,
`SP_RECALCULAR_TOTAL`, `SP_CANCELAR_RESERVA` y `SP_ARCHIVAR_HISTORICO`, necesarios
para que el flujo de una reserva quede completo y coherente con la Entrega 1.

---

## 4. Estados reales y criterios de negocio

### 4.1 Catálogos de la Entrega 1

| Catálogo | Descripciones reales |
|---|---|
| `ESTADO_RESERVA` | `pendiente`, `confirmada`, `cancelada`, `completada` |
| `ESTADO_PAGO` | `exitoso`, `fallido`, `pendiente`, `reembolsado` |
| `ESTADO_PAGO_TOTAL` | `pendiente`, `abonado`, `pagado`, `reembolsado`, `cancelado` |

No existe `PARCIAL` en `ESTADO_PAGO_TOTAL`. Un pago incompleto queda en **`ABONADO`**;
por eso el paquete usa `c_ept_abonado` y no un estado inventado. Todas las
comparaciones se hacen con `UPPER(TRIM(...))` porque la carga escribe las
descripciones en minúsculas.

### 4.2 Tres criterios distintos, a propósito

| Concepto | Cabecera `RESERVA` | Línea `RESERVA_HABITACION` | Dónde se usa |
|---|---|---|---|
| **Ocupa la habitación** | `pendiente` o `confirmada` | `pendiente` o `confirmada` | `FN_HABITACION_DISPONIBLE`, `TRG_RH_NO_SOLAPE`, `SP_CREAR_RESERVA` |
| **Se liquida / ocupa en la MV** | `confirmada` o `completada` | distinta de `cancelada` | `SP_LIQUIDACION_MENSUAL`, `MV_OCUPACION_MENSUAL` |
| **Se archiva al histórico** | `completada` o `cancelada` | `completada` o `cancelada` | `SP_ARCHIVAR_HISTORICO` |

La diferencia es intencional:

- Una reserva **pendiente** aparta la habitación mientras el cliente paga, pero todavía
  no genera ingreso; por eso ocupa inventario y **no** se liquida.
- Una **cabecera cancelada** no debe ocupar ni liquidar aunque alguna línea haya
  quedado mal marcada. Los datos de la Entrega 1 traen 301 líneas `cancelada` con
  cabecera `completada` y 28 con cabecera `confirmada`; por eso el filtro de cabecera
  es obligatorio.
- Una **línea cancelada** dentro de una cabecera activa (un grupo que cancela una sola
  habitación) libera esa habitación y no se cobra, pero la reserva sigue activa.
- El histórico exige que **cabecera y línea** estén cerradas: una línea cancelada de
  un grupo activo todavía pertenece a la operación y no se archiva.

### 4.3 Reembolso y cancelación

- Si faltan **más de 5 días** para el check-in: se devuelve el **80 %** de lo pagado
  con éxito.
- Con **exactamente 5 días o menos**: se devuelve **0 %**.
- El reembolso se registra como una **fila nueva en `PAGO`** con estado `reembolsado` y
  monto positivo. No se modifica el pago original. Así lo modela la carga de la
  Entrega 1 y así lo suma su consulta 7.
- `PAGO_TOTAL` queda en `reembolsado` si hubo devolución y en `cancelado` si no la hubo.
  El `total` original **no se altera**: es el valor histórico de la reserva.
- `SP_RECALCULAR_TOTAL` rechaza reservas `cancelada` o `completada` con `-20009` para
  no reescribir valores ya cerrados.

---

## 5. Componentes

### 5.1 Script 05: privilegios y tablespace

Concede al esquema los privilegios que necesita la capa PL/SQL (`CREATE PROCEDURE`,
`CREATE TRIGGER`, `CREATE MATERIALIZED VIEW`, `CREATE JOB`, `CREATE TABLE`,
`CREATE VIEW`) y crea el tablespace propio del histórico.

Parámetros al inicio del script:

```sql
DEFINE esquema     = TURISMOUQ
DEFINE ts_datafile = "ts_turismouq_hist01.dbf"
```

`ts_datafile` es relativo a la carpeta de datafiles de la instalación. Así el script
funciona en otra máquina sin cambiar una ruta absoluta. Si se quiere un archivo en una
ruta concreta, se cambia esa línea. El bloque comprueba `DBA_TABLESPACES` antes de
crear, de modo que el script se puede volver a ejecutar sin error.

**Justificación del tablespace** (también está en el encabezado del script):

1. **Naturaleza distinta:** las reservas operativas se modifican todo el tiempo; el
   histórico solo crece y se lee para reportes. Separarlos evita que compitan por el
   mismo espacio y E/S.
2. **Crecimiento acotado:** el histórico puede crecer sin límite. Con `AUTOEXTEND ON
   NEXT 10M MAXSIZE 1G` no puede llenar el tablespace de las tablas operativas.
3. **Administración independiente:** al cerrar un año se puede poner `READ ONLY`, con
   lo que sale de los respaldos diarios y queda protegido.
4. **Ubicación física independiente:** el datafile puede estar en otro disco sin tocar
   la aplicación, porque la tabla solo conoce el nombre lógico del tablespace.

### 5.2 Script 06: tablas de soporte

| Tabla | Para qué | Detalle |
|---|---|---|
| `AUDITORIA_TARIFA` | Rastro de cambios de `TARIFA` | Guarda operación, valores anterior/nuevo, usuario BD, usuario SO, equipo y fecha. No tiene FK a `TARIFA`: la auditoría debe sobrevivir si la tarifa se borra. |
| `LIQUIDACION_MENSUAL` | Resultado del proceso masivo | Una fila por alojamiento y mes, con `UNIQUE (anio, mes, id_alojamiento)` para que el reproceso reemplace, no duplique. |
| `RESERVA_HISTORICO` | Histórico desnormalizado | Vive en `TS_TURISMOUQ_HIST`, incluido el índice de la PK. Guarda nombres y municipio para poder consultarse solo. |

### 5.3 Script 07: paquete `PKG_TURISMO`

**`FN_VALOR_ESTADIA(id_habitacion, fecha_in, fecha_out)`**

Recorre la estadía **noche por noche** (desde el check-in hasta el día anterior al
check-out) y suma la tarifa de la temporada vigente en cada noche. Así una estadía que
cruza dos temporadas cobra cada tramo con su precio. Las noches se guardan además en
`RESERVA_NOCHE` con el valor congelado: si la tarifa cambia después, la reserva conserva
el precio con que se vendió.

Errores controlados: `-20002` fechas inválidas, `-20003` habitación inexistente,
`-20010` noche sin temporada, `-20011` noche cubierta por dos temporadas y `-20012`
habitación sin tarifa en esa temporada.

**`SP_CREAR_RESERVA(...)`**

1. Valida fechas, cliente y habitación.
2. Inserta la cabecera `RESERVA` en estado `pendiente`.
3. Inserta la línea `RESERVA_HABITACION` y una fila de `RESERVA_NOCHE` por noche.
4. Crea/actualiza `PAGO_TOTAL` con el valor calculado.

Marca un `SAVEPOINT` al inicio. Si cualquier paso falla, hace `ROLLBACK TO SAVEPOINT` y
relanza el error: no queda una cabecera huérfana ni una reserva a medio crear. No hace
`COMMIT`; la transacción la cierra quien lo llama.

**`SP_AGREGAR_HABITACION(...)`**

Agrega otra habitación a una reserva existente (reserva de grupo). La línea puede tener
fechas propias, pero dentro del rango de la cabecera, y la habitación debe ser del mismo
alojamiento. La línea hereda el estado de la cabecera. También es atómico.

**`SP_RECALCULAR_TOTAL(...)`**

Deja `PAGO_TOTAL` coherente con las líneas no canceladas y los servicios:
`subtotal` = suma de `valor_estadia`; `total` = subtotal + servicios; estado `pagado`
si lo pagado cubre el total, `abonado` si hay pago parcial y `pendiente` si no hay pago.
Rechaza reservas cerradas (`cancelada`/`completada`) con `-20009`.

**`SP_CANCELAR_RESERVA(...)`**

Cancela cabecera y líneas activas, calcula el reembolso con la regla 80 %/0 %, registra
el reembolso en `PAGO` (estado `reembolsado`) y actualiza `PAGO_TOTAL` a `reembolsado`
o `cancelado`. Al quedar las líneas en `cancelada`, la habitación se libera.

**`SP_LIQUIDACION_MENSUAL(anio, mes)` — cursor explícito con parámetros**

```sql
CURSOR c_liquidacion (p_desde DATE, p_hasta DATE) IS
  SELECT ...
  FROM   alojamiento a
  LEFT JOIN (...) est ON ...
  LEFT JOIN (...) srv ON ...
  ORDER BY a.id;
```

El cursor recibe el primer día del mes y el primer día del mes siguiente. Devuelve una
fila por alojamiento, incluso los que no vendieron (LEFT JOIN). El proceso usa
`OPEN` / `FETCH` / `EXIT WHEN %NOTFOUND` / `CLOSE`, y guarda cada fila en
`LIQUIDACION_MENSUAL`.

- **Estadía:** noches de `RESERVA_NOCHE` dentro del mes, con cabecera
  `confirmada`/`completada` y línea no `cancelada`; se usa el `valor_noche` congelado.
- **Servicios:** reservas con check-in en el mes y cabecera `confirmada`/`completada`
  (el modelo de la Entrega 1 no tiene fecha propia para el servicio).
- **Reproceso:** borra la liquidación anterior del mismo mes y la reinserta dentro de un
  `SAVEPOINT`; si una fila falla, se restaura la liquidación anterior completa.

**`SP_ARCHIVAR_HISTORICO(fecha_corte, filas)`**

Copia a `RESERVA_HISTORICO` las líneas con cabecera y línea cerradas
(`completada`/`cancelada`) cuyo check-out es anterior al corte, y que aún no estaban
archivadas. Es idempotente: se puede ejecutar varias veces sin duplicar. **Copia, no
borra**, porque `PAGO`, `RESENA`, `RESERVA_NOCHE` y las consultas de la Entrega 1
dependen de las tablas operativas. La purga sería el paso siguiente, ya fuera de esta
entrega.

### 5.4 Script 08: disparadores

**`TRG_AUDITORIA_TARIFA` — disparador de sentencia**

Es un `COMPOUND TRIGGER`, la forma correcta de cumplir "disparador de sentencia" cuando
se necesitan `:OLD` y `:NEW`:

- `BEFORE STATEMENT`: limpia la colección y captura una sola vez quién y cuándo.
- `AFTER EACH ROW`: solo anota en memoria los valores anterior y nuevo.
- `AFTER STATEMENT`: escribe **todo el lote** en `AUDITORIA_TARIFA` con un `FORALL`.

Así un `UPDATE` de 400 tarifas genera 400 filas de auditoría con una sola escritura
masiva, no 400 escrituras individuales. Un `UPDATE` que deja el mismo valor no se
audita.

**`TRG_RH_NO_SOLAPE` — disparador de fila**

`BEFORE INSERT FOR EACH ROW` sobre `RESERVA_HABITACION`. Impide una línea cuya
habitación se cruza con otra línea activa. Solo valida si la cabecera y la línea nueva
están en `pendiente`/`confirmada`, y compara contra líneas cuya cabecera y línea también
estén activas. Fórmula de solape:

```text
existente.check_in < nuevo.check_out  AND  existente.check_out > nuevo.check_in
```

Con esa fórmula, salir el 26 y que otra persona entre el 26 **no** es solape (la noche
del 26 no se cobra dos veces).

Es la segunda barrera: aunque alguien inserte directamente en la tabla saltándose el
paquete, el solape se rechaza. Limitación conocida: cubre el `INSERT` de una fila con
`VALUES` (el camino del paquete); un `UPDATE` de fechas o un `INSERT ... SELECT`
masivo no pasan por este disparador y los controla `FN_HABITACION_DISPONIBLE` en el
paquete. Se documenta para la Entrega 3.

**Disparadores adicionales de coherencia**

- `TRG_RH_COHERENCIA`: la habitación debe ser del alojamiento de la reserva y las
  fechas de la línea deben estar dentro del rango de la cabecera.
- `TRG_RS_COHERENCIA`: el servicio debe ser del mismo alojamiento de la reserva.
- `TRG_RESENA_COMPLETADA`: solo se reseñan reservas `completada`.

### 5.5 Script 09: vista materializada

`MV_OCUPACION_MENSUAL` precalcula, por alojamiento y mes:

- `noches_disponibles` = habitaciones del alojamiento × días del mes.
- `noches_ocupadas` = noches vendidas en ese mes (`RESERVA_NOCHE`).
- `pct_ocupacion` = ocupadas / disponibles × 100.
- Municipio y tipo de alojamiento para agrupar sin más JOIN.

Se cuenta por **noche**, no por reserva: una estadía del 30 de enero al 3 de febrero
aporta 2 noches a enero y 2 a febrero. Solo cuentan las noches con cabecera
`confirmada`/`completada` y línea no `cancelada`. El `CROSS JOIN` alojamiento × meses
con `LEFT JOIN` hace que un alojamiento sin ventas aparezca con 0 %, no desaparezca.

**Política de refresco: `REFRESH COMPLETE ON DEMAND` + job diario a las 2:00 a.m.**

- **No `FAST ON COMMIT`:** exigiría *materialized view logs* en `RESERVA_NOCHE`,
  `RESERVA_HABITACION`, `RESERVA`, `HABITACION`, `ALOJAMIENTO`, etc., y la consulta
  (CROSS JOIN, LEFT JOIN, subconsultas) no cumple las restricciones del refresco
  rápido. Además, `ON COMMIT` recalcularía dentro de la transacción de **cada** reserva
  y haría más lento el camino crítico de venta.
- **Sí `COMPLETE` + diario:** es un reporte gerencial mensual; un dato con corte a la
  madrugada es suficiente. El resultado es pequeño (60 alojamientos × 37 meses ≈ 2.220
  filas), recalcularlo toma segundos y a las 2:00 a.m. no compite con la operación.
- Refresco manual cuando se necesite al instante:

```sql
EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
```

---

## 6. Pruebas y evidencia

El script `10_pruebas_entrega2.sql` busca los datos en la propia base (no usa ids
fijos), imprime `OK` o `FALLA` por prueba y hace `ROLLBACK` al final de las pruebas
transaccionales. La prueba de la vista materializada va después del `ROLLBACK` porque
`DBMS_MVIEW.REFRESH` hace `COMMIT` implícito.

| Prueba | Qué comprueba | Resultado de la ejecución limpia |
|---|---|---|
| T1 | `fn_valor_estadia` cruzando dos temporadas | `OK` (2.692.000) |
| T2 | Check-out igual al check-in | `OK` (`-20002`) |
| T3 | Noche sin temporada | `OK` (`-20010`) |
| T4 | `sp_crear_reserva` completa | `OK` (cabecera, línea, noches y total) |
| T5 | Check-out anterior al check-in | `OK` (`-20002`) |
| T6 | Capacidad excedida | `OK` (`-20004`) |
| T7 | Habitación no disponible | `OK` (`-20005`) |
| T8 | Disparador de fila ante inserción directa solapada | `OK` (`-20005`, `TRG_RH_NO_SOLAPE`) |
| T9 | Check-in el día del check-out de otra reserva | `OK` (se permite) |
| T10 | `sp_agregar_habitacion` en reserva de grupo | `OK` (suma de líneas = total) |
| T11 | Auditoría de `TARIFA` | `OK` (78/78 filas, precio congelado, INSERT/DELETE 1/1) |
| T12 | Pago parcial, reembolso y cancelación | `OK` (`abonado`, reembolso 80.000, `reembolsado`, doble cancelación y recálculo rechazados con `-20009`) |
| T13 | Reseñas | `OK` (rechaza reserva no completada, acepta completada) |
| T14 | Servicio de otro alojamiento | `OK` (`-20007`) |
| T15 | Liquidación mensual con cursor | `OK` (60 filas, 384.597.000, coincide con consulta directa, reproceso sin duplicar) |
| T16 | Archivado al histórico | `OK` (8.543 líneas, segunda ejecución 0, ninguna cabecera activa archivada) |
| T17 | Vista materializada | `OK` (MV = consulta directa, total del mes coincide, `FRESH`) |

Resultado global de la última ejecución desde base limpia:

```text
FALLA: 0
SP2-: 0
ORA- inesperados: 0
Pruebas T1–T17: OK
```

Los logs completos están en `evidencias/`:

| Archivo | Contenido |
|---|---|
| `clean_05.log` | Tablespace y cuota |
| `clean_06.log` | Tablas de soporte y tablespace del histórico |
| `clean_07.log` | Paquete `VALID` |
| `clean_08.log` | 5 disparadores `ENABLED`/`VALID` |
| `clean_09.log` | MV `FRESH` y job `SCHEDULED` |
| `clean_10.log` | Pruebas T1–T17 |

### 6.1 Comprobaciones manuales útiles

```sql
-- Objetos del paquete
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name = 'PKG_TURISMO';

-- Disparadores
SELECT trigger_name, status
FROM   user_triggers
WHERE  trigger_name LIKE 'TRG_%';

-- Vista materializada y job
SELECT mview_name, refresh_mode, refresh_method, staleness
FROM   user_mviews
WHERE  mview_name = 'MV_OCUPACION_MENSUAL';

SELECT job_name, enabled, state, next_run_date
FROM   user_scheduler_jobs
WHERE  job_name = 'JOB_REFRESCO_MV_OCUPACION';

-- Histórico en su tablespace
SELECT segment_name, segment_type, tablespace_name
FROM   user_segments
WHERE  segment_name IN ('RESERVA_HISTORICO', 'PK_RESERVA_HISTORICO');
```

---

## 7. Re-ejecución y limpieza

- `05` es idempotente: comprueba si el tablespace existe antes de crearlo.
- `06` **borra y recrea** las tres tablas de soporte. Si se vuelve a ejecutar, hay que
  volver a ejecutar `07`, `08` y `09`, porque el paquete, los disparadores y la MV
  dependen de ellas. También se pierde la liquidación y el histórico generados.
- `07`, `08` y `09` usan `CREATE OR REPLACE` o borran y recrean sus objetos: se pueden
  volver a ejecutar sin problema.
- `10` no deja datos de prueba: hace `ROLLBACK` antes de T17. El refresco de la MV de
  T17 solo actualiza la vista, no las tablas base.
- Para conservar una liquidación o un histórico reales, ejecutar el procedimiento y
  hacer `COMMIT` explícito; los procedimientos no hacen `COMMIT` por diseño.

---

## 8. Limitaciones conocidas y siguientes pasos

1. **`TRG_RH_NO_SOLAPE`** cubre el `INSERT` de una fila con `VALUES` (el camino del
   paquete). No cubre `UPDATE` de fechas ni `INSERT ... SELECT` masivo; esos casos los
   controla `FN_HABITACION_DISPONIBLE` en el paquete. Para la Entrega 3 se puede
   extender con un disparador compuesto o una restricción adicional.
2. **Histórico:** se copia, no se mueve. La purga de las tablas operativas queda para
   la Entrega 3, después de verificar el histórico.
3. **Servicios en la liquidación:** se asignan al mes del check-in porque el modelo de
   la Entrega 1 no tiene fecha propia del servicio.
4. **Meses sin ninguna noche:** la MV toma los meses que aparecen en `RESERVA_NOCHE`.
   Un mes sin ninguna noche en toda la plataforma no genera filas.
5. **Temporadas:** `fn_valor_estadia` exige que cada noche esté cubierta por una
   temporada y que la habitación tenga tarifa en ella. Si la carga tiene un hueco,
   falla con `-20010`/`-20012` en vez de inventar un precio.

---

## 9. Archivos de la entrega

```text
scripts/05_privilegios_y_tablespace.sql
scripts/06_tablas_soporte.sql
scripts/07_paquete_pkg_turismo.sql
scripts/08_disparadores.sql
scripts/09_vista_materializada.sql
scripts/10_pruebas_entrega2.sql
evidencias/clean_05.log ... clean_10.log
README_Entrega2.md
```
