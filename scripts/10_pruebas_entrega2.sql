/* =====================================================================
   TurismoUQ - Entrega 2
   Script 10: PRUEBAS (evidencia de funcionamiento)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA, despues de 05 a 09.
   En SQL Developer: "Ejecutar script" (F5).
   En SQL*Plus    : @10_pruebas_entrega2.sql

   - Los datos de prueba se buscan en la propia base (no hay ids fijos):
     una habitacion con tarifa en dos temporadas consecutivas y libre
     alrededor del corte de temporada.
   - Cada prueba imprime OK o FALLA y el motivo.
   - Al final se hace ROLLBACK: las pruebas no dejan basura en la base.
     La vista materializada se prueba DESPUES del ROLLBACK porque
     DBMS_MVIEW.REFRESH hace COMMIT implicito.
   - Los PROMPT no terminan en guion: en SQL*Plus un guion final indica
     continuacion de linea y se comeria el SELECT siguiente.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 200
SET VERIFY OFF
SET FEEDBACK ON
SET SQLBLANKLINES ON

VARIABLE g_hab        NUMBER
VARIABLE g_hab2       NUMBER
VARIABLE g_aloj       NUMBER
VARIABLE g_corte      VARCHAR2(10)
VARIABLE g_v1         NUMBER
VARIABLE g_v2         NUMBER
VARIABLE g_cliente    NUMBER
VARIABLE g_esperado   NUMBER
VARIABLE g_pago       NUMBER
VARIABLE g_reserva    NUMBER
VARIABLE g_reserva2   NUMBER
VARIABLE g_anio       NUMBER
VARIABLE g_mes        NUMBER

/* =====================================================================
   P0. PREPARACION: escoger datos reales para las pruebas
   Se busca un "corte de temporada": dos temporadas consecutivas te1 y
   te2 (te2 empieza el dia siguiente al fin de te1) donde una habitacion
   tiene tarifas DISTINTAS, capacidad >= 2 y esta libre 4 noches antes
   y 4 noches despues del corte.
   ===================================================================== */
DECLARE
  v_hab    NUMBER;
  v_hab2   NUMBER;
  v_aloj   NUMBER;
  v_te1    NUMBER;
  v_te2    NUMBER;
  v_corte  DATE;
  v_v1     NUMBER;
  v_v2     NUMBER;
  v_total  NUMBER;
BEGIN
  SELECT h.id, h.id_alojamiento, te1.id, te2.id, te2.fecha_inicio, t1.valor_noche, t2.valor_noche
  INTO   v_hab, v_aloj, v_te1, v_te2, v_corte, v_v1, v_v2
  FROM   temporada te1
  JOIN   temporada te2 ON te2.fecha_inicio = te1.fecha_fin + 1
  JOIN   tarifa t1     ON t1.id_temporada = te1.id
  JOIN   tarifa t2     ON t2.id_temporada = te2.id AND t2.id_habitacion = t1.id_habitacion
  JOIN   habitacion h  ON h.id = t1.id_habitacion
  WHERE  t1.valor_noche <> t2.valor_noche
  AND    te1.fecha_fin - te1.fecha_inicio >= 4
  AND    te2.fecha_fin - te2.fecha_inicio >= 4
  AND    h.capacidad_maxima >= 2
  AND    pkg_turismo.fn_habitacion_disponible(h.id, te2.fecha_inicio - 4, te2.fecha_inicio + 4) = 'S'
  ORDER  BY te2.fecha_inicio DESC, h.id
  FETCH FIRST 1 ROWS ONLY;

  -- Segunda habitacion del MISMO alojamiento (para la reserva de grupo)
  BEGIN
    SELECT h2.id INTO v_hab2
    FROM   habitacion h2
    WHERE  h2.id_alojamiento = v_aloj
    AND    h2.id <> v_hab
    AND    EXISTS (SELECT 1 FROM tarifa t WHERE t.id_habitacion = h2.id AND t.id_temporada = v_te1)
    AND    EXISTS (SELECT 1 FROM tarifa t WHERE t.id_habitacion = h2.id AND t.id_temporada = v_te2)
    AND    pkg_turismo.fn_habitacion_disponible(h2.id, v_corte - 3, v_corte + 2) = 'S'
    ORDER  BY h2.id
    FETCH FIRST 1 ROWS ONLY;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN v_hab2 := NULL;
  END;

  SELECT MIN(id) INTO :g_cliente FROM cliente;

  v_total := pkg_turismo.fn_valor_estadia(v_hab, v_corte - 4, v_corte + 2);

  :g_hab      := v_hab;
  :g_hab2     := v_hab2;
  :g_aloj     := v_aloj;
  :g_corte    := TO_CHAR(v_corte, 'YYYY-MM-DD');
  :g_v1       := v_v1;
  :g_v2       := v_v2;
  :g_esperado := v_total;
  -- Pago parcial: la mitad del total, con tope de 100.000, para que
  -- siempre sea MENOR que el total y el estado quede en ABONADO.
  :g_pago     := LEAST(100000, ROUND(v_total / 2, 2));

  DBMS_OUTPUT.PUT_LINE('=== P0. Datos escogidos para las pruebas ===');
  DBMS_OUTPUT.PUT_LINE('Habitacion            : ' || v_hab || ' (alojamiento ' || v_aloj || ')');
  DBMS_OUTPUT.PUT_LINE('Segunda habitacion    : ' || NVL(TO_CHAR(v_hab2), 'no hay'));
  DBMS_OUTPUT.PUT_LINE('Corte de temporada    : ' || TO_CHAR(v_corte, 'YYYY-MM-DD') ||
                       ' (temporada ' || v_te1 || ' -> ' || v_te2 || ')');
  DBMS_OUTPUT.PUT_LINE('Tarifa antes del corte: ' || v_v1);
  DBMS_OUTPUT.PUT_LINE('Tarifa desde el corte : ' || v_v2);
  DBMS_OUTPUT.PUT_LINE('Cliente               : ' || :g_cliente);
  DBMS_OUTPUT.PUT_LINE('Total de la estadia   : ' || v_total);
  DBMS_OUTPUT.PUT_LINE('Pago parcial de prueba: ' || :g_pago);
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    DBMS_OUTPUT.PUT_LINE('P0 FALLA: no se encontro un corte de temporada con una habitacion libre. ' ||
                         'Revisar que TEMPORADA tenga temporadas consecutivas y TARIFA este cargada.');
    RAISE;
END;
/

/* =====================================================================
   T1. fn_valor_estadia CRUZANDO TEMPORADAS
   Estadia: (corte - 4) a (corte + 2) = 6 noches
     4 noches con la tarifa de te1 + 2 noches con la tarifa de te2
   Se compara contra DOS calculos independientes:
     a) formula manual 4*v1 + 2*v2
     b) una consulta SQL que genera las 6 noches y suma sus tarifas
   ===================================================================== */
PROMPT
PROMPT === T1. Detalle noche por noche de la estadia de prueba ===
SELECT d.noche,
       te.nombre        AS temporada,
       tt.nombre        AS tipo,
       t.valor_noche
FROM   (SELECT TO_DATE(:g_corte, 'YYYY-MM-DD') - 4 + LEVEL - 1 AS noche
        FROM   dual CONNECT BY LEVEL <= 6) d
JOIN   temporada te      ON d.noche BETWEEN te.fecha_inicio AND te.fecha_fin
JOIN   tipo_temporada tt ON tt.id = te.id_tipo_temporada
JOIN   tarifa t          ON t.id_temporada = te.id AND t.id_habitacion = :g_hab
ORDER  BY d.noche;

DECLARE
  v_corte   DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_fn      NUMBER;
  v_manual  NUMBER;
  v_sql     NUMBER;
BEGIN
  v_fn     := pkg_turismo.fn_valor_estadia(:g_hab, v_corte - 4, v_corte + 2);
  v_manual := 4 * :g_v1 + 2 * :g_v2;

  SELECT SUM(t.valor_noche) INTO v_sql
  FROM   (SELECT v_corte - 4 + LEVEL - 1 AS noche FROM dual CONNECT BY LEVEL <= 6) d
  JOIN   temporada te ON d.noche BETWEEN te.fecha_inicio AND te.fecha_fin
  JOIN   tarifa t     ON t.id_temporada = te.id AND t.id_habitacion = :g_hab;

  :g_esperado := v_manual;

  DBMS_OUTPUT.PUT_LINE('=== T1. fn_valor_estadia cruzando temporadas ===');
  DBMS_OUTPUT.PUT_LINE('Funcion        : ' || v_fn);
  DBMS_OUTPUT.PUT_LINE('4*v1 + 2*v2    : ' || v_manual);
  DBMS_OUTPUT.PUT_LINE('Consulta SQL   : ' || v_sql);
  DBMS_OUTPUT.PUT_LINE('Precio unico v1: ' || 6 * :g_v1 || '  (incorrecto)');
  DBMS_OUTPUT.PUT_LINE('Precio unico v2: ' || 6 * :g_v2 || '  (incorrecto)');
  IF v_fn = v_manual AND v_fn = v_sql THEN
    DBMS_OUTPUT.PUT_LINE('T1 OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('T1 FALLA');
  END IF;
END;
/

/* =====================================================================
   T2 y T3. fn_valor_estadia: errores controlados
   ===================================================================== */
DECLARE
  v NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T2. fn_valor_estadia con check-out = check-in (espera -20002) ===');
  v := pkg_turismo.fn_valor_estadia(:g_hab, TO_DATE(:g_corte, 'YYYY-MM-DD'), TO_DATE(:g_corte, 'YYYY-MM-DD'));
  DBMS_OUTPUT.PUT_LINE('T2 FALLA: no se lanzo error');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20002 THEN 'T2 OK: ' ELSE 'T2 FALLA: ' END || SQLERRM);
END;
/

DECLARE
  v NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T3. fn_valor_estadia en fechas sin temporada (espera -20010) ===');
  v := pkg_turismo.fn_valor_estadia(:g_hab, DATE '2099-01-01', DATE '2099-01-03');
  DBMS_OUTPUT.PUT_LINE('T3 FALLA: no se lanzo error');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20010 THEN 'T3 OK: ' ELSE 'T3 FALLA: ' END || SQLERRM);
END;
/

/* =====================================================================
   T4. sp_crear_reserva: caso exitoso cruzando temporadas
   Verifica: 6 filas en RESERVA_NOCHE, valor_estadia = valor esperado,
   PAGO_TOTAL creado con ese total y estado PENDIENTE.
   ===================================================================== */
DECLARE
  v_corte   DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_id      NUMBER;
  v_noches  NUMBER;
  v_valor   NUMBER;
  v_subtotal NUMBER;
  v_total   NUMBER;
  v_estado  VARCHAR2(20);
  v_ept     VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T4. sp_crear_reserva exitosa ===');
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab, v_corte - 4, v_corte + 2, 2, v_id);
  :g_reserva := v_id;

  SELECT COUNT(*) INTO v_noches
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  WHERE  rh.id_reserva = v_id;

  SELECT valor_estadia INTO v_valor FROM reserva_habitacion WHERE id_reserva = v_id;
  SELECT pt.subtotal, pt.total, e.descripcion
  INTO   v_subtotal, v_total, v_ept
  FROM   pago_total pt
  JOIN   estado_pago_total e ON e.id = pt.id_estado_pago_total
  WHERE  pt.id_reserva = v_id;

  SELECT er.descripcion INTO v_estado
  FROM   reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva
  WHERE  r.id = v_id;

  DBMS_OUTPUT.PUT_LINE('Reserva creada : ' || v_id || ' (' || v_estado || ')');
  DBMS_OUTPUT.PUT_LINE('Noches         : ' || v_noches || ' (esperado 6)');
  DBMS_OUTPUT.PUT_LINE('Valor estadia  : ' || v_valor || ' (esperado ' || :g_esperado || ')');
  DBMS_OUTPUT.PUT_LINE('PAGO_TOTAL     : subtotal ' || v_subtotal || ', total ' || v_total ||
                       ', estado ' || v_ept);
  IF v_noches = 6
     AND v_valor = :g_esperado
     AND v_subtotal = :g_esperado
     AND v_total = :g_esperado
     AND UPPER(v_estado) = 'PENDIENTE'
     AND UPPER(v_ept) = 'PENDIENTE' THEN
    DBMS_OUTPUT.PUT_LINE('T4 OK');
  ELSE
    DBMS_OUTPUT.PUT_LINE('T4 FALLA');
  END IF;
END;
/

PROMPT === T4. Noches registradas (valor congelado por noche) ===
SELECT rn.fecha, te.nombre AS temporada, rn.valor_noche, rn.id_tarifa
FROM   reserva_noche rn
JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
JOIN   tarifa t              ON t.id  = rn.id_tarifa
JOIN   temporada te          ON te.id = t.id_temporada
WHERE  rh.id_reserva = :g_reserva
ORDER  BY rn.fecha;

/* =====================================================================
   T5, T6, T7. sp_crear_reserva: las tres excepciones pedidas
   T7 ademas demuestra la atomicidad: el procedimiento alcanza a
   insertar la cabecera antes de detectar el choque, y el ROLLBACK TO
   SAVEPOINT la deshace (el conteo de reservas no cambia).
   ===================================================================== */
DECLARE
  v_id NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T5. Check-out anterior al check-in (espera -20002) ===');
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab,
                               TO_DATE(:g_corte, 'YYYY-MM-DD') + 5,
                               TO_DATE(:g_corte, 'YYYY-MM-DD') + 3, 1, v_id);
  DBMS_OUTPUT.PUT_LINE('T5 FALLA: no se lanzo error');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20002 THEN 'T5 OK: ' ELSE 'T5 FALLA: ' END || SQLERRM);
END;
/

DECLARE
  v_id   NUMBER;
  v_cap  NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T6. Capacidad excedida (espera -20004) ===');
  SELECT capacidad_maxima INTO v_cap FROM habitacion WHERE id = :g_hab;
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab,
                               TO_DATE(:g_corte, 'YYYY-MM-DD') + 10,
                               TO_DATE(:g_corte, 'YYYY-MM-DD') + 12, v_cap + 1, v_id);
  DBMS_OUTPUT.PUT_LINE('T6 FALLA: no se lanzo error');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20004 THEN 'T6 OK: ' ELSE 'T6 FALLA: ' END || SQLERRM);
END;
/

DECLARE
  v_id       NUMBER;
  v_antes    NUMBER;
  v_despues  NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T7. Habitacion no disponible (espera -20005) ===');
  SELECT COUNT(*) INTO v_antes FROM reserva;
  BEGIN
    pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab,
                                 TO_DATE(:g_corte, 'YYYY-MM-DD') - 1,
                                 TO_DATE(:g_corte, 'YYYY-MM-DD') + 1, 1, v_id);
    DBMS_OUTPUT.PUT_LINE('T7 FALLA: no se lanzo error');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20005 THEN 'T7 OK: ' ELSE 'T7 FALLA: ' END || SQLERRM);
  END;
  SELECT COUNT(*) INTO v_despues FROM reserva;
  DBMS_OUTPUT.PUT_LINE('Reservas antes/despues: ' || v_antes || ' / ' || v_despues ||
                       CASE WHEN v_antes = v_despues THEN '  -> OK, no quedo cabecera huerfana'
                            ELSE '  -> FALLA, quedo una cabecera' END);
END;
/

/* =====================================================================
   T8. DISPARADOR DE FILA TRG_RH_NO_SOLAPE con un caso real
   Se inserta DIRECTAMENTE en las tablas (saltandose el paquete) una
   reserva CONFIRMADA que se cruza con la de T4. El disparador debe
   rechazarla con -20005 y el mensaje [TRG_RH_NO_SOLAPE].
   ===================================================================== */
DECLARE
  v_corte  DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_conf   NUMBER;
  v_res    NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T8. Trigger de fila: insercion directa solapada (espera -20005) ===');
  SAVEPOINT t8_ini;
  v_conf := pkg_turismo.fn_id_estado_reserva('CONFIRMADA');

  INSERT INTO reserva (fecha_creacion, fecha_check_in, fecha_check_out,
                       id_cliente, id_alojamiento, id_estado_reserva)
  VALUES (SYSDATE, v_corte - 1, v_corte + 1, :g_cliente, :g_aloj, v_conf)
  RETURNING id INTO v_res;

  INSERT INTO reserva_habitacion (fecha_check_in, fecha_check_out, numero_huespedes,
                                  valor_estadia, id_reserva, id_habitacion, id_estado_reserva)
  VALUES (v_corte - 1, v_corte + 1, 1, 100000, v_res, :g_hab, v_conf);

  DBMS_OUTPUT.PUT_LINE('T8 FALLA: el disparador no impidio el solape');
  ROLLBACK TO t8_ini;
EXCEPTION
  WHEN OTHERS THEN
    ROLLBACK TO t8_ini;
    DBMS_OUTPUT.PUT_LINE(
      CASE WHEN SQLCODE = -20005 AND INSTR(SQLERRM, 'TRG_RH_NO_SOLAPE') > 0
           THEN 'T8 OK: ' ELSE 'T8 FALLA: ' END || SQLERRM);
END;
/

/* =====================================================================
   T9. Frontera: entrar el MISMO dia en que sale la reserva de T4 NO es
   solape. Debe crearse sin error.
   ===================================================================== */
DECLARE
  v_corte DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_id    NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T9. Check-in el dia del check-out de otra reserva (espera exito) ===');
  pkg_turismo.sp_crear_reserva(:g_cliente, :g_hab, v_corte + 2, v_corte + 4, 1, v_id);
  :g_reserva2 := v_id;
  DBMS_OUTPUT.PUT_LINE('T9 OK: reserva ' || v_id || ' creada del ' ||
                       TO_CHAR(v_corte + 2, 'YYYY-MM-DD') || ' al ' || TO_CHAR(v_corte + 4, 'YYYY-MM-DD'));
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('T9 FALLA: ' || SQLERRM);
END;
/

/* =====================================================================
   T10. Reserva de grupo: segunda habitacion que llega UN DIA DESPUES
   (corte-3 a corte+2, dentro del rango corte-4 a corte+2), y un intento
   fuera del rango de la reserva (espera -20008).
   ===================================================================== */
DECLARE
  v_corte  DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_linea  NUMBER;
  v_total  NUMBER;
  v_suma   NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T10. sp_agregar_habitacion (reserva de grupo) ===');
  IF :g_hab2 IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('T10 OMITIDA: el alojamiento no tiene una segunda habitacion libre');
  ELSE
    pkg_turismo.sp_agregar_habitacion(:g_reserva, :g_hab2, v_corte - 3, v_corte + 2, 1, v_linea);

    SELECT SUM(valor_estadia) INTO v_suma FROM reserva_habitacion WHERE id_reserva = :g_reserva;
    SELECT total INTO v_total FROM pago_total WHERE id_reserva = :g_reserva;

    DBMS_OUTPUT.PUT_LINE('Linea agregada : ' || v_linea);
    DBMS_OUTPUT.PUT_LINE('Suma lineas    : ' || v_suma || ' / Total PAGO_TOTAL: ' || v_total);
    DBMS_OUTPUT.PUT_LINE(CASE WHEN v_suma = v_total THEN 'T10a OK' ELSE 'T10a FALLA' END);

    BEGIN
      pkg_turismo.sp_agregar_habitacion(:g_reserva, :g_hab2, v_corte - 6, v_corte - 4, 1, v_linea);
      DBMS_OUTPUT.PUT_LINE('T10b FALLA: no se lanzo error');
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20008 THEN 'T10b OK: ' ELSE 'T10b FALLA: ' END || SQLERRM);
    END;
  END IF;
END;
/

PROMPT === T10. Lineas de la reserva de grupo ===
SELECT rh.id, rh.id_habitacion, rh.fecha_check_in, rh.fecha_check_out,
       rh.numero_huespedes, rh.valor_estadia
FROM   reserva_habitacion rh
WHERE  rh.id_reserva = :g_reserva
ORDER  BY rh.id;

/* =====================================================================
   T11. DISPARADOR DE SENTENCIA: auditoria de TARIFA
   a) Un solo UPDATE modifica todas las tarifas de la habitacion. Deben
      aparecer en AUDITORIA_TARIFA tantas filas como tarifas cambiaron,
      con usuario, equipo, fecha, valor anterior y nuevo.
   b) Demuestra el VALOR CONGELADO: la reserva de T4 conserva su precio
      aunque la tarifa haya subido.
   c) Prueba tambien los INSERT y DELETE: el disparador audita las tres
      operaciones, no solo el UPDATE.
   ===================================================================== */
PROMPT
PROMPT === T11. Auditoria de TARIFA (sube 10.000 todas las tarifas de la habitacion) ===
UPDATE tarifa SET valor_noche = valor_noche + 10000 WHERE id_habitacion = :g_hab;

SELECT * FROM (
  SELECT id_tarifa, id_temporada, operacion, valor_anterior, valor_nuevo,
         usuario_bd, usuario_so, equipo,
         TO_CHAR(fecha_cambio, 'YYYY-MM-DD HH24:MI:SS') AS fecha_cambio
  FROM   auditoria_tarifa
  WHERE  id_habitacion = :g_hab
  ORDER  BY id
) WHERE ROWNUM <= 8;

SELECT operacion, COUNT(*) AS filas_auditadas
FROM   auditoria_tarifa
WHERE  id_habitacion = :g_hab
GROUP  BY operacion
ORDER  BY operacion;

DECLARE
  v_corte    DATE := TO_DATE(:g_corte, 'YYYY-MM-DD');
  v_audit    NUMBER;
  v_tarifas  NUMBER;
  v_guardado NUMBER;
  v_nuevo    NUMBER;
  v_temporada NUMBER;
  v_tipo     NUMBER;
  v_valor    NUMBER := 123456;
  v_ins      NUMBER;
  v_del      NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T11. Verificacion ===');
  SELECT COUNT(*) INTO v_tarifas FROM tarifa WHERE id_habitacion = :g_hab;
  SELECT COUNT(*) INTO v_audit
  FROM   auditoria_tarifa
  WHERE  id_habitacion = :g_hab AND operacion = 'UPDATE' AND valor_nuevo = valor_anterior + 10000;
  DBMS_OUTPUT.PUT_LINE('Tarifas de la habitacion: ' || v_tarifas || ' / filas auditadas: ' || v_audit);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_audit = v_tarifas THEN 'T11a OK' ELSE 'T11a FALLA' END);

  SELECT valor_estadia INTO v_guardado
  FROM   reserva_habitacion
  WHERE  id_reserva = :g_reserva AND id_habitacion = :g_hab;
  v_nuevo := pkg_turismo.fn_valor_estadia(:g_hab, v_corte - 4, v_corte + 2);
  DBMS_OUTPUT.PUT_LINE('Valor guardado en la reserva: ' || v_guardado ||
                       ' / valor con la tarifa nueva: ' || v_nuevo);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_guardado = :g_esperado AND v_nuevo = :g_esperado + 60000
                            THEN 'T11b OK: el precio vendido quedo congelado'
                            ELSE 'T11b FALLA' END);

  -- c) INSERT y DELETE sobre TARIFA. La carga tiene una tarifa por cada
  --    cruce habitacion x temporada, asi que para probar el INSERT se
  --    crea una temporada temporal (2099) y su tarifa; luego se borran.
  --    Todo queda dentro de la transaccion y se deshace con el ROLLBACK.
  SELECT MIN(id) INTO v_tipo FROM tipo_temporada;

  INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada)
  VALUES ('Temporada temporal de prueba', DATE '2099-01-01', DATE '2099-01-05', v_tipo)
  RETURNING id INTO v_temporada;

  INSERT INTO tarifa (valor_noche, id_habitacion, id_temporada)
  VALUES (v_valor, :g_hab, v_temporada);

  SELECT COUNT(*) INTO v_ins
  FROM   auditoria_tarifa
  WHERE  id_habitacion = :g_hab AND id_temporada = v_temporada
  AND    operacion = 'INSERT' AND valor_nuevo = v_valor AND valor_anterior IS NULL;

  DELETE FROM tarifa
  WHERE  id_habitacion = :g_hab AND id_temporada = v_temporada;

  SELECT COUNT(*) INTO v_del
  FROM   auditoria_tarifa
  WHERE  id_habitacion = :g_hab AND id_temporada = v_temporada
  AND    operacion = 'DELETE' AND valor_anterior = v_valor AND valor_nuevo IS NULL;

  DELETE FROM temporada WHERE id = v_temporada;

  DBMS_OUTPUT.PUT_LINE('Auditoria INSERT/DELETE (temporada temporal ' || v_temporada || '): ' ||
                       v_ins || '/' || v_del || ' (esperado 1/1)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_ins = 1 AND v_del = 1 THEN 'T11c OK' ELSE 'T11c FALLA' END);
END;
/

/* =====================================================================
   T12. Pago parcial, cancelacion y regla de reembolso
   a) Un pago exitoso menor que el total deja PAGO_TOTAL en ABONADO
      (no en "PARCIAL": ese estado no existe en la carga de la E1).
   b) La regla devuelve 80 % con MAS de 5 dias y 0 % con 5 o menos.
   c) sp_cancelar_reserva registra el reembolso como fila de PAGO con
      estado REEMBOLSADO y deja PAGO_TOTAL en REEMBOLSADO.
   d) Una cabecera cancelada libera la habitacion aunque alguna linea
      haya quedado mal marcada (se prueba y se restaura con SAVEPOINT).
   ===================================================================== */
DECLARE
  v_check_in  DATE := TO_DATE(:g_corte, 'YYYY-MM-DD') - 4;
  v_res       NUMBER := :g_reserva;
  v_reemb     NUMBER;
  v_estado    VARCHAR2(20);
  v_lineas    NUMBER;
  v_ept       VARCHAR2(20);
  v_total_pt  NUMBER;
  v_total_antes NUMBER;
  v_reemb_n   NUMBER;
  v_reemb_m   NUMBER;
  v_reemb_esp NUMBER := ROUND(:g_pago * 0.80, 2);
  v_disp      VARCHAR2(1);
  v_id_canc   NUMBER;
  v_id_conf   NUMBER;

  PROCEDURE probar (p_dias NUMBER, p_esperado NUMBER) IS
    v NUMBER;
  BEGIN
    v := pkg_turismo.fn_calcular_reembolso(v_res, v_check_in - p_dias);
    DBMS_OUTPUT.PUT_LINE('  ' || p_dias || ' dias antes -> reembolso ' || v ||
                         CASE WHEN v = p_esperado THEN '  OK' ELSE '  FALLA (esperado ' || p_esperado || ')' END);
  END probar;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T12. Pago parcial, reembolso y cancelacion ===');

  -- Total antes del abono: debe quedar igual despues de recalcular.
  -- (OJO: T10 agrego una segunda habitacion, por eso NO se compara
  -- contra :g_esperado, que es solo el valor de la primera linea.)
  SELECT total INTO v_total_antes FROM pago_total WHERE id_reserva = :g_reserva;

  INSERT INTO pago (fecha, monto, id_pago_total, id_metodo_pago, id_estado_pago)
  VALUES (SYSDATE, :g_pago,
          (SELECT id FROM pago_total WHERE id_reserva = :g_reserva),
          (SELECT MIN(id) FROM metodo_pago),
          (SELECT id FROM estado_pago WHERE UPPER(TRIM(descripcion)) = 'EXITOSO'));

  -- a) Pago parcial -> ABONADO
  pkg_turismo.sp_recalcular_total(:g_reserva);
  SELECT e.descripcion, pt.total
  INTO   v_ept, v_total_pt
  FROM   pago_total pt
  JOIN   estado_pago_total e ON e.id = pt.id_estado_pago_total
  WHERE  pt.id_reserva = :g_reserva;
  DBMS_OUTPUT.PUT_LINE('Pagado ' || :g_pago || ' de ' || v_total_pt ||
                       ' -> PAGO_TOTAL: ' || v_ept || ' (esperado ABONADO)');
  DBMS_OUTPUT.PUT_LINE('Reserva pagada?: ' || pkg_turismo.fn_reserva_pagada(:g_reserva) ||
                       ' (esperado N)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN UPPER(v_ept) = 'ABONADO'
                             AND v_total_pt = v_total_antes
                             AND pkg_turismo.fn_reserva_pagada(:g_reserva) = 'N'
                            THEN 'T12a OK' ELSE 'T12a FALLA' END);

  -- b) Regla del 80 % / 0 %
  probar(10, v_reemb_esp);
  probar(6,  v_reemb_esp);
  probar(5,  0);
  probar(2,  0);

  -- c) Cancelacion
  pkg_turismo.sp_cancelar_reserva(:g_reserva, v_check_in - 10, v_reemb);

  SELECT er.descripcion INTO v_estado
  FROM   reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva
  WHERE  r.id = :g_reserva;
  SELECT COUNT(*) INTO v_lineas
  FROM   reserva_habitacion rh JOIN estado_reserva er ON er.id = rh.id_estado_reserva
  WHERE  rh.id_reserva = :g_reserva AND UPPER(TRIM(er.descripcion)) <> 'CANCELADA';

  SELECT e.descripcion, pt.total
  INTO   v_ept, v_total_pt
  FROM   pago_total pt
  JOIN   estado_pago_total e ON e.id = pt.id_estado_pago_total
  WHERE  pt.id_reserva = :g_reserva;

  SELECT COUNT(*), NVL(SUM(p.monto), 0)
  INTO   v_reemb_n, v_reemb_m
  FROM   pago p
  JOIN   pago_total  pt ON pt.id = p.id_pago_total
  JOIN   estado_pago ep ON ep.id = p.id_estado_pago
  WHERE  pt.id_reserva = :g_reserva
  AND    UPPER(TRIM(ep.descripcion)) = 'REEMBOLSADO';

  DBMS_OUTPUT.PUT_LINE('sp_cancelar_reserva -> reembolso ' || v_reemb || ', estado ' || v_estado ||
                       ', lineas sin cancelar ' || v_lineas);
  DBMS_OUTPUT.PUT_LINE('PAGO_TOTAL: ' || v_ept || ', total ' || v_total_pt ||
                       ' (el total original no se altera)');
  DBMS_OUTPUT.PUT_LINE('Filas de reembolso en PAGO: ' || v_reemb_n || ', monto ' || v_reemb_m);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_reemb = v_reemb_esp
                             AND UPPER(v_estado) = 'CANCELADA'
                             AND v_lineas = 0
                             AND UPPER(v_ept) = 'REEMBOLSADO'
                             AND v_total_pt = v_total_antes
                             AND v_reemb_n = 1
                             AND v_reemb_m = v_reemb_esp
                            THEN 'T12b OK' ELSE 'T12b FALLA' END);

  DBMS_OUTPUT.PUT_LINE('Habitacion liberada?: ' ||
                       pkg_turismo.fn_habitacion_disponible(:g_hab, v_check_in, v_check_in + 6) ||
                       ' (esperado S)');

  -- d) Cabecera cancelada + linea activa: no debe ocupar
  SAVEPOINT t12d_ini;
  SELECT id INTO v_id_conf FROM estado_reserva WHERE UPPER(TRIM(descripcion)) = 'CONFIRMADA';
  SELECT id INTO v_id_canc FROM estado_reserva WHERE UPPER(TRIM(descripcion)) = 'CANCELADA';
  UPDATE reserva_habitacion
  SET    id_estado_reserva = v_id_conf
  WHERE  id_reserva = :g_reserva
  AND    id_habitacion = :g_hab;
  v_disp := pkg_turismo.fn_habitacion_disponible(:g_hab, v_check_in, v_check_in + 6);
  DBMS_OUTPUT.PUT_LINE('Cabecera CANCELADA con linea CONFIRMADA -> disponible: ' || v_disp ||
                       ' (esperado S)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_disp = 'S' THEN 'T12c OK' ELSE 'T12c FALLA' END);
  ROLLBACK TO t12d_ini;

  -- e) No se puede cancelar dos veces ni recalcular una reserva cerrada
  BEGIN
    pkg_turismo.sp_cancelar_reserva(:g_reserva, v_check_in - 10, v_reemb);
    DBMS_OUTPUT.PUT_LINE('T12d FALLA: permitio cancelar dos veces');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20009 THEN 'T12d OK: ' ELSE 'T12d FALLA: ' END || SQLERRM);
  END;

  BEGIN
    pkg_turismo.sp_recalcular_total(:g_reserva);
    DBMS_OUTPUT.PUT_LINE('T12e FALLA: recalculo una reserva cancelada');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(CASE WHEN SQLCODE = -20009 THEN 'T12e OK: ' ELSE 'T12e FALLA: ' END || SQLERRM);
  END;
END;
/

PROMPT === T12. Movimientos de PAGO de la reserva cancelada ===
SELECT p.id, p.fecha, p.monto, ep.descripcion AS estado_pago, mp.nombre AS metodo
FROM   pago p
JOIN   pago_total  pt ON pt.id = p.id_pago_total
JOIN   estado_pago ep ON ep.id = p.id_estado_pago
JOIN   metodo_pago mp ON mp.id = p.id_metodo_pago
WHERE  pt.id_reserva = :g_reserva
ORDER  BY p.id;

/* =====================================================================
   T13. Resenas solo de reservas COMPLETADAS (TRG_RESENA_COMPLETADA)
   a) resena de la reserva cancelada en T12 -> -20020
   b) resena de una reserva completada sin resena -> se acepta
   ===================================================================== */
DECLARE
  v_completada NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T13. Resenas ===');
  BEGIN
    INSERT INTO resena (calificacion, comentario, fecha, id_reserva)
    VALUES (5, 'Prueba sobre reserva cancelada', SYSDATE, :g_reserva);
    DBMS_OUTPUT.PUT_LINE('T13a FALLA: acepto la resena');
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE(
        CASE WHEN SQLCODE = -20020 AND INSTR(SQLERRM, 'TRG_RESENA_COMPLETADA') > 0
             THEN 'T13a OK: ' ELSE 'T13a FALLA: ' END || SQLERRM);
  END;

  SELECT MIN(r.id) INTO v_completada
  FROM   reserva r JOIN estado_reserva er ON er.id = r.id_estado_reserva
  WHERE  UPPER(TRIM(er.descripcion)) = 'COMPLETADA'
  AND    NOT EXISTS (SELECT 1 FROM resena s WHERE s.id_reserva = r.id);

  IF v_completada IS NULL THEN
    DBMS_OUTPUT.PUT_LINE('T13b OMITIDA: todas las reservas completadas ya tienen resena');
  ELSE
    INSERT INTO resena (calificacion, comentario, fecha, id_reserva)
    VALUES (4, 'Prueba sobre reserva completada', SYSDATE, v_completada);
    DBMS_OUTPUT.PUT_LINE('T13b OK: resena aceptada para la reserva completada ' || v_completada);
  END IF;
END;
/

/* =====================================================================
   T14. Servicio de OTRO alojamiento (TRG_RS_COHERENCIA) -> -20007
   ===================================================================== */
DECLARE
  v_servicio NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T14. Servicio de otro alojamiento (espera -20007) ===');
  SELECT MIN(id) INTO v_servicio FROM servicio WHERE id_alojamiento <> :g_aloj;
  INSERT INTO reserva_servicio (cantidad, precio_unitario, id_reserva, id_servicio)
  VALUES (1, 50000, :g_reserva2, v_servicio);
  DBMS_OUTPUT.PUT_LINE('T14 FALLA: acepto el servicio');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE(
      CASE WHEN SQLCODE = -20007 AND INSTR(SQLERRM, 'TRG_RS_COHERENCIA') > 0
           THEN 'T14 OK: ' ELSE 'T14 FALLA: ' END || SQLERRM);
END;
/

/* =====================================================================
   T15. CURSOR CON PARAMETROS: liquidacion mensual
   Se liquida el ultimo mes con noches completadas y se cruza el total
   del proceso contra una consulta directa que usa el MISMO criterio de
   la Entrega 1: cabecera CONFIRMADA/COMPLETADA y linea no CANCELADA.
   ===================================================================== */
DECLARE
  v_mes        DATE;
  v_total_liq  NUMBER;
  v_dir        NUMBER;
  v_srv_liq    NUMBER;
  v_srv_dir    NUMBER;
  v_filas      NUMBER;
  v_alojs      NUMBER;
  v_canceladas NUMBER;
BEGIN
  SELECT MAX(TRUNC(rn.fecha, 'MM')) INTO v_mes
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  JOIN   reserva r             ON r.id  = rh.id_reserva
  JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
  JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
  WHERE  UPPER(TRIM(erh.descripcion)) = 'COMPLETADA'
  AND    UPPER(TRIM(erl.descripcion)) <> 'CANCELADA';

  :g_anio := EXTRACT(YEAR  FROM v_mes);
  :g_mes  := EXTRACT(MONTH FROM v_mes);

  DBMS_OUTPUT.PUT_LINE('=== T15. Liquidacion mensual ' || TO_CHAR(v_mes, 'YYYY-MM') || ' ===');
  pkg_turismo.sp_liquidacion_mensual(:g_anio, :g_mes);

  SELECT COUNT(*), SUM(ingreso_estadia), SUM(ingreso_servicios)
  INTO   v_filas, v_total_liq, v_srv_liq
  FROM   liquidacion_mensual
  WHERE  anio = :g_anio AND mes = :g_mes;

  SELECT COUNT(*) INTO v_alojs FROM alojamiento;

  SELECT NVL(SUM(rn.valor_noche), 0) INTO v_dir
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  JOIN   reserva r             ON r.id  = rh.id_reserva
  JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
  JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
  WHERE  rn.fecha >= v_mes AND rn.fecha < ADD_MONTHS(v_mes, 1)
  AND    UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA')
  AND    UPPER(TRIM(erl.descripcion)) <> 'CANCELADA';

  SELECT NVL(SUM(rs.cantidad * rs.precio_unitario), 0) INTO v_srv_dir
  FROM   reserva_servicio rs
  JOIN   reserva r          ON r.id  = rs.id_reserva
  JOIN   estado_reserva erh ON erh.id = r.id_estado_reserva
  WHERE  r.fecha_check_in >= v_mes AND r.fecha_check_in < ADD_MONTHS(v_mes, 1)
  AND    UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA');

  -- Noches de lineas canceladas dentro de cabeceras activas en ese mes
  SELECT COUNT(*) INTO v_canceladas
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  JOIN   reserva r             ON r.id  = rh.id_reserva
  JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
  JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
  WHERE  rn.fecha >= v_mes AND rn.fecha < ADD_MONTHS(v_mes, 1)
  AND    UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA')
  AND    UPPER(TRIM(erl.descripcion)) = 'CANCELADA';

  DBMS_OUTPUT.PUT_LINE('Filas generadas: ' || v_filas || ' (alojamientos: ' || v_alojs || ')');
  DBMS_OUTPUT.PUT_LINE('Estadia liquidada: ' || v_total_liq || ' / consulta directa: ' || v_dir);
  DBMS_OUTPUT.PUT_LINE('Servicios liquidados: ' || v_srv_liq || ' / consulta directa: ' || v_srv_dir);
  DBMS_OUTPUT.PUT_LINE('Noches de lineas canceladas en cabeceras activas (excluidas): ' || v_canceladas);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = v_alojs
                             AND v_total_liq = v_dir
                             AND v_srv_liq = v_srv_dir
                            THEN 'T15a OK' ELSE 'T15a FALLA' END);

  -- Reproceso: correrlo otra vez no duplica
  pkg_turismo.sp_liquidacion_mensual(:g_anio, :g_mes);
  SELECT COUNT(*) INTO v_filas FROM liquidacion_mensual WHERE anio = :g_anio AND mes = :g_mes;
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = v_alojs THEN 'T15b OK: reproceso sin duplicados'
                            ELSE 'T15b FALLA: ' || v_filas || ' filas' END);
END;
/

PROMPT === T15. Top 10 alojamientos del mes liquidado ===
SELECT l.id_alojamiento, a.nombre_comercial, l.noches_ocupadas, l.num_reservas,
       l.ingreso_estadia, l.ingreso_servicios, l.ingreso_total
FROM   liquidacion_mensual l
JOIN   alojamiento a ON a.id = l.id_alojamiento
WHERE  l.anio = :g_anio AND l.mes = :g_mes
ORDER  BY l.ingreso_total DESC
FETCH FIRST 10 ROWS ONLY;

/* =====================================================================
   T16. Historico en el tablespace propio
   Se archivan las lineas con cabecera y linea cerradas (COMPLETADA o
   CANCELADA) y check-out anterior al corte. Se compara contra el
   conteo directo y se verifica que ninguna reserva activa se archivo.
   ===================================================================== */
DECLARE
  v_filas    NUMBER;
  v_esperadas NUMBER;
  v_activos  NUMBER;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T16. Archivado al historico (corte 2025-01-01) ===');

  SELECT COUNT(*) INTO v_esperadas
  FROM   reserva_habitacion rh
  JOIN   reserva r            ON r.id  = rh.id_reserva
  JOIN   estado_reserva er    ON er.id = rh.id_estado_reserva
  JOIN   estado_reserva erh   ON erh.id = r.id_estado_reserva
  WHERE  UPPER(TRIM(er.descripcion))  IN ('COMPLETADA', 'CANCELADA')
  AND    UPPER(TRIM(erh.descripcion)) IN ('COMPLETADA', 'CANCELADA')
  AND    rh.fecha_check_out < DATE '2025-01-01';

  pkg_turismo.sp_archivar_historico(DATE '2025-01-01', v_filas);
  DBMS_OUTPUT.PUT_LINE('Lineas archivadas: ' || v_filas || ' (esperadas: ' || v_esperadas || ')');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = v_esperadas THEN 'T16a OK' ELSE 'T16a FALLA' END);

  pkg_turismo.sp_archivar_historico(DATE '2025-01-01', v_filas);
  DBMS_OUTPUT.PUT_LINE('Segunda ejecucion: ' || v_filas || ' (esperado 0, no duplica)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_filas = 0 THEN 'T16b OK' ELSE 'T16b FALLA' END);

  SELECT COUNT(*) INTO v_activos
  FROM   reserva_historico hi
  JOIN   reserva r          ON r.id  = hi.id_reserva
  JOIN   estado_reserva er  ON er.id = r.id_estado_reserva
  WHERE  UPPER(TRIM(er.descripcion)) IN ('PENDIENTE', 'CONFIRMADA');
  DBMS_OUTPUT.PUT_LINE('Archivadas con cabecera activa: ' || v_activos || ' (esperado 0)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_activos = 0 THEN 'T16c OK' ELSE 'T16c FALLA' END);
END;
/

PROMPT === T16. Segmentos del historico y su tablespace ===
SELECT segment_name, segment_type, tablespace_name, ROUND(bytes/1024/1024, 2) AS mb
FROM   user_segments
WHERE  segment_name IN ('RESERVA_HISTORICO', 'PK_RESERVA_HISTORICO');

/* =====================================================================
   FIN DE PRUEBAS TRANSACCIONALES: se deshace todo lo hecho por T4-T16
   (reservas de prueba, cambio de tarifas, auditoria, liquidacion,
   historico). Para CONSERVAR la liquidacion o el historico, ejecutar
   solo sp_liquidacion_mensual / sp_archivar_historico y luego COMMIT.
   ===================================================================== */
ROLLBACK;

/* =====================================================================
   T17. VISTA MATERIALIZADA (despues del ROLLBACK porque el refresco
   hace COMMIT). Se refresca y se compara el total del mes contra el
   calculo directo con el criterio cabecera + linea de la Entrega 1.
   ===================================================================== */
EXEC DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');

DECLARE
  v_aloj     NUMBER;
  v_mes      DATE;
  v_mv       NUMBER;
  v_directo  NUMBER;
  v_mv_total NUMBER;
  v_dir_total NUMBER;
  v_stale    VARCHAR2(20);
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== T17. Vista materializada ===');

  SELECT id_alojamiento, mes, noches_ocupadas INTO v_aloj, v_mes, v_mv
  FROM   mv_ocupacion_mensual
  ORDER  BY noches_ocupadas DESC
  FETCH FIRST 1 ROWS ONLY;

  SELECT COUNT(*) INTO v_directo
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  JOIN   habitacion h          ON h.id  = rh.id_habitacion
  JOIN   reserva r             ON r.id  = rh.id_reserva
  JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
  JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
  WHERE  h.id_alojamiento = v_aloj
  AND    rn.fecha >= v_mes AND rn.fecha < ADD_MONTHS(v_mes, 1)
  AND    UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA')
  AND    UPPER(TRIM(erl.descripcion)) <> 'CANCELADA';

  DBMS_OUTPUT.PUT_LINE('Alojamiento ' || v_aloj || ', mes ' || TO_CHAR(v_mes, 'YYYY-MM') ||
                       ': MV=' || v_mv || ' / directo=' || v_directo);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_mv = v_directo THEN 'T17a OK' ELSE 'T17a FALLA' END);

  SELECT SUM(noches_ocupadas) INTO v_mv_total
  FROM   mv_ocupacion_mensual
  WHERE  mes = v_mes;

  SELECT COUNT(*) INTO v_dir_total
  FROM   reserva_noche rn
  JOIN   reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
  JOIN   reserva r             ON r.id  = rh.id_reserva
  JOIN   estado_reserva erh    ON erh.id = r.id_estado_reserva
  JOIN   estado_reserva erl    ON erl.id = rh.id_estado_reserva
  WHERE  rn.fecha >= v_mes AND rn.fecha < ADD_MONTHS(v_mes, 1)
  AND    UPPER(TRIM(erh.descripcion)) IN ('CONFIRMADA', 'COMPLETADA')
  AND    UPPER(TRIM(erl.descripcion)) <> 'CANCELADA';

  DBMS_OUTPUT.PUT_LINE('Total del mes ' || TO_CHAR(v_mes, 'YYYY-MM') ||
                       ': MV=' || v_mv_total || ' / directo=' || v_dir_total);
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_mv_total = v_dir_total THEN 'T17b OK' ELSE 'T17b FALLA' END);

  SELECT staleness INTO v_stale
  FROM   user_mviews
  WHERE  mview_name = 'MV_OCUPACION_MENSUAL';
  DBMS_OUTPUT.PUT_LINE('Estado de la MV: ' || v_stale || ' (esperado FRESH)');
  DBMS_OUTPUT.PUT_LINE(CASE WHEN v_stale = 'FRESH' THEN 'T17c OK' ELSE 'T17c FALLA' END);
END;
/

PROMPT === T17. Ocupacion del mes con mas noches, por municipio ===
SELECT municipio,
       SUM(noches_ocupadas)    AS ocupadas,
       SUM(noches_disponibles) AS disponibles,
       ROUND(100 * SUM(noches_ocupadas) / SUM(noches_disponibles), 2) AS pct_ocupacion
FROM   mv_ocupacion_mensual
WHERE  mes = (SELECT mes FROM (
                SELECT mes, SUM(noches_ocupadas) AS n
                FROM   mv_ocupacion_mensual
                GROUP  BY mes
                ORDER  BY n DESC
                FETCH FIRST 1 ROWS ONLY))
GROUP  BY municipio
ORDER  BY pct_ocupacion DESC;

SELECT mview_name, last_refresh_date, staleness
FROM   user_mviews
WHERE  mview_name = 'MV_OCUPACION_MENSUAL';
