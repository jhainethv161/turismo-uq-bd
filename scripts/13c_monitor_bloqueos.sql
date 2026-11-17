/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13c: CONCURRENCIA - OBSERVADOR DE BLOQUEOS
   ---------------------------------------------------------------------
   Abrir en una TERCERA ventana, conectado como el dueño del esquema
   (necesita SELECT_CATALOG_ROLE, concedido en el script 11).
   Ejecutarlo mientras la sesion B esta esperando (paso B3) y capturar la
   pantalla: es la evidencia del bloqueo real.
   ===================================================================== */
SET LINESIZE 220
SET PAGESIZE 100
SET VERIFY OFF
SET SQLBLANKLINES ON

COLUMN sid              FORMAT 99999
COLUMN usuario          FORMAT A12
COLUMN estado           FORMAT A9
COLUMN evento           FORMAT A38
COLUMN bloqueada_por    FORMAT 99999
COLUMN seg_esperando    FORMAT 99999
COLUMN sql_texto        FORMAT A60 TRUNC
COLUMN tipo             FORMAT A5
COLUMN modo_retenido    FORMAT A14
COLUMN modo_pedido      FORMAT A14
COLUMN objeto           FORMAT A22

PROMPT
PROMPT === 1. Quien espera a quien (V$SESSION) ===
SELECT s.sid,
       s.username                    AS usuario,
       s.status                      AS estado,
       s.event                       AS evento,
       s.blocking_session            AS bloqueada_por,
       s.seconds_in_wait             AS seg_esperando,
       SUBSTR(q.sql_text, 1, 60)     AS sql_texto
FROM   v$session s
LEFT   JOIN v$sql q ON q.sql_id = s.sql_id AND q.child_number = 0
WHERE  s.username = USER
AND    (s.blocking_session IS NOT NULL
        OR s.sid IN (SELECT blocking_session FROM v$session WHERE blocking_session IS NOT NULL))
ORDER  BY s.blocking_session NULLS FIRST;

PROMPT
PROMPT === 2. Bloqueos de fila (TX) y de tabla (TM): REQUEST > 0 = esta esperando ===
SELECT l.sid,
       l.type                                                      AS tipo,
       DECODE(l.lmode, 0,'ninguno', 1,'null', 2,'row-S (RS)', 3,'row-X (RX)',
                       4,'share (S)', 5,'S/row-X (SRX)', 6,'exclusive (X)') AS modo_retenido,
       DECODE(l.request,0,'ninguno', 1,'null', 2,'row-S (RS)', 3,'row-X (RX)',
                       4,'share (S)', 5,'S/row-X (SRX)', 6,'exclusive (X)') AS modo_pedido,
       o.object_name                                               AS objeto
FROM   v$lock l
LEFT   JOIN dba_objects o ON o.object_id = l.id1 AND l.type = 'TM'
WHERE  l.sid IN (SELECT sid FROM v$session WHERE username = USER)
AND    l.type IN ('TX', 'TM')
AND    (l.type = 'TX' OR o.object_name IN ('HABITACION', 'RESERVA', 'RESERVA_HABITACION'))
ORDER  BY l.request DESC, l.sid, l.type;

PROMPT
PROMPT Lectura: la sesion con REQUEST > 0 en TX es la que esta esperando; su columna
PROMPT bloqueada_por (consulta 1) es el SID de la sesion A, que retiene la fila de HABITACION.
