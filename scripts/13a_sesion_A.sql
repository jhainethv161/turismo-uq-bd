/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13a: CONCURRENCIA - SESION A
   ---------------------------------------------------------------------
   Abrir en la ventana 1, conectado como el dueño del esquema, despues de
   haber ejecutado 13_concurrencia_preparacion.sql.
   La sesion B (13b_sesion_B.sql) se ejecuta en OTRA ventana al mismo
   tiempo. Cada PAUSE indica cuando pasar a la otra ventana.

   FASE 1 - ANTES (sin bloqueo):  SP_CREAR_RESERVA de la Entrega 2
        A1  A reserva la habitacion de prueba (sin COMMIT)
        B1  B reserva la MISMA habitacion y fechas: tambien lo logra
        A2  A hace COMMIT
        B2  B hace COMMIT       -> DOBLE RESERVA

   FASE 2 - DESPUES (con SELECT ... FOR UPDATE):  SP_CREAR_RESERVA_SEGURA
        A3  A reserva y mantiene el bloqueo (sin COMMIT)
        B3  B intenta reservar: QUEDA ESPERANDO (bloqueo real)
        --  observador (13c) captura el bloqueo
        A4  A hace COMMIT       -> B se libera y es RECHAZADA (-20005)
   ===================================================================== */
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET VERIFY OFF
SET TIMING OFF
SET SQLBLANKLINES ON

COLUMN sesion          FORMAT 9999
COLUMN id_reserva      FORMAT 99999999
COLUMN estado          FORMAT A12
COLUMN numero          FORMAT A8

VARIABLE g_hab      NUMBER
VARIABLE g_cliente  NUMBER
VARIABLE g_res      NUMBER

BEGIN
  SELECT id INTO :g_hab FROM habitacion WHERE numero = 'ZZ-CONC';
  SELECT id INTO :g_cliente FROM cliente ORDER BY id FETCH FIRST 1 ROWS ONLY;
END;
/

PROMPT
PROMPT ===== SESION A =====
SELECT SYS_CONTEXT('USERENV', 'SID') AS sesion, USER AS usuario FROM dual;

-- Limpia posibles restos de una corrida anterior
@@13d_limpieza_reservas_prueba.sql

/* =====================================================================
   FASE 1 - ANTES: SP_CREAR_RESERVA sin bloqueo
   ===================================================================== */
PROMPT
PROMPT ##### FASE 1 - ANTES (sin bloqueo) #####
PROMPT
PROMPT === A1. Sesion A reserva la habitacion ZZ-CONC del 10 al 13 de diciembre de 2026 ===
BEGIN
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab, DATE '2026-12-10', DATE '2026-12-13', 2, :g_res);
  DBMS_OUTPUT.PUT_LINE('A1: reserva ' || :g_res || ' creada por A (SIN COMMIT todavia)');
END;
/
PROMPT
PAUSE >>> Ahora ejecute en la ventana de la SESION B el paso B1 y vuelva aqui. Luego ENTER para el paso A2...

PROMPT
PROMPT === A2. Sesion A confirma ===
COMMIT;
PROMPT A2: COMMIT hecho por A
PROMPT
PAUSE >>> Ahora haga el paso B2 (COMMIT de B) en la sesion B. Luego ENTER para ver el resultado...

PROMPT
PROMPT === Resultado de la fase ANTES: lineas ACTIVAS de la habitacion de prueba ===
SELECT rh.id_reserva, rh.fecha_check_in, rh.fecha_check_out,
       UPPER(TRIM(er.descripcion)) AS estado
FROM   reserva_habitacion rh
JOIN   estado_reserva er ON er.id = rh.id_estado_reserva
WHERE  rh.id_habitacion = :g_hab
ORDER  BY rh.id_reserva;

-- Misma habitacion, mismas noches, dos reservas activas = doble reserva
SELECT rn.fecha AS noche, COUNT(*) AS reservas_esa_noche,
       CASE WHEN COUNT(*) > 1 THEN '<< DOBLE RESERVA' END AS problema
FROM   reserva_noche rn
JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
WHERE  rh.id_habitacion = :g_hab
GROUP  BY rn.fecha
ORDER  BY rn.fecha;

PROMPT
PAUSE >>> Capture esta pantalla (evidencia de la fase ANTES). ENTER para limpiar y pasar a la fase DESPUES...

-- Se borran las reservas de la fase 1 para repetir el experimento limpio
@@13d_limpieza_reservas_prueba.sql

/* =====================================================================
   FASE 2 - DESPUES: SP_CREAR_RESERVA_SEGURA con FOR UPDATE
   ===================================================================== */
PROMPT
PROMPT ##### FASE 2 - DESPUES (SELECT ... FOR UPDATE) #####
PROMPT
PROMPT === A3. Sesion A reserva con bloqueo de la habitacion (sin COMMIT) ===
BEGIN
  sp_crear_reserva_segura(:g_cliente, :g_hab, DATE '2026-12-10', DATE '2026-12-13', 2, :g_res);
  DBMS_OUTPUT.PUT_LINE('A3: reserva ' || :g_res || ' creada por A. A RETIENE el bloqueo de la habitacion.');
END;
/
PROMPT
PROMPT >>> Ahora, en la sesion B, ejecute el paso B3: B quedara ESPERANDO.
PROMPT >>> En la ventana 3 ejecute 13c_monitor_bloqueos.sql y capture el bloqueo.
PAUSE >>> Cuando haya capturado el bloqueo, pulse ENTER para que A haga COMMIT (paso A4)...

PROMPT
PROMPT === A4. Sesion A confirma: se libera el bloqueo y B continua ===
COMMIT;
PROMPT A4: COMMIT hecho por A. Mire la ventana de la sesion B.
PROMPT
PAUSE >>> Cuando B haya terminado (B4), pulse ENTER para ver el resultado final...

PROMPT
PROMPT === Resultado de la fase DESPUES: lineas de la habitacion de prueba ===
SELECT rh.id_reserva, rh.fecha_check_in, rh.fecha_check_out,
       UPPER(TRIM(er.descripcion)) AS estado
FROM   reserva_habitacion rh
JOIN   estado_reserva er ON er.id = rh.id_estado_reserva
WHERE  rh.id_habitacion = :g_hab
ORDER  BY rh.id_reserva;

SELECT rn.fecha AS noche, COUNT(*) AS reservas_esa_noche
FROM   reserva_noche rn
JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
WHERE  rh.id_habitacion = :g_hab
GROUP  BY rn.fecha
ORDER  BY rn.fecha;

PROMPT
PROMPT Esperado: UNA sola reserva y 1 reserva por noche (sin doble reserva).
PROMPT Para dejar la base limpia ejecute 13e_limpieza_total.sql
