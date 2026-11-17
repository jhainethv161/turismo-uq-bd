/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13d: borra las RESERVAS de la habitacion de prueba 'ZZ-CONC'
   ---------------------------------------------------------------------
   Elimina lineas, noches, pagos, totales y cabeceras de las reservas
   hechas sobre la habitacion de prueba. Se usa entre la fase ANTES y la
   fase DESPUES del experimento de concurrencia. La habitacion y sus
   tarifas se conservan (para borrarlas, 13e_limpieza_total.sql).
   Se puede ejecutar varias veces sin error.
   ===================================================================== */
SET SERVEROUTPUT ON

DECLARE
  TYPE t_ids IS TABLE OF NUMBER;
  v_hab      habitacion.id%TYPE;
  v_reservas t_ids;
BEGIN
  BEGIN
    SELECT id INTO v_hab FROM habitacion WHERE numero = 'ZZ-CONC';
  EXCEPTION
    WHEN NO_DATA_FOUND THEN RETURN;     -- nada que limpiar
  END;

  SELECT DISTINCT id_reserva BULK COLLECT INTO v_reservas
  FROM   reserva_habitacion WHERE id_habitacion = v_hab;

  IF v_reservas.COUNT > 0 THEN
    FORALL i IN 1 .. v_reservas.COUNT
      DELETE FROM reserva_noche
      WHERE  id_reserva_habitacion IN (SELECT id FROM reserva_habitacion WHERE id_reserva = v_reservas(i));
    FORALL i IN 1 .. v_reservas.COUNT
      DELETE FROM pago
      WHERE  id_pago_total IN (SELECT id FROM pago_total WHERE id_reserva = v_reservas(i));
    FORALL i IN 1 .. v_reservas.COUNT
      DELETE FROM pago_total WHERE id_reserva = v_reservas(i);
    FORALL i IN 1 .. v_reservas.COUNT
      DELETE FROM reserva_habitacion WHERE id_reserva = v_reservas(i);
    FORALL i IN 1 .. v_reservas.COUNT
      DELETE FROM reserva WHERE id = v_reservas(i);
  END IF;

  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Reservas de prueba borradas: ' || v_reservas.COUNT);
END;
/
