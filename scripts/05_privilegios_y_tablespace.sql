/* =====================================================================
   TurismoUQ - Entrega 2
   Script 05: privilegios del esquema y tablespace del historico
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO SYSTEM (o un usuario DBA) A LA PDB DONDE VIVE
   EL ESQUEMA:
     - Oracle XE 21c        -> XEPDB1
     - Oracle 23ai/26ai Free -> FREEPDB1
   Es el unico script de la Entrega 2 que necesita privilegios de DBA:
   un usuario normal no puede crear tablespaces ni darse privilegios.
   ===================================================================== */

SET SERVEROUTPUT ON
SET VERIFY OFF
SET SQLBLANKLINES ON

-- ---------------------------------------------------------------------
-- Parametros del script. Se pueden cambiar sin editar el resto:
--   DEFINE esquema    = TURISMOUQ
--   DEFINE ts_datafile = "C:\ruta\al\archivo.dbf"
-- Si no se define ts_datafile, se usa un nombre relativo: Oracle lo
-- crea en la carpeta de datafiles por defecto de la instalacion. Es la
-- opcion portable para una base limpia (no depende de una ruta fija de
-- este equipo). Para ver donde quedo:
--   SELECT file_name FROM dba_data_files
--   WHERE tablespace_name = 'TS_TURISMOUQ_HIST';
-- ---------------------------------------------------------------------
DEFINE esquema     = TURISMOUQ
DEFINE ts_datafile = "ts_turismouq_hist01.dbf"

/* ---------------------------------------------------------------------
   1. Privilegios que la Entrega 2 necesita en el esquema
      - CREATE PROCEDURE         : paquete PKG_TURISMO
      - CREATE TRIGGER           : disparadores de auditoria y de solape
      - CREATE MATERIALIZED VIEW : MV_OCUPACION_MENSUAL
      - CREATE JOB               : job que refresca la vista materializada
      - CREATE TABLE / VIEW      : tablas de soporte (ya los deberia tener)
    --------------------------------------------------------------------- */
GRANT CREATE PROCEDURE, CREATE TRIGGER, CREATE MATERIALIZED VIEW,
      CREATE JOB, CREATE TABLE, CREATE VIEW TO &esquema;

/* ---------------------------------------------------------------------
   2. Tablespace propio para el historico de reservas

   JUSTIFICACION (por que separarlo):
   a) Naturaleza distinta de los datos. Las reservas operativas se
      consultan y modifican todo el tiempo (crear, confirmar, pagar,
      cancelar). El historico (reservas ya completadas o canceladas de
      periodos cerrados) solo crece y casi solo se lee para reportes.
      Mezclarlos en el mismo tablespace hace que los segmentos
      calientes y los frios compitan por el mismo espacio y E/S.
   b) Crecimiento controlado. El historico crece sin limite (25.000+
      reservas en 3 anios). En su propio tablespace, con AUTOEXTEND y
      MAXSIZE, su crecimiento no puede llenar el tablespace de las
      tablas operativas y detener las reservas nuevas.
   c) Administracion independiente. Un periodo cerrado no cambia, asi
      que el tablespace se puede respaldar con menor frecuencia, e
      incluso ponerse READ ONLY al cerrar un anio
      (ALTER TABLESPACE ts_turismouq_hist READ ONLY), lo que lo saca
      de los respaldos diarios y lo protege de modificaciones.
   d) Fisicamente puede ubicarse en otro disco (otro datafile) sin
      tocar la aplicacion: la tabla solo sabe su nombre logico.

   El datafile se toma de &ts_datafile. El bloque comprueba primero si
   el tablespace ya existe, asi el script se puede volver a ejecutar
   sin error (no depende de capturar ORA-01543).
    --------------------------------------------------------------------- */
DECLARE
  v_existe NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_existe
  FROM   dba_tablespaces
  WHERE  tablespace_name = 'TS_TURISMOUQ_HIST';

  IF v_existe = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLESPACE ts_turismouq_hist
        DATAFILE '&ts_datafile' SIZE 50M
        AUTOEXTEND ON NEXT 10M MAXSIZE 1G
        EXTENT MANAGEMENT LOCAL AUTOALLOCATE
        SEGMENT SPACE MANAGEMENT AUTO ]';
    DBMS_OUTPUT.PUT_LINE('Tablespace TS_TURISMOUQ_HIST creado (datafile: &ts_datafile).');
  ELSE
    DBMS_OUTPUT.PUT_LINE('El tablespace TS_TURISMOUQ_HIST ya existia.');
  END IF;
END;
/

-- 3. Cuota: sin cuota el esquema no puede crear segmentos en el tablespace
ALTER USER &esquema QUOTA UNLIMITED ON ts_turismouq_hist;

-- 4. Verificacion
SELECT tablespace_name, status, contents, extent_management
FROM   dba_tablespaces
WHERE  tablespace_name = 'TS_TURISMOUQ_HIST';

SELECT tablespace_name, file_name, bytes/1024/1024 AS mb, autoextensible
FROM   dba_data_files
WHERE  tablespace_name = 'TS_TURISMOUQ_HIST';
