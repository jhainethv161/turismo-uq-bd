/* =====================================================================
   TurismoUQ - Entrega 2
   Script 08: disparadores
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA.
   Requiere: script 05 (privilegio CREATE TRIGGER), script 06
   (AUDITORIA_TARIFA) y script 07 (PKG_TURISMO, de donde se toman los
   codigos de error y los nombres de estado).

   Disparadores:
     1. TRG_AUDITORIA_TARIFA         auditoria de TARIFA      (sentencia)
     2. TRG_RH_NO_SOLAPE             impide reservas solapadas (fila)
     3. TRG_RH_COHERENCIA            habitacion del alojamiento de la
                                     reserva y fechas dentro del rango
     4. TRG_RS_COHERENCIA            servicio del alojamiento de la reserva
     5. TRG_RESENA_COMPLETADA        solo se resenan reservas completadas
   Los 3 a 5 cumplen lo que la Entrega 1 dejo "para la Entrega 2"
   (reglas de negocio 2 y 4 del documento).
   ===================================================================== */

SET SERVEROUTPUT ON

/* =====================================================================
   1. TRG_AUDITORIA_TARIFA  -  disparador a nivel de SENTENCIA

   Problema: un disparador de sentencia se ejecuta UNA vez por
   sentencia y NO tiene acceso a :OLD ni :NEW (esos valores solo
   existen fila por fila). Sin embargo, la auditoria pide el valor
   anterior y el nuevo.

   Solucion: COMPOUND TRIGGER (Oracle 11g+). Un solo disparador con
   varias secciones que comparten variables durante la sentencia:
     - BEFORE STATEMENT : inicia la coleccion y captura QUIEN y CUANDO
                          una sola vez por sentencia.
     - AFTER EACH ROW   : solo ANOTA en memoria el valor anterior y
                          el nuevo de cada fila (unico lugar donde
                          existen :OLD y :NEW).
     - AFTER STATEMENT  : al terminar la sentencia, escribe TODO el
                          lote en AUDITORIA_TARIFA con un FORALL
                          (una sola operacion masiva).
   La escritura de la auditoria ocurre a nivel de sentencia, que es lo
   pedido, sin perder los valores de cada fila.

   Ej.: UPDATE tarifa SET valor_noche = valor_noche * 1.1
        WHERE id_temporada = 7;     -- 400 filas
   -> BEFORE STATEMENT 1 vez, AFTER EACH ROW 400 veces (en memoria),
      AFTER STATEMENT 1 vez con un FORALL de 400 filas.

   Un UPDATE que no cambia el valor (mismo valor) no se audita.
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_auditoria_tarifa
  FOR INSERT OR UPDATE OF valor_noche OR DELETE ON tarifa
  COMPOUND TRIGGER

  TYPE t_lista_auditoria IS TABLE OF auditoria_tarifa%ROWTYPE INDEX BY PLS_INTEGER;

  g_cambios     t_lista_auditoria;
  g_usuario_bd  auditoria_tarifa.usuario_bd%TYPE;
  g_usuario_so  auditoria_tarifa.usuario_so%TYPE;
  g_equipo      auditoria_tarifa.equipo%TYPE;
  g_momento     auditoria_tarifa.fecha_cambio%TYPE;

  -- ---------------- Una vez, antes de la sentencia ----------------
  BEFORE STATEMENT IS
  BEGIN
    g_cambios.DELETE;
    g_usuario_bd := SYS_CONTEXT('USERENV', 'SESSION_USER');
    g_usuario_so := SYS_CONTEXT('USERENV', 'OS_USER');
    g_equipo     := SYS_CONTEXT('USERENV', 'HOST');
    g_momento    := SYSTIMESTAMP;
  END BEFORE STATEMENT;

  -- ---------------- Por cada fila: solo se anota ------------------
  AFTER EACH ROW IS
    v_reg auditoria_tarifa%ROWTYPE;
  BEGIN
    IF INSERTING OR DELETING OR (UPDATING AND :OLD.valor_noche <> :NEW.valor_noche) THEN
      v_reg.id            := NULL;   -- lo genera la IDENTITY
      v_reg.id_tarifa     := NVL(:NEW.id, :OLD.id);
      v_reg.id_habitacion := NVL(:NEW.id_habitacion, :OLD.id_habitacion);
      v_reg.id_temporada  := NVL(:NEW.id_temporada, :OLD.id_temporada);

      IF INSERTING THEN
        v_reg.operacion      := 'INSERT';
        v_reg.valor_anterior := NULL;
        v_reg.valor_nuevo    := :NEW.valor_noche;
      ELSIF UPDATING THEN
        v_reg.operacion      := 'UPDATE';
        v_reg.valor_anterior := :OLD.valor_noche;
        v_reg.valor_nuevo    := :NEW.valor_noche;
      ELSE
        v_reg.operacion      := 'DELETE';
        v_reg.valor_anterior := :OLD.valor_noche;
        v_reg.valor_nuevo    := NULL;
      END IF;

      v_reg.usuario_bd   := g_usuario_bd;
      v_reg.usuario_so   := g_usuario_so;
      v_reg.equipo       := g_equipo;
      v_reg.fecha_cambio := g_momento;

      g_cambios(g_cambios.COUNT + 1) := v_reg;
    END IF;
  END AFTER EACH ROW;

  -- ---------------- Una vez, despues de la sentencia --------------
  AFTER STATEMENT IS
  BEGIN
    FORALL i IN 1 .. g_cambios.COUNT
      INSERT INTO auditoria_tarifa VALUES g_cambios(i);
    g_cambios.DELETE;
  END AFTER STATEMENT;

END trg_auditoria_tarifa;
/

/* =====================================================================
   2. TRG_RH_NO_SOLAPE  -  disparador a nivel de FILA

   Impide registrar una linea de reserva (RESERVA_HABITACION) cuya
   habitacion ya esta ocupada en un rango de fechas que se cruza.

   - Solo se valida si la linea nueva esta ACTIVA (PENDIENTE o
     CONFIRMADA) y su cabecera tambien lo esta: registrar una linea ya
     cancelada, o una linea de una reserva cancelada, no ocupa nada.
   - Se compara contra lineas ACTIVAS de la misma habitacion, exigiendo
     que la CABECERA y la LINEA esten activas. Asi una cabecera
     cancelada no bloquea aunque alguna linea haya quedado mal marcada,
     y una linea cancelada de un grupo no bloquea la habitacion.
   - Solape: existente.check_in < nuevo.check_out
             Y existente.check_out > nuevo.check_in
     (salir el 26 y que otro entre el 26 es valido).

   Por que es BEFORE INSERT (y no INSERT OR UPDATE):
   un disparador de fila que consulta su propia tabla produce
   ORA-04091 (tabla mutante) porque la tabla esta a mitad de cambio.
   Oracle hace UNA excepcion: un INSERT de una sola fila con VALUES.
   Asi inserta las lineas PKG_TURISMO (una por una), por lo que el
   disparador funciona sobre el camino real de la aplicacion.
   Limitacion conocida (y documentada): un INSERT ... SELECT de varias
   filas o un UPDATE de fechas no pasan por este disparador; esos
   casos los controla el paquete (fn_habitacion_disponible).

   Es la segunda barrera: aunque alguien inserte directamente en la
   tabla saltandose sp_crear_reserva, el solape se rechaza igual.
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_rh_no_solape
  BEFORE INSERT ON reserva_habitacion
  FOR EACH ROW
DECLARE
  v_estado_linea        estado_reserva.descripcion%TYPE;
  v_estado_reserva      estado_reserva.descripcion%TYPE;
  v_reserva_conflicto   reserva_habitacion.id_reserva%TYPE;
BEGIN
  SELECT UPPER(TRIM(descripcion)) INTO v_estado_linea
  FROM   estado_reserva
  WHERE  id = :NEW.id_estado_reserva;

  -- Estado de la cabecera duena de la linea nueva
  BEGIN
    SELECT UPPER(TRIM(er.descripcion)) INTO v_estado_reserva
    FROM   reserva r
    JOIN   estado_reserva er ON er.id = r.id_estado_reserva
    WHERE  r.id = :NEW.id_reserva;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      -- La FK de RESERVA_HABITACION dara el error correspondiente
      RETURN;
  END;

  IF v_estado_reserva IN (pkg_turismo.c_est_pendiente, pkg_turismo.c_est_confirmada)
     AND v_estado_linea IN (pkg_turismo.c_est_pendiente, pkg_turismo.c_est_confirmada) THEN

    SELECT MIN(rh.id_reserva) INTO v_reserva_conflicto
    FROM   reserva_habitacion rh
    JOIN   reserva r           ON r.id   = rh.id_reserva
    JOIN   estado_reserva erh  ON erh.id = r.id_estado_reserva
    JOIN   estado_reserva erl  ON erl.id = rh.id_estado_reserva
    WHERE  rh.id_habitacion = :NEW.id_habitacion
    AND    UPPER(TRIM(erh.descripcion)) IN (pkg_turismo.c_est_pendiente,
                                            pkg_turismo.c_est_confirmada)
    AND    UPPER(TRIM(erl.descripcion)) IN (pkg_turismo.c_est_pendiente,
                                            pkg_turismo.c_est_confirmada)
    AND    rh.fecha_check_in  < :NEW.fecha_check_out
    AND    rh.fecha_check_out > :NEW.fecha_check_in;

    IF v_reserva_conflicto IS NOT NULL THEN
      RAISE_APPLICATION_ERROR(pkg_turismo.c_err_no_disponible,
        '[TRG_RH_NO_SOLAPE] La habitacion ' || :NEW.id_habitacion ||
        ' ya esta ocupada por la reserva ' || v_reserva_conflicto ||
        ' en el rango ' || TO_CHAR(:NEW.fecha_check_in, 'YYYY-MM-DD') ||
        ' a ' || TO_CHAR(:NEW.fecha_check_out, 'YYYY-MM-DD'));
    END IF;
  END IF;
END trg_rh_no_solape;
/

/* =====================================================================
   3. TRG_RH_COHERENCIA  (fila)  -  regla 4 y regla 7 de la Entrega 1
   - La habitacion de la linea pertenece al alojamiento de la reserva
     (una FK sola no lo puede garantizar: son dos FK independientes).
   - Las fechas de la linea estan dentro del rango general de la reserva.
   Consulta RESERVA y HABITACION (no su propia tabla), por eso puede
   cubrir INSERT y UPDATE sin problema de tabla mutante.
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_rh_coherencia
  BEFORE INSERT OR UPDATE OF id_reserva, id_habitacion, fecha_check_in, fecha_check_out
  ON reserva_habitacion
  FOR EACH ROW
DECLARE
  v_aloj_reserva   reserva.id_alojamiento%TYPE;
  v_res_in         reserva.fecha_check_in%TYPE;
  v_res_out        reserva.fecha_check_out%TYPE;
  v_aloj_hab       habitacion.id_alojamiento%TYPE;
BEGIN
  SELECT id_alojamiento, fecha_check_in, fecha_check_out
  INTO   v_aloj_reserva, v_res_in, v_res_out
  FROM   reserva
  WHERE  id = :NEW.id_reserva;

  SELECT id_alojamiento INTO v_aloj_hab
  FROM   habitacion
  WHERE  id = :NEW.id_habitacion;

  IF v_aloj_hab <> v_aloj_reserva THEN
    RAISE_APPLICATION_ERROR(pkg_turismo.c_err_alojamiento,
      '[TRG_RH_COHERENCIA] La habitacion ' || :NEW.id_habitacion ||
      ' no pertenece al alojamiento de la reserva ' || :NEW.id_reserva);
  END IF;

  IF :NEW.fecha_check_in < v_res_in OR :NEW.fecha_check_out > v_res_out THEN
    RAISE_APPLICATION_ERROR(pkg_turismo.c_err_rango_linea,
      '[TRG_RH_COHERENCIA] Las fechas de la linea deben estar dentro del rango de la reserva ' ||
      :NEW.id_reserva);
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;  -- reserva o habitacion inexistente: la FK correspondiente dara el error
END trg_rh_coherencia;
/

/* =====================================================================
   4. TRG_RS_COHERENCIA  (fila)  -  regla 4 de la Entrega 1
   El servicio contratado debe ser del mismo alojamiento de la reserva:
   el desayuno del Hotel X no se puede cargar a una reserva del Hotel Y.
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_rs_coherencia
  BEFORE INSERT OR UPDATE OF id_reserva, id_servicio ON reserva_servicio
  FOR EACH ROW
DECLARE
  v_aloj_reserva   reserva.id_alojamiento%TYPE;
  v_aloj_servicio  servicio.id_alojamiento%TYPE;
BEGIN
  SELECT id_alojamiento INTO v_aloj_reserva  FROM reserva  WHERE id = :NEW.id_reserva;
  SELECT id_alojamiento INTO v_aloj_servicio FROM servicio WHERE id = :NEW.id_servicio;

  IF v_aloj_servicio <> v_aloj_reserva THEN
    RAISE_APPLICATION_ERROR(pkg_turismo.c_err_alojamiento,
      '[TRG_RS_COHERENCIA] El servicio ' || :NEW.id_servicio ||
      ' no pertenece al alojamiento de la reserva ' || :NEW.id_reserva);
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;  -- la FK correspondiente dara el error
END trg_rs_coherencia;
/

/* =====================================================================
   5. TRG_RESENA_COMPLETADA  (fila)  -  regla 2 de la Entrega 1
   Solo se acepta una resena si la reserva esta COMPLETADA: no se
   resenan reservas pendientes, confirmadas (aun no se hospedo) ni
   canceladas. (La unicidad 1 resena por reserva ya la da el UNIQUE.)
   ===================================================================== */
CREATE OR REPLACE TRIGGER trg_resena_completada
  BEFORE INSERT OR UPDATE OF id_reserva ON resena
  FOR EACH ROW
DECLARE
  v_estado estado_reserva.descripcion%TYPE;
BEGIN
  SELECT UPPER(TRIM(er.descripcion)) INTO v_estado
  FROM   reserva r
  JOIN   estado_reserva er ON er.id = r.id_estado_reserva
  WHERE  r.id = :NEW.id_reserva;

  IF v_estado <> pkg_turismo.c_est_completada THEN
    RAISE_APPLICATION_ERROR(pkg_turismo.c_err_resena,
      '[TRG_RESENA_COMPLETADA] La reserva ' || :NEW.id_reserva ||
      ' esta ' || v_estado || ': solo se pueden resenar reservas COMPLETADAS');
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    NULL;  -- la FK dara el error
END trg_resena_completada;
/

-- Verificacion: los 5 disparadores deben quedar ENABLED y VALID
SELECT t.trigger_name, t.trigger_type, t.triggering_event, t.table_name, t.status, o.status AS compilacion
FROM   user_triggers t
JOIN   user_objects  o ON o.object_name = t.trigger_name AND o.object_type = 'TRIGGER'
WHERE  t.trigger_name IN ('TRG_AUDITORIA_TARIFA','TRG_RH_NO_SOLAPE','TRG_RH_COHERENCIA',
                          'TRG_RS_COHERENCIA','TRG_RESENA_COMPLETADA')
ORDER  BY t.trigger_name;

SELECT name, line, position, text
FROM   user_errors
WHERE  type = 'TRIGGER'
ORDER  BY name, sequence;
