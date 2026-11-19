SET DEFINE ON
SET SERVEROUTPUT ON
SET VERIFY OFF
SET FEEDBACK ON
SET LINESIZE 200
SET PAGESIZE 100

DEFINE esquema  = TURISMOUQ
DEFINE ts_datos = USERS

ACCEPT clave_esquema CHAR PROMPT 'Clave para el usuario &esquema: ' HIDE

DECLARE
  v_existe NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_existe
  FROM   dba_users
  WHERE  username = UPPER('&esquema');

  IF v_existe = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER &esquema IDENTIFIED BY "&clave_esquema"'
                   || ' DEFAULT TABLESPACE &ts_datos'
                   || ' TEMPORARY TABLESPACE temp';
    DBMS_OUTPUT.PUT_LINE('Usuario &esquema creado.');
  ELSE
    DBMS_OUTPUT.PUT_LINE('El usuario &esquema ya existia: no se borra, solo se '
                      || 'vuelven a conceder privilegios y cuota.');
  END IF;
END;
/

UNDEFINE clave_esquema

GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE TO &esquema;
ALTER USER &esquema QUOTA UNLIMITED ON &ts_datos;