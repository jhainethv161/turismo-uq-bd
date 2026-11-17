# TurismoUQ · Entrega 3 · Índices: planes de ejecución antes y después

Bases de Datos II · Proyecto integrador. Oracle AI Database 26ai Free, PDB `FREEPDB1`,
esquema `TURISMOUQ`. Script: `scripts/14_indices.sql`. Evidencia completa (consulta, plan y
medición de cada caso): `evidencias/e3_14_indices.log`.

## 1. Método

- **Datos:** 25.500 reservas, 29.791 líneas de reserva y 3.000 clientes, con distribución
  asimétrica. Los parámetros se toman de los propios datos (el alojamiento y la habitación con
  más reservas, un apellido poco frecuente); no hay ids fijos.
- **Estadísticas:** `DBMS_STATS.GATHER_TABLE_STATS` antes de medir y después de crear los
  índices, para que el optimizador decida con información real.
- **Plan:** `EXPLAIN PLAN` + `DBMS_XPLAN.DISPLAY`.
- **Medición:** *lecturas lógicas* (`session logical reads` de `V$MYSTAT`) de una ejecución, que
  es repetible y no depende de la caché del disco; y el tiempo promedio de 20 ejecuciones como
  apoyo. Las consultas se leen completas (todas las filas y columnas, con `DBMS_SQL`) como lo haría
  una aplicación.
- Antes de crear los índices de esta entrega solo existían los de las llaves primarias y
  `UNIQUE` de la Entrega 1 (Oracle **no** indexa las llaves foráneas por sí solo).

## 2. Resumen

| Consulta | Tipo de índice | Lecturas antes | Lecturas después | Mejora | Tiempo antes → después |
|---|---|---|---|---|---|
| **C1** Reservas de un alojamiento en una semana | **Compuesto** | 206 | 44 | 4,7 veces | 1,18 → 0,36 ms |
| **C2** Cliente por apellido sin distinguir mayúsculas | **Basado en función** | 46 | 20 | 2,3 veces | 0,71 → 0,14 ms |
| **C3** Disponibilidad de una habitación | **Compuesto** | 253 | 8 | 31,6 veces | 1,43 → 0,21 ms |
| **C4** Reservas «completadas» | Ninguno ayuda | 19.456 | 19.456 | 1 vez | 171 → 165 ms |
| **C4b** C4 forzando el índice | Forzado con `INDEX()` | — | 38.741 | **empeora 2 veces** | 181 ms |

## 3. Consultas lentas y planes

### C1 · Agenda semanal del encargado (índice compuesto)

```sql
SELECT r.id, r.fecha_check_in, r.fecha_check_out, r.id_cliente, r.id_estado_reserva
FROM   reserva r
WHERE  r.id_alojamiento = 35
AND    r.fecha_check_in BETWEEN DATE '2026-07-06' AND DATE '2026-07-12'
ORDER  BY r.fecha_check_in;
```

| | Antes | Después |
|---|---|---|
| Plan | `SORT ORDER BY` → `TABLE ACCESS FULL` de `RESERVA` | `TABLE ACCESS BY INDEX ROWID` ← `INDEX RANGE SCAN` `IDX_RESERVA_ALOJ_CHECKIN` |
| Costo (EXPLAIN) | 70 | 16 |
| Lecturas lógicas | 206 | 44 |
| Filas | 21 | 21 |

```sql
CREATE INDEX idx_reserva_aloj_checkin ON reserva (id_alojamiento, fecha_check_in);
```

**Por qué ese orden.** La igualdad (`id_alojamiento`) va primero y el rango
(`fecha_check_in`) después: el rango queda en un tramo **contiguo** del índice. Además las
filas salen ya ordenadas por fecha, así que **desaparece el `SORT ORDER BY`** del plan. Con el
orden inverso, el rango de fechas abarcaría todos los alojamientos y el índice sería mucho
menos útil.

### C2 · Búsqueda de cliente por apellido (índice basado en función)

```sql
SELECT c.id, c.nombres, c.apellidos, c.correo_electronico
FROM   cliente c
WHERE  UPPER(c.apellidos) = 'GIRALDO ARANGO';
```

| | Antes | Después |
|---|---|---|
| Plan | `TABLE ACCESS FULL` de `CLIENTE` | `TABLE ACCESS BY INDEX ROWID BATCHED` ← `INDEX RANGE SCAN` `IDX_CLIENTE_APELLIDO_UP` |
| Costo (EXPLAIN) | 11 | 5 |
| Lecturas lógicas | 46 | 20 |
| Filas | 9 | 9 |

```sql
CREATE INDEX idx_cliente_apellido_up ON cliente (UPPER(apellidos));
```

**Por qué una función.** Un índice normal sobre `apellidos` guarda el valor original, no el
resultado de `UPPER`, así que **no se puede usar** con `WHERE UPPER(apellidos) = ...`. El
índice basado en función guarda `UPPER(apellidos)` ya calculado. La mejora absoluta es
moderada porque `CLIENTE` solo tiene 3.000 filas; crece con la tabla.

### C3 · Disponibilidad de una habitación (índice compuesto, la consulta más crítica)

Es el `SELECT` de `PKG_TURISMO.FN_HABITACION_DISPONIBLE` y de `TRG_RH_NO_SOLAPE`: se ejecuta
en **cada** reserva nueva.

```sql
SELECT COUNT(*)
FROM   reserva_habitacion rh
JOIN   reserva r          ON r.id   = rh.id_reserva
JOIN   estado_reserva erh ON erh.id = r.id_estado_reserva
JOIN   estado_reserva erl ON erl.id = rh.id_estado_reserva
WHERE  rh.id_habitacion = 269
AND    UPPER(TRIM(erh.descripcion)) IN ('PENDIENTE', 'CONFIRMADA')
AND    UPPER(TRIM(erl.descripcion)) IN ('PENDIENTE', 'CONFIRMADA')
AND    rh.fecha_check_in  < DATE '2026-11-14'
AND    rh.fecha_check_out > DATE '2026-11-10';
```

| | Antes | Después |
|---|---|---|
| Acceso a `RESERVA_HABITACION` | `TABLE ACCESS FULL` (paso 11) | `INDEX RANGE SCAN` `IDX_RH_HAB_FECHAS` + `TABLE ACCESS BY INDEX ROWID BATCHED` (pasos 11–12) |
| Costo (EXPLAIN) | 73 | 8 |
| Lecturas lógicas | 253 | **8** |

```sql
CREATE INDEX idx_rh_hab_fechas
  ON reserva_habitacion (id_habitacion, fecha_check_in, fecha_check_out);
```

**Por qué.** Los tres predicados de solape (la habitación y las dos fechas) se resuelven dentro
del índice antes de tocar la tabla: de leer toda `RESERVA_HABITACION` se pasa a leer unos pocos
bloques. Es la mejora más importante porque acelera el camino crítico de la venta.

## 4. Caso donde el índice NO ayuda

### C4 · Reservas en estado «completada»

```sql
SELECT r.id, r.id_cliente, r.fecha_check_in, r.fecha_check_out
FROM   reserva r
WHERE  r.id_estado_reserva = 4;      -- completada
```

Distribución real de `RESERVA.ID_ESTADO_RESERVA`:

| Estado | Reservas | % |
|---|---|---|
| completada | 19.370 | **76,0** |
| cancelada | 3.726 | 14,6 |
| confirmada | 1.878 | 7,4 |
| pendiente | 526 | 2,1 |

Se creó `idx_reserva_estado ON reserva (id_estado_reserva)` y se midieron tres variantes:

| Variante | Plan | Lecturas lógicas | Tiempo |
|---|---|---|---|
| Sin el índice | `TABLE ACCESS FULL` (costo 69) | 19.456 | 171 ms |
| Con el índice creado, el optimizador decide | **`TABLE ACCESS FULL`** (descarta el índice) | 19.456 | 165 ms |
| Forzando `/*+ INDEX(r idx_reserva_estado) */` | `INDEX RANGE SCAN` + `TABLE ACCESS BY INDEX ROWID BATCHED` (costo **524**) | **38.741** | 181 ms |

### Explicación técnica

1. **Cómo se lee por índice.** Para devolver una fila, Oracle recorre el índice y **además va a
   la tabla una vez por fila** (acceso por `ROWID`, lecturas de bloque individuales y al azar).
2. **Cuando casi toda la tabla cumple el filtro** (76 %), esas visitas por `ROWID` se repiten
   para 19.370 filas y terminan tocando los mismos bloques una y otra vez. Leer la tabla **una
   sola vez, de corrido** (`TABLE ACCESS FULL`, lecturas multibloque) es más barato.
3. **Por eso el optimizador lo descarta solo** (el plan con el índice creado sigue siendo
   `TABLE ACCESS FULL`) y, al **forzarlo**, las lecturas lógicas **se duplican** (19.456 →
   38.741) y el costo estimado salta de 69 a 524.
4. **Regla práctica.** Un índice B-tree ayuda cuando el predicado devuelve una fracción pequeña
   de la tabla (del orden del 5 % o menos). La columna de estado tiene solo 4 valores distintos
   (baja cardinalidad) y el valor consultado es el mayoritario: es el peor caso. Para valores
   raros del mismo estado (por ejemplo, las 526 reservas `pendiente`, el 2 %), el índice sí
   podría ayudar.
5. **Costo de mantenerlo.** Cada índice ocupa espacio y hace más lentos los `INSERT`, `UPDATE` y
   `DELETE`; un índice que el optimizador no usa solo cuesta.

### Caso adicional · C5, índice de función que no se usa

Con `idx_cliente_apellido_up` ya creado, `WHERE c.apellidos = INITCAP('GIRALDO ARANGO')` (sin
`UPPER`) sigue haciendo `TABLE ACCESS FULL` (46 lecturas antes y después). Un índice de función
solo sirve si la consulta contiene **la misma expresión** con la que se creó.

## 5. Conclusiones

- Los índices **compuestos** deben ordenarse con la igualdad primero y el rango después; en C1
  eliminan además el `SORT`.
- El índice **basado en función** es obligatorio cuando el filtro aplica una función a la
  columna (`UPPER`).
- C3 muestra el mayor beneficio (31,6 veces) porque se ejecuta en cada reserva.
- La **selectividad** decide si un índice sirve: 76 % de las filas es demasiado para un índice.
- Los índices llevan costo de escritura y espacio: se crean para consultas concretas y medidas,
  no «por si acaso».

## 6. Cómo repetir

```text
@scripts/14_indices.sql
```

El script borra y recrea los índices y las tablas auxiliares (`IDX_CONSULTA`, `IDX_RESULTADO`),
imprime cada plan y medición, y termina con la tabla de resumen. Se puede repetir sin error.
Requiere los privilegios del script 11.
