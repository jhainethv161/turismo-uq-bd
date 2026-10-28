/* =====================================================================
   TurismoUQ - Entrega 2
   Script 07: paquete PKG_TURISMO (funcion, procedimientos y cursor)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA.
   Requiere: Entrega 1 + scripts 05 y 06.

   Contenido del paquete
   ---------------------
   Funciones publicas
     fn_valor_estadia          valor de una estadia noche por noche,
                               cruzando temporadas
     fn_habitacion_disponible  'S'/'N' segun haya o no solape
     fn_reserva_pagada         'S'/'N' (regla de negocio 5 de la E1)
     fn_calcular_reembolso     regla del 80 % / 0 % (regla 1 de la E1)
     fn_id_estado_reserva      traduce 'CONFIRMADA' -> id del catalogo
   Procedimientos publicos
     sp_crear_reserva          crea cabecera + linea + noches + total
     sp_agregar_habitacion     agrega otra habitacion a una reserva
     sp_recalcular_total       actualiza PAGO_TOTAL de una reserva
     sp_cancelar_reserva       cancela, registra el reembolso en PAGO
                               y actualiza el estado de PAGO_TOTAL
     sp_liquidacion_mensual    proceso masivo con CURSOR EXPLICITO
                               CON PARAMETROS
     sp_archivar_historico     copia reservas cerradas al historico

   Convenciones
   ------------
   * Ningun procedimiento hace COMMIT: la transaccion la cierra quien
     llama. Asi se pueden combinar en una transaccion mayor (Entrega 3).
   * Los procedimientos que hacen varios INSERT marcan un SAVEPOINT al
     inicio y, si algo falla, deshacen SOLO su propio trabajo antes de
     relanzar el error. Asi nunca queda una reserva a medio crear.
   * Los estados se buscan por su descripcion (no por id fijo), para no
     depender de los ids que genero la carga de datos. La carga de la
     Entrega 1 escribe las descripciones en minusculas; por eso todas
     las comparaciones usan UPPER(TRIM(...)).
   * Catalogos reales de la Entrega 1 (verificados en la base):
       ESTADO_RESERVA      : pendiente, confirmada, cancelada, completada
       ESTADO_PAGO         : exitoso, fallido, pendiente, reembolsado
       ESTADO_PAGO_TOTAL   : pendiente, abonado, pagado, reembolsado,
                             cancelado
     OJO: el estado de un pago incompleto es ABONADO. No existe
     "PARCIAL" en ESTADO_PAGO_TOTAL.
   * Todos los errores propios usan RAISE_APPLICATION_ERROR con codigos
     declarados como constantes en la especificacion (-20001 a -20020).
   ===================================================================== */

SET SERVEROUTPUT ON

/* =====================================================================
   ESPECIFICACION
   ===================================================================== */
CREATE OR REPLACE PACKAGE pkg_turismo AS

  -- ---------------------------------------------------------------
  -- Codigos de error propios (rango permitido: -20000 a -20999)
  -- ---------------------------------------------------------------
  c_err_parametros        CONSTANT PLS_INTEGER := -20001; -- parametro obligatorio nulo
  c_err_fechas            CONSTANT PLS_INTEGER := -20002; -- check-out <= check-in
  c_err_habitacion        CONSTANT PLS_INTEGER := -20003; -- habitacion inexistente
  c_err_capacidad         CONSTANT PLS_INTEGER := -20004; -- capacidad excedida / huespedes <= 0
  c_err_no_disponible     CONSTANT PLS_INTEGER := -20005; -- habitacion ocupada (solape)
  c_err_cliente           CONSTANT PLS_INTEGER := -20006; -- cliente inexistente
  c_err_alojamiento       CONSTANT PLS_INTEGER := -20007; -- habitacion/servicio de otro alojamiento
  c_err_rango_linea       CONSTANT PLS_INTEGER := -20008; -- linea fuera del rango de la reserva
  c_err_estado_reserva    CONSTANT PLS_INTEGER := -20009; -- operacion no permitida en ese estado
  c_err_sin_temporada     CONSTANT PLS_INTEGER := -20010; -- noche sin temporada definida
  c_err_temporada_doble   CONSTANT PLS_INTEGER := -20011; -- noche cubierta por 2 temporadas
  c_err_sin_tarifa        CONSTANT PLS_INTEGER := -20012; -- habitacion sin tarifa en la temporada
  c_err_reserva           CONSTANT PLS_INTEGER := -20013; -- reserva inexistente
  c_err_periodo           CONSTANT PLS_INTEGER := -20014; -- anio/mes invalido
  c_err_catalogo          CONSTANT PLS_INTEGER := -20015; -- valor que no existe en un catalogo
  c_err_resena            CONSTANT PLS_INTEGER := -20020; -- resena de reserva no completada

  -- ---------------------------------------------------------------
  -- Descripciones de catalogo usadas por la logica. Son las que trae
  -- la carga de la Entrega 1 (en minusculas); todas las comparaciones
  -- usan UPPER(TRIM(...)), asi que 'Confirmada' tambien coincide.
  -- ---------------------------------------------------------------
  c_est_pendiente   CONSTANT VARCHAR2(20) := 'PENDIENTE';
  c_est_confirmada  CONSTANT VARCHAR2(20) := 'CONFIRMADA';
  c_est_cancelada   CONSTANT VARCHAR2(20) := 'CANCELADA';
  c_est_completada  CONSTANT VARCHAR2(20) := 'COMPLETADA';

  c_pago_exitoso    CONSTANT VARCHAR2(20) := 'EXITOSO';      -- ESTADO_PAGO
  c_pago_reembolsado CONSTANT VARCHAR2(20) := 'REEMBOLSADO'; -- ESTADO_PAGO

  c_ept_pendiente   CONSTANT VARCHAR2(20) := 'PENDIENTE';    -- ESTADO_PAGO_TOTAL
  c_ept_abonado     CONSTANT VARCHAR2(20) := 'ABONADO';      -- pago incompleto
  c_ept_pagado      CONSTANT VARCHAR2(20) := 'PAGADO';       -- pago completo
  c_ept_reembolsado CONSTANT VARCHAR2(20) := 'REEMBOLSADO'; -- cancelada con devolucion
  c_ept_cancelado   CONSTANT VARCHAR2(20) := 'CANCELADO';   -- cancelada sin devolucion

  -- Regla de cancelacion: MAS de 5 dias de anticipacion -> 80 %
  -- (exactamente 5 dias o menos -> 0 %)
  c_dias_min_reembolso CONSTANT PLS_INTEGER := 5;
  c_pct_reembolso      CONSTANT NUMBER      := 0.80;

  -- ---------------------------------------------------------------
  -- Funciones
  -- ---------------------------------------------------------------
  FUNCTION fn_id_estado_reserva (p_descripcion IN VARCHAR2)
    RETURN estado_reserva.id%TYPE;

  FUNCTION fn_valor_estadia (p_id_habitacion IN habitacion.id%TYPE,
                             p_fecha_in      IN DATE,
                             p_fecha_out     IN DATE)
    RETURN NUMBER;

  FUNCTION fn_habitacion_disponible (p_id_habitacion IN habitacion.id%TYPE,
                                     p_fecha_in      IN DATE,
                                     p_fecha_out     IN DATE)
    RETURN VARCHAR2;

  FUNCTION fn_reserva_pagada (p_id_reserva IN reserva.id%TYPE)
    RETURN VARCHAR2;

  FUNCTION fn_calcular_reembolso (p_id_reserva        IN reserva.id%TYPE,
                                  p_fecha_cancelacion IN DATE DEFAULT SYSDATE)
    RETURN NUMBER;

  -- ---------------------------------------------------------------
  -- Procedimientos
  -- ---------------------------------------------------------------
  PROCEDURE sp_crear_reserva (p_id_cliente     IN  cliente.id%TYPE,
                              p_id_habitacion  IN  habitacion.id%TYPE,
                              p_fecha_in       IN  DATE,
                              p_fecha_out      IN  DATE,
                              p_num_huespedes  IN  NUMBER,
                              p_id_reserva     OUT reserva.id%TYPE);

  PROCEDURE sp_agregar_habitacion (p_id_reserva     IN  reserva.id%TYPE,
                                   p_id_habitacion  IN  habitacion.id%TYPE,
                                   p_fecha_in       IN  DATE,
                                   p_fecha_out      IN  DATE,
                                   p_num_huespedes  IN  NUMBER,
                                   p_id_linea       OUT reserva_habitacion.id%TYPE);

  PROCEDURE sp_recalcular_total (p_id_reserva IN reserva.id%TYPE);

  PROCEDURE sp_cancelar_reserva (p_id_reserva        IN  reserva.id%TYPE,
                                 p_fecha_cancelacion IN  DATE DEFAULT SYSDATE,
                                 p_reembolso         OUT NUMBER);

  PROCEDURE sp_liquidacion_mensual (p_anio IN NUMBER,
                                    p_mes  IN NUMBER);

  PROCEDURE sp_archivar_historico (p_fecha_corte IN  DATE,
                                   p_filas       OUT NUMBER);

END pkg_turismo;
/

/* =====================================================================
   CUERPO
   ===================================================================== */
CREATE OR REPLACE PACKAGE BODY pkg_turismo AS

  /* =================================================================
     SECCION 1. Utilidades privadas (no visibles fuera del paquete)
     ================================================================= */

  -- Id de un estado de PAGO_TOTAL a partir de su descripcion
  FUNCTION fn_id_estado_pago_total (p_descripcion IN VARCHAR2)
    RETURN estado_pago_total.id%TYPE
  IS
    v_id estado_pago_total.id%TYPE;
  BEGIN
    SELECT id INTO v_id
    FROM   estado_pago_total
    WHERE  UPPER(TRIM(descripcion)) = UPPER(TRIM(p_descripcion));
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_catalogo,
        'No existe el estado "' || p_descripcion || '" en ESTADO_PAGO_TOTAL');
  END fn_id_estado_pago_total;

  -- Valida que las dos fechas existan y que la salida sea posterior a la entrada
  PROCEDURE p_validar_fechas (p_fecha_in IN DATE, p_fecha_out IN DATE) IS
  BEGIN
    IF p_fecha_in IS NULL OR p_fecha_out IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_parametros,
        'Las fechas de check-in y check-out son obligatorias');
    END IF;

    IF TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
      RAISE_APPLICATION_ERROR(c_err_fechas,
        'El check-out (' || TO_CHAR(p_fecha_out, 'YYYY-MM-DD') ||
        ') debe ser posterior al check-in (' || TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ')');
    END IF;
  END p_validar_fechas;

  /* -----------------------------------------------------------------
     p_tarifa_noche: corazon del calculo por temporadas.
     Para UNA noche concreta devuelve la tarifa vigente y su valor.
       Paso 1: buscar la temporada cuyo rango [fecha_inicio, fecha_fin]
               contiene la noche (ambos extremos incluidos).
       Paso 2: buscar la tarifa de esa habitacion en esa temporada.
     Errores controlados:
       - ninguna temporada cubre la noche  -> -20010
       - dos temporadas cubren la noche    -> -20011 (temporadas mal
         definidas: la tarifa seria ambigua)
       - la habitacion no tiene tarifa en esa temporada -> -20012
     ----------------------------------------------------------------- */
  PROCEDURE p_tarifa_noche (p_id_habitacion IN  habitacion.id%TYPE,
                            p_noche         IN  DATE,
                            p_id_tarifa     OUT tarifa.id%TYPE,
                            p_valor_noche   OUT tarifa.valor_noche%TYPE)
  IS
    v_id_temporada temporada.id%TYPE;
  BEGIN
    -- Paso 1: temporada de la noche
    BEGIN
      SELECT id INTO v_id_temporada
      FROM   temporada
      WHERE  TRUNC(p_noche) BETWEEN TRUNC(fecha_inicio) AND TRUNC(fecha_fin);
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_sin_temporada,
          'No hay temporada definida para la noche del ' || TO_CHAR(p_noche, 'YYYY-MM-DD'));
      WHEN TOO_MANY_ROWS THEN
        RAISE_APPLICATION_ERROR(c_err_temporada_doble,
          'La noche del ' || TO_CHAR(p_noche, 'YYYY-MM-DD') ||
          ' pertenece a mas de una temporada (temporadas solapadas)');
    END;

    -- Paso 2: tarifa de la habitacion en esa temporada
    BEGIN
      SELECT id, valor_noche INTO p_id_tarifa, p_valor_noche
      FROM   tarifa
      WHERE  id_habitacion = p_id_habitacion
      AND    id_temporada  = v_id_temporada;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_sin_tarifa,
          'La habitacion ' || p_id_habitacion || ' no tiene tarifa para la temporada ' ||
          v_id_temporada || ' (noche del ' || TO_CHAR(p_noche, 'YYYY-MM-DD') || ')');
    END;
  END p_tarifa_noche;

  /* =================================================================
     SECCION 2. Funciones publicas
     ================================================================= */

  FUNCTION fn_id_estado_reserva (p_descripcion IN VARCHAR2)
    RETURN estado_reserva.id%TYPE
  IS
    v_id estado_reserva.id%TYPE;
  BEGIN
    SELECT id INTO v_id
    FROM   estado_reserva
    WHERE  UPPER(TRIM(descripcion)) = UPPER(TRIM(p_descripcion));
    RETURN v_id;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      RAISE_APPLICATION_ERROR(c_err_catalogo,
        'No existe el estado "' || p_descripcion || '" en ESTADO_RESERVA');
  END fn_id_estado_reserva;

  /* -----------------------------------------------------------------
     fn_valor_estadia(id_habitacion, fecha_in, fecha_out)

     Calcula el valor de una estadia aplicando, NOCHE POR NOCHE, la
     tarifa de la temporada vigente ese dia. Asi resuelve estadias que
     empiezan en una temporada y terminan en otra.

     Se cobran las noches desde fecha_in hasta fecha_out - 1: la noche
     del dia de salida no se cobra.
       Ej.: 20 al 26 de dic -> noches 20,21,22,23,24,25 (6 noches).
       Si el 24 empieza temporada alta:
         4 noches x tarifa media + 2 noches x tarifa alta.

     Algoritmo:
       total := 0
       noche := fecha_in
       MIENTRAS noche < fecha_out:
         total := total + tarifa(habitacion, temporada de "noche")
         noche := noche + 1
     ----------------------------------------------------------------- */
  FUNCTION fn_valor_estadia (p_id_habitacion IN habitacion.id%TYPE,
                             p_fecha_in      IN DATE,
                             p_fecha_out     IN DATE)
    RETURN NUMBER
  IS
    v_existe       PLS_INTEGER;
    v_noche        DATE;
    v_id_tarifa    tarifa.id%TYPE;
    v_valor_noche  tarifa.valor_noche%TYPE;
    v_total        NUMBER(14,2) := 0;
  BEGIN
    -- Validaciones previas
    p_validar_fechas(p_fecha_in, p_fecha_out);

    SELECT COUNT(*) INTO v_existe FROM habitacion WHERE id = p_id_habitacion;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_habitacion,
        'La habitacion ' || p_id_habitacion || ' no existe');
    END IF;

    -- Recorrido noche por noche
    v_noche := TRUNC(p_fecha_in);
    WHILE v_noche < TRUNC(p_fecha_out) LOOP
      p_tarifa_noche(p_id_habitacion, v_noche, v_id_tarifa, v_valor_noche);
      v_total := v_total + v_valor_noche;
      v_noche := v_noche + 1;
    END LOOP;

    RETURN v_total;
  END fn_valor_estadia;

  /* -----------------------------------------------------------------
     fn_habitacion_disponible: 'S' si la habitacion esta libre en
     [fecha_in, fecha_out), 'N' si choca con otra linea activa.

     Linea activa = la cabecera RESERVA y la linea RESERVA_HABITACION
     estan las dos en PENDIENTE o CONFIRMADA. Una pendiente tambien
     aparta la habitacion mientras se paga. Si la cabecera fue
     cancelada, sus lineas ya no ocupan aunque por error alguna siguiera
     marcada como activa.

     Dos rangos [a_in, a_out) y [b_in, b_out) se solapan si
          a_in < b_out  Y  a_out > b_in
     Con esta formula, salir el 26 y que otro entre el 26 NO es solape.
     ----------------------------------------------------------------- */
  FUNCTION fn_habitacion_disponible (p_id_habitacion IN habitacion.id%TYPE,
                                     p_fecha_in      IN DATE,
                                     p_fecha_out     IN DATE)
    RETURN VARCHAR2
  IS
    v_choques PLS_INTEGER;
  BEGIN
    SELECT COUNT(*) INTO v_choques
    FROM   reserva_habitacion rh
    JOIN   reserva r           ON r.id   = rh.id_reserva
    JOIN   estado_reserva erh  ON erh.id = r.id_estado_reserva
    JOIN   estado_reserva erl  ON erl.id = rh.id_estado_reserva
    WHERE  rh.id_habitacion = p_id_habitacion
    AND    UPPER(TRIM(erh.descripcion)) IN (c_est_pendiente, c_est_confirmada)
    AND    UPPER(TRIM(erl.descripcion)) IN (c_est_pendiente, c_est_confirmada)
    AND    rh.fecha_check_in  < TRUNC(p_fecha_out)
    AND    rh.fecha_check_out > TRUNC(p_fecha_in);

    RETURN CASE WHEN v_choques = 0 THEN 'S' ELSE 'N' END;
  END fn_habitacion_disponible;

  /* -----------------------------------------------------------------
     fn_reserva_pagada: 'S' cuando la suma de los pagos EXITOSOS
     cubre el total de la reserva (estadia + servicios), 'N' si no.
     ----------------------------------------------------------------- */
  FUNCTION fn_reserva_pagada (p_id_reserva IN reserva.id%TYPE)
    RETURN VARCHAR2
  IS
    v_total   pago_total.total%TYPE;
    v_pagado  NUMBER(14,2);
  BEGIN
    BEGIN
      SELECT total INTO v_total FROM pago_total WHERE id_reserva = p_id_reserva;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_reserva,
          'La reserva ' || p_id_reserva || ' no tiene registro en PAGO_TOTAL');
    END;

    SELECT NVL(SUM(p.monto), 0) INTO v_pagado
    FROM   pago p
    JOIN   pago_total  pt ON pt.id = p.id_pago_total
    JOIN   estado_pago ep ON ep.id = p.id_estado_pago
    WHERE  pt.id_reserva = p_id_reserva
    AND    UPPER(TRIM(ep.descripcion)) = c_pago_exitoso;

    RETURN CASE WHEN v_total IS NOT NULL AND v_pagado >= v_total THEN 'S' ELSE 'N' END;
  END fn_reserva_pagada;

  /* -----------------------------------------------------------------
     fn_calcular_reembolso: regla de cancelacion.
       dias de anticipacion = check-in - fecha de cancelacion
       dias > 5  -> 80 % de lo pagado con exito
       dias <= 5 -> 0   (incluye exactamente 5 dias y cancelar
                         despues del check-in)
     Se reembolsa sobre lo PAGADO, no sobre el total: si el cliente
     solo dio un anticipo, se le devuelve el 80 % del anticipo.
     ----------------------------------------------------------------- */
  FUNCTION fn_calcular_reembolso (p_id_reserva        IN reserva.id%TYPE,
                                  p_fecha_cancelacion IN DATE DEFAULT SYSDATE)
    RETURN NUMBER
  IS
    v_check_in  reserva.fecha_check_in%TYPE;
    v_dias      NUMBER;
    v_pagado    NUMBER(14,2);
  BEGIN
    BEGIN
      SELECT fecha_check_in INTO v_check_in FROM reserva WHERE id = p_id_reserva;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_reserva, 'La reserva ' || p_id_reserva || ' no existe');
    END;

    v_dias := TRUNC(v_check_in) - TRUNC(NVL(p_fecha_cancelacion, SYSDATE));

    SELECT NVL(SUM(p.monto), 0) INTO v_pagado
    FROM   pago p
    JOIN   pago_total  pt ON pt.id = p.id_pago_total
    JOIN   estado_pago ep ON ep.id = p.id_estado_pago
    WHERE  pt.id_reserva = p_id_reserva
    AND    UPPER(TRIM(ep.descripcion)) = c_pago_exitoso;

    IF v_dias > c_dias_min_reembolso THEN
      RETURN ROUND(v_pagado * c_pct_reembolso, 2);
    ELSE
      RETURN 0;
    END IF;
  END fn_calcular_reembolso;

  /* =================================================================
     SECCION 3. Creacion de reservas
     ================================================================= */

  /* -----------------------------------------------------------------
     p_insertar_linea (privado): valida e inserta UNA linea de reserva
     (RESERVA_HABITACION) y sus noches (RESERVA_NOCHE).
     Lo usan sp_crear_reserva y sp_agregar_habitacion, asi las reglas
     se escriben una sola vez.

     Orden de validacion:
       1. fechas (check-out > check-in)                  -> -20002
       2. la habitacion existe                           -> -20003
       3. la habitacion es del alojamiento de la reserva -> -20007
       4. huespedes > 0 y <= capacidad maxima            -> -20004
       5. la habitacion esta disponible en esas fechas   -> -20005
     Luego:
       6. valor_estadia := fn_valor_estadia(...)
       7. INSERT de la linea
       8. INSERT de una fila en RESERVA_NOCHE por noche, con la tarifa
          aplicada y su valor CONGELADO (si la tarifa cambia despues,
          la reserva conserva el precio con que se vendio).
     ----------------------------------------------------------------- */
  PROCEDURE p_insertar_linea (p_id_reserva      IN  reserva.id%TYPE,
                              p_id_alojamiento  IN  alojamiento.id%TYPE,
                              p_id_habitacion   IN  habitacion.id%TYPE,
                              p_fecha_in        IN  DATE,
                              p_fecha_out       IN  DATE,
                              p_num_huespedes   IN  NUMBER,
                              p_id_estado       IN  estado_reserva.id%TYPE,
                              p_id_linea        OUT reserva_habitacion.id%TYPE)
  IS
    v_capacidad    habitacion.capacidad_maxima%TYPE;
    v_aloj_hab     habitacion.id_alojamiento%TYPE;
    v_valor        reserva_habitacion.valor_estadia%TYPE;
    v_noche        DATE;
    v_id_tarifa    tarifa.id%TYPE;
    v_valor_noche  tarifa.valor_noche%TYPE;
  BEGIN
    -- 1. Fechas
    p_validar_fechas(p_fecha_in, p_fecha_out);

    -- 2. Habitacion
    BEGIN
      SELECT capacidad_maxima, id_alojamiento
      INTO   v_capacidad, v_aloj_hab
      FROM   habitacion
      WHERE  id = p_id_habitacion;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_habitacion,
          'La habitacion ' || p_id_habitacion || ' no existe');
    END;

    -- 3. Mismo alojamiento que la reserva
    IF v_aloj_hab <> p_id_alojamiento THEN
      RAISE_APPLICATION_ERROR(c_err_alojamiento,
        'La habitacion ' || p_id_habitacion || ' pertenece al alojamiento ' || v_aloj_hab ||
        ' y la reserva es del alojamiento ' || p_id_alojamiento);
    END IF;

    -- 4. Capacidad
    IF p_num_huespedes IS NULL OR p_num_huespedes <= 0 THEN
      RAISE_APPLICATION_ERROR(c_err_capacidad,
        'El numero de huespedes debe ser mayor que cero');
    ELSIF p_num_huespedes > v_capacidad THEN
      RAISE_APPLICATION_ERROR(c_err_capacidad,
        'Capacidad excedida: la habitacion ' || p_id_habitacion || ' admite ' ||
        v_capacidad || ' huespedes y se solicitaron ' || p_num_huespedes);
    END IF;

    -- 5. Disponibilidad
    IF fn_habitacion_disponible(p_id_habitacion, p_fecha_in, p_fecha_out) = 'N' THEN
      RAISE_APPLICATION_ERROR(c_err_no_disponible,
        'La habitacion ' || p_id_habitacion || ' no esta disponible entre el ' ||
        TO_CHAR(p_fecha_in, 'YYYY-MM-DD') || ' y el ' || TO_CHAR(p_fecha_out, 'YYYY-MM-DD'));
    END IF;

    -- 6. Valor de la estadia (cruzando temporadas)
    v_valor := fn_valor_estadia(p_id_habitacion, p_fecha_in, p_fecha_out);

    -- 7. Linea de la reserva
    --    La Entrega 1 define RESERVA_HABITACION.ID como IDENTITY.
    INSERT INTO reserva_habitacion
      (fecha_check_in, fecha_check_out, numero_huespedes, valor_estadia,
       fecha_cancelacion, id_reserva, id_habitacion, id_estado_reserva)
    VALUES
      (TRUNC(p_fecha_in), TRUNC(p_fecha_out), p_num_huespedes, v_valor,
       NULL, p_id_reserva, p_id_habitacion, p_id_estado)
    RETURNING id INTO p_id_linea;

    -- 8. Una fila por noche con la tarifa aplicada (valor congelado)
    v_noche := TRUNC(p_fecha_in);
    WHILE v_noche < TRUNC(p_fecha_out) LOOP
      p_tarifa_noche(p_id_habitacion, v_noche, v_id_tarifa, v_valor_noche);

      INSERT INTO reserva_noche (fecha, valor_noche, id_reserva_habitacion, id_tarifa)
      VALUES (v_noche, v_valor_noche, p_id_linea, v_id_tarifa);

      v_noche := v_noche + 1;
    END LOOP;
  END p_insertar_linea;

  /* -----------------------------------------------------------------
     sp_recalcular_total: deja PAGO_TOTAL coherente con la reserva.
       subtotal = suma de valor_estadia de las lineas NO canceladas
       total    = subtotal + servicios (cantidad x precio_unitario)
       estado   = PAGADO / ABONADO / PENDIENTE segun lo pagado

     El estado ABONADO es el que la carga de la Entrega 1 usa para un
     pago incompleto (no existe "PARCIAL" en ESTADO_PAGO_TOTAL).

     No se permite recalcular una reserva CANCELADA o COMPLETADA: en
     esos estados el valor es un dato historico y no debe cambiar. Para
     una reserva cancelada, la carga de la Entrega 1 conserva el total
     original aunque sus lineas esten canceladas; recalcularlo lo
     dejaria en cero.
     ----------------------------------------------------------------- */
  PROCEDURE sp_recalcular_total (p_id_reserva IN reserva.id%TYPE)
  IS
    v_estado_reserva estado_reserva.descripcion%TYPE;
    v_subtotal   NUMBER(14,2);
    v_servicios  NUMBER(14,2);
    v_pagado     NUMBER(14,2);
    v_estado     VARCHAR2(20);
    v_id_estado  estado_pago_total.id%TYPE;
  BEGIN
    -- La reserva debe existir y estar abierta
    BEGIN
      SELECT UPPER(TRIM(er.descripcion)) INTO v_estado_reserva
      FROM   reserva r
      JOIN   estado_reserva er ON er.id = r.id_estado_reserva
      WHERE  r.id = p_id_reserva;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_reserva,
          'La reserva ' || p_id_reserva || ' no existe');
    END;

    IF v_estado_reserva IN (c_est_cancelada, c_est_completada) THEN
      RAISE_APPLICATION_ERROR(c_err_estado_reserva,
        'No se puede recalcular una reserva ' || v_estado_reserva ||
        ': su valor ya quedo cerrado');
    END IF;

    SELECT NVL(SUM(rh.valor_estadia), 0) INTO v_subtotal
    FROM   reserva_habitacion rh
    JOIN   estado_reserva er ON er.id = rh.id_estado_reserva
    WHERE  rh.id_reserva = p_id_reserva
    AND    UPPER(TRIM(er.descripcion)) <> c_est_cancelada;

    SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0) INTO v_servicios
    FROM   reserva_servicio rs
    WHERE  rs.id_reserva = p_id_reserva;

    SELECT NVL(SUM(p.monto), 0) INTO v_pagado
    FROM   pago p
    JOIN   pago_total  pt ON pt.id = p.id_pago_total
    JOIN   estado_pago ep ON ep.id = p.id_estado_pago
    WHERE  pt.id_reserva = p_id_reserva
    AND    UPPER(TRIM(ep.descripcion)) = c_pago_exitoso;

    v_estado := CASE
                  WHEN v_pagado >= v_subtotal + v_servicios AND v_pagado > 0 THEN c_ept_pagado
                  WHEN v_pagado > 0                                         THEN c_ept_abonado
                  ELSE                                                           c_ept_pendiente
                END;

    -- Se traduce a id ANTES del UPDATE: una funcion privada del paquete
    -- no se puede invocar dentro de una sentencia SQL (PLS-00231).
    v_id_estado := fn_id_estado_pago_total(v_estado);

    UPDATE pago_total
    SET    subtotal             = v_subtotal,
           total                = v_subtotal + v_servicios,
           id_estado_pago_total = v_id_estado
    WHERE  id_reserva = p_id_reserva;

    -- Si la reserva aun no tenia PAGO_TOTAL, se crea.
    -- La Entrega 1 define PAGO_TOTAL.ID como IDENTITY: no se envía.
    IF SQL%ROWCOUNT = 0 THEN
      INSERT INTO pago_total (subtotal, total, id_reserva, id_estado_pago_total)
      VALUES (v_subtotal, v_subtotal + v_servicios, p_id_reserva, v_id_estado);
    END IF;
  END sp_recalcular_total;

  /* -----------------------------------------------------------------
     sp_crear_reserva: crea una reserva nueva de UNA habitacion.
       1. RESERVA (cabecera) en estado PENDIENTE
       2. RESERVA_HABITACION (linea) + RESERVA_NOCHE (noches)
       3. PAGO_TOTAL con el valor calculado
     Para un grupo, despues se llama sp_agregar_habitacion por cada
     habitacion adicional.

     Excepciones propias (RAISE_APPLICATION_ERROR):
       -20002 check-out anterior o igual al check-in
       -20004 capacidad excedida
       -20005 habitacion no disponible
       y ademas -20001, -20003, -20006, -20010..-20012

     Es ATOMICO: si cualquier paso falla, ROLLBACK TO SAVEPOINT deshace
     cabecera, linea y noches ya insertadas, y el error se relanza.
     ----------------------------------------------------------------- */
  PROCEDURE sp_crear_reserva (p_id_cliente     IN  cliente.id%TYPE,
                              p_id_habitacion  IN  habitacion.id%TYPE,
                              p_fecha_in       IN  DATE,
                              p_fecha_out      IN  DATE,
                              p_num_huespedes  IN  NUMBER,
                              p_id_reserva     OUT reserva.id%TYPE)
  IS
    v_existe        PLS_INTEGER;
    v_id_aloj       alojamiento.id%TYPE;
    v_id_pendiente  estado_reserva.id%TYPE;
    v_id_linea      reserva_habitacion.id%TYPE;
  BEGIN
    SAVEPOINT sp_crear_reserva_ini;

    -- Validaciones de cabecera (las de la linea las hace p_insertar_linea)
    p_validar_fechas(p_fecha_in, p_fecha_out);

    SELECT COUNT(*) INTO v_existe FROM cliente WHERE id = p_id_cliente;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(c_err_cliente, 'El cliente ' || p_id_cliente || ' no existe');
    END IF;

    BEGIN
      SELECT id_alojamiento INTO v_id_aloj FROM habitacion WHERE id = p_id_habitacion;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_habitacion,
          'La habitacion ' || p_id_habitacion || ' no existe');
    END;

    v_id_pendiente := fn_id_estado_reserva(c_est_pendiente);

    -- 1. Cabecera. La Entrega 1 define RESERVA.ID como IDENTITY.
    INSERT INTO reserva
      (fecha_creacion, fecha_check_in, fecha_check_out, fecha_cancelacion,
       id_cliente, id_alojamiento, id_estado_reserva)
    VALUES
      (SYSDATE, TRUNC(p_fecha_in), TRUNC(p_fecha_out), NULL,
       p_id_cliente, v_id_aloj, v_id_pendiente)
    RETURNING id INTO p_id_reserva;

    -- 2. Linea + noches (aqui se valida capacidad y disponibilidad)
    p_insertar_linea(p_id_reserva, v_id_aloj, p_id_habitacion,
                     p_fecha_in, p_fecha_out, p_num_huespedes,
                     v_id_pendiente, v_id_linea);

    -- 3. Total a pagar
    sp_recalcular_total(p_id_reserva);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_crear_reserva_ini;
      p_id_reserva := NULL;
      RAISE;
  END sp_crear_reserva;

  /* -----------------------------------------------------------------
     sp_agregar_habitacion: agrega una habitacion a una reserva
     existente (reservas de grupo). La linea puede tener fechas
     propias (alguien llega un dia despues) pero DENTRO del rango
     general de la reserva, y la habitacion debe ser del mismo
     alojamiento. La linea hereda el estado de la cabecera.
     ----------------------------------------------------------------- */
  PROCEDURE sp_agregar_habitacion (p_id_reserva     IN  reserva.id%TYPE,
                                   p_id_habitacion  IN  habitacion.id%TYPE,
                                   p_fecha_in       IN  DATE,
                                   p_fecha_out      IN  DATE,
                                   p_num_huespedes  IN  NUMBER,
                                   p_id_linea       OUT reserva_habitacion.id%TYPE)
  IS
    v_id_aloj    reserva.id_alojamiento%TYPE;
    v_res_in     reserva.fecha_check_in%TYPE;
    v_res_out    reserva.fecha_check_out%TYPE;
    v_id_estado  reserva.id_estado_reserva%TYPE;
    v_estado     estado_reserva.descripcion%TYPE;
  BEGIN
    SAVEPOINT sp_agregar_hab_ini;

    p_validar_fechas(p_fecha_in, p_fecha_out);

    -- Cabecera bloqueada (FOR UPDATE) para que nadie la cambie mientras tanto
    BEGIN
      SELECT r.id_alojamiento, r.fecha_check_in, r.fecha_check_out,
             r.id_estado_reserva, UPPER(TRIM(er.descripcion))
      INTO   v_id_aloj, v_res_in, v_res_out, v_id_estado, v_estado
      FROM   reserva r
      JOIN   estado_reserva er ON er.id = r.id_estado_reserva
      WHERE  r.id = p_id_reserva
      FOR UPDATE OF r.id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_reserva, 'La reserva ' || p_id_reserva || ' no existe');
    END;

    IF v_estado NOT IN (c_est_pendiente, c_est_confirmada) THEN
      RAISE_APPLICATION_ERROR(c_err_estado_reserva,
        'No se pueden agregar habitaciones a una reserva en estado ' || v_estado);
    END IF;

    IF TRUNC(p_fecha_in) < v_res_in OR TRUNC(p_fecha_out) > v_res_out THEN
      RAISE_APPLICATION_ERROR(c_err_rango_linea,
        'Las fechas de la habitacion deben estar dentro del rango de la reserva (' ||
        TO_CHAR(v_res_in, 'YYYY-MM-DD') || ' a ' || TO_CHAR(v_res_out, 'YYYY-MM-DD') || ')');
    END IF;

    p_insertar_linea(p_id_reserva, v_id_aloj, p_id_habitacion,
                     p_fecha_in, p_fecha_out, p_num_huespedes,
                     v_id_estado, p_id_linea);

    sp_recalcular_total(p_id_reserva);
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_agregar_hab_ini;
      p_id_linea := NULL;
      RAISE;
  END sp_agregar_habitacion;

  /* -----------------------------------------------------------------
     sp_cancelar_reserva: cancela la reserva completa (cabecera y
     lineas activas), registra la fecha de cancelacion y devuelve el
     reembolso segun la regla del 80 % / 0 %.

     El reembolso NO se queda solo en una variable: se registra como un
     movimiento MAS en PAGO con estado REEMBOLSADO. Asi lo modela la
     carga de la Entrega 1 y asi lo suma la consulta 7 de la E1
     (ESTADO_PAGO = 'reembolsado'). El metodo de pago es el del ultimo
     pago exitoso y el monto es positivo: representa lo devuelto.

     Despues se actualiza PAGO_TOTAL:
       con reembolso -> REEMBOLSADO
       sin reembolso -> CANCELADO
     Son exactamente los dos estados que usa la carga de la E1 para las
     reservas canceladas.

     Al quedar las lineas en CANCELADA, la habitacion se libera.
     ----------------------------------------------------------------- */
  PROCEDURE sp_cancelar_reserva (p_id_reserva        IN  reserva.id%TYPE,
                                 p_fecha_cancelacion IN  DATE DEFAULT SYSDATE,
                                 p_reembolso         OUT NUMBER)
  IS
    v_estado          estado_reserva.descripcion%TYPE;
    v_id_cancelada    estado_reserva.id%TYPE;
    v_estado_ept      VARCHAR2(20);
    v_id_estado_ept   estado_pago_total.id%TYPE;
    v_id_pago_total   pago_total.id%TYPE;
    v_id_metodo       pago.id_metodo_pago%TYPE;
    v_id_estado_pago  pago.id_estado_pago%TYPE;
    v_fecha           DATE := TRUNC(NVL(p_fecha_cancelacion, SYSDATE));
  BEGIN
    SAVEPOINT sp_cancelar_ini;

    BEGIN
      SELECT UPPER(TRIM(er.descripcion)) INTO v_estado
      FROM   reserva r
      JOIN   estado_reserva er ON er.id = r.id_estado_reserva
      WHERE  r.id = p_id_reserva
      FOR UPDATE OF r.id;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(c_err_reserva, 'La reserva ' || p_id_reserva || ' no existe');
    END;

    IF v_estado IN (c_est_cancelada, c_est_completada) THEN
      RAISE_APPLICATION_ERROR(c_err_estado_reserva,
        'Una reserva ' || v_estado || ' no se puede cancelar');
    END IF;

    p_reembolso    := fn_calcular_reembolso(p_id_reserva, v_fecha);
    v_id_cancelada := fn_id_estado_reserva(c_est_cancelada);

    UPDATE reserva
    SET    id_estado_reserva = v_id_cancelada,
           fecha_cancelacion = v_fecha
    WHERE  id = p_id_reserva;

    UPDATE reserva_habitacion
    SET    id_estado_reserva = v_id_cancelada,
           fecha_cancelacion = v_fecha
    WHERE  id_reserva = p_id_reserva
    AND    id_estado_reserva <> v_id_cancelada;

    -- Registro contable del reembolso (solo si hay algo que devolver)
    IF p_reembolso > 0 THEN
      BEGIN
        SELECT id INTO v_id_pago_total
        FROM   pago_total
        WHERE  id_reserva = p_id_reserva;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(c_err_reserva,
            'La reserva ' || p_id_reserva || ' tiene pagos pero no registro en PAGO_TOTAL');
      END;

      -- Metodo del ultimo pago exitoso (el reembolso se devuelve por la
      -- misma via en que entro el dinero)
      BEGIN
        SELECT p.id_metodo_pago INTO v_id_metodo
        FROM   pago p
        JOIN   pago_total  pt ON pt.id = p.id_pago_total
        JOIN   estado_pago ep ON ep.id = p.id_estado_pago
        WHERE  pt.id_reserva = p_id_reserva
        AND    UPPER(TRIM(ep.descripcion)) = c_pago_exitoso
        ORDER  BY p.fecha DESC, p.id DESC
        FETCH FIRST 1 ROWS ONLY;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(c_err_reserva,
            'No hay un pago exitoso del cual tomar el metodo para el reembolso');
      END;

      BEGIN
        SELECT id INTO v_id_estado_pago
        FROM   estado_pago
        WHERE  UPPER(TRIM(descripcion)) = c_pago_reembolsado;
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(c_err_catalogo,
            'No existe el estado "' || c_pago_reembolsado || '" en ESTADO_PAGO');
      END;

      INSERT INTO pago (fecha, monto, id_pago_total, id_metodo_pago, id_estado_pago)
      VALUES (v_fecha, p_reembolso, v_id_pago_total, v_id_metodo, v_id_estado_pago);

      v_estado_ept := c_ept_reembolsado;
    ELSE
      v_estado_ept := c_ept_cancelado;
    END IF;

    v_id_estado_ept := fn_id_estado_pago_total(v_estado_ept);

    UPDATE pago_total
    SET    id_estado_pago_total = v_id_estado_ept
    WHERE  id_reserva = p_id_reserva;
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_cancelar_ini;
      p_reembolso := NULL;
      RAISE;
  END sp_cancelar_reserva;

  /* =================================================================
     SECCION 4. Proceso masivo: liquidacion mensual por alojamiento
     ================================================================= */

  /* -----------------------------------------------------------------
     sp_liquidacion_mensual(anio, mes)

     Usa un CURSOR EXPLICITO CON PARAMETROS (c_liquidacion) que recibe
     el primer dia del mes y el primer dia del mes siguiente, y devuelve
     UNA FILA POR ALOJAMIENTO (LEFT JOIN: tambien los que no vendieron).

     Que se liquida (mismo criterio que las consultas de la Entrega 1):
       - Estadia: noches de RESERVA_NOCHE que caen dentro del mes, de
         lineas cuya CABECERA esta CONFIRMADA o COMPLETADA y cuya LINEA
         no esta CANCELADA. Se usa el valor_noche congelado. Si una
         estadia va del 30 de enero al 3 de febrero, 2 noches se
         liquidan en enero y 2 en febrero: cada mes recibe exactamente
         lo que le corresponde.
         El filtro de cabecera es importante: si un grupo cancela una
         sola habitacion, esa linea queda CANCELADA pero la cabecera
         sigue activa; y una cabecera cancelada nunca debe liquidar,
         aunque alguna linea haya quedado mal marcada.
       - Servicios: de las reservas confirmadas o completadas cuyo
         check-in cae en el mes (un servicio no tiene fecha propia).

     Cada fila del cursor se procesa con OPEN / FETCH / EXIT WHEN
     %NOTFOUND / CLOSE y se guarda en LIQUIDACION_MENSUAL. Antes se
     borra la liquidacion previa del mismo mes, asi el proceso se puede
     repetir sin duplicar (y sin violar el UNIQUE).
     El borrado y la re-insercion van dentro de un SAVEPOINT: si una
     fila falla, se restaura la liquidacion anterior completa y no queda
     un mes a medio liquidar.
     ----------------------------------------------------------------- */
  PROCEDURE sp_liquidacion_mensual (p_anio IN NUMBER,
                                    p_mes  IN NUMBER)
  IS
    CURSOR c_liquidacion (p_desde DATE, p_hasta DATE) IS
      SELECT a.id                         AS id_alojamiento,
             a.nombre_comercial           AS nombre_comercial,
             NVL(est.noches, 0)           AS noches_ocupadas,
             NVL(est.reservas, 0)         AS num_reservas,
             NVL(est.ingreso, 0)          AS ingreso_estadia,
             NVL(srv.ingreso, 0)          AS ingreso_servicios
      FROM   alojamiento a
      LEFT JOIN (
             SELECT r.id_alojamiento,
                    COUNT(*)               AS noches,
                    COUNT(DISTINCT r.id)   AS reservas,
                    SUM(rn.valor_noche)    AS ingreso
             FROM   reserva_noche rn
             JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
             JOIN   reserva r             ON r.id  = rh.id_reserva
             JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
             JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
             WHERE  rn.fecha >= p_desde
             AND    rn.fecha <  p_hasta
             AND    UPPER(TRIM(erh.descripcion)) IN (c_est_confirmada, c_est_completada)
             AND    UPPER(TRIM(erl.descripcion)) <> c_est_cancelada
             GROUP  BY r.id_alojamiento
           ) est ON est.id_alojamiento = a.id
      LEFT JOIN (
             SELECT r.id_alojamiento,
                    SUM(rs.cantidad * rs.precio_unitario) AS ingreso
             FROM   reserva_servicio rs
             JOIN   reserva r          ON r.id  = rs.id_reserva
             JOIN   estado_reserva erh ON erh.id = r.id_estado_reserva
             WHERE  r.fecha_check_in >= p_desde
             AND    r.fecha_check_in <  p_hasta
             AND    UPPER(TRIM(erh.descripcion)) IN (c_est_confirmada, c_est_completada)
             GROUP  BY r.id_alojamiento
           ) srv ON srv.id_alojamiento = a.id
      ORDER  BY a.id;

    v_fila         c_liquidacion%ROWTYPE;
    v_desde        DATE;
    v_hasta        DATE;
    v_procesados   PLS_INTEGER  := 0;
    v_con_ventas   PLS_INTEGER  := 0;
    v_gran_total   NUMBER(16,2) := 0;
  BEGIN
    SAVEPOINT sp_liquidacion_ini;

    -- Validacion del periodo
    IF p_anio IS NULL OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12
       OR p_anio NOT BETWEEN 2000 AND 2100 THEN
      RAISE_APPLICATION_ERROR(c_err_periodo,
        'Periodo invalido: anio=' || p_anio || ', mes=' || p_mes);
    END IF;

    v_desde := TO_DATE(TO_CHAR(p_anio) || '-' || LPAD(TO_CHAR(p_mes), 2, '0') || '-01', 'YYYY-MM-DD');
    v_hasta := ADD_MONTHS(v_desde, 1);

    -- Reproceso: se reemplaza la liquidacion anterior del mismo mes
    DELETE FROM liquidacion_mensual WHERE anio = p_anio AND mes = p_mes;

    DBMS_OUTPUT.PUT_LINE('=== Liquidacion ' || TO_CHAR(v_desde, 'YYYY-MM') || ' ===');

    OPEN c_liquidacion(v_desde, v_hasta);
    LOOP
      FETCH c_liquidacion INTO v_fila;
      EXIT WHEN c_liquidacion%NOTFOUND;

      INSERT INTO liquidacion_mensual
        (anio, mes, id_alojamiento, noches_ocupadas, num_reservas,
         ingreso_estadia, ingreso_servicios, ingreso_total, fecha_generacion)
      VALUES
        (p_anio, p_mes, v_fila.id_alojamiento, v_fila.noches_ocupadas, v_fila.num_reservas,
         v_fila.ingreso_estadia, v_fila.ingreso_servicios,
         v_fila.ingreso_estadia + v_fila.ingreso_servicios, SYSDATE);

      v_procesados := v_procesados + 1;
      IF v_fila.noches_ocupadas > 0 OR v_fila.ingreso_servicios > 0 THEN
        v_con_ventas := v_con_ventas + 1;
      END IF;
      v_gran_total := v_gran_total + v_fila.ingreso_estadia + v_fila.ingreso_servicios;
    END LOOP;
    CLOSE c_liquidacion;

    DBMS_OUTPUT.PUT_LINE('Alojamientos liquidados : ' || v_procesados);
    DBMS_OUTPUT.PUT_LINE('Alojamientos con ventas : ' || v_con_ventas);
    DBMS_OUTPUT.PUT_LINE('Ingreso total del mes   : ' ||
                         TO_CHAR(v_gran_total, 'FM999,999,999,990.00'));
  EXCEPTION
    WHEN OTHERS THEN
      IF c_liquidacion%ISOPEN THEN
        CLOSE c_liquidacion;
      END IF;
      ROLLBACK TO sp_liquidacion_ini;
      RAISE;
  END sp_liquidacion_mensual;

  /* =================================================================
     SECCION 5. Historico (tablespace TS_TURISMOUQ_HIST)
     ================================================================= */

  /* -----------------------------------------------------------------
     sp_archivar_historico: copia a RESERVA_HISTORICO las lineas
     cerradas (cabecera y linea COMPLETADAS o CANCELADAS) cuyo check-out
     es anterior a la fecha de corte y que aun no estaban archivadas (se
     puede correr varias veces sin duplicar).
     Se exige que la CABECERA tambien este cerrada: una linea cancelada
     dentro de una reserva activa (un grupo que cancela una sola
     habitacion) todavia pertenece a la operacion y no se archiva.
     Decision: se COPIAN, no se borran de las tablas operativas, porque
     PAGO, RESENA, RESERVA_NOCHE y las consultas de la Entrega 1
     dependen de ellas. En produccion el paso siguiente seria purgar
     las operativas una vez verificado el historico.
     ----------------------------------------------------------------- */
  PROCEDURE sp_archivar_historico (p_fecha_corte IN  DATE,
                                   p_filas       OUT NUMBER)
  IS
  BEGIN
    IF p_fecha_corte IS NULL THEN
      RAISE_APPLICATION_ERROR(c_err_parametros, 'La fecha de corte es obligatoria');
    END IF;

    INSERT INTO reserva_historico
      (id_reserva_habitacion, id_reserva, fecha_creacion, id_cliente,
       numero_documento, nombre_cliente, id_alojamiento, nombre_alojamiento,
       municipio, tipo_alojamiento, id_habitacion, numero_habitacion,
       fecha_check_in, fecha_check_out, noches, numero_huespedes,
       valor_estadia, estado, fecha_cancelacion, fecha_archivo)
    SELECT rh.id, r.id, r.fecha_creacion, c.id,
           c.numero_documento, c.nombres || ' ' || c.apellidos, a.id, a.nombre_comercial,
           ci.nombre, ta.nombre, h.id, h.numero,
           rh.fecha_check_in, rh.fecha_check_out,
           rh.fecha_check_out - rh.fecha_check_in, rh.numero_huespedes,
           rh.valor_estadia, UPPER(TRIM(er.descripcion)), rh.fecha_cancelacion, SYSDATE
    FROM   reserva_habitacion rh
    JOIN   reserva r            ON r.id  = rh.id_reserva
    JOIN   cliente c            ON c.id  = r.id_cliente
    JOIN   habitacion h         ON h.id  = rh.id_habitacion
    JOIN   alojamiento a        ON a.id  = h.id_alojamiento
    JOIN   ciudad ci            ON ci.id = a.id_ciudad
    JOIN   tipo_alojamiento ta  ON ta.id = a.id_tipo_alojamiento
    JOIN   estado_reserva er    ON er.id = rh.id_estado_reserva
    JOIN   estado_reserva erh   ON erh.id = r.id_estado_reserva
    WHERE  UPPER(TRIM(er.descripcion))  IN (c_est_completada, c_est_cancelada)
    AND    UPPER(TRIM(erh.descripcion)) IN (c_est_completada, c_est_cancelada)
    AND    rh.fecha_check_out < TRUNC(p_fecha_corte)
    AND    NOT EXISTS (SELECT 1
                       FROM   reserva_historico hi
                       WHERE  hi.id_reserva_habitacion = rh.id);

    p_filas := SQL%ROWCOUNT;
  END sp_archivar_historico;

END pkg_turismo;
/

-- Verificacion: ambos objetos deben quedar VALID
SELECT object_name, object_type, status
FROM   user_objects
WHERE  object_name = 'PKG_TURISMO';

-- Si alguno queda INVALID, aqui sale la linea y el error exacto
SELECT name, type, line, position, text
FROM   user_errors
WHERE  name = 'PKG_TURISMO'
ORDER  BY type, sequence;
