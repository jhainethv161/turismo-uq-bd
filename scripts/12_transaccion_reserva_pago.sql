/* =====================================================================
   TurismoUQ - Entrega 3
   Script 12: TRANSACCION ATOMICA reserva + pago con SAVEPOINT
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA, despues de 01 a 11.

   Contenido
     0. Procedimiento SP_CREAR_RESERVA_SEGURA (bloqueo con FOR UPDATE)
     1. Procedimiento SP_RESERVAR_Y_PAGAR
     2. Demostracion con tres escenarios (cada uno imprime OK / FALLA)
          D1  Todo sale bien           -> reserva confirmada y pagada
          D2  ROLLBACK PARCIAL         -> el pago falla DESPUES de insertarse;
                                          se deshace solo el pago y la reserva
                                          queda pendiente
          D3  ROLLBACK TOTAL           -> falla el pago y no queda ni reserva
     3. ROLLBACK final: las pruebas no dejan datos en la base.

   Por que es una transaccion unica
     Reservar y pagar son dos pasos de negocio que, para la plataforma,
     deben verse como uno solo: nunca puede quedar un pago sin reserva ni
     una reserva "pagada" sin pago. El procedimiento NO hace COMMIT; quien
     lo llama decide cuando confirmar (igual que PKG_TURISMO).

   Los dos SAVEPOINT
        sp_rp_inicio       antes de crear la reserva
        sp_rp_reserva_ok   justo despues de crear la reserva y antes del pago

     ROLLBACK TO sp_rp_reserva_ok deshace SOLO lo escrito despues de ese
     punto (el pago); la reserva sigue viva en la misma transaccion.
     ROLLBACK TO sp_rp_inicio lo deshace todo.

   Modo (parametro p_rollback_total)
     'S' (por defecto)  Atomico estricto: si falla el pago, no queda nada.
                        El error se relanza al llamador.
     'N'                Tolerante: si falla el pago, se conserva la reserva
                        en estado PENDIENTE (aparta la habitacion mientras el
                        cliente reintenta pagar) y se informa en p_resultado.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET VERIFY OFF
SET SQLBLANKLINES ON

/* =====================================================================
   0. SP_CREAR_RESERVA_SEGURA: SP_CREAR_RESERVA con bloqueo pesimista
   ---------------------------------------------------------------------
   Antes de revisar la disponibilidad bloquea la fila de la HABITACION
   con SELECT ... FOR UPDATE. Dos sesiones que reserven la MISMA
   habitacion se serializan; la segunda, cuando la primera confirma,
   ve la reserva y se rechaza con -20005. SP_RESERVAR_Y_PAGAR (seccion 1)
   usa esta version, de modo que reservar por recepcion es seguro bajo
   concurrencia. El experimento de dos sesiones esta en los scripts 13.
   ===================================================================== */
CREATE OR REPLACE PROCEDURE sp_crear_reserva_segura (
  p_id_cliente     IN  cliente.id%TYPE,
  p_id_habitacion  IN  habitacion.id%TYPE,
  p_fecha_in       IN  DATE,
  p_fecha_out      IN  DATE,
  p_num_huespedes  IN  NUMBER,
  p_id_reserva     OUT reserva.id%TYPE,
  p_espera_seg     IN  NUMBER DEFAULT 60)
IS
  v_id       habitacion.id%TYPE;
  e_timeout  EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_timeout, -30006);   -- resource busy: WAIT vencido
BEGIN
  -- Bloqueo de la fila de la habitacion. Dura hasta el COMMIT/ROLLBACK
  -- de la transaccion que llama. WAIT no admite una variable: se usa
  -- SQL dinamico para respetar p_espera_seg.
  BEGIN
    EXECUTE IMMEDIATE
      'SELECT id FROM habitacion WHERE id = :1 FOR UPDATE WAIT ' ||
      TO_CHAR(TRUNC(p_espera_seg))
      INTO v_id USING p_id_habitacion;
  EXCEPTION
    WHEN e_timeout THEN
      RAISE_APPLICATION_ERROR(-20040,
        'La habitacion ' || p_id_habitacion ||
        ' esta siendo reservada por otra sesion (espera de ' ||
        p_espera_seg || ' s agotada)');
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(-20003,
        'La habitacion ' || p_id_habitacion || ' no existe');
  END;

  -- Con el bloqueo tomado, la lectura de disponibilidad ya ve lo que la
  -- sesion anterior confirmo. Se reutiliza toda la logica de la Entrega 2.
  pkg_turismo.sp_crear_reserva(p_id_cliente, p_id_habitacion,
                               p_fecha_in, p_fecha_out,
                               p_num_huespedes, p_id_reserva);
END sp_crear_reserva_segura;
/
SHOW ERRORS PROCEDURE sp_crear_reserva_segura

/* =====================================================================
   1. PROCEDIMIENTO
   Codigos de error propios (el paquete usa -20001 a -20020):
     -20030  metodo de pago inexistente
     -20031  el pago excede lo que se debe
     -20032  monto invalido (nulo o menor o igual a cero)
   ===================================================================== */
CREATE OR REPLACE PROCEDURE sp_reservar_y_pagar (
  p_id_cliente      IN  cliente.id%TYPE,
  p_id_habitacion   IN  habitacion.id%TYPE,
  p_fecha_in        IN  DATE,
  p_fecha_out       IN  DATE,
  p_num_huespedes   IN  NUMBER,
  p_id_metodo_pago  IN  metodo_pago.id%TYPE,
  p_monto           IN  NUMBER,
  p_rollback_total  IN  VARCHAR2 DEFAULT 'S',
  p_traza           IN  VARCHAR2 DEFAULT 'N',
  p_id_reserva      OUT reserva.id%TYPE,
  p_id_pago         OUT pago.id%TYPE,
  p_resultado       OUT VARCHAR2)
IS
  v_existe     PLS_INTEGER;
  v_id_ep      estado_pago.id%TYPE;
  v_id_pt      pago_total.id%TYPE;
  v_total      pago_total.total%TYPE;
  v_pagado     NUMBER;
  v_pagos_vis  PLS_INTEGER;
  v_id_conf    estado_reserva.id%TYPE;

  -- Escribe una linea de seguimiento solo si se pidio traza
  PROCEDURE traza (p_msg IN VARCHAR2) IS
  BEGIN
    IF p_traza = 'S' THEN
      DBMS_OUTPUT.PUT_LINE('      [traza] ' || p_msg);
    END IF;
  END traza;
BEGIN
  p_id_reserva := NULL;
  p_id_pago    := NULL;
  p_resultado  := NULL;

  -- Punto de retorno 1: antes de tocar nada
  SAVEPOINT sp_rp_inicio;

  -- PASO 1. Crear la reserva (cabecera + linea + noches + PAGO_TOTAL).
  -- sp_crear_reserva_segura (y sp_crear_reserva dentro) ya es atomico por si mismo; si falla relanza el
  -- error y el handler de abajo deja todo como estaba.
  -- Version con SELECT ... FOR UPDATE sobre la habitacion (seccion 0)
  sp_crear_reserva_segura(p_id_cliente, p_id_habitacion,
                          p_fecha_in, p_fecha_out,
                          p_num_huespedes, p_id_reserva);
  traza('reserva ' || p_id_reserva || ' creada en estado PENDIENTE');

  -- Punto de retorno 2: la reserva existe, el pago todavia no
  SAVEPOINT sp_rp_reserva_ok;

  /* ------------------------------------------------------------------
     PASO 2. Registrar el pago. Cualquier fallo aqui cae en el handler
     interno, que decide entre rollback parcial o total.
     ------------------------------------------------------------------ */
  BEGIN
    IF p_monto IS NULL OR p_monto <= 0 THEN
      RAISE_APPLICATION_ERROR(-20032, 'El monto del pago debe ser mayor que cero');
    END IF;

    SELECT COUNT(*) INTO v_existe FROM metodo_pago WHERE id = p_id_metodo_pago;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(-20030,
        'El metodo de pago ' || p_id_metodo_pago || ' no existe');
    END IF;

    SELECT id INTO v_id_ep
    FROM   estado_pago
    WHERE  UPPER(TRIM(descripcion)) = pkg_turismo.c_pago_exitoso;

    SELECT id, total INTO v_id_pt, v_total
    FROM   pago_total
    WHERE  id_reserva = p_id_reserva;

    -- Se INSERTA primero y se valida despues, a proposito: asi, cuando la
    -- validacion falla, hay un pago ya escrito que el ROLLBACK TO deshace
    -- de verdad (esa es la demostracion del rollback parcial).
    INSERT INTO pago (fecha, monto, id_pago_total, id_metodo_pago, id_estado_pago)
    VALUES (SYSDATE, p_monto, v_id_pt, p_id_metodo_pago, v_id_ep)
    RETURNING id INTO p_id_pago;
    traza('pago ' || p_id_pago || ' insertado por ' || p_monto);

    SELECT COUNT(*) INTO v_pagos_vis FROM pago WHERE id_pago_total = v_id_pt;
    traza('pagos visibles dentro de la transaccion: ' || v_pagos_vis);

    -- Total pagado con exito, incluido el que se acaba de insertar
    SELECT NVL(SUM(monto), 0) INTO v_pagado
    FROM   pago
    WHERE  id_pago_total = v_id_pt
    AND    id_estado_pago = v_id_ep;

    IF v_pagado > v_total THEN
      RAISE_APPLICATION_ERROR(-20031,
        'El pago excede lo que se debe: total ' || v_total ||
        ', pagado con este pago ' || v_pagado);
    END IF;

    -- Estado de PAGO_TOTAL: pagado / abonado
    pkg_turismo.sp_recalcular_total(p_id_reserva);

    -- Pago completo: la reserva (y sus lineas) pasan a CONFIRMADA
    IF v_pagado >= v_total THEN
      v_id_conf := pkg_turismo.fn_id_estado_reserva(pkg_turismo.c_est_confirmada);

      UPDATE reserva
      SET    id_estado_reserva = v_id_conf
      WHERE  id = p_id_reserva;

      UPDATE reserva_habitacion
      SET    id_estado_reserva = v_id_conf
      WHERE  id_reserva = p_id_reserva;

      p_resultado := 'RESERVA CONFIRMADA Y PAGADA';
    ELSE
      p_resultado := 'RESERVA PENDIENTE CON ABONO (' || v_pagado || ' de ' || v_total || ')';
    END IF;
  EXCEPTION
    WHEN OTHERS THEN
      IF UPPER(p_rollback_total) = 'S' THEN
        -- Atomico estricto: se propaga al handler externo, que deshace todo
        RAISE;
      ELSE
        -- ROLLBACK PARCIAL: se deshace solo el pago; la reserva queda
        ROLLBACK TO sp_rp_reserva_ok;
        p_id_pago   := NULL;
        p_resultado := 'RESERVA PENDIENTE SIN PAGO. Motivo: ' || SQLERRM;
        traza('rollback parcial a sp_rp_reserva_ok');
      END IF;
  END;
EXCEPTION
  WHEN OTHERS THEN
    -- ROLLBACK TOTAL: no queda reserva, linea, noches, total ni pago
    ROLLBACK TO sp_rp_inicio;
    p_id_reserva := NULL;
    p_id_pago    := NULL;
    traza('rollback total a sp_rp_inicio');
    RAISE;
END sp_reservar_y_pagar;
/
SHOW ERRORS PROCEDURE sp_reservar_y_pagar

/* =====================================================================
   2. DEMOSTRACION
   P0 escoge datos reales: una habitacion libre en el rango elegido y un
   cliente. Los ids no estan fijos en el script.
   ===================================================================== */
VARIABLE g_hab      NUMBER
VARIABLE g_cliente  NUMBER
VARIABLE g_metodo   NUMBER
VARIABLE g_in       VARCHAR2(10)
VARIABLE g_out      VARCHAR2(10)
VARIABLE g_total    NUMBER

PROMPT
PROMPT === P0. Datos de la demostracion ===
DECLARE
  v_in   DATE := DATE '2026-12-20';
  v_out  DATE := DATE '2026-12-23';
  v_hab  habitacion.id%TYPE;
  v_val  NUMBER;
BEGIN
  -- Primera habitacion libre en el rango y con tarifa para todas las noches
  FOR h IN (SELECT id FROM habitacion WHERE capacidad_maxima >= 2 ORDER BY id) LOOP
    BEGIN
      -- Libre en TODO el margen que usan los tres escenarios
      -- (3 noches antes del check-in y 3 despues del check-out)
      IF pkg_turismo.fn_habitacion_disponible(h.id, v_in - 3, v_out + 3) = 'S' THEN
        v_val := pkg_turismo.fn_valor_estadia(h.id, v_in - 3, v_out + 3);   -- falla si falta tarifa
        v_val := pkg_turismo.fn_valor_estadia(h.id, v_in, v_out);
        v_hab := h.id;
        EXIT;
      END IF;
    EXCEPTION
      WHEN OTHERS THEN NULL;   -- sin tarifa en alguna noche: probar otra
    END;
  END LOOP;

  IF v_hab IS NULL THEN
    RAISE_APPLICATION_ERROR(-20099, 'No se encontro una habitacion libre para la demostracion');
  END IF;

  :g_hab   := v_hab;
  :g_in    := TO_CHAR(v_in,  'YYYY-MM-DD');
  :g_out   := TO_CHAR(v_out, 'YYYY-MM-DD');
  :g_total := v_val;
  SELECT MIN(id) INTO :g_cliente FROM cliente;
  SELECT MIN(id) INTO :g_metodo  FROM metodo_pago;

  DBMS_OUTPUT.PUT_LINE('Habitacion : ' || :g_hab);
  DBMS_OUTPUT.PUT_LINE('Cliente    : ' || :g_cliente);
  DBMS_OUTPUT.PUT_LINE('Estadia    : ' || :g_in || ' a ' || :g_out);
  DBMS_OUTPUT.PUT_LINE('Valor      : ' || :g_total);
END;
/

/* ---------------------------------------------------------------------
   D1. Todo sale bien: pago por el total exacto
   Esperado: reserva CONFIRMADA, PAGO_TOTAL = pagado, 1 pago exitoso.
   --------------------------------------------------------------------- */
PROMPT
PROMPT === D1. Reserva + pago completo (camino feliz) ===
DECLARE
  v_res   reserva.id%TYPE;
  v_pago  pago.id%TYPE;
  v_msg   VARCHAR2(400);
  v_est   VARCHAR2(20);
  v_ept   VARCHAR2(20);
  v_npag  PLS_INTEGER;
BEGIN
  sp_reservar_y_pagar(:g_cliente, :g_hab, TO_DATE(:g_in,'YYYY-MM-DD'), TO_DATE(:g_out,'YYYY-MM-DD'),
                      2, :g_metodo, :g_total, 'S', 'S', v_res, v_pago, v_msg);

  SELECT UPPER(TRIM(er.descripcion)) INTO v_est
  FROM reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva WHERE r.id = v_res;

  SELECT UPPER(TRIM(e.descripcion)), (SELECT COUNT(*) FROM pago WHERE id_pago_total = pt.id)
  INTO   v_ept, v_npag
  FROM   pago_total pt JOIN estado_pago_total e ON e.id = pt.id_estado_pago_total
  WHERE  pt.id_reserva = v_res;

  DBMS_OUTPUT.PUT_LINE('   resultado: ' || v_msg);
  DBMS_OUTPUT.PUT_LINE('   reserva=' || v_est || ', pago_total=' || v_ept || ', pagos=' || v_npag);
  IF v_est = 'CONFIRMADA' AND v_ept = 'PAGADO' AND v_npag = 1 THEN
    DBMS_OUTPUT.PUT_LINE('D1 OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('D1 FALLA');
  END IF;
END;
/

-- La reserva de D1 sigue en la transaccion (sin COMMIT) y ocupa la
-- habitacion; D2 y D3 usan otras fechas de la misma habitacion.

/* ---------------------------------------------------------------------
   D2. ROLLBACK PARCIAL
   Se paga el DOBLE de lo que se debe. El pago se INSERTA (la traza lo
   muestra), la validacion lo rechaza (-20031) y ROLLBACK TO
   sp_rp_reserva_ok lo deshace. Modo 'N': la reserva se conserva.
   Esperado: reserva PENDIENTE, 0 pagos, PAGO_TOTAL = pendiente.
   --------------------------------------------------------------------- */
PROMPT
PROMPT === D2. ROLLBACK PARCIAL: el pago falla, la reserva se conserva ===
DECLARE
  v_res    reserva.id%TYPE;
  v_pago   pago.id%TYPE;
  v_msg    VARCHAR2(400);
  v_est    VARCHAR2(20);
  v_ept    VARCHAR2(20);
  v_npag   PLS_INTEGER;
  v_in     DATE := TO_DATE(:g_out, 'YYYY-MM-DD');       -- justo despues de D1
  v_out    DATE := TO_DATE(:g_out, 'YYYY-MM-DD') + 3;
  v_monto  NUMBER;
BEGIN
  v_monto := 2 * pkg_turismo.fn_valor_estadia(:g_hab, v_in, v_out);

  sp_reservar_y_pagar(:g_cliente, :g_hab, v_in, v_out,
                      2, :g_metodo, v_monto, 'N', 'S', v_res, v_pago, v_msg);

  SELECT UPPER(TRIM(er.descripcion)) INTO v_est
  FROM reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva WHERE r.id = v_res;

  SELECT UPPER(TRIM(e.descripcion)), (SELECT COUNT(*) FROM pago WHERE id_pago_total = pt.id)
  INTO   v_ept, v_npag
  FROM   pago_total pt JOIN estado_pago_total e ON e.id = pt.id_estado_pago_total
  WHERE  pt.id_reserva = v_res;

  DBMS_OUTPUT.PUT_LINE('   resultado: ' || v_msg);
  DBMS_OUTPUT.PUT_LINE('   reserva=' || v_est || ', pago_total=' || v_ept ||
                       ', pagos despues del rollback=' || v_npag);
  IF v_res IS NOT NULL AND v_est = 'PENDIENTE' AND v_ept = 'PENDIENTE'
     AND v_npag = 0 AND v_pago IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('D2 OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('D2 FALLA');
  END IF;
END;
/

/* ---------------------------------------------------------------------
   D3. ROLLBACK TOTAL
   Metodo de pago inexistente en modo 'S': falla -20030 y no debe quedar
   ninguna reserva nueva para esas fechas.
   Esperado: error -20030 y 0 reservas nuevas.
   --------------------------------------------------------------------- */
PROMPT
PROMPT === D3. ROLLBACK TOTAL: falla el pago y no queda nada ===
DECLARE
  v_res    reserva.id%TYPE;
  v_pago   pago.id%TYPE;
  v_msg    VARCHAR2(400);
  v_in     DATE := TO_DATE(:g_in, 'YYYY-MM-DD') - 3;      -- justo antes de D1
  v_out    DATE := TO_DATE(:g_in, 'YYYY-MM-DD') - 1;
  v_antes  PLS_INTEGER;
  v_desp   PLS_INTEGER;
  v_codigo PLS_INTEGER := 0;
BEGIN
  SELECT COUNT(*) INTO v_antes FROM reserva_habitacion
  WHERE  id_habitacion = :g_hab AND fecha_check_in >= v_in;

  BEGIN
    sp_reservar_y_pagar(:g_cliente, :g_hab, v_in, v_out,
                        2, -999, 100000, 'S', 'S', v_res, v_pago, v_msg);
  EXCEPTION
    WHEN OTHERS THEN
      v_codigo := SQLCODE;
      DBMS_OUTPUT.PUT_LINE('   error recibido: ' || SQLERRM);
  END;

  SELECT COUNT(*) INTO v_desp FROM reserva_habitacion
  WHERE  id_habitacion = :g_hab AND fecha_check_in >= v_in;

  DBMS_OUTPUT.PUT_LINE('   lineas antes=' || v_antes || ', despues=' || v_desp);
  IF v_codigo = -20030 AND v_antes = v_desp THEN
    DBMS_OUTPUT.PUT_LINE('D3 OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('D3 FALLA');
  END IF;
END;
/

/* =====================================================================
   3. LIMPIEZA: se deshace todo lo creado por la demostracion
   ===================================================================== */
ROLLBACK;
PROMPT
PROMPT Demostracion terminada: ROLLBACK ejecutado, no quedan datos de prueba.
