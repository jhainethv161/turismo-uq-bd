/* =====================================================================
   TurismoUQ - Entrega 3
   Script 14: INDICES - 3 consultas lentas, plan antes/despues y un caso
              donde el indice NO ayuda
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA, despues de 01 a 11.
   Requiere los privilegios del script 11.

   Como esta organizado
     0. Preparacion: tablas auxiliares, parametros reales y estadisticas
     1. Las consultas bajo prueba (guardadas en IDX_CONSULTA)
     2. Procedimiento IDX_MEDIR_CONSULTA: imprime el EXPLAIN PLAN y MIDE
        (lecturas logicas, tiempo y filas) y lo guarda en IDX_RESULTADO
     3. ANTES: se miden las consultas sin indices nuevos
     4. Creacion de los indices
     5. DESPUES: se miden de nuevo
     6. Caso donde el indice no ayuda (y por que)
     7. Resumen comparativo

   Como se mide
     Lecturas logicas ("session logical reads", de V$MYSTAT) es la medida
     principal: no depende de la carga del equipo ni de la cache del disco,
     asi que es repetible. El tiempo se muestra como apoyo (promedio de
     20 ejecuciones). EXPLAIN PLAN muestra el plan elegido por el
     optimizador con las estadisticas del esquema.

   Las 3 consultas lentas (salen de la operacion real de la plataforma)
     C1  Reservas de un alojamiento en un rango de fechas
         (agenda del encargado)                          -> indice COMPUESTO
     C2  Busqueda de clientes por apellido sin importar mayusculas
         (recepcion)                                     -> indice BASADO EN FUNCION
     C3  Disponibilidad de una habitacion en un rango
         (es el SELECT de PKG_TURISMO.FN_HABITACION_DISPONIBLE y del
          disparador TRG_RH_NO_SOLAPE: se ejecuta en CADA reserva)
                                                         -> indice COMPUESTO
   Caso donde el indice NO ayuda
     C4  Reservas en estado 'completada' (la mayoria de las filas):
         un indice sobre una columna de baja selectividad.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK OFF
SET SQLBLANKLINES ON
SET DEFINE ON

/* =====================================================================
   0. PREPARACION
   ===================================================================== */
-- 0.1 Indices de la Entrega 3 (si existian de una corrida anterior)
BEGIN
  FOR i IN (SELECT index_name FROM user_indexes
            WHERE  index_name IN ('IDX_RESERVA_ALOJ_CHECKIN', 'IDX_CLIENTE_APELLIDO_UP',
                                  'IDX_RH_HAB_FECHAS', 'IDX_RESERVA_ESTADO'))
  LOOP
    EXECUTE IMMEDIATE 'DROP INDEX ' || i.index_name;
  END LOOP;
  -- IDX_RESULTADO primero: tiene una FK hacia IDX_CONSULTA
  FOR t IN (SELECT table_name FROM user_tables
            WHERE  table_name IN ('IDX_RESULTADO', 'IDX_CONSULTA')
            ORDER  BY CASE table_name WHEN 'IDX_RESULTADO' THEN 1 ELSE 2 END)
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
  END LOOP;
END;
/

-- 0.2 Tablas auxiliares
CREATE TABLE idx_consulta (
  id           NUMBER         PRIMARY KEY,
  nombre       VARCHAR2(60)   NOT NULL,
  descripcion  VARCHAR2(300),
  sql_texto    VARCHAR2(4000) NOT NULL
);

CREATE TABLE idx_resultado (
  id_consulta       NUMBER        NOT NULL REFERENCES idx_consulta (id),
  fase              VARCHAR2(30)  NOT NULL,
  filas             NUMBER,
  lecturas_logicas  NUMBER,
  ms_promedio       NUMBER(10,3),
  CONSTRAINT pk_idx_resultado PRIMARY KEY (id_consulta, fase)
);

-- 0.3 Estadisticas actualizadas: el optimizador decide con ellas
BEGIN
  FOR t IN (SELECT column_value AS nombre
            FROM   TABLE(sys.odcivarchar2list('RESERVA', 'CLIENTE', 'RESERVA_HABITACION',
                                              'ESTADO_RESERVA', 'RESERVA_NOCHE')))
  LOOP
    DBMS_STATS.GATHER_TABLE_STATS(USER, t.nombre, cascade => TRUE);
  END LOOP;
END;
/

-- 0.4 Parametros REALES tomados de los datos (no hay ids fijos).
--     Los datos son asimetricos: se usa el alojamiento y la habitacion con
--     mas reservas, que es el caso exigente, y un apellido poco frecuente.
COLUMN v_aloj  NEW_VALUE v_aloj  NOPRINT
COLUMN v_hab   NEW_VALUE v_hab   NOPRINT
COLUMN v_apel  NEW_VALUE v_apel  NOPRINT
COLUMN v_est   NEW_VALUE v_est   NOPRINT

SELECT id_alojamiento AS v_aloj
FROM  (SELECT id_alojamiento, COUNT(*) n FROM reserva GROUP BY id_alojamiento ORDER BY n DESC)
FETCH FIRST 1 ROWS ONLY;

SELECT id_habitacion AS v_hab
FROM  (SELECT id_habitacion, COUNT(*) n FROM reserva_habitacion GROUP BY id_habitacion ORDER BY n DESC)
FETCH FIRST 1 ROWS ONLY;

SELECT apellido AS v_apel
FROM  (SELECT UPPER(apellidos) AS apellido, COUNT(*) n
       FROM   cliente GROUP BY UPPER(apellidos)
       HAVING COUNT(*) BETWEEN 3 AND 15
              AND REGEXP_LIKE(UPPER(apellidos), '^[A-Z]+( [A-Z]+)*$')   -- solo letras ASCII: evita problemas de juego de caracteres del cliente
       ORDER  BY n DESC, apellido)
FETCH FIRST 1 ROWS ONLY;

SELECT er.id AS v_est
FROM   estado_reserva er
WHERE  UPPER(TRIM(er.descripcion)) = 'COMPLETADA';

SET FEEDBACK ON
PROMPT
PROMPT === Parametros de la prueba ===
PROMPT Alojamiento con mas reservas : &v_aloj
PROMPT Habitacion con mas lineas    : &v_hab
PROMPT Apellido                     : &v_apel
PROMPT Id del estado "completada"   : &v_est
SELECT (SELECT COUNT(*) FROM reserva)            AS reservas,
       (SELECT COUNT(*) FROM reserva_habitacion) AS lineas,
       (SELECT COUNT(*) FROM cliente)            AS clientes,
       (SELECT COUNT(*) FROM reserva WHERE id_estado_reserva = &v_est) AS reservas_completadas
FROM   dual;
SET FEEDBACK OFF

/* =====================================================================
   1. LAS CONSULTAS
   ===================================================================== */
INSERT INTO idx_consulta VALUES (1, 'C1 reservas de un alojamiento por fechas',
  'Agenda semanal del encargado: reservas de un alojamiento con check-in en una semana',
  q'[SELECT r.id, r.fecha_check_in, r.fecha_check_out, r.id_cliente, r.id_estado_reserva
FROM   reserva r
WHERE  r.id_alojamiento = &v_aloj
AND    r.fecha_check_in BETWEEN DATE '2026-07-06' AND DATE '2026-07-12'
ORDER  BY r.fecha_check_in]');

INSERT INTO idx_consulta VALUES (2, 'C2 cliente por apellido (UPPER)',
  'Recepcion busca un cliente por apellido sin distinguir mayusculas',
  q'[SELECT c.id, c.nombres, c.apellidos, c.correo_electronico
FROM   cliente c
WHERE  UPPER(c.apellidos) = '&v_apel']');

INSERT INTO idx_consulta VALUES (3, 'C3 disponibilidad de una habitacion',
  'El SELECT de fn_habitacion_disponible y trg_rh_no_solape (cada reserva lo ejecuta)',
  q'[SELECT COUNT(*)
FROM   reserva_habitacion rh
JOIN   reserva r          ON r.id   = rh.id_reserva
JOIN   estado_reserva erh ON erh.id = r.id_estado_reserva
JOIN   estado_reserva erl ON erl.id = rh.id_estado_reserva
WHERE  rh.id_habitacion = &v_hab
AND    UPPER(TRIM(erh.descripcion)) IN ('PENDIENTE', 'CONFIRMADA')
AND    UPPER(TRIM(erl.descripcion)) IN ('PENDIENTE', 'CONFIRMADA')
AND    rh.fecha_check_in  < DATE '2026-11-14'
AND    rh.fecha_check_out > DATE '2026-11-10']');

INSERT INTO idx_consulta VALUES (4, 'C4 reservas completadas (baja selectividad)',
  'CASO DONDE EL INDICE NO AYUDA: la mayoria de las reservas esta completada',
  q'[SELECT r.id, r.id_cliente, r.fecha_check_in, r.fecha_check_out
FROM   reserva r
WHERE  r.id_estado_reserva = &v_est]');

INSERT INTO idx_consulta VALUES (5, 'C4b igual a C4 FORZANDO el indice',
  'Misma consulta con INDEX(): fuerza lo que el optimizador descarto',
  q'[SELECT /*+ INDEX(r idx_reserva_estado) */ r.id, r.id_cliente, r.fecha_check_in, r.fecha_check_out
FROM   reserva r
WHERE  r.id_estado_reserva = &v_est]');

INSERT INTO idx_consulta VALUES (6, 'C5 apellido SIN usar UPPER',
  'Otro caso: el indice basado en UPPER() no sirve si la consulta no usa UPPER()',
  q'[SELECT c.id, c.nombres, c.apellidos, c.correo_electronico
FROM   cliente c
WHERE  c.apellidos = INITCAP('&v_apel')]');
COMMIT;

/* =====================================================================
   2. PROCEDIMIENTO DE MEDICION
      - imprime el EXPLAIN PLAN de la consulta
      - la ejecuta 20 veces y mide tiempo promedio
      - mide las lecturas logicas de UNA ejecucion (la ultima)
      - guarda el resultado en IDX_RESULTADO
      Ejecuta la consulta recorriendo TODAS sus columnas con DBMS_SQL,
      como lo haria una aplicacion (si se envolviera en COUNT(*), el
      optimizador podria descartar columnas y contar solo con el indice,
      lo que falsearia la comparacion).
   ===================================================================== */
CREATE OR REPLACE PROCEDURE idx_medir_consulta (
  p_id_consulta IN NUMBER,
  p_fase        IN VARCHAR2,
  p_imprimir    IN VARCHAR2 DEFAULT 'S')
IS
  v_nombre   idx_consulta.nombre%TYPE;
  v_sql      idx_consulta.sql_texto%TYPE;
  v_filas    NUMBER;
  v_lect     NUMBER;
  v_t0       TIMESTAMP;
  v_ms       NUMBER;
  c_veces    CONSTANT PLS_INTEGER := 20;

  FUNCTION lecturas_logicas RETURN NUMBER IS
    v_n NUMBER;
  BEGIN
    SELECT s.value INTO v_n
    FROM   v$mystat s JOIN v$statname n ON n.statistic# = s.statistic#
    WHERE  n.name = 'session logical reads';
    RETURN v_n;
  END lecturas_logicas;

  -- Ejecuta la consulta, lee todas las filas y todas las columnas
  FUNCTION ejecutar (p_texto IN VARCHAR2) RETURN NUMBER IS
    v_cur   INTEGER := DBMS_SQL.OPEN_CURSOR;
    v_cols  INTEGER;
    v_desc  DBMS_SQL.DESC_TAB;
    v_val   VARCHAR2(4000);
    v_n     NUMBER := 0;
    v_dummy INTEGER;
  BEGIN
    DBMS_SQL.PARSE(v_cur, p_texto, DBMS_SQL.NATIVE);
    DBMS_SQL.DESCRIBE_COLUMNS(v_cur, v_cols, v_desc);
    FOR i IN 1 .. v_cols LOOP
      DBMS_SQL.DEFINE_COLUMN(v_cur, i, v_val, 4000);
    END LOOP;
    v_dummy := DBMS_SQL.EXECUTE(v_cur);
    WHILE DBMS_SQL.FETCH_ROWS(v_cur) > 0 LOOP
      FOR i IN 1 .. v_cols LOOP
        DBMS_SQL.COLUMN_VALUE(v_cur, i, v_val);
      END LOOP;
      v_n := v_n + 1;
    END LOOP;
    DBMS_SQL.CLOSE_CURSOR(v_cur);
    RETURN v_n;
  END ejecutar;
BEGIN
  SELECT nombre, sql_texto INTO v_nombre, v_sql FROM idx_consulta WHERE id = p_id_consulta;

  IF p_imprimir = 'S' THEN
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '--- ' || v_nombre || '  [' || p_fase || '] ---');
    DBMS_OUTPUT.PUT_LINE(v_sql);
    DBMS_OUTPUT.PUT_LINE('');
    EXECUTE IMMEDIATE 'EXPLAIN PLAN SET STATEMENT_ID = ''IDX' || p_id_consulta ||
                      ''' FOR ' || v_sql;
    FOR l IN (SELECT plan_table_output
              FROM   TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'IDX' || p_id_consulta, 'BASIC +COST +ROWS')))
    LOOP
      DBMS_OUTPUT.PUT_LINE(l.plan_table_output);
    END LOOP;
  END IF;

  v_filas := ejecutar(v_sql);                    -- calienta cache y parseo

  v_t0 := SYSTIMESTAMP;
  FOR i IN 1 .. c_veces LOOP
    v_filas := ejecutar(v_sql);
  END LOOP;
  v_ms := ( EXTRACT(MINUTE FROM (SYSTIMESTAMP - v_t0)) * 60000
          + EXTRACT(SECOND FROM (SYSTIMESTAMP - v_t0)) * 1000 ) / c_veces;

  v_lect  := lecturas_logicas;                   -- lecturas de UNA ejecucion
  v_filas := ejecutar(v_sql);
  v_lect  := lecturas_logicas - v_lect;

  MERGE INTO idx_resultado r
  USING (SELECT p_id_consulta AS id_consulta, p_fase AS fase FROM dual) s
  ON    (r.id_consulta = s.id_consulta AND r.fase = s.fase)
  WHEN MATCHED THEN UPDATE SET filas = v_filas, lecturas_logicas = v_lect, ms_promedio = v_ms
  WHEN NOT MATCHED THEN INSERT (id_consulta, fase, filas, lecturas_logicas, ms_promedio)
                        VALUES (s.id_consulta, s.fase, v_filas, v_lect, v_ms);
  COMMIT;

  IF p_imprimir = 'S' THEN
    DBMS_OUTPUT.PUT_LINE('>> MEDICION [' || p_fase || ']: filas=' || v_filas ||
                         '  lecturas logicas=' || v_lect ||
                         '  tiempo promedio=' || TO_CHAR(v_ms, 'FM990.000') || ' ms');
  END IF;
END idx_medir_consulta;
/
SHOW ERRORS PROCEDURE idx_medir_consulta

/* =====================================================================
   3. ANTES: sin los indices de la Entrega 3
      (solo existen los de las PK y UNIQUE de la Entrega 1)
   ===================================================================== */
PROMPT
PROMPT #####################################################################
PROMPT ##  3. ANTES de crear los indices
PROMPT #####################################################################
BEGIN
  idx_medir_consulta(1, 'ANTES');
  idx_medir_consulta(2, 'ANTES');
  idx_medir_consulta(3, 'ANTES');
  idx_medir_consulta(4, 'ANTES');
  idx_medir_consulta(6, 'ANTES');
END;
/

/* =====================================================================
   4. CREACION DE LOS INDICES
   ===================================================================== */
-- C1: COMPUESTO (id_alojamiento, fecha_check_in)
--   Igualdad primero (id_alojamiento), rango despues (fecha_check_in).
--   Ese orden permite recorrer UN tramo contiguo del indice; ademas las
--   filas salen ya ordenadas por fecha, asi que desaparece el SORT del
--   ORDER BY. (Tambien indexa la FK RESERVA.ID_ALOJAMIENTO, que Oracle
--   no indexa automaticamente.)
CREATE INDEX idx_reserva_aloj_checkin
  ON reserva (id_alojamiento, fecha_check_in);

-- C2: BASADO EN FUNCION UPPER(apellidos)
--   Un indice normal sobre APELLIDOS no sirve para WHERE UPPER(apellidos) = ...
--   porque el indice guarda el valor original, no el resultado de UPPER.
--   El indice de funcion guarda UPPER(apellidos) ya calculado.
CREATE INDEX idx_cliente_apellido_up
  ON cliente (UPPER(apellidos));

-- C3: COMPUESTO (id_habitacion, fecha_check_in, fecha_check_out)
--   Los tres predicados de solape (habitacion, check_in, check_out) se
--   resuelven dentro del indice, antes de tocar la tabla. Acelera cada
--   reserva nueva (fn_habitacion_disponible y trg_rh_no_solape).
--   (Tambien indexa la FK RESERVA_HABITACION.ID_HABITACION.)
CREATE INDEX idx_rh_hab_fechas
  ON reserva_habitacion (id_habitacion, fecha_check_in, fecha_check_out);

-- C4: indice sobre una columna de BAJA SELECTIVIDAD (solo 4 valores
--   distintos). Se crea para demostrar que NO ayuda (seccion 6).
CREATE INDEX idx_reserva_estado
  ON reserva (id_estado_reserva);

BEGIN
  FOR t IN (SELECT column_value AS nombre
            FROM   TABLE(sys.odcivarchar2list('RESERVA', 'CLIENTE', 'RESERVA_HABITACION')))
  LOOP
    DBMS_STATS.GATHER_TABLE_STATS(USER, t.nombre, cascade => TRUE);
  END LOOP;
END;
/

PROMPT
PROMPT === Indices creados ===
SELECT index_name, table_name, uniqueness, status
FROM   user_indexes
WHERE  index_name IN ('IDX_RESERVA_ALOJ_CHECKIN', 'IDX_CLIENTE_APELLIDO_UP',
                      'IDX_RH_HAB_FECHAS', 'IDX_RESERVA_ESTADO')
ORDER  BY index_name;

/* =====================================================================
   5. DESPUES: con los indices
   ===================================================================== */
PROMPT
PROMPT #####################################################################
PROMPT ##  5. DESPUES de crear los indices
PROMPT #####################################################################
BEGIN
  idx_medir_consulta(1, 'DESPUES');
  idx_medir_consulta(2, 'DESPUES');
  idx_medir_consulta(3, 'DESPUES');
END;
/

/* =====================================================================
   6. CASO DONDE EL INDICE NO AYUDA
   ===================================================================== */
PROMPT
PROMPT #####################################################################
PROMPT ##  6. CASO DONDE EL INDICE NO AYUDA
PROMPT #####################################################################
PROMPT
PROMPT -- Distribucion de RESERVA.ID_ESTADO_RESERVA: por que el indice no sirve
SELECT er.descripcion AS estado,
       COUNT(*) AS reservas,
       ROUND(100 * RATIO_TO_REPORT(COUNT(*)) OVER (), 1) AS porcentaje
FROM   reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva
GROUP  BY er.descripcion
ORDER  BY reservas DESC;

BEGIN
  -- C4 con el indice ya creado: el optimizador decide solo
  idx_medir_consulta(4, 'DESPUES');
  -- C4b: se le OBLIGA a usar el indice
  idx_medir_consulta(5, 'DESPUES');
  -- C5: indice de UPPER() existente, pero la consulta no usa UPPER()
  idx_medir_consulta(6, 'DESPUES');
END;
/

/* =====================================================================
   7. RESUMEN COMPARATIVO
   ===================================================================== */
PROMPT
PROMPT #####################################################################
PROMPT ##  7. RESUMEN (lecturas logicas: menos es mejor)
PROMPT #####################################################################
COLUMN consulta  FORMAT A46
COLUMN antes     FORMAT 999G999
COLUMN despues   FORMAT 999G999
COLUMN mejora    FORMAT A12
COLUMN ms_antes  FORMAT 990D000
COLUMN ms_desp   FORMAT 990D000
SELECT c.nombre AS consulta,
       a.lecturas_logicas AS antes,
       d.lecturas_logicas AS despues,
       CASE WHEN d.lecturas_logicas > 0 AND a.lecturas_logicas IS NOT NULL
            THEN TO_CHAR(ROUND(a.lecturas_logicas / d.lecturas_logicas, 1)) || ' veces'
       END AS mejora,
       a.ms_promedio AS ms_antes,
       d.ms_promedio AS ms_desp
FROM   idx_consulta c
LEFT   JOIN idx_resultado a ON a.id_consulta = c.id AND a.fase = 'ANTES'
JOIN   idx_resultado d ON d.id_consulta = c.id AND d.fase = 'DESPUES'
ORDER  BY c.id;

PROMPT
PROMPT Lectura del caso donde el indice NO ayuda (C4 / C4b):
PROMPT  * El estado "completada" agrupa la gran mayoria de las filas. Para leer
PROMPT    esas filas por el indice, Oracle debe recorrer el indice Y ADEMAS ir a la
PROMPT    tabla una vez por fila (acceso por ROWID, lecturas de bloque al azar).
PROMPT    Cuando la consulta necesita casi toda la tabla, leer la tabla de corrido
PROMPT    (TABLE ACCESS FULL, lecturas multibloque) cuesta menos: por eso el
PROMPT    optimizador ELIGE el recorrido completo y descarta el indice.
PROMPT  * Al forzarlo con INDEX() las lecturas logicas SUBEN, no bajan.
PROMPT  * Regla practica: un indice B-tree ayuda cuando el predicado devuelve una
PROMPT    fraccion pequena de la tabla (del orden de 5 % o menos), no cuando
PROMPT    devuelve la mayoria de las filas. Ademas cada indice extra cuesta espacio
PROMPT    y hace mas lentos los INSERT/UPDATE/DELETE.
PROMPT
PROMPT Lectura de C5 (UPPER no usado): el indice de funcion solo se usa si la
PROMPT consulta contiene la MISMA expresion UPPER(apellidos); sin ella, el
PROMPT optimizador no puede usarlo.

SET FEEDBACK ON
