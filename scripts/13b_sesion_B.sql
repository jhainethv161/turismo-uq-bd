/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13b: CONCURRENCIA - SESION B
   ---------------------------------------------------------------------
   Abrir en la ventana 2, conectado como el MISMO dueño del esquema (dos
   conexiones independientes = dos sesiones). Se ejecuta en paralelo con
   13a_sesion_A.sql: A avisa en cada PAUSE cuando le toca a B, y este
   script avisa cuando debe volver a A.

   Este script NO usa SET AUTOCOMMIT: cada transaccion termina solo con
   el COMMIT explicito de los pasos B2 y B4.
   ===================================================================== */
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET VERIFY OFF
SET TIMING ON
SET SQLBLANKLINES ON

COLUMN sesion FORMAT 9999

VARIABLE g_hab      NUMBER
VARIABLE g_cliente  NUMBER
VARIABLE g_res      NUMBER

BEGIN
  SELECT id INTO :g_hab FROM habitacion WHERE numero = 'ZZ-CONC';
  -- Un cliente DISTINTO al de la sesion A
  SELECT id INTO :g_cliente FROM cliente ORDER BY id OFFSET 1 ROWS FETCH FIRST 1 ROWS ONLY;
END;
/

PROMPT
PROMPT ===== SESION B =====
SELECT SYS_CONTEXT('USERENV', 'SID') AS sesion, USER AS usuario FROM dual;

/* =====================================================================
   FASE 1 - ANTES
   ===================================================================== */
PROMPT
PROMPT ##### FASE 1 - ANTES (sin bloqueo) #####
PROMPT
PAUSE >>> Espere a que la sesion A termine el paso A1 y luego pulse ENTER para ejecutar B1...

PROMPT
PROMPT === B1. Sesion B reserva LA MISMA habitacion y fechas (A todavia no hizo COMMIT) ===
BEGIN
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab, DATE '2026-12-10', DATE '2026-12-13', 2, :g_res);
  DBMS_OUTPUT.PUT_LINE('B1: reserva ' || :g_res || ' creada por B. NO hubo bloqueo ni error.');
END;
/
PROMPT
PROMPT >>> Vuelva a la sesion A y pulse ENTER alli (paso A2: COMMIT de A).
PAUSE >>> Cuando A haya hecho COMMIT, pulse ENTER para que B haga COMMIT (paso B2)...

PROMPT
PROMPT === B2. Sesion B confirma ===
COMMIT;
PROMPT B2: COMMIT hecho por B  ->  la habitacion quedo reservada DOS veces.
PROMPT >>> Vuelva a la sesion A (ENTER) para ver el resultado de la fase ANTES.

/* =====================================================================
   FASE 2 - DESPUES
   ===================================================================== */
PROMPT
PROMPT ##### FASE 2 - DESPUES (SELECT ... FOR UPDATE) #####
PROMPT
PAUSE >>> Espere a que la sesion A termine el paso A3 (reserva con bloqueo). Luego ENTER para ejecutar B3...

PROMPT
PROMPT === B3. Sesion B intenta reservar la misma habitacion: debe quedar ESPERANDO ===
PROMPT (el prompt no vuelve hasta que A haga COMMIT; espera maxima 60 s)
BEGIN
  sp_crear_reserva_segura(:g_cliente, :g_hab, DATE '2026-12-10', DATE '2026-12-13', 2, :g_res, 60);
  DBMS_OUTPUT.PUT_LINE('B3: reserva ' || :g_res || ' creada por B (no esperado)');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('B3: B fue RECHAZADA -> ' || SQLERRM);
    ROLLBACK;
END;
/
PROMPT
PROMPT === B4. Resultado para B (observe el tiempo transcurrido arriba: es lo que B espero a A) ===
SELECT COUNT(*) AS reservas_de_b_en_la_habitacion
FROM   reserva r
JOIN   reserva_habitacion rh ON rh.id_reserva = r.id
WHERE  rh.id_habitacion = :g_hab
AND    r.id_cliente = :g_cliente;
PROMPT
PROMPT Esperado: ORA-20005 (habitacion no disponible) y 0 reservas de B.
PROMPT >>> Vuelva a la sesion A (ENTER) para ver el resultado final.
