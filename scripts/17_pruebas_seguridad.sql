/* =====================================================================
   TurismoUQ - Entrega 3
   Script 17: PRUEBAS DE SEGURIDAD (evidencia)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA (TURISMOUQ), despues de
   los scripts 12 y 15 y 16. Se conecta, uno por uno, como cada usuario
   de demostracion y comprueba que:
     - lo permitido FUNCIONA, y
     - lo prohibido FALLA con el error de Oracle esperado.
   Cada prueba imprime OK o FALLA.

   Pide dos datos:
     - la clave de los usuarios de demostracion (la misma del script 16)
     - el servicio de la PDB (por defecto localhost:1521/FREEPDB1)

   Errores esperados
     ORA-00942  la tabla o vista no existe (para quien no tiene privilegio
                SELECT, Oracle no revela que el objeto exista)
     ORA-01031  privilegios insuficientes (el objeto es visible pero la
                operacion no esta concedida). En Oracle 23ai/26ai el mismo
                caso puede salir como ORA-41900 ("missing UPDATE/DELETE/
                INSERT privilege on ..."): son equivalentes y las pruebas
                aceptan los dos.
     Nota: SET SERVEROUTPUT se repite despues de cada CONNECT porque la
     nueva sesion arranca con la salida de DBMS_OUTPUT desactivada.
   Al terminar queda conectado como el ultimo usuario de prueba; las
   pruebas que modifican datos hacen ROLLBACK.
   ===================================================================== */
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET PAGESIZE 100
SET FEEDBACK OFF
SET SQLBLANKLINES ON
SET DEFINE ON

ACCEPT clave_demo CHAR PROMPT 'Clave de los usuarios de demostracion: ' HIDE
ACCEPT servicio   CHAR DEFAULT 'localhost:1521/FREEPDB1' PROMPT 'Servicio de la PDB [localhost:1521/FREEPDB1]: '

VARIABLE esp_ospina_hab    NUMBER
VARIABLE esp_restrepo_hab  NUMBER
VARIABLE total_hab         NUMBER
VARIABLE esp_ospina_tar    NUMBER
VARIABLE id_tarifa_propia  NUMBER
VARIABLE id_tarifa_ajena   NUMBER

/* ---------------------------------------------------------------------
   P0. Valores esperados, calculados como DUEÑO (ve las tablas)
   --------------------------------------------------------------------- */
BEGIN
  SELECT COUNT(*) INTO :total_hab FROM habitacion;

  SELECT COUNT(*) INTO :esp_ospina_hab
  FROM   habitacion h
  WHERE  h.id_alojamiento = (SELECT id_alojamiento FROM usuario_sistema WHERE username = 'enc.ospina');

  SELECT COUNT(*) INTO :esp_restrepo_hab
  FROM   habitacion h
  WHERE  h.id_alojamiento = (SELECT id_alojamiento FROM usuario_sistema WHERE username = 'enc.restrepo');

  -- Una tarifa del alojamiento de Ospina y una de otro alojamiento
  SELECT MIN(t.id) INTO :id_tarifa_propia
  FROM   tarifa t JOIN habitacion h ON h.id = t.id_habitacion
  WHERE  h.id_alojamiento = (SELECT id_alojamiento FROM usuario_sistema WHERE username = 'enc.ospina');

  SELECT MIN(t.id) INTO :id_tarifa_ajena
  FROM   tarifa t JOIN habitacion h ON h.id = t.id_habitacion
  WHERE  h.id_alojamiento <> (SELECT id_alojamiento FROM usuario_sistema WHERE username = 'enc.ospina');

  DBMS_OUTPUT.PUT_LINE('Habitaciones en total: ' || :total_hab ||
                       ' | de Ospina: ' || :esp_ospina_hab ||
                       ' | de Restrepo: ' || :esp_restrepo_hab);
END;
/

/* =====================================================================
   RECEPCION  (REC_PRUEBA)
   ===================================================================== */
PROMPT
PROMPT ===== RECEPCION (rec_prueba) =====
CONNECT rec_prueba/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  v_n NUMBER;

  -- Ejecuta una sentencia y espera un resultado: 0 = debe funcionar,
  -- otro numero = codigo ORA que debe producir
  PROCEDURE probar (p_nombre VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
    v_codigo NUMBER := 0;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_codigo := ABS(SQLCODE);
    END;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 62) ||
      CASE WHEN v_codigo = p_esperado OR (p_esperado = 1031 AND v_codigo = 41900) THEN 'OK'
           ELSE 'FALLA (esperado ' || p_esperado || ', obtenido ' || v_codigo || ')' END);
  END probar;
BEGIN
  probar('Lee V_REC_RESERVAS (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_rec_reservas', 0);
  probar('Lee V_REC_CLIENTES (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_rec_clientes', 0);
  probar('Lee V_REC_HABITACIONES (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_rec_habitaciones', 0);

  -- Lo que NO debe poder hacer: tocar las tablas
  probar('SELECT sobre la TABLA reserva',
         'SELECT COUNT(*) FROM turismouq.reserva', 942);
  probar('SELECT sobre la TABLA cliente',
         'SELECT COUNT(*) FROM turismouq.cliente', 942);
  probar('SELECT sobre la TABLA pago',
         'SELECT COUNT(*) FROM turismouq.pago', 942);
  probar('SELECT sobre la TABLA tarifa',
         'SELECT COUNT(*) FROM turismouq.tarifa', 942);
  probar('INSERT en la TABLA reserva',
         'INSERT INTO turismouq.reserva (fecha_creacion, fecha_check_in, fecha_check_out, id_cliente, id_alojamiento, id_estado_reserva) VALUES (SYSDATE, SYSDATE, SYSDATE+1, 1, 1, 1)', 942);
  probar('DELETE en la TABLA cliente',
         'DELETE FROM turismouq.cliente', 942);
  probar('UPDATE sobre la VISTA v_rec_clientes (solo lectura)',
         'UPDATE turismouq.v_rec_clientes SET nombres = ''X''', 1031);
  probar('Lee la tabla de auditoria',
         'SELECT COUNT(*) FROM turismouq.auditoria_tarifa', 942);
  probar('Lee las vistas del gerente (V_GER_INGRESOS)',
         'SELECT COUNT(*) FROM turismouq.v_ger_ingresos', 942);

  -- EXECUTE concedido: el procedimiento se ejecuta (falla por la logica,
  -- no por permisos: cliente inexistente = ORA-20006)
  probar('Ejecuta SP_RESERVAR_Y_PAGAR (cliente inexistente -> ORA-20006)',
         'DECLARE a NUMBER; b NUMBER; c VARCHAR2(400); BEGIN ' ||
         'turismouq.sp_reservar_y_pagar(-1, 1, DATE ''2026-12-01'', DATE ''2026-12-03'', 2, 1, 100000, ''S'', ''N'', a, b, c); END;',
         20006);
  probar('Ejecuta PKG_TURISMO directamente (no concedido)',
         'DECLARE a NUMBER; BEGIN turismouq.pkg_turismo.sp_crear_reserva(1, 1, SYSDATE, SYSDATE+1, 1, a); END;',
         6550);
END;
/

/* =====================================================================
   ADMINISTRADOR DE ALOJAMIENTO  (ENC_OSPINA, ENC_RESTREPO, ENC_MARIN)
   ===================================================================== */
PROMPT
PROMPT ===== ADMINISTRADOR DE ALOJAMIENTO (enc_ospina) =====
CONNECT enc_ospina/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED

DECLARE
  v_n      NUMBER;
  v_antes  NUMBER;
  v_desp   NUMBER;

  PROCEDURE probar (p_nombre VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
    v_codigo NUMBER := 0;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_codigo := ABS(SQLCODE);
    END;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 62) ||
      CASE WHEN v_codigo = p_esperado OR (p_esperado = 1031 AND v_codigo = 41900) THEN 'OK'
           ELSE 'FALLA (esperado ' || p_esperado || ', obtenido ' || v_codigo || ')' END);
  END probar;
BEGIN
  -- Seguridad a nivel de fila: solo ve las habitaciones de SU alojamiento
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM turismouq.v_adm_habitaciones' INTO v_n;
  DBMS_OUTPUT.PUT_LINE(RPAD('Ve SOLO sus habitaciones (' || v_n || ' de ' || :total_hab || ')', 62) ||
    CASE WHEN v_n = :esp_ospina_hab AND v_n < :total_hab THEN 'OK' ELSE 'FALLA' END);

  probar('Lee V_ADM_RESERVAS (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_adm_reservas', 0);

  -- Cambiar una tarifa PROPIA: permitido
  EXECUTE IMMEDIATE 'SELECT valor_noche FROM turismouq.v_adm_tarifas WHERE id = :1'
    INTO v_antes USING :id_tarifa_propia;
  EXECUTE IMMEDIATE 'UPDATE turismouq.v_adm_tarifas SET valor_noche = valor_noche + 1000 WHERE id = :1'
    USING :id_tarifa_propia;
  EXECUTE IMMEDIATE 'SELECT valor_noche FROM turismouq.v_adm_tarifas WHERE id = :1'
    INTO v_desp USING :id_tarifa_propia;
  DBMS_OUTPUT.PUT_LINE(RPAD('Actualiza el valor de una tarifa PROPIA', 62) ||
    CASE WHEN v_desp = v_antes + 1000 THEN 'OK' ELSE 'FALLA' END);
  ROLLBACK;

  -- Tarifa de OTRO alojamiento: la vista la oculta, no actualiza nada
  EXECUTE IMMEDIATE 'UPDATE turismouq.v_adm_tarifas SET valor_noche = 1 WHERE id = :1'
    USING :id_tarifa_ajena;
  DBMS_OUTPUT.PUT_LINE(RPAD('Actualiza tarifa de OTRO alojamiento (0 filas afectadas)', 62) ||
    CASE WHEN SQL%ROWCOUNT = 0 THEN 'OK' ELSE 'FALLA' END);
  ROLLBACK;

  probar('Cambia la habitacion de una tarifa (columna no concedida)',
         'UPDATE turismouq.v_adm_tarifas SET id_habitacion = id_habitacion', 1031);
  probar('DELETE sobre v_adm_tarifas',
         'DELETE FROM turismouq.v_adm_tarifas', 1031);
  probar('INSERT sobre v_adm_tarifas',
         'INSERT INTO turismouq.v_adm_tarifas (id_habitacion, id_temporada, valor_noche) VALUES (1, 1, 1)', 1031);
  probar('SELECT sobre la TABLA tarifa',
         'SELECT COUNT(*) FROM turismouq.tarifa', 942);
  probar('SELECT sobre la TABLA reserva',
         'SELECT COUNT(*) FROM turismouq.reserva', 942);
  probar('Lee las vistas de recepcion (V_REC_RESERVAS)',
         'SELECT COUNT(*) FROM turismouq.v_rec_reservas', 942);
  probar('Lee las vistas del auditor (V_AUD_PAGOS)',
         'SELECT COUNT(*) FROM turismouq.v_aud_pagos', 942);
END;
/

PROMPT
PROMPT ===== ADMINISTRADOR DE ALOJAMIENTO (enc_restrepo): otro alojamiento, otros datos =====
CONNECT enc_restrepo/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_n NUMBER;
  v_propia NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM turismouq.v_adm_habitaciones' INTO v_n;
  DBMS_OUTPUT.PUT_LINE(RPAD('Ve SOLO sus habitaciones (' || v_n || ')', 62) ||
    CASE WHEN v_n = :esp_restrepo_hab THEN 'OK' ELSE 'FALLA' END);

  -- La tarifa de Ospina no existe para Restrepo
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM turismouq.v_adm_tarifas WHERE id = :1'
    INTO v_propia USING :id_tarifa_propia;
  DBMS_OUTPUT.PUT_LINE(RPAD('No ve las tarifas del alojamiento de Ospina', 62) ||
    CASE WHEN v_propia = 0 THEN 'OK' ELSE 'FALLA' END);
END;
/

PROMPT
PROMPT ===== ENCARGADO INACTIVO (enc_marin, activo = N): conecta pero no ve nada =====
CONNECT enc_marin/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  v_h NUMBER;
  v_r NUMBER;
BEGIN
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM turismouq.v_adm_habitaciones' INTO v_h;
  EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM turismouq.v_adm_reservas'     INTO v_r;
  DBMS_OUTPUT.PUT_LINE(RPAD('Encargado inactivo: habitaciones=' || v_h || ', reservas=' || v_r, 62) ||
    CASE WHEN v_h = 0 AND v_r = 0 THEN 'OK' ELSE 'FALLA' END);
END;
/

/* =====================================================================
   GERENTE  (GER_PRUEBA)
   ===================================================================== */
PROMPT
PROMPT ===== GERENTE (ger_prueba) =====
CONNECT ger_prueba/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  PROCEDURE probar (p_nombre VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
    v_codigo NUMBER := 0;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_codigo := ABS(SQLCODE);
    END;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 62) ||
      CASE WHEN v_codigo = p_esperado OR (p_esperado = 1031 AND v_codigo = 41900) THEN 'OK'
           ELSE 'FALLA (esperado ' || p_esperado || ', obtenido ' || v_codigo || ')' END);
  END probar;
BEGIN
  probar('Lee V_GER_OCUPACION (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_ger_ocupacion', 0);
  probar('Lee V_GER_INGRESOS (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_ger_ingresos', 0);
  probar('Lee V_GER_CALIFICACIONES (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_ger_calificaciones', 0);
  probar('SELECT sobre la TABLA liquidacion_mensual',
         'SELECT COUNT(*) FROM turismouq.liquidacion_mensual', 942);
  probar('SELECT sobre la vista MV_OCUPACION_MENSUAL',
         'SELECT COUNT(*) FROM turismouq.mv_ocupacion_mensual', 942);
  probar('DELETE sobre v_ger_ingresos',
         'DELETE FROM turismouq.v_ger_ingresos', 1031);
  probar('Lee datos de pagos (V_AUD_PAGOS)',
         'SELECT COUNT(*) FROM turismouq.v_aud_pagos', 942);
  probar('Lee clientes (V_REC_CLIENTES)',
         'SELECT COUNT(*) FROM turismouq.v_rec_clientes', 942);
END;
/

/* =====================================================================
   AUDITOR  (AUD_PRUEBA)
   ===================================================================== */
PROMPT
PROMPT ===== AUDITOR (aud_prueba) =====
CONNECT aud_prueba/"&clave_demo"@&servicio
SET SERVEROUTPUT ON SIZE UNLIMITED
DECLARE
  PROCEDURE probar (p_nombre VARCHAR2, p_sql VARCHAR2, p_esperado NUMBER) IS
    v_codigo NUMBER := 0;
  BEGIN
    BEGIN
      EXECUTE IMMEDIATE p_sql;
    EXCEPTION
      WHEN OTHERS THEN v_codigo := ABS(SQLCODE);
    END;
    DBMS_OUTPUT.PUT_LINE(RPAD(p_nombre, 62) ||
      CASE WHEN v_codigo = p_esperado OR (p_esperado = 1031 AND v_codigo = 41900) THEN 'OK'
           ELSE 'FALLA (esperado ' || p_esperado || ', obtenido ' || v_codigo || ')' END);
  END probar;
BEGIN
  probar('Lee V_AUD_AUDITORIA_TARIFA (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_aud_auditoria_tarifa', 0);
  probar('Lee V_AUD_PAGOS (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_aud_pagos', 0);
  probar('Lee V_AUD_RESERVAS (permitido)',
         'SELECT COUNT(*) FROM turismouq.v_aud_reservas', 0);
  probar('DELETE sobre v_aud_auditoria_tarifa (borrar la auditoria)',
         'DELETE FROM turismouq.v_aud_auditoria_tarifa', 1031);
  probar('UPDATE sobre v_aud_pagos',
         'UPDATE turismouq.v_aud_pagos SET monto = 0', 1031);
  probar('SELECT sobre la TABLA auditoria_tarifa',
         'SELECT COUNT(*) FROM turismouq.auditoria_tarifa', 942);
  probar('SELECT sobre la TABLA pago',
         'SELECT COUNT(*) FROM turismouq.pago', 942);
  probar('Lee vistas del gerente (V_GER_INGRESOS)',
         'SELECT COUNT(*) FROM turismouq.v_ger_ingresos', 942);
  probar('Ejecuta SP_RESERVAR_Y_PAGAR',
         'DECLARE a NUMBER; b NUMBER; c VARCHAR2(400); BEGIN ' ||
         'turismouq.sp_reservar_y_pagar(1, 1, DATE ''2026-12-01'', DATE ''2026-12-03'', 2, 1, 100000, ''S'', ''N'', a, b, c); END;',
         6550);
END;
/

PROMPT
PROMPT Pruebas de seguridad terminadas. Buscar en la salida: ningun FALLA.
UNDEFINE clave_demo
