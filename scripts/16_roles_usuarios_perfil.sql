/* =====================================================================
   TurismoUQ - Entrega 3
   Script 16: ROLES, PERFIL y USUARIOS de demostracion
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO SYSTEM (o un usuario DBA) A LA PDB DONDE VIVE
   EL ESQUEMA, despues de 15_vistas_seguridad.sql.
   Pide la clave de los usuarios de demostracion (no se guarda en el
   repositorio ni se muestra en pantalla).

   Que crea
     1. PERFIL_TURISMO   limites de sesion y de contraseña
     2. Cuatro roles con privilegios diferenciados
          ROL_RECEPCION           consulta por vistas V_REC_* y registra
                                  reserva + pago con SP_RESERVAR_Y_PAGAR
          ROL_ADMIN_ALOJAMIENTO   ve y ajusta tarifas SOLO de su alojamiento
          ROL_GERENTE             indicadores agregados V_GER_*
          ROL_AUDITOR             lectura de auditoria y pagos V_AUD_*
     3. Usuarios de demostracion (uno por rol, mas dos encargados)

   Principios aplicados
     - Minimo privilegio: cada rol recibe SOLO lo que su trabajo exige.
     - Recepcion NO tiene ningun privilegio sobre tablas: solo SELECT sobre
       vistas y EXECUTE sobre un procedimiento (que corre con los
       derechos de su dueño). Intentar leer una tabla da ORA-00942.
     - Ningun rol recibe privilegios de sistema salvo CREATE SESSION.
     - Los privilegios se dan a ROLES y los roles a usuarios: dar de alta
       o de baja a una persona es un solo GRANT/REVOKE.

   Es idempotente: borra y recrea los usuarios, roles y perfil.
   ===================================================================== */

SET VERIFY OFF
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET SQLBLANKLINES ON

DEFINE esquema = TURISMOUQ

ACCEPT clave_demo CHAR PROMPT 'Clave para los usuarios de demostracion: ' HIDE

/* =====================================================================
   0. LIMPIEZA (permite volver a ejecutar el script)
   ===================================================================== */
BEGIN
  FOR u IN (SELECT username FROM dba_users
            WHERE  username IN ('REC_PRUEBA', 'ENC_OSPINA', 'ENC_RESTREPO', 'ENC_MARIN',
                                'GER_PRUEBA', 'AUD_PRUEBA'))
  LOOP
    -- Si el usuario esta conectado, se cierran sus sesiones antes de borrarlo
    FOR s IN (SELECT sid, serial# FROM v$session WHERE username = u.username) LOOP
      EXECUTE IMMEDIATE 'ALTER SYSTEM KILL SESSION ''' || s.sid || ',' || s.serial# || ''' IMMEDIATE';
    END LOOP;
    EXECUTE IMMEDIATE 'DROP USER ' || u.username || ' CASCADE';
  END LOOP;

  FOR r IN (SELECT role FROM dba_roles
            WHERE  role IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR'))
  LOOP
    EXECUTE IMMEDIATE 'DROP ROLE ' || r.role;
  END LOOP;

  FOR p IN (SELECT profile FROM dba_profiles WHERE profile = 'PERFIL_TURISMO' AND ROWNUM = 1) LOOP
    EXECUTE IMMEDIATE 'DROP PROFILE perfil_turismo CASCADE';
  END LOOP;
END;
/

/* =====================================================================
   1. PERFIL: limites de sesion y de contraseña
   ---------------------------------------------------------------------
   SESSIONS_PER_USER 2        maximo 2 sesiones simultaneas por usuario
   CONNECT_TIME 480           una sesion dura como maximo 8 horas (minutos)
   IDLE_TIME 30               se cierra tras 30 minutos sin actividad
   CPU_PER_CALL 6000          una llamada no puede usar mas de 60 s de CPU
                              (centesimas de segundo): corta consultas
                              fuera de control
   LOGICAL_READS_PER_CALL     tope de lecturas por llamada: evita que un
                              SELECT sin filtro recorra toda la base
   FAILED_LOGIN_ATTEMPTS 3    3 claves erroneas bloquean la cuenta...
   PASSWORD_LOCK_TIME 1/24    ...por 1 hora
   PASSWORD_LIFE_TIME 90      la clave caduca a los 90 dias...
   PASSWORD_GRACE_TIME 7      ...con 7 dias de aviso
   PASSWORD_REUSE_TIME 180    una clave no se reutiliza hasta pasados 180 dias
   (CONNECT_TIME, IDLE_TIME, CPU_* y LOGICAL_READS_* se aplican cuando el
    parametro RESOURCE_LIMIT esta en TRUE, valor por defecto desde 12c.)
   ===================================================================== */
CREATE PROFILE perfil_turismo LIMIT
  SESSIONS_PER_USER        2
  CONNECT_TIME             480
  IDLE_TIME                30
  CPU_PER_CALL             6000
  LOGICAL_READS_PER_CALL   5000000
  FAILED_LOGIN_ATTEMPTS    3
  PASSWORD_LOCK_TIME       1/24
  PASSWORD_LIFE_TIME       90
  PASSWORD_GRACE_TIME      7
  PASSWORD_REUSE_TIME      180
  PASSWORD_REUSE_MAX       UNLIMITED;

/* =====================================================================
   2. ROLES
   ===================================================================== */
CREATE ROLE rol_recepcion;
CREATE ROLE rol_admin_alojamiento;
CREATE ROLE rol_gerente;
CREATE ROLE rol_auditor;

-- 2.1 RECEPCION ------------------------------------------------------
GRANT CREATE SESSION TO rol_recepcion;
GRANT SELECT  ON &esquema..v_rec_clientes      TO rol_recepcion;
GRANT SELECT  ON &esquema..v_rec_habitaciones  TO rol_recepcion;
GRANT SELECT  ON &esquema..v_rec_reservas      TO rol_recepcion;
-- Registra reserva + pago en una sola transaccion atomica (script 12).
-- Es un EXECUTE, no un acceso a tablas: el procedimiento corre con los
-- derechos de su dueño y recepcion nunca toca las tablas.
GRANT EXECUTE ON &esquema..sp_reservar_y_pagar TO rol_recepcion;

-- 2.2 ADMINISTRADOR DE ALOJAMIENTO -----------------------------------
GRANT CREATE SESSION TO rol_admin_alojamiento;
GRANT SELECT ON &esquema..v_adm_habitaciones TO rol_admin_alojamiento;
GRANT SELECT ON &esquema..v_adm_reservas     TO rol_admin_alojamiento;
GRANT SELECT ON &esquema..v_adm_resenas      TO rol_admin_alojamiento;
GRANT SELECT ON &esquema..v_adm_tarifas      TO rol_admin_alojamiento;
-- Solo puede cambiar el VALOR de la noche (no habitacion ni temporada)
GRANT UPDATE (valor_noche) ON &esquema..v_adm_tarifas TO rol_admin_alojamiento;

-- 2.3 GERENTE --------------------------------------------------------
GRANT CREATE SESSION TO rol_gerente;
GRANT SELECT ON &esquema..v_ger_ocupacion       TO rol_gerente;
GRANT SELECT ON &esquema..v_ger_ingresos        TO rol_gerente;
GRANT SELECT ON &esquema..v_ger_calificaciones  TO rol_gerente;

-- 2.4 AUDITOR --------------------------------------------------------
GRANT CREATE SESSION TO rol_auditor;
GRANT SELECT ON &esquema..v_aud_auditoria_tarifa TO rol_auditor;
GRANT SELECT ON &esquema..v_aud_pagos            TO rol_auditor;
GRANT SELECT ON &esquema..v_aud_reservas         TO rol_auditor;

/* =====================================================================
   3. USUARIOS DE DEMOSTRACION
   Los encargados se llaman como su username de USUARIO_SISTEMA con el
   punto cambiado por guion bajo (enc.ospina -> ENC_OSPINA): asi las
   vistas V_ADM_* saben a que alojamiento pertenecen.
   ENC_MARIN corresponde a un encargado INACTIVO (activo = 'N'): conecta
   pero no ve ningun dato.
   ===================================================================== */
CREATE USER rec_prueba   IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;
CREATE USER enc_ospina   IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;
CREATE USER enc_restrepo IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;
CREATE USER enc_marin    IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;
CREATE USER ger_prueba   IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;
CREATE USER aud_prueba   IDENTIFIED BY "&clave_demo" PROFILE perfil_turismo;

GRANT rol_recepcion         TO rec_prueba;
GRANT rol_admin_alojamiento TO enc_ospina, enc_restrepo, enc_marin;
GRANT rol_gerente           TO ger_prueba;
GRANT rol_auditor           TO aud_prueba;

/* =====================================================================
   4. VERIFICACION
   ===================================================================== */
PROMPT
PROMPT === Perfil y limites ===
COLUMN resource_name FORMAT A26
COLUMN limit         FORMAT A12
SELECT resource_name, limit
FROM   dba_profiles
WHERE  profile = 'PERFIL_TURISMO'
ORDER  BY resource_type, resource_name;

PROMPT
PROMPT === Usuarios de demostracion ===
COLUMN username FORMAT A14
COLUMN profile  FORMAT A16
SELECT u.username, u.profile, u.account_status, r.granted_role
FROM   dba_users u
LEFT   JOIN dba_role_privs r ON r.grantee = u.username
WHERE  u.username IN ('REC_PRUEBA', 'ENC_OSPINA', 'ENC_RESTREPO', 'ENC_MARIN', 'GER_PRUEBA', 'AUD_PRUEBA')
ORDER  BY u.username;

PROMPT
PROMPT === Privilegios de cada rol (matriz) ===
COLUMN grantee    FORMAT A24
COLUMN privilege  FORMAT A16
COLUMN table_name FORMAT A26
COLUMN columna    FORMAT A12
SELECT grantee, privilege, table_name, NULL AS columna
FROM   dba_tab_privs
WHERE  grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
UNION ALL
SELECT grantee, privilege, table_name, column_name
FROM   dba_col_privs
WHERE  grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
ORDER  BY 1, 3, 2;

PROMPT
PROMPT === Privilegios de sistema de los roles (solo CREATE SESSION) ===
SELECT grantee, privilege
FROM   dba_sys_privs
WHERE  grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
ORDER  BY grantee;

PROMPT
PROMPT === Comprobacion clave: ningun rol tiene privilegios sobre TABLAS (esperado: 0 filas) ===
SELECT p.grantee, p.table_name
FROM   dba_tab_privs p
JOIN   dba_objects o ON o.owner = p.owner AND o.object_name = p.table_name
WHERE  p.grantee IN ('ROL_RECEPCION', 'ROL_ADMIN_ALOJAMIENTO', 'ROL_GERENTE', 'ROL_AUDITOR')
AND    o.object_type = 'TABLE';

UNDEFINE clave_demo
