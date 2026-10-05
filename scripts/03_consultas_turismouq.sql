/* =====================================================================
   TurismoUQ · Plataforma de reservas turísticas del Quindío
   Bases de Datos II · Proyecto integrador · Entrega 1
   Script 03 · Consultas de análisis

   Definiciones que usan todas las consultas
     - Reservas que cuentan: las completadas y las confirmadas (incluye las
       que están en curso y las futuras ya confirmadas). Las pendientes y
       las canceladas no cuentan, y tampoco las líneas canceladas dentro
       de una reserva activa (cuando el grupo cancela solo una habitación).
     - Período: noches del 01-ene-2024 al 31-dic-2026. Fecha de corte de
       los datos: 30-sep-2026, así que octubre a diciembre de 2026 solo
       muestran lo que ya estaba reservado y confirmado en esa fecha.
     - Ocupación (%): noches ocupadas / noches disponibles x 100.
       Noches disponibles = habitaciones del municipio x días del mes.
       Se cuenta noche por noche (tabla RESERVA_NOCHE): una estadía del
       30-jun al 02-jul suma una noche a junio y una a julio.
     - Ingreso: valor de las noches (la tarifa vigente cada noche, ya
       guardada en RESERVA_NOCHE) más los servicios contratados. Cada noche
       cuenta en su propio mes y en su propia temporada. Los servicios no
       tienen fecha, así que cuentan en el mes y la temporada del check-in
       de la reserva. Valores en pesos colombianos.
     - Municipio: en el modelo es la tabla CIUDAD (todos los alojamientos
       están en ciudades del Quindío).

   Contenido
      1. Ocupación por municipio y mes ........................ PIVOT
      2. Ingresos por municipio, tipo y temporada ... CUBE + GROUPING
      3. Top 3 alojamientos por ingreso en cada municipio ..... RANK
      4. Variación de ingresos mes contra mes .................. LAG
      5. Habitaciones libres en un rango de fechas . variables de enlace
      6. Estrellas autoasignadas frente a reseñas ........... UNPIVOT
      7. Consulta libre: cancelaciones y reembolsos ... GROUPING SETS
   ===================================================================== */

/* =====================================================================
   CONSULTA 1 · Ocupación por municipio y mes (PIVOT)
  
   Pregunta: ¿qué porcentaje de las noches disponibles se ocupó en cada
   municipio, mes a mes?

   ===================================================================== */
WITH noches_ocupadas AS (
  SELECT a.id_ciudad,
         TRUNC(rn.fecha, 'MM') AS mes,
         COUNT(*)             AS noches
    FROM reserva_noche rn
    JOIN reserva_habitacion rh ON rh.id = rn.id_reserva_habitacion
    JOIN estado_reserva erh     ON erh.id = rh.id_estado_reserva
    JOIN reserva r             ON r.id = rh.id_reserva
    JOIN estado_reserva er     ON er.id = r.id_estado_reserva
    JOIN alojamiento a         ON a.id = r.id_alojamiento
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND erh.descripcion <> 'cancelada'
     AND rn.fecha BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
   GROUP BY a.id_ciudad, TRUNC(rn.fecha, 'MM')
),
habitaciones AS (
  SELECT a.id_ciudad,
         COUNT(*) AS habitaciones
    FROM habitacion h
    JOIN alojamiento a ON a.id = h.id_alojamiento
   GROUP BY a.id_ciudad
),
meses AS (
  SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS mes
    FROM dual
 CONNECT BY LEVEL <= 36
),
base AS (
  SELECT c.nombre                                       AS municipio,
         EXTRACT(YEAR FROM m.mes)                       AS anio,
         EXTRACT(MONTH FROM m.mes)                      AS mes,
         NVL(o.noches, 0)                               AS ocupadas,
         hb.habitaciones * (LAST_DAY(m.mes) - m.mes + 1) AS disponibles
    FROM habitaciones hb
    JOIN ciudad c ON c.id = hb.id_ciudad
   CROSS JOIN meses m
    LEFT JOIN noches_ocupadas o ON o.id_ciudad = hb.id_ciudad
                               AND o.mes = m.mes
)
SELECT municipio,
       anio,
       ene, feb, mar, abr, may, jun, jul, ago, sep, oct, nov, dic,
       anual
  FROM (SELECT municipio,
               anio,
               mes,
               ROUND(100 * ocupadas / disponibles, 1) AS ocupacion,
               ROUND(100 * SUM(ocupadas)    OVER (PARTITION BY municipio, anio)
                         / SUM(disponibles) OVER (PARTITION BY municipio, anio), 1) AS anual
          FROM base)
 PIVOT (MAX(ocupacion) FOR mes IN (1 AS ene, 2 AS feb,  3 AS mar,  4 AS abr,
                                   5 AS may, 6 AS jun,  7 AS jul,  8 AS ago,
                                   9 AS sep, 10 AS oct, 11 AS nov, 12 AS dic))
 ORDER BY municipio, anio;


/* =====================================================================
   CONSULTA 2 · Ingresos por municipio, tipo de alojamiento y temporada
                (CUBE + GROUPING)

   Pregunta: ¿cuánto ingresa cada municipio y cada tipo de alojamiento en
   temporada alta, media y baja, con sus subtotales?

   ===================================================================== */
WITH ingreso AS (
  SELECT r.id_alojamiento,
         tm.id_tipo_temporada,
         n.valor_noche AS valor
    FROM reserva_noche n
    JOIN reserva_habitacion rh ON rh.id = n.id_reserva_habitacion
    JOIN estado_reserva el     ON el.id = rh.id_estado_reserva
    JOIN reserva r             ON r.id = rh.id_reserva
    JOIN estado_reserva er     ON er.id = r.id_estado_reserva
    JOIN tarifa t              ON t.id = n.id_tarifa
    JOIN temporada tm          ON tm.id = t.id_temporada
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND el.descripcion <> 'cancelada'
     AND n.fecha BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
  UNION ALL
  SELECT r.id_alojamiento,
         tm.id_tipo_temporada,
         rs.cantidad * rs.precio_unitario
    FROM reserva_servicio rs
    JOIN reserva r         ON r.id = rs.id_reserva
    JOIN estado_reserva er ON er.id = r.id_estado_reserva
    JOIN temporada tm      ON r.fecha_check_in BETWEEN tm.fecha_inicio AND tm.fecha_fin
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND r.fecha_check_in BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
)
SELECT CASE WHEN GROUPING(c.nombre)  = 1 THEN '(Todos los municipios)' ELSE c.nombre  END AS municipio,
       CASE WHEN GROUPING(ta.nombre) = 1 THEN '(Todos los tipos)'      ELSE ta.nombre END AS tipo_alojamiento,
       CASE WHEN GROUPING(tt.nombre) = 1 THEN '(Todas)'                ELSE tt.nombre END AS temporada,
       CASE GROUPING_ID(c.nombre, ta.nombre, tt.nombre)
            WHEN 0 THEN 'Detalle'
            WHEN 1 THEN 'Subtotal municipio y tipo'
            WHEN 2 THEN 'Subtotal municipio y temporada'
            WHEN 3 THEN 'Subtotal municipio'
            WHEN 4 THEN 'Subtotal tipo y temporada'
            WHEN 5 THEN 'Subtotal tipo'
            WHEN 6 THEN 'Subtotal temporada'
            WHEN 7 THEN 'Total general'
       END AS nivel,
       ROUND(SUM(i.valor)) AS ingreso
  FROM ingreso i
  JOIN alojamiento a       ON a.id = i.id_alojamiento
  JOIN ciudad c            ON c.id = a.id_ciudad
  JOIN tipo_alojamiento ta ON ta.id = a.id_tipo_alojamiento
  JOIN tipo_temporada tt   ON tt.id = i.id_tipo_temporada
 GROUP BY CUBE(c.nombre, ta.nombre, tt.nombre)
 ORDER BY GROUPING(c.nombre),  c.nombre,
          GROUPING(ta.nombre), ta.nombre,
          GROUPING(tt.nombre), DECODE(tt.nombre, 'Alta', 1, 'Media', 2, 'Baja', 3);


/* =====================================================================
   CONSULTA 3 · Los 3 alojamientos de mayor ingreso en cada municipio
                (RANK con PARTITION BY)

   Pregunta: ¿cuáles son los alojamientos más rentables dentro de cada
   municipio?

   ===================================================================== */
WITH ingreso AS (
  SELECT r.id_alojamiento,
         n.valor_noche AS valor
    FROM reserva_noche n
    JOIN reserva_habitacion rh ON rh.id = n.id_reserva_habitacion
    JOIN estado_reserva el     ON el.id = rh.id_estado_reserva
    JOIN reserva r             ON r.id = rh.id_reserva
    JOIN estado_reserva er     ON er.id = r.id_estado_reserva
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND el.descripcion <> 'cancelada'
     AND n.fecha BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
  UNION ALL
  SELECT r.id_alojamiento,
         rs.cantidad * rs.precio_unitario
    FROM reserva_servicio rs
    JOIN reserva r         ON r.id = rs.id_reserva
    JOIN estado_reserva er ON er.id = r.id_estado_reserva
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND r.fecha_check_in BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
),
por_alojamiento AS (
  SELECT c.nombre           AS municipio,
         a.nombre_comercial AS alojamiento,
         ta.nombre          AS tipo_alojamiento,
         SUM(i.valor)       AS ingreso
    FROM ingreso i
    JOIN alojamiento a       ON a.id = i.id_alojamiento
    JOIN ciudad c            ON c.id = a.id_ciudad
    JOIN tipo_alojamiento ta ON ta.id = a.id_tipo_alojamiento
   GROUP BY c.nombre, a.id, a.nombre_comercial, ta.nombre
),
ranking AS (
  SELECT municipio,
         alojamiento,
         tipo_alojamiento,
         ingreso,
         RANK()          OVER (PARTITION BY municipio ORDER BY ingreso DESC) AS puesto,
         RATIO_TO_REPORT(ingreso) OVER (PARTITION BY municipio)               AS participacion,
         COUNT(*)        OVER (PARTITION BY municipio)                        AS alojamientos_municipio
    FROM por_alojamiento
)
SELECT municipio,
       puesto,
       alojamiento,
       tipo_alojamiento,
       ROUND(ingreso)                AS ingreso,
       ROUND(100 * participacion, 1) AS pct_del_municipio,
       alojamientos_municipio
  FROM ranking
 WHERE puesto <= 3
 ORDER BY municipio, puesto;


/* =====================================================================
   CONSULTA 4 · Variación de ingresos mes contra mes (LAG)

   Pregunta: ¿cuánto subió o bajó el ingreso de la plataforma de un mes al
   siguiente?
   
   ===================================================================== */
WITH ingreso AS (
  SELECT TRUNC(n.fecha, 'MM') AS mes,
         n.valor_noche        AS valor
    FROM reserva_noche n
    JOIN reserva_habitacion rh ON rh.id = n.id_reserva_habitacion
    JOIN estado_reserva el     ON el.id = rh.id_estado_reserva
    JOIN reserva r             ON r.id = rh.id_reserva
    JOIN estado_reserva er     ON er.id = r.id_estado_reserva
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND el.descripcion <> 'cancelada'
     AND n.fecha BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
  UNION ALL
  SELECT TRUNC(r.fecha_check_in, 'MM'),
         rs.cantidad * rs.precio_unitario
    FROM reserva_servicio rs
    JOIN reserva r         ON r.id = rs.id_reserva
    JOIN estado_reserva er ON er.id = r.id_estado_reserva
   WHERE er.descripcion IN ('completada', 'confirmada')
     AND r.fecha_check_in BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
),
meses AS (
  SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS mes
    FROM dual
 CONNECT BY LEVEL <= 36
),
mensual AS (
  SELECT m.mes,
         NVL(SUM(i.valor), 0) AS ingreso
    FROM meses m
    LEFT JOIN ingreso i ON i.mes = m.mes
   GROUP BY m.mes
)
SELECT TO_CHAR(mes, 'YYYY-MM') AS periodo,
       CASE WHEN LAST_DAY(mes) <= DATE '2026-09-30' THEN 'Cerrado'
            ELSE 'Futuro: solo lo reservado al corte'
       END AS situacion,
       ROUND(ingreso)                              AS ingreso,
       ROUND(LAG(ingreso) OVER (ORDER BY mes))     AS ingreso_mes_anterior,
       ROUND(ingreso - LAG(ingreso) OVER (ORDER BY mes)) AS variacion,
       ROUND(100 * (ingreso - LAG(ingreso) OVER (ORDER BY mes))
                 / NULLIF(LAG(ingreso) OVER (ORDER BY mes), 0), 1) AS variacion_pct,
       ROUND(100 * (ingreso - LAG(ingreso, 12) OVER (ORDER BY mes))
                 / NULLIF(LAG(ingreso, 12) OVER (ORDER BY mes), 0), 1) AS var_vs_anio_anterior_pct
  FROM mensual
 ORDER BY mes;


/* =====================================================================
   CONSULTA 5 · Habitaciones libres en un rango de fechas
                (consulta parametrizada con variables de enlace)

   Pregunta: ¿qué habitaciones se pueden ofrecer entre dos fechas y
   cuánto costaría la estadía en cada una?

   ===================================================================== */
VARIABLE fecha_ini VARCHAR2(10)
VARIABLE fecha_fin VARCHAR2(10)
EXEC :fecha_ini := '2026-10-09';
EXEC :fecha_fin := '2026-10-12';

WITH rango AS (
  SELECT TO_DATE(:fecha_ini, 'YYYY-MM-DD') AS ini,
         TO_DATE(:fecha_fin, 'YYYY-MM-DD') AS fin
    FROM dual
),
valor AS (
  SELECT t.id_habitacion,
         SUM(t.valor_noche * (LEAST(rg.fin, tm.fecha_fin + 1) - GREATEST(rg.ini, tm.fecha_inicio))) AS valor,
         SUM(LEAST(rg.fin, tm.fecha_fin + 1) - GREATEST(rg.ini, tm.fecha_inicio))                 AS noches
    FROM tarifa t
    JOIN temporada tm ON tm.id = t.id_temporada
   CROSS JOIN rango rg
   WHERE tm.fecha_inicio < rg.fin
     AND tm.fecha_fin   >= rg.ini
   GROUP BY t.id_habitacion
)
SELECT c.nombre           AS municipio,
       a.nombre_comercial AS alojamiento,
       h.numero           AS habitacion,
       th.nombre          AS tipo_habitacion,
       h.capacidad_maxima,
       rg.fin - rg.ini    AS noches,
       CASE WHEN v.noches = rg.fin - rg.ini THEN v.valor END AS valor_estadia
  FROM habitacion h
  JOIN alojamiento a      ON a.id = h.id_alojamiento
  JOIN ciudad c           ON c.id = a.id_ciudad
  JOIN tipo_habitacion th ON th.id = h.id_tipo_habitacion
 CROSS JOIN rango rg
  LEFT JOIN valor v       ON v.id_habitacion = h.id
 WHERE rg.fin > rg.ini
   AND NOT EXISTS (SELECT 1
                     FROM reserva_habitacion rh
                     JOIN estado_reserva el ON el.id = rh.id_estado_reserva
                    WHERE rh.id_habitacion   = h.id
                      AND el.descripcion    <> 'cancelada'
                      AND rh.fecha_check_in  < rg.fin
                      AND rh.fecha_check_out > rg.ini)
 ORDER BY c.nombre, a.nombre_comercial, h.numero;


/* =====================================================================
   CONSULTA 6 · Estrellas autoasignadas frente a reseñas, por tipo de
                alojamiento (UNPIVOT)

   Pregunta: ¿los alojamientos de cada tipo se califican a sí mismos como
   los califican sus clientes?

   ===================================================================== */
WITH estrellas AS (
  SELECT NVL(a.id_tipo_alojamiento, 0)              AS id_tipo,
         ROUND(AVG(a.calificacion_autoasignada), 2) AS promedio,
         COUNT(*)                                   AS cantidad
    FROM alojamiento a
   GROUP BY ROLLUP(a.id_tipo_alojamiento)
),
resenas AS (
  SELECT NVL(a.id_tipo_alojamiento, 0) AS id_tipo,
         ROUND(AVG(rs.calificacion), 2) AS promedio,
         COUNT(*)                       AS cantidad
    FROM resena rs
    JOIN reserva r     ON r.id = rs.id_reserva
    JOIN alojamiento a ON a.id = r.id_alojamiento
   GROUP BY ROLLUP(a.id_tipo_alojamiento)
),
resumen AS (
  SELECT NVL(ta.nombre, '(Todos los tipos)') AS tipo_alojamiento,
         e.promedio AS estrellas_prom,
         e.cantidad AS estrellas_cant,
         rn.promedio AS resenas_prom,
         rn.cantidad AS resenas_cant
    FROM estrellas e
    LEFT JOIN tipo_alojamiento ta ON ta.id = e.id_tipo
    LEFT JOIN resenas rn          ON rn.id_tipo = e.id_tipo
)
SELECT tipo_alojamiento,
       fuente,
       calificacion,
       cantidad,
       CASE WHEN fuente <> 'Estrellas autoasignadas' THEN
            ROUND(calificacion - MAX(CASE WHEN fuente = 'Estrellas autoasignadas' THEN calificacion END)
                                 OVER (PARTITION BY tipo_alojamiento), 2)
       END AS diferencia
  FROM resumen
UNPIVOT ((calificacion, cantidad)
         FOR fuente IN ((estrellas_prom, estrellas_cant) AS 'Estrellas autoasignadas',
                        (resenas_prom,   resenas_cant)   AS 'Reseñas de clientes'))
 ORDER BY CASE WHEN tipo_alojamiento = '(Todos los tipos)' THEN 2 ELSE 1 END,
          tipo_alojamiento,
          fuente;


/* =====================================================================
   CONSULTA 7 · Consulta libre: cancelaciones y reembolsos
                (GROUPING SETS)

   Pregunta de negocio: ¿dónde y en qué temporada se cancelan más
   reservas, y cuánto de lo que pagaron esos clientes se devuelve y
   cuánto se queda la plataforma?

   ===================================================================== */
WITH reservas AS (
  SELECT r.id,
         c.nombre                               AS municipio,
         tt.nombre                              AS temporada,
         er.descripcion                         AS estado,
         r.fecha_check_in - r.fecha_cancelacion AS dias_antes
    FROM reserva r
    JOIN estado_reserva er ON er.id = r.id_estado_reserva
    JOIN alojamiento a     ON a.id = r.id_alojamiento
    JOIN ciudad c          ON c.id = a.id_ciudad
    JOIN temporada tm      ON r.fecha_check_in BETWEEN tm.fecha_inicio AND tm.fecha_fin
    JOIN tipo_temporada tt ON tt.id = tm.id_tipo_temporada
   WHERE r.fecha_check_in BETWEEN DATE '2024-01-01' AND DATE '2026-12-31'
),
dinero AS (
  SELECT pt.id_reserva,
         SUM(CASE WHEN ep.descripcion = 'exitoso'     THEN p.monto ELSE 0 END) AS pagado,
         SUM(CASE WHEN ep.descripcion = 'reembolsado' THEN p.monto ELSE 0 END) AS reembolsado
    FROM pago_total pt
    JOIN pago p         ON p.id_pago_total = pt.id
    JOIN estado_pago ep ON ep.id = p.id_estado_pago
   GROUP BY pt.id_reserva
)
SELECT CASE WHEN GROUPING(rv.municipio) = 1 THEN '(Todo el Quindío)' ELSE rv.municipio END AS municipio,
       CASE WHEN GROUPING(rv.temporada) = 1 THEN '(Todas)'           ELSE rv.temporada END AS temporada,
       COUNT(*) AS reservas,
       SUM(CASE WHEN rv.estado = 'cancelada' THEN 1 ELSE 0 END) AS canceladas,
       ROUND(100 * SUM(CASE WHEN rv.estado = 'cancelada' THEN 1 ELSE 0 END) / COUNT(*), 1) AS tasa_cancelacion_pct,
       SUM(CASE WHEN rv.estado = 'cancelada' AND rv.dias_antes > 5 THEN 1 ELSE 0 END)     AS con_derecho_reembolso,
       ROUND(SUM(CASE WHEN rv.estado = 'cancelada' THEN NVL(d.pagado, 0) ELSE 0 END))      AS pagado_canceladas,
       ROUND(SUM(CASE WHEN rv.estado = 'cancelada' THEN NVL(d.reembolsado, 0) ELSE 0 END)) AS reembolsado,
       ROUND(SUM(CASE WHEN rv.estado = 'cancelada'
                      THEN NVL(d.pagado, 0) - NVL(d.reembolsado, 0) ELSE 0 END))           AS retenido
  FROM reservas rv
  LEFT JOIN dinero d ON d.id_reserva = rv.id
 GROUP BY GROUPING SETS ((rv.municipio, rv.temporada), (rv.temporada), ())
 ORDER BY GROUPING(rv.municipio), rv.municipio,
          GROUPING(rv.temporada), DECODE(rv.temporada, 'Alta', 1, 'Media', 2, 'Baja', 3);
