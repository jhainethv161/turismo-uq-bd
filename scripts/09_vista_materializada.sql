/* =====================================================================
   TurismoUQ - Entrega 2
   Script 09: vista materializada de ocupacion mensual
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA.
   Requiere: Entrega 1 (con RESERVA_NOCHE cargada) y script 05
   (privilegios CREATE MATERIALIZED VIEW y CREATE JOB).

   QUE PRECALCULA
   --------------
   Una fila por ALOJAMIENTO y MES con:
     noches_disponibles = habitaciones del alojamiento x dias del mes
     noches_ocupadas    = noches vendidas en ese mes (RESERVA_NOCHE)
     pct_ocupacion      = noches_ocupadas / noches_disponibles x 100
   e incluye municipio y tipo para poder agrupar sin mas JOIN:
     SELECT municipio, mes, SUM(noches_ocupadas)/SUM(noches_disponibles)
     FROM mv_ocupacion_mensual GROUP BY municipio, mes;

   Decisiones del calculo
   - Se cuenta por NOCHE (RESERVA_NOCHE), no por reserva: una estadia
     del 30 de enero al 3 de febrero aporta 2 noches a enero y 2 a
     febrero. Contar reservas por fecha de check-in daria una ocupacion
     falsa en los cambios de mes.
   - Solo cuentan las noches de reservas cuya CABECERA esta CONFIRMADA
     o COMPLETADA y cuya LINEA no esta CANCELADA. Es el mismo criterio
     de las consultas de la Entrega 1: una cabecera cancelada no ocupa
     aunque alguna linea haya quedado mal marcada, y una habitacion
     cancelada dentro de un grupo activo tampoco ocupa.
   - Se usa CROSS JOIN alojamiento x meses + LEFT JOIN: un alojamiento
     sin ventas en un mes aparece con 0 % (no desaparece del reporte).
     Los meses son los que tienen alguna noche en la plataforma.

   POLITICA DE REFRESCO:  REFRESH COMPLETE ON DEMAND
                          + job diario a las 2:00 a.m.
   ---------------------------------------------------------------
   Por que NO "FAST ON COMMIT":
   - Exigiria MATERIALIZED VIEW LOGs en RESERVA_NOCHE,
     RESERVA_HABITACION, RESERVA, HABITACION, ALOJAMIENTO, etc., y
     esta consulta (CROSS JOIN, LEFT JOIN, COUNT DISTINCT, subconsultas)
     no cumple las restricciones del refresco rapido.
   - ON COMMIT recalcula dentro de la transaccion de CADA reserva: el
     camino mas critico del sistema (vender) se volveria mas lento y
     generaria contencion, solo para alimentar un reporte.
   Por que COMPLETE + diario:
   - Es un reporte gerencial MENSUAL: un dato con corte a la
     madrugada de hoy es suficiente; nadie decide con la ocupacion
     del ultimo minuto.
   - El resultado es pequeño (alojamientos x meses: 60 x 37 = ~2.220
     filas): recalcularlo completo toma segundos.
   - A las 2:00 a.m. casi no hay transacciones, asi que no compite con
     la operacion.
   - Si se necesita al instante (ej. justo despues de un cierre de mes)
     se refresca a mano:
        EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
   ===================================================================== */

SET SERVEROUTPUT ON
SET SQLBLANKLINES ON

-- 0. Re-ejecucion: borrar la MV si existe (ORA-12003 = no existe)
BEGIN
  EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW mv_ocupacion_mensual';
  DBMS_OUTPUT.PUT_LINE('MV_OCUPACION_MENSUAL eliminada.');
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -12003 THEN RAISE; END IF;
END;
/

-- 1. Vista materializada
CREATE MATERIALIZED VIEW mv_ocupacion_mensual
  BUILD IMMEDIATE
  REFRESH COMPLETE ON DEMAND
AS
SELECT a.id                                       AS id_alojamiento,
       a.nombre_comercial                         AS alojamiento,
       ci.id                                      AS id_municipio,
       ci.nombre                                  AS municipio,
       ta.nombre                                  AS tipo_alojamiento,
       m.mes                                      AS mes,
       EXTRACT(YEAR  FROM m.mes)                  AS anio,
       EXTRACT(MONTH FROM m.mes)                  AS num_mes,
       hab.num_habitaciones                       AS num_habitaciones,
       hab.num_habitaciones * (ADD_MONTHS(m.mes, 1) - m.mes)
                                                  AS noches_disponibles,
       NVL(oc.noches_ocupadas, 0)                 AS noches_ocupadas,
       ROUND(100 * NVL(oc.noches_ocupadas, 0)
             / (hab.num_habitaciones * (ADD_MONTHS(m.mes, 1) - m.mes)), 2)
                                                  AS pct_ocupacion
FROM   alojamiento a
JOIN   ciudad ci            ON ci.id = a.id_ciudad
JOIN   tipo_alojamiento ta  ON ta.id = a.id_tipo_alojamiento
JOIN   (SELECT id_alojamiento, COUNT(*) AS num_habitaciones
        FROM   habitacion
        GROUP  BY id_alojamiento) hab
       ON hab.id_alojamiento = a.id
CROSS JOIN
       (SELECT DISTINCT TRUNC(fecha, 'MM') AS mes
        FROM   reserva_noche) m
LEFT JOIN
       (SELECT h.id_alojamiento,
               TRUNC(rn.fecha, 'MM') AS mes,
               COUNT(*)              AS noches_ocupadas
        FROM   reserva_noche rn
        JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
        JOIN   habitacion h          ON h.id  = rh.id_habitacion
        JOIN   reserva r             ON r.id  = rh.id_reserva
        JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
        JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
        WHERE  UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA')
        AND    UPPER(TRIM(erl.descripcion)) <> 'CANCELADA'
        GROUP  BY h.id_alojamiento, TRUNC(rn.fecha, 'MM')) oc
       ON  oc.id_alojamiento = a.id
       AND oc.mes            = m.mes;

COMMENT ON MATERIALIZED VIEW mv_ocupacion_mensual IS
  'Ocupacion mensual por alojamiento (noches ocupadas / noches disponibles). Refresco COMPLETE ON DEMAND, job diario 2:00 a.m.';

-- 2. Indice para las consultas tipicas (por municipio y mes)
CREATE INDEX ix_mv_ocup_municipio_mes ON mv_ocupacion_mensual (id_municipio, mes);

/* 3. Job de refresco diario (DBMS_SCHEDULER)
      Se borra primero si ya existia (ORA-27475 = el job no existe). */
BEGIN
  BEGIN
    DBMS_SCHEDULER.DROP_JOB(job_name => 'JOB_REFRESCO_MV_OCUPACION', force => TRUE);
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE <> -27475 THEN RAISE; END IF;
  END;

  DBMS_SCHEDULER.CREATE_JOB(
    job_name        => 'JOB_REFRESCO_MV_OCUPACION',
    job_type        => 'PLSQL_BLOCK',
    job_action      => 'BEGIN DBMS_MVIEW.REFRESH(''MV_OCUPACION_MENSUAL'', ''C''); END;',
    start_date      => TRUNC(SYSTIMESTAMP) + 1 + 2/24,
    repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0; BYSECOND=0',
    enabled         => TRUE,
    comments        => 'Refresco completo diario de MV_OCUPACION_MENSUAL a las 2:00 a.m.');

  DBMS_OUTPUT.PUT_LINE('Job JOB_REFRESCO_MV_OCUPACION creado.');
END;
/

-- 4. Verificacion
SELECT mview_name, refresh_mode, refresh_method, build_mode, last_refresh_date, staleness
FROM   user_mviews
WHERE  mview_name = 'MV_OCUPACION_MENSUAL';

SELECT job_name, enabled, state, repeat_interval, next_run_date
FROM   user_scheduler_jobs
WHERE  job_name = 'JOB_REFRESCO_MV_OCUPACION';

-- Ocupacion por municipio en el ultimo mes con datos (ejemplo de uso)
SELECT municipio,
       SUM(noches_ocupadas)    AS noches_ocupadas,
       SUM(noches_disponibles) AS noches_disponibles,
       ROUND(100 * SUM(noches_ocupadas) / SUM(noches_disponibles), 2) AS pct_ocupacion
FROM   mv_ocupacion_mensual
WHERE  mes = (SELECT MAX(mes) FROM mv_ocupacion_mensual WHERE noches_ocupadas > 0)
GROUP  BY municipio
ORDER  BY pct_ocupacion DESC;
