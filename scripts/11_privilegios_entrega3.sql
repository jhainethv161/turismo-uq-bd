/* =====================================================================
   TurismoUQ - Entrega 3
   Script 11: privilegios que necesita el dueño del esquema
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO SYSTEM (o un usuario DBA) A LA PDB DONDE VIVE
   EL ESQUEMA (FREEPDB1 en Oracle 23ai/26ai Free, XEPDB1 en XE 21c).

   Que se concede y para que:
     SELECT_CATALOG_ROLE
        Permite al dueño consultar las vistas V$ y DBA_* de solo lectura.
        Se usa en 13c_monitor_bloqueos.sql para ver los bloqueos
        (V$LOCK, V$SESSION) mientras una sesion espera a otra.
     SELECT sobre V_$MYSTAT y V_$STATNAME (concesion DIRECTA)
        Un procedimiento almacenado NO hereda privilegios de roles, solo
        los directos. IDX_MEDIR_CONSULTA (script 14) es un procedimiento
        y lee las estadisticas de la sesion ("session logical reads"), asi
        que necesita estos dos privilegios directos.

   El script es idempotente: volver a ejecutarlo no produce error.
   ===================================================================== */

SET VERIFY OFF
SET SQLBLANKLINES ON

DEFINE esquema = TURISMOUQ

-- 1. Lectura del catalogo y de las vistas de rendimiento
GRANT SELECT_CATALOG_ROLE TO &esquema;

-- 1b. Estadisticas de la sesion, concedidas directamente (para PL/SQL)
GRANT SELECT ON sys.v_$mystat   TO &esquema;
GRANT SELECT ON sys.v_$statname TO &esquema;

-- 2. Verificacion
PROMPT
PROMPT === Roles concedidos a &esquema ===
SELECT grantee, granted_role
FROM   dba_role_privs
WHERE  grantee = UPPER('&esquema')
ORDER  BY granted_role;
