/* =====================================================================
   TurismoUQ - Entrega 3
   Script 15: VISTAS de seguridad (una familia por rol)
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA, despues de 01 a 14.
   Se ejecuta ANTES del 16 (el 16 concede privilegios sobre estas vistas).

   Idea de diseño
     Ningun usuario final recibe privilegios sobre las TABLAS. Cada rol ve
     el negocio a traves de vistas que:
       - muestran solo las columnas necesarias (nada de correos de
         usuarios internos, metodos de pago de otros, etc.);
       - filtran FILAS segun quien consulta (encargados);
       - son de solo lectura (WITH READ ONLY) salvo la de tarifas del
         encargado, que permite actualizar el valor de la noche.

   Familias
     V_REC_*   Recepcion            (lectura, toda la plataforma, sin datos de pago)
     V_ADM_*   Administrador de     (solo su alojamiento: seguridad a nivel de FILA)
               alojamiento
     V_GER_*   Gerente              (indicadores agregados: ocupacion, ingresos, resenas)
     V_AUD_*   Auditor              (lectura de auditoria, pagos y reservas)

   Seguridad a nivel de fila para el administrador de alojamiento
     USUARIO_SISTEMA (Entrega 1) relaciona cada ENCARGADO con su
     alojamiento. La vista V_MI_ALOJAMIENTO toma el usuario de la sesion
     (SYS_CONTEXT('USERENV','SESSION_USER')) y lo busca ahi. El nombre de
     usuario de Oracle es el username con el punto convertido en guion
     bajo y en mayusculas:  'enc.ospina'  ->  ENC_OSPINA.
     Un encargado marcado como inactivo (activo = 'N') no ve nada.
   ===================================================================== */

SET SQLBLANKLINES ON
SET FEEDBACK ON

/* =====================================================================
   0. VISTA AUXILIAR: a que alojamiento pertenece quien consulta
   ===================================================================== */
CREATE OR REPLACE VIEW v_mi_alojamiento AS
SELECT us.id_alojamiento
FROM   usuario_sistema us
WHERE  us.activo = 'S'
AND    us.rol = 'ENCARGADO'
AND    UPPER(REPLACE(us.username, '.', '_')) = SYS_CONTEXT('USERENV', 'SESSION_USER')
WITH READ ONLY;

COMMENT ON TABLE v_mi_alojamiento IS 'Alojamiento del encargado conectado (por USERENV SESSION_USER). Base de la seguridad por fila.';

/* =====================================================================
   1. RECEPCION - lectura de toda la plataforma, sin datos de pago
   ===================================================================== */
CREATE OR REPLACE VIEW v_rec_clientes AS
SELECT c.id,
       td.nombre            AS tipo_documento,
       c.numero_documento,
       c.nombres,
       c.apellidos,
       c.correo_electronico,
       ci.nombre            AS ciudad_origen
FROM   cliente c
JOIN   tipo_documento td ON td.id = c.id_tipo_documento
JOIN   ciudad ci         ON ci.id = c.id_ciudad
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_habitaciones AS
SELECT h.id,
       a.id                 AS id_alojamiento,
       a.nombre_comercial   AS alojamiento,
       ci.nombre            AS municipio,
       h.numero,
       th.nombre            AS tipo_habitacion,
       h.capacidad_maxima
FROM   habitacion h
JOIN   alojamiento a      ON a.id  = h.id_alojamiento
JOIN   ciudad ci          ON ci.id = a.id_ciudad
JOIN   tipo_habitacion th ON th.id = h.id_tipo_habitacion
WITH READ ONLY;

CREATE OR REPLACE VIEW v_rec_reservas AS
SELECT r.id,
       r.fecha_check_in,
       r.fecha_check_out,
       c.nombres || ' ' || c.apellidos AS cliente,
       a.nombre_comercial              AS alojamiento,
       er.descripcion                  AS estado_reserva,
       pt.total,
       ept.descripcion                 AS estado_pago
FROM   reserva r
JOIN   cliente c            ON c.id  = r.id_cliente
JOIN   alojamiento a        ON a.id  = r.id_alojamiento
JOIN   estado_reserva er    ON er.id = r.id_estado_reserva
LEFT   JOIN pago_total pt        ON pt.id_reserva = r.id
LEFT   JOIN estado_pago_total ept ON ept.id = pt.id_estado_pago_total
WITH READ ONLY;

/* =====================================================================
   2. ADMINISTRADOR DE ALOJAMIENTO - solo las filas de SU alojamiento
   ===================================================================== */
CREATE OR REPLACE VIEW v_adm_habitaciones AS
SELECT h.id,
       h.numero,
       th.nombre         AS tipo_habitacion,
       h.capacidad_maxima,
       h.descripcion
FROM   habitacion h
JOIN   tipo_habitacion th ON th.id = h.id_tipo_habitacion
WHERE  h.id_alojamiento IN (SELECT id_alojamiento FROM v_mi_alojamiento)
WITH READ ONLY;

-- Unica vista con escritura: el encargado ajusta el valor de la noche de
-- SUS habitaciones. WITH CHECK OPTION impide mover una fila fuera de su
-- alojamiento. El disparador de auditoria de TARIFA sigue registrando
-- cada cambio con el usuario de base de datos que lo hizo.
CREATE OR REPLACE VIEW v_adm_tarifas AS
SELECT t.id,
       t.id_habitacion,
       t.id_temporada,
       t.valor_noche
FROM   tarifa t
WHERE  t.id_habitacion IN (SELECT h.id
                           FROM   habitacion h
                           WHERE  h.id_alojamiento IN (SELECT id_alojamiento FROM v_mi_alojamiento))
WITH CHECK OPTION;

CREATE OR REPLACE VIEW v_adm_reservas AS
SELECT r.id,
       r.fecha_check_in,
       r.fecha_check_out,
       c.nombres || ' ' || c.apellidos AS cliente,
       er.descripcion                  AS estado_reserva,
       pt.total,
       ept.descripcion                 AS estado_pago
FROM   reserva r
JOIN   cliente c         ON c.id  = r.id_cliente
JOIN   estado_reserva er ON er.id = r.id_estado_reserva
LEFT   JOIN pago_total pt         ON pt.id_reserva = r.id
LEFT   JOIN estado_pago_total ept ON ept.id = pt.id_estado_pago_total
WHERE  r.id_alojamiento IN (SELECT id_alojamiento FROM v_mi_alojamiento)
WITH READ ONLY;

CREATE OR REPLACE VIEW v_adm_resenas AS
SELECT rs.id,
       rs.fecha,
       rs.calificacion,
       rs.comentario,
       r.id AS id_reserva
FROM   resena rs
JOIN   reserva r ON r.id = rs.id_reserva
WHERE  r.id_alojamiento IN (SELECT id_alojamiento FROM v_mi_alojamiento)
WITH READ ONLY;

/* =====================================================================
   3. GERENTE - indicadores agregados de toda la plataforma
   ===================================================================== */
CREATE OR REPLACE VIEW v_ger_ocupacion AS
SELECT municipio, tipo_alojamiento, alojamiento, anio, num_mes,
       noches_disponibles, noches_ocupadas, pct_ocupacion
FROM   mv_ocupacion_mensual
WITH READ ONLY;

CREATE OR REPLACE VIEW v_ger_ingresos AS
SELECT lm.anio, lm.mes,
       a.nombre_comercial AS alojamiento,
       ci.nombre          AS municipio,
       ta.nombre          AS tipo_alojamiento,
       lm.noches_ocupadas, lm.num_reservas,
       lm.ingreso_estadia, lm.ingreso_servicios, lm.ingreso_total
FROM   liquidacion_mensual lm
JOIN   alojamiento a       ON a.id  = lm.id_alojamiento
JOIN   ciudad ci           ON ci.id = a.id_ciudad
JOIN   tipo_alojamiento ta ON ta.id = a.id_tipo_alojamiento
WITH READ ONLY;

CREATE OR REPLACE VIEW v_ger_calificaciones AS
SELECT a.nombre_comercial           AS alojamiento,
       ci.nombre                    AS municipio,
       a.calificacion_autoasignada  AS estrellas_autoasignadas,
       COUNT(rs.id)                 AS num_resenas,
       ROUND(AVG(rs.calificacion), 2) AS promedio_resenas
FROM   alojamiento a
JOIN   ciudad ci      ON ci.id = a.id_ciudad
LEFT   JOIN reserva r ON r.id_alojamiento = a.id
LEFT   JOIN resena rs ON rs.id_reserva = r.id
GROUP  BY a.nombre_comercial, ci.nombre, a.calificacion_autoasignada
WITH READ ONLY;

/* =====================================================================
   4. AUDITOR - lectura de la trazabilidad y de los movimientos de dinero
   ===================================================================== */
CREATE OR REPLACE VIEW v_aud_auditoria_tarifa AS
SELECT id, id_tarifa, id_habitacion, id_temporada, operacion,
       valor_anterior, valor_nuevo, usuario_bd, usuario_so, equipo, fecha_cambio
FROM   auditoria_tarifa
WITH READ ONLY;

CREATE OR REPLACE VIEW v_aud_pagos AS
SELECT p.id,
       p.fecha,
       p.monto,
       mp.nombre        AS metodo_pago,
       ep.descripcion   AS estado_pago,
       pt.id_reserva
FROM   pago p
JOIN   pago_total pt   ON pt.id = p.id_pago_total
JOIN   metodo_pago mp  ON mp.id = p.id_metodo_pago
JOIN   estado_pago ep  ON ep.id = p.id_estado_pago
WITH READ ONLY;

CREATE OR REPLACE VIEW v_aud_reservas AS
SELECT r.id, r.fecha_creacion, r.fecha_check_in, r.fecha_check_out, r.fecha_cancelacion,
       r.id_cliente, r.id_alojamiento,
       er.descripcion AS estado_reserva
FROM   reserva r
JOIN   estado_reserva er ON er.id = r.id_estado_reserva
WITH READ ONLY;

/* =====================================================================
   5. VERIFICACION: todas las vistas deben quedar VALID
   ===================================================================== */
PROMPT
PROMPT === Vistas de seguridad (todas deben estar VALID) ===
SELECT object_name, status
FROM   user_objects
WHERE  object_type = 'VIEW'
AND    (object_name LIKE 'V\_REC\_%' ESCAPE '\' OR object_name LIKE 'V\_ADM\_%' ESCAPE '\'
     OR object_name LIKE 'V\_GER\_%' ESCAPE '\' OR object_name LIKE 'V\_AUD\_%' ESCAPE '\'
     OR object_name = 'V_MI_ALOJAMIENTO')
ORDER  BY object_name;
