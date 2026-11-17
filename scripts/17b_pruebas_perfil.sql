/* =====================================================================
   TurismoUQ - Entrega 3
   Script 17b: PRUEBAS DEL PERFIL (limites de sesion y de contraseña)
   ---------------------------------------------------------------------
   EJECUTAR COMO SYSTEM (o DBA) en la PDB, despues del script 16.

   Pide:
     - la clave de los usuarios de demostracion
     - el servicio de la PDB
     - la conexion DBA completa (usuario/clave@servicio) para volver a
       entrar como DBA despues de los intentos fallidos. No se muestra.

   Prueba 1  FAILED_LOGIN_ATTEMPTS 3
             3 claves erroneas -> la cuenta pasa a LOCKED(TIMED); incluso
             la clave CORRECTA es rechazada con ORA-28000 hasta que pasa
             PASSWORD_LOCK_TIME (1 hora) o el DBA la desbloquea.
   Prueba 2  SESSIONS_PER_USER 2
             La tercera sesion simultanea del mismo usuario es rechazada con
             ORA-02391. Es la unica prueba que necesita varias ventanas;
             el procedimiento manual esta al final de este script.
   ===================================================================== */
SET VERIFY OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
SET FEEDBACK OFF
SET SQLBLANKLINES ON
SET DEFINE ON
WHENEVER SQLERROR CONTINUE

ACCEPT clave_demo   CHAR PROMPT 'Clave de los usuarios de demostracion: ' HIDE
ACCEPT servicio     CHAR DEFAULT 'localhost:1521/FREEPDB1' PROMPT 'Servicio de la PDB [localhost:1521/FREEPDB1]: '
ACCEPT conexion_dba CHAR PROMPT 'Conexion DBA (usuario/clave@servicio): ' HIDE

COLUMN username       FORMAT A14
COLUMN account_status FORMAT A16
COLUMN lock_date      FORMAT A20

PROMPT
PROMPT === Estado inicial de AUD_PRUEBA ===
SELECT username, account_status FROM dba_users WHERE username = 'AUD_PRUEBA';

PROMPT
PROMPT === Prueba 1. Tres claves erroneas seguidas (se esperan 3 x ORA-01017) ===
CONNECT aud_prueba/clave_incorrecta_1@&servicio
CONNECT aud_prueba/clave_incorrecta_2@&servicio
CONNECT aud_prueba/clave_incorrecta_3@&servicio

PROMPT
PROMPT === Cuarto intento con la clave CORRECTA: debe responder ORA-28000 (cuenta bloqueada) ===
CONNECT aud_prueba/"&clave_demo"@&servicio

CONNECT &conexion_dba
PROMPT
PROMPT === Estado de la cuenta despues de los intentos (esperado LOCKED(TIMED)) ===
SELECT username, account_status, TO_CHAR(lock_date, 'YYYY-MM-DD HH24:MI:SS') AS lock_date
FROM   dba_users WHERE username = 'AUD_PRUEBA';

PROMPT
PROMPT === El DBA desbloquea la cuenta ===
ALTER USER aud_prueba ACCOUNT UNLOCK;
SELECT username, account_status FROM dba_users WHERE username = 'AUD_PRUEBA';

PROMPT
PROMPT === Despues de desbloquear, la clave correcta entra ===
CONNECT aud_prueba/"&clave_demo"@&servicio
SELECT USER AS conectado_como FROM dual;

CONNECT &conexion_dba

PROMPT
PROMPT === Prueba 2. SESSIONS_PER_USER = 2 (procedimiento manual) ===
PROMPT   1) Abrir tres ventanas de SQL*Plus.
PROMPT   2) En cada una:  CONNECT rec_prueba/clave@localhost:1521/FREEPDB1
PROMPT   3) Las dos primeras entran; la TERCERA responde:
PROMPT        ORA-02391: exceeded simultaneous SESSIONS_PER_USER limit
PROMPT   4) Verificacion desde el DBA:
PROMPT        SELECT username, COUNT(*) FROM v$session
PROMPT        WHERE username = 'REC_PRUEBA' GROUP BY username;
PROMPT
PROMPT Limites vigentes del perfil:
COLUMN resource_name FORMAT A26
COLUMN limit         FORMAT A12
SELECT resource_name, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_TURISMO'
AND    resource_name IN ('SESSIONS_PER_USER', 'CONNECT_TIME', 'IDLE_TIME',
                         'FAILED_LOGIN_ATTEMPTS', 'PASSWORD_LOCK_TIME')
ORDER  BY resource_name;

UNDEFINE clave_demo
UNDEFINE conexion_dba
