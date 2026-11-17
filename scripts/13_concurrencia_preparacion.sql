/* =====================================================================
   TurismoUQ - Entrega 3
   Script 13: CONCURRENCIA - preparacion del experimento
   ---------------------------------------------------------------------
   EJECUTAR CONECTADO COMO EL DUEÑO DEL ESQUEMA, despues de 01 a 12.

   El experimento completo se hace con DOS (mas una) sesiones:
        13_concurrencia_preparacion.sql   una vez (este script)
        13a_sesion_A.sql                  ventana 1 (sesion A)
        13b_sesion_B.sql                  ventana 2 (sesion B)
        13c_monitor_bloqueos.sql          ventana 3 (observador)
        13d_limpieza_reservas_prueba.sql  entre fases
        13e_limpieza_total.sql            al final
   Los pasos estan numerados (A1, B1, A2 ...) y cada script avisa cuando
   debe esperar al otro. El documento README_Entrega3.md explica que
   capturar en cada paso.

   Que hace este script
     1. Crea una HABITACION DE PRUEBA (numero 'ZZ-CONC') con tarifa en
        todas las temporadas. Asi el experimento no toca datos reales y
        la habitacion esta garantizadamente libre.
     2. Comprueba SP_CREAR_RESERVA_SEGURA (creada en el script 12): la
        version de SP_CREAR_RESERVA que bloquea la habitacion con
        SELECT ... FOR UPDATE antes de revisar la disponibilidad.

   Por que SP_CREAR_RESERVA (Entrega 2) NO basta bajo concurrencia
     fn_habitacion_disponible lee RESERVA_HABITACION. Oracle solo muestra
     datos CONFIRMADOS (COMMIT) de otras sesiones. Si A y B consultan
     al mismo tiempo, ninguna ve la reserva sin confirmar de la otra, las
     dos concluyen "libre" y las dos insertan. TRG_RH_NO_SOLAPE tiene la
     misma limitacion: tambien lee solo lo confirmado. Resultado: DOBLE
     RESERVA de la misma habitacion. Es la anomalia clasica de "comprobar
     y luego actuar" (check-then-act) sin serializar.

   Solucion: SELECT ... FOR UPDATE sobre la fila de HABITACION
     Una reserva de esa habitacion necesita primero el bloqueo de su fila
     en HABITACION. Las demas sesiones que quieran reservar LA MISMA
     habitacion esperan (habitaciones distintas no se estorban). Cuando
     la primera hace COMMIT, la segunda obtiene el bloqueo, vuelve a
     leer, ahora SI ve la reserva confirmada y se rechaza con -20005.
     El bloqueo se libera en el COMMIT/ROLLBACK.
   ===================================================================== */

SET SERVEROUTPUT ON SIZE UNLIMITED
SET VERIFY OFF
SET SQLBLANKLINES ON

/* ---------------------------------------------------------------------
   1. Habitacion de prueba (se recrea si ya existia)
   --------------------------------------------------------------------- */

@@13e_limpieza_total.sql

INSERT INTO habitacion (numero, capacidad_maxima, descripcion, id_alojamiento, id_tipo_habitacion)
SELECT 'ZZ-CONC', 2, 'Habitacion de prueba del experimento de concurrencia',
       a.id, (SELECT MIN(id) FROM tipo_habitacion)
FROM   alojamiento a
WHERE  a.id = (SELECT MIN(id) FROM alojamiento);

-- Tarifa en TODAS las temporadas: el calculo de la estadia no puede fallar
INSERT INTO tarifa (valor_noche, id_habitacion, id_temporada)
SELECT 150000, h.id, t.id
FROM   habitacion h
CROSS  JOIN temporada t
WHERE  h.numero = 'ZZ-CONC';

COMMIT;

/* ---------------------------------------------------------------------
   2. SP_CREAR_RESERVA_SEGURA (la version con SELECT ... FOR UPDATE) se
      crea en el script 12, porque SP_RESERVAR_Y_PAGAR la usa. Aqui solo
      se comprueba que exista y este VALID.
   --------------------------------------------------------------------- */
PROMPT
PROMPT === Procedimientos de la fase DESPUES (creados en el script 12) ===
SELECT object_name, status FROM user_objects
WHERE  object_name IN ('SP_CREAR_RESERVA_SEGURA', 'SP_RESERVAR_Y_PAGAR')
ORDER  BY object_name;

PROMPT
PROMPT === Habitacion de prueba ===
SELECT h.id, h.numero, h.id_alojamiento,
       (SELECT COUNT(*) FROM tarifa t WHERE t.id_habitacion = h.id) AS tarifas
FROM   habitacion h
WHERE  h.numero = 'ZZ-CONC';
