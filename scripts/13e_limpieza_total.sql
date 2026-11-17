/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13e: limpieza TOTAL del experimento de concurrencia
   ---------------------------------------------------------------------
   Borra las reservas de prueba (13d), la habitacion 'ZZ-CONC', sus
   tarifas y las filas que el disparador de auditoria genero por ellas.
   Deja la base como estaba antes del experimento. No borra
   SP_CREAR_RESERVA_SEGURA. Se puede ejecutar varias veces sin error.
   ===================================================================== */
SET SERVEROUTPUT ON

@@13d_limpieza_reservas_prueba.sql

DECLARE
  v_hab habitacion.id%TYPE;
BEGIN
  SELECT id INTO v_hab FROM habitacion WHERE numero = 'ZZ-CONC';
  DELETE FROM tarifa           WHERE id_habitacion = v_hab;
  DELETE FROM auditoria_tarifa WHERE id_habitacion = v_hab;
  DELETE FROM habitacion       WHERE id = v_hab;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Habitacion de prueba borrada.');
EXCEPTION
  WHEN NO_DATA_FOUND THEN NULL;         -- ya no existia
END;
/
