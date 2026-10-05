/* =====================================================================
   TurismoUQ · Plataforma de reservas turísticas del Quindío
   Bases de Datos II · Proyecto integrador · Entrega 1
   Script 02 · Carga de datos (volumen mínimo)

   Motor: Oracle XE 21c. Se ejecuta justo después de 01_ddl_turismouq.sql,
   con las tablas vacías y conectado al mismo esquema:
     - SQL Developer: abrir el archivo y ejecutar como script (F5).
       Si las tildes se ven mal, poner la codificación en UTF-8
       (Herramientas > Preferencias > Entorno > Codificación).
     - SQL*Plus / SQLcl: @02_carga_turismouq.sql
   Tarda unos minutos. Si algo falla, se deshace toda la carga.

   Cómo se generan los datos
     - Secciones 1 a 4: catálogos, departamentos, ciudades, temporadas y
       alojamientos se insertan uno por uno, con valores explícitos.
     - Secciones 5 a 8: el resto se genera con PL/SQL y DBMS_RANDOM.
       Cada bloque fija su semilla con DBMS_RANDOM.SEED, así que cada
       ejecución produce exactamente los mismos datos.
     - Fecha de corte: 30-sep-2026. Las reservas que terminaron antes de
       esa fecha están completadas o canceladas; las que empiezan después
       están confirmadas, pendientes o canceladas.

   Volumen resultante (aproximado) y mínimo exigido
     MUNICIPIO (CIUDAD del Quindío)    12        (12)
     TIPO_ALOJAMIENTO                   4         (4)
     ALOJAMIENTO                       60        (60)
     HABITACION                       535       (400)
     TEMPORADA                         78         (6)
     TARIFA                        41 730  (habitación x temporada)
     CLIENTE                        3 000     (3 000)
     RESERVA                       25 500    (25 000)
     RESERVA_HABITACION           ~29 700  (>= 25 000)
     PAGO                         ~35 800  (>= 25 000)
     SERVICIO                         180        (30)
     RESERVA_SERVICIO             ~47 000    (40 000)
     RESENA                        ~50 %   (>= 40 % de las completadas)
     USUARIO_SISTEMA                   10        (10)
     RESERVA_NOCHE                ~85 000   (tabla agregada)

   Contenido
      0. Preparación
      1. Catálogos
      2. Departamentos y ciudades
      3. Temporadas 2024-2026 (con los festivos colombianos)
      4. Alojamientos
      5. Habitaciones y tarifas
      6. Clientes y sus teléfonos
      7. Contactos de los alojamientos, servicios y usuarios
      8. Reservas, noches, servicios contratados, pagos y reseñas
      9. Confirmación
     10. Verificación
   ===================================================================== */


/* ---------------------------------------------------------------------
   0. PREPARACIÓN
   --------------------------------------------------------------------- */
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
-- Ante cualquier error se detiene el script y se deshace la carga.
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

-- La carga parte de tablas vacías: si ya hay datos, se detiene.
DECLARE
  v_filas NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_filas FROM departamento;
  IF v_filas > 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Las tablas ya tienen datos. Ejecute primero 01_ddl_turismouq.sql para recrearlas.');
  END IF;
END;
/


/* ---------------------------------------------------------------------
   1. CATÁLOGOS
   --------------------------------------------------------------------- */
INSERT INTO tipo_alojamiento (nombre) VALUES ('Finca cafetera');
INSERT INTO tipo_alojamiento (nombre) VALUES ('Hotel');
INSERT INTO tipo_alojamiento (nombre) VALUES ('Glamping');
INSERT INTO tipo_alojamiento (nombre) VALUES ('Hostal');

INSERT INTO tipo_habitacion (nombre) VALUES ('Sencilla');
INSERT INTO tipo_habitacion (nombre) VALUES ('Doble');
INSERT INTO tipo_habitacion (nombre) VALUES ('Suite');
INSERT INTO tipo_habitacion (nombre) VALUES ('Cabaña');

INSERT INTO tipo_temporada (nombre) VALUES ('Alta');
INSERT INTO tipo_temporada (nombre) VALUES ('Media');
INSERT INTO tipo_temporada (nombre) VALUES ('Baja');

INSERT INTO tipo_documento (nombre) VALUES ('Cédula de ciudadanía');
INSERT INTO tipo_documento (nombre) VALUES ('Cédula de extranjería');
INSERT INTO tipo_documento (nombre) VALUES ('Pasaporte');

INSERT INTO estado_reserva (descripcion) VALUES ('pendiente');
INSERT INTO estado_reserva (descripcion) VALUES ('confirmada');
INSERT INTO estado_reserva (descripcion) VALUES ('cancelada');
INSERT INTO estado_reserva (descripcion) VALUES ('completada');

INSERT INTO metodo_pago (nombre) VALUES ('Tarjeta de crédito');
INSERT INTO metodo_pago (nombre) VALUES ('Tarjeta débito');
INSERT INTO metodo_pago (nombre) VALUES ('PSE');
INSERT INTO metodo_pago (nombre) VALUES ('Transferencia');
INSERT INTO metodo_pago (nombre) VALUES ('Efectivo');

-- Estado de cada pago individual
INSERT INTO estado_pago (descripcion) VALUES ('exitoso');
INSERT INTO estado_pago (descripcion) VALUES ('fallido');
INSERT INTO estado_pago (descripcion) VALUES ('pendiente');
INSERT INTO estado_pago (descripcion) VALUES ('reembolsado');

-- Estado del cobro total de la reserva. 'cancelado' cubre las reservas
-- canceladas sin reembolso: el cliente no pagó nada o perdió el anticipo.
INSERT INTO estado_pago_total (descripcion) VALUES ('pendiente');
INSERT INTO estado_pago_total (descripcion) VALUES ('abonado');
INSERT INTO estado_pago_total (descripcion) VALUES ('pagado');
INSERT INTO estado_pago_total (descripcion) VALUES ('reembolsado');
INSERT INTO estado_pago_total (descripcion) VALUES ('cancelado');


/* ---------------------------------------------------------------------
   2. DEPARTAMENTOS Y CIUDADES
   Los 12 municipios del Quindío (donde están los alojamientos) y 25
   ciudades de otros departamentos (origen de los clientes).
   --------------------------------------------------------------------- */
INSERT INTO departamento (nombre) VALUES ('Antioquia');
INSERT INTO departamento (nombre) VALUES ('Atlántico');
INSERT INTO departamento (nombre) VALUES ('Bogotá D.C.');
INSERT INTO departamento (nombre) VALUES ('Bolívar');
INSERT INTO departamento (nombre) VALUES ('Boyacá');
INSERT INTO departamento (nombre) VALUES ('Caldas');
INSERT INTO departamento (nombre) VALUES ('Cauca');
INSERT INTO departamento (nombre) VALUES ('Cundinamarca');
INSERT INTO departamento (nombre) VALUES ('Huila');
INSERT INTO departamento (nombre) VALUES ('Meta');
INSERT INTO departamento (nombre) VALUES ('Nariño');
INSERT INTO departamento (nombre) VALUES ('Norte de Santander');
INSERT INTO departamento (nombre) VALUES ('Quindío');
INSERT INTO departamento (nombre) VALUES ('Risaralda');
INSERT INTO departamento (nombre) VALUES ('Santander');
INSERT INTO departamento (nombre) VALUES ('Tolima');
INSERT INTO departamento (nombre) VALUES ('Valle del Cauca');

-- Quindío
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Armenia', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Buenavista', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Calarcá', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Circasia', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Córdoba', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Filandia', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Génova', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'La Tebaida', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Montenegro', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Pijao', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Quimbaya', id FROM departamento WHERE nombre = 'Quindío';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Salento', id FROM departamento WHERE nombre = 'Quindío';
-- Bogotá D.C.
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Bogotá', id FROM departamento WHERE nombre = 'Bogotá D.C.';
-- Antioquia
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Medellín', id FROM departamento WHERE nombre = 'Antioquia';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Envigado', id FROM departamento WHERE nombre = 'Antioquia';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Rionegro', id FROM departamento WHERE nombre = 'Antioquia';
-- Valle del Cauca
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Cali', id FROM departamento WHERE nombre = 'Valle del Cauca';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Palmira', id FROM departamento WHERE nombre = 'Valle del Cauca';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Tuluá', id FROM departamento WHERE nombre = 'Valle del Cauca';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Cartago', id FROM departamento WHERE nombre = 'Valle del Cauca';
-- Risaralda
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Pereira', id FROM departamento WHERE nombre = 'Risaralda';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Dosquebradas', id FROM departamento WHERE nombre = 'Risaralda';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Santa Rosa de Cabal', id FROM departamento WHERE nombre = 'Risaralda';
-- Caldas
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Manizales', id FROM departamento WHERE nombre = 'Caldas';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Chinchiná', id FROM departamento WHERE nombre = 'Caldas';
-- Atlántico
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Barranquilla', id FROM departamento WHERE nombre = 'Atlántico';
-- Bolívar
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Cartagena', id FROM departamento WHERE nombre = 'Bolívar';
-- Santander
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Bucaramanga', id FROM departamento WHERE nombre = 'Santander';
-- Norte de Santander
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Cúcuta', id FROM departamento WHERE nombre = 'Norte de Santander';
-- Tolima
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Ibagué', id FROM departamento WHERE nombre = 'Tolima';
-- Huila
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Neiva', id FROM departamento WHERE nombre = 'Huila';
-- Meta
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Villavicencio', id FROM departamento WHERE nombre = 'Meta';
-- Boyacá
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Tunja', id FROM departamento WHERE nombre = 'Boyacá';
-- Nariño
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Pasto', id FROM departamento WHERE nombre = 'Nariño';
-- Cauca
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Popayán', id FROM departamento WHERE nombre = 'Cauca';
-- Cundinamarca
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Chía', id FROM departamento WHERE nombre = 'Cundinamarca';
INSERT INTO ciudad (nombre, id_departamento) SELECT 'Zipaquirá', id FROM departamento WHERE nombre = 'Cundinamarca';


/* ---------------------------------------------------------------------
   3. TEMPORADAS 2024-2026
   Cubren sin huecos ni solapes desde el 15-dic-2023 hasta el 15-ene-2027
   (reservas de 2024 a 2026 y salidas en enero de 2027). Cada día
   pertenece a una sola temporada.
     Alta : diciembre-enero (15-dic a 15-ene), Semana Santa (Domingo de
            Ramos a Domingo de Resurrección), mitad de año (15-jun a
            15-jul) y puentes festivos (las 3 noches del fin de semana
            largo de cada festivo en lunes o viernes, según la Ley Emiliani).
     Media: 1 a 14-jun, 16-jul a 31-ago, octubre y 1 a 14-dic.
     Baja : el resto del año.
   Las fechas son las noches: una noche con fecha d pertenece a la
   temporada cuyo rango contiene d.
   --------------------------------------------------------------------- */
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Diciembre-enero 2023-2024', DATE '2023-12-15', DATE '2024-01-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 16-ene al 23-mar', DATE '2024-01-16', DATE '2024-03-23', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Semana Santa 2024', DATE '2024-03-24', DATE '2024-03-31', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 01-abr al 09-may', DATE '2024-04-01', DATE '2024-05-09', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Ascensión 2024', DATE '2024-05-10', DATE '2024-05-12', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 13-may al 30-may', DATE '2024-05-13', DATE '2024-05-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de Corpus Christi 2024', DATE '2024-05-31', DATE '2024-06-02', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 03-jun al 06-jun', DATE '2024-06-03', DATE '2024-06-06', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Sagrado Corazón 2024', DATE '2024-06-07', DATE '2024-06-09', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 10-jun al 14-jun', DATE '2024-06-10', DATE '2024-06-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Mitad de año 2024', DATE '2024-06-15', DATE '2024-07-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 16-jul al 15-ago', DATE '2024-07-16', DATE '2024-08-15', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Asunción 2024', DATE '2024-08-16', DATE '2024-08-18', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 19-ago al 31-ago', DATE '2024-08-19', DATE '2024-08-31', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 01-sep al 30-sep', DATE '2024-09-01', DATE '2024-09-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 01-oct al 10-oct', DATE '2024-10-01', DATE '2024-10-10', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Día de la Raza 2024', DATE '2024-10-11', DATE '2024-10-13', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 14-oct al 31-oct', DATE '2024-10-14', DATE '2024-10-31', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de Todos los Santos 2024', DATE '2024-11-01', DATE '2024-11-03', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 04-nov al 07-nov', DATE '2024-11-04', DATE '2024-11-07', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Independencia de Cartagena 2024', DATE '2024-11-08', DATE '2024-11-10', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2024: 11-nov al 30-nov', DATE '2024-11-11', DATE '2024-11-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2024: 01-dic al 14-dic', DATE '2024-12-01', DATE '2024-12-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Diciembre-enero 2024-2025', DATE '2024-12-15', DATE '2025-01-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 16-ene al 20-mar', DATE '2025-01-16', DATE '2025-03-20', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de San José 2025', DATE '2025-03-21', DATE '2025-03-23', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 24-mar al 12-abr', DATE '2025-03-24', DATE '2025-04-12', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Semana Santa 2025', DATE '2025-04-13', DATE '2025-04-20', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 21-abr al 29-may', DATE '2025-04-21', DATE '2025-05-29', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Ascensión 2025', DATE '2025-05-30', DATE '2025-06-01', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 02-jun al 14-jun', DATE '2025-06-02', DATE '2025-06-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Mitad de año 2025', DATE '2025-06-15', DATE '2025-07-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 16-jul al 14-ago', DATE '2025-07-16', DATE '2025-08-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Asunción 2025', DATE '2025-08-15', DATE '2025-08-17', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 18-ago al 31-ago', DATE '2025-08-18', DATE '2025-08-31', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 01-sep al 30-sep', DATE '2025-09-01', DATE '2025-09-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 01-oct al 09-oct', DATE '2025-10-01', DATE '2025-10-09', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Día de la Raza 2025', DATE '2025-10-10', DATE '2025-10-12', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 13-oct al 30-oct', DATE '2025-10-13', DATE '2025-10-30', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de Todos los Santos 2025', DATE '2025-10-31', DATE '2025-11-02', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 03-nov al 13-nov', DATE '2025-11-03', DATE '2025-11-13', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Independencia de Cartagena 2025', DATE '2025-11-14', DATE '2025-11-16', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2025: 17-nov al 30-nov', DATE '2025-11-17', DATE '2025-11-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 01-dic al 04-dic', DATE '2025-12-01', DATE '2025-12-04', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Inmaculada Concepción 2025', DATE '2025-12-05', DATE '2025-12-07', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2025: 08-dic al 14-dic', DATE '2025-12-08', DATE '2025-12-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Diciembre-enero 2025-2026', DATE '2025-12-15', DATE '2026-01-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 16-ene al 19-mar', DATE '2026-01-16', DATE '2026-03-19', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de San José 2026', DATE '2026-03-20', DATE '2026-03-22', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 23-mar al 28-mar', DATE '2026-03-23', DATE '2026-03-28', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Semana Santa 2026', DATE '2026-03-29', DATE '2026-04-05', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 06-abr al 29-abr', DATE '2026-04-06', DATE '2026-04-29', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Día del Trabajo 2026', DATE '2026-04-30', DATE '2026-05-02', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 03-may al 14-may', DATE '2026-05-03', DATE '2026-05-14', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Ascensión 2026', DATE '2026-05-15', DATE '2026-05-17', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 18-may al 31-may', DATE '2026-05-18', DATE '2026-05-31', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 01-jun al 04-jun', DATE '2026-06-01', DATE '2026-06-04', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de Corpus Christi 2026', DATE '2026-06-05', DATE '2026-06-07', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 08-jun al 11-jun', DATE '2026-06-08', DATE '2026-06-11', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Sagrado Corazón 2026', DATE '2026-06-12', DATE '2026-06-14', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Mitad de año 2026', DATE '2026-06-15', DATE '2026-07-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 16-jul al 16-jul', DATE '2026-07-16', DATE '2026-07-16', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Independencia 2026', DATE '2026-07-17', DATE '2026-07-19', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 20-jul al 05-ago', DATE '2026-07-20', DATE '2026-08-05', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Batalla de Boyacá 2026', DATE '2026-08-06', DATE '2026-08-08', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 09-ago al 13-ago', DATE '2026-08-09', DATE '2026-08-13', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Asunción 2026', DATE '2026-08-14', DATE '2026-08-16', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 17-ago al 31-ago', DATE '2026-08-17', DATE '2026-08-31', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 01-sep al 30-sep', DATE '2026-09-01', DATE '2026-09-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 01-oct al 08-oct', DATE '2026-10-01', DATE '2026-10-08', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente del Día de la Raza 2026', DATE '2026-10-09', DATE '2026-10-11', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 12-oct al 29-oct', DATE '2026-10-12', DATE '2026-10-29', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de Todos los Santos 2026', DATE '2026-10-30', DATE '2026-11-01', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 02-nov al 12-nov', DATE '2026-11-02', DATE '2026-11-12', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Puente de la Independencia de Cartagena 2026', DATE '2026-11-13', DATE '2026-11-15', id FROM tipo_temporada WHERE nombre = 'Alta';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Baja 2026: 16-nov al 30-nov', DATE '2026-11-16', DATE '2026-11-30', id FROM tipo_temporada WHERE nombre = 'Baja';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Media 2026: 01-dic al 14-dic', DATE '2026-12-01', DATE '2026-12-14', id FROM tipo_temporada WHERE nombre = 'Media';
INSERT INTO temporada (nombre, fecha_inicio, fecha_fin, id_tipo_temporada) SELECT 'Diciembre-enero 2026-2027', DATE '2026-12-15', DATE '2027-01-15', id FROM tipo_temporada WHERE nombre = 'Alta';


/* ---------------------------------------------------------------------
   4. ALOJAMIENTOS
   60 alojamientos repartidos de forma desigual según el peso turístico
   de cada municipio: Salento 12, Armenia 10, Filandia 8, Montenegro 7,
   Quimbaya 6, Calarcá 5, Circasia 4, La Tebaida 3, Pijao 2, Córdoba 1,
   Génova 1 y Buenavista 1. El orden de inserción importa: las secciones
   5 y 7 asignan habitaciones y servicios en este mismo orden.
   --------------------------------------------------------------------- */
-- Salento
-- 1. 5 habitaciones, 4 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Mirador', 'Km 3 vía Salento-Boquía', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Finca cafetera';
-- 2. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Palma de Cera', 'Km 9 vía Salento-Cocora', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Finca cafetera';
-- 3. 6 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Los Guaduales', 'Km 9 vía Salento-Cocora', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Finca cafetera';
-- 4. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Cafetal', 'Km 7 vía Salento-Cocora', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Finca cafetera';
-- 5. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Monteverde', 'Km 7 vía Salento-Cocora', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Glamping';
-- 6. 3 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping La Aurora', 'Vereda Morelia, Salento', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Glamping';
-- 7. 6 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Villa Café', 'Km 7 vía Salento-Cocora', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Glamping';
-- 8. 5 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Santa Bárbara', 'Km 3 vía Salento-Boquía', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Glamping';
-- 9. 10 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal La Esperanza', 'Calle 19 # 9-83', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Hostal';
-- 10. 8 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Altos del Valle', 'Calle 5 # 39-83', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Hostal';
-- 11. 12 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal El Edén Verde', 'Calle 13 # 8-80', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Hostal';
-- 12. 16 habitaciones, 6 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel La Cascada', 'Calle 20 # 5-89', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Salento' AND t.nombre = 'Hotel';
-- Armenia
-- 13. 40 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Bambú Real', 'Carrera 23 # 36-64', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hotel';
-- 14. 32 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel El Roble', 'Carrera 20 # 31-56', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hotel';
-- 15. 24 habitaciones, 6 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Las Heliconias', 'Calle 27 # 13-41', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hotel';
-- 16. 18 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel El Guayacán', 'Carrera 18 # 33-53', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hotel';
-- 17. 12 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Aroma de Café', 'Carrera 11 # 40-19', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hotel';
-- 18. 6 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal La Montaña', 'Carrera 7 # 23-29', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hostal';
-- 19. 9 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal El Arrayán', 'Carrera 3 # 6-81', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hostal';
-- 20. 7 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Brisas del Quindío', 'Carrera 12 # 24-86', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hostal';
-- 21. 11 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Colibrí', 'Carrera 4 # 7-44', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Hostal';
-- 22. 8 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Tierra Alta', 'Vereda El Agrado, Armenia', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Armenia' AND t.nombre = 'Finca cafetera';
-- Filandia
-- 23. 4 habitaciones, 4 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Colina', 'Vereda El Caimo, Filandia', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Finca cafetera';
-- 24. 5 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Los Naranjos', 'Km 11 vía Filandia-Circasia', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Finca cafetera';
-- 25. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Bosque', 'Vereda La Granja, Filandia', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Finca cafetera';
-- 26. 3 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping La Ceiba', 'Vereda La Granja, Filandia', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Glamping';
-- 27. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping El Balcón', 'Vereda El Roble, Filandia', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Glamping';
-- 28. 5 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Rincón Cafetero', 'Km 5 vía Filandia-Quimbaya', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Glamping';
-- 29. 5 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Las Orquídeas', 'Carrera 14 # 33-20', 2, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Hostal';
-- 30. 8 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Vista Hermosa', 'Carrera 14 # 37-45', 2, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Filandia' AND t.nombre = 'Hostal';
-- Montenegro
-- 31. 7 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Paraíso', 'Vereda Cruces, Montenegro', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Finca cafetera';
-- 32. 6 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Pradera', 'Vereda La Granja, Montenegro', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Finca cafetera';
-- 33. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Los Andes', 'Vereda La Sierra, Montenegro', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Finca cafetera';
-- 34. 5 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Turpial', 'Km 3 vía Montenegro-Pueblo Tapao', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Finca cafetera';
-- 35. 36 habitaciones, 6 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel La Arboleda', 'Calle 2 # 33-85', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Hotel';
-- 36. 20 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Mirador del Cocora', 'Carrera 11 # 2-28', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Hotel';
-- 37. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping El Barranquero', 'Km 10 vía Montenegro-Armenia', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Montenegro' AND t.nombre = 'Glamping';
-- Quimbaya
-- 38. 6 habitaciones, 4 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Quebrada', 'Vereda Cruces, Quimbaya', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Finca cafetera';
-- 39. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Cielo Abierto', 'Vereda La Palmera, Quimbaya', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Finca cafetera';
-- 40. 5 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Estrella', 'Vereda Cruces, Quimbaya', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Finca cafetera';
-- 41. 28 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel El Refugio', 'Carrera 14 # 27-23', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Hotel';
-- 42. 6 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Los Pinos', 'Vereda La Palmera, Quimbaya', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Glamping';
-- 43. 6 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Cerro Alto', 'Calle 8 # 30-30', 2, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Quimbaya' AND t.nombre = 'Hostal';
-- Calarcá
-- 44. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Herradura', 'Km 1 vía Calarcá-La Virginia', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Calarcá' AND t.nombre = 'Finca cafetera';
-- 45. 7 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Manantial', 'Km 9 vía Calarcá-La Virginia', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Calarcá' AND t.nombre = 'Finca cafetera';
-- 46. 6 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Tulia', 'Vereda El Agrado, Calarcá', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Calarcá' AND t.nombre = 'Finca cafetera';
-- 47. 14 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Las Acacias', 'Carrera 6 # 18-54', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Calarcá' AND t.nombre = 'Hotel';
-- 48. 10 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal El Recreo', 'Carrera 17 # 9-24', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Calarcá' AND t.nombre = 'Hostal';
-- Circasia
-- 49. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Montebello', 'Vereda El Roble, Circasia', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Circasia' AND t.nombre = 'Finca cafetera';
-- 50. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca La Victoria', 'Km 2 vía Circasia-Armenia', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Circasia' AND t.nombre = 'Finca cafetera';
-- 51. 4 habitaciones, 2 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping El Retiro', 'Vereda El Caimo, Circasia', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Circasia' AND t.nombre = 'Glamping';
-- 52. 7 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal La Floresta', 'Calle 18 # 3-36', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Circasia' AND t.nombre = 'Hostal';
-- La Tebaida
-- 53. 22 habitaciones, 5 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hotel Sol de Montaña', 'Carrera 6 # 36-13', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'La Tebaida' AND t.nombre = 'Hotel';
-- 54. 5 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Jardín', 'Km 11 vía La Tebaida-Armenia', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'La Tebaida' AND t.nombre = 'Finca cafetera';
-- 55. 9 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal Luna Verde', 'Carrera 18 # 25-31', 3, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'La Tebaida' AND t.nombre = 'Hostal';
-- Pijao
-- 56. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Los Arrieros', 'Vereda Cruces, Pijao', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Pijao' AND t.nombre = 'Finca cafetera';
-- 57. 6 habitaciones, 1 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Hostal La Primavera', 'Carrera 22 # 16-88', 2, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Pijao' AND t.nombre = 'Hostal';
-- Córdoba
-- 58. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca El Silencio', 'Vereda Pueblo Tapao, Córdoba', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Córdoba' AND t.nombre = 'Finca cafetera';
-- Génova
-- 59. 4 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Finca Bahareque', 'Vereda La Sierra, Génova', 5, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Génova' AND t.nombre = 'Finca cafetera';
-- Buenavista
-- 60. 3 habitaciones, 3 servicios
INSERT INTO alojamiento (nombre_comercial, direccion, calificacion_autoasignada, id_ciudad, id_tipo_alojamiento) SELECT 'Glamping Guadual del Río', 'Km 12 vía Buenavista-Pijao', 4, c.id, t.id FROM ciudad c, departamento d, tipo_alojamiento t WHERE c.id_departamento = d.id AND d.nombre = 'Quindío' AND c.nombre = 'Buenavista' AND t.nombre = 'Glamping';


/* ---------------------------------------------------------------------
   5. HABITACIONES Y TARIFAS
   Cada alojamiento recibe su número de habitaciones (lista c_hab, en el
   orden de la sección 4): hoteles de 12 a 40, hostales de 5 a 12, fincas
   de 3 a 8 y glampings de 3 a 6. El tipo, la capacidad y el precio base
   de cada habitación dependen del tipo de alojamiento.
   La tarifa sale del cruce habitación x temporada:
     valor_noche = precio base x factor de la temporada x ajuste anual
   El factor de temporada es propio de cada alojamiento: algunos suben
   mucho en temporada alta y otros casi nada para competir por volumen.
   El ajuste anual es +7 % por año desde 2024.
   --------------------------------------------------------------------- */
DECLARE
  TYPE t_lista IS TABLE OF PLS_INTEGER;
  -- Habitaciones por alojamiento, en el orden de inserción de la sección 4
  c_hab CONSTANT t_lista := t_lista(
    5, 4, 6, 3, 4, 3, 6, 5, 10, 8, 12, 16, 40, 32, 24, 18, 12, 6, 9, 7,
    11, 8, 4, 5, 3, 3, 4, 5, 5, 8, 7, 6, 4, 5, 36, 20, 3, 6, 3, 5,
    28, 6, 6, 4, 7, 6, 14, 10, 4, 3, 4, 7, 22, 5, 9, 3, 6, 3, 4, 3);

  v_i         PLS_INTEGER := 0;
  v_total     PLS_INTEGER := 0;
  v_r         NUMBER;
  v_tipo_hab  VARCHAR2(30);
  v_id_tipo   NUMBER;
  v_cap       PLS_INTEGER;
  v_base      NUMBER;
  v_numero    VARCHAR2(10);
  v_desc      VARCHAR2(300);
  v_id_hab    NUMBER;
  v_calidad   NUMBER;
  v_f_alta    NUMBER;
  v_f_media   NUMBER;
  v_f_baja    NUMBER;
BEGIN
  DBMS_RANDOM.SEED(2026001);

  FOR a IN (SELECT al.id, ta.nombre AS tipo
              FROM alojamiento al
              JOIN tipo_alojamiento ta ON ta.id = al.id_tipo_alojamiento
             ORDER BY al.id)
  LOOP
    v_i := v_i + 1;
    -- Factores propios del alojamiento: nivel de precios y variación por temporada
    v_calidad := DBMS_RANDOM.VALUE(0.85, 1.30);
    v_f_alta  := DBMS_RANDOM.VALUE(1.05, 1.60);
    v_f_media := DBMS_RANDOM.VALUE(0.95, 1.10);
    v_f_baja  := DBMS_RANDOM.VALUE(0.75, 0.95);

    FOR j IN 1 .. c_hab(v_i) LOOP
      -- Tipo de habitación según el tipo de alojamiento
      v_r := DBMS_RANDOM.VALUE;
      IF a.tipo = 'Hotel' THEN
        v_tipo_hab := CASE WHEN v_r < 0.35 THEN 'Sencilla' WHEN v_r < 0.80 THEN 'Doble' ELSE 'Suite' END;
      ELSIF a.tipo = 'Hostal' THEN
        v_tipo_hab := CASE WHEN v_r < 0.50 THEN 'Sencilla' ELSE 'Doble' END;
      ELSIF a.tipo = 'Finca cafetera' THEN
        v_tipo_hab := CASE WHEN v_r < 0.50 THEN 'Doble' WHEN v_r < 0.70 THEN 'Suite' ELSE 'Cabaña' END;
      ELSE  -- Glamping
        v_tipo_hab := CASE WHEN v_r < 0.60 THEN 'Suite' ELSE 'Cabaña' END;
      END IF;

      -- Capacidad máxima según el tipo de habitación
      IF v_tipo_hab = 'Sencilla' THEN
        v_cap := 1 + TRUNC(DBMS_RANDOM.VALUE * 2);      -- 1 a 2
      ELSIF v_tipo_hab = 'Doble' THEN
        v_cap := 2 + TRUNC(DBMS_RANDOM.VALUE * 2);      -- 2 a 3
      ELSIF v_tipo_hab = 'Suite' THEN
        v_cap := 2 + TRUNC(DBMS_RANDOM.VALUE * 3);      -- 2 a 4
      ELSE
        v_cap := 4 + TRUNC(DBMS_RANDOM.VALUE * 3);      -- 4 a 6
      END IF;

      -- Precio base por noche en pesos de 2024
      v_base := CASE a.tipo || '/' || v_tipo_hab
                  WHEN 'Hotel/Sencilla'       THEN 150000
                  WHEN 'Hotel/Doble'          THEN 210000
                  WHEN 'Hotel/Suite'          THEN 380000
                  WHEN 'Hostal/Sencilla'      THEN  55000
                  WHEN 'Hostal/Doble'         THEN  90000
                  WHEN 'Finca cafetera/Doble' THEN 240000
                  WHEN 'Finca cafetera/Suite' THEN 340000
                  WHEN 'Finca cafetera/Cabaña' THEN 420000
                  WHEN 'Glamping/Suite'       THEN 380000
                  ELSE                             460000   -- Glamping/Cabaña
                END * v_calidad * DBMS_RANDOM.VALUE(0.95, 1.05);

      -- Número: por pisos en los hoteles (101, 102, ..., 201, ...); consecutivo en los demás
      IF a.tipo = 'Hotel' THEN
        v_numero := TO_CHAR((TRUNC((j - 1) / 10) + 1) * 100 + MOD(j - 1, 10) + 1);
      ELSE
        v_numero := TO_CHAR(j);
      END IF;

      -- Descripción (opcional: 1 de cada 10 queda vacía)
      v_r := DBMS_RANDOM.VALUE;
      IF v_r < 0.10 THEN
        v_desc := NULL;
      ELSIF v_tipo_hab = 'Sencilla' THEN
        v_desc := 'Habitación sencilla con cama semidoble y baño privado';
      ELSIF v_tipo_hab = 'Doble' AND v_r < 0.55 THEN
        v_desc := 'Habitación doble con vista a las montañas';
      ELSIF v_tipo_hab = 'Doble' THEN
        v_desc := 'Habitación doble con dos camas y balcón';
      ELSIF v_tipo_hab = 'Suite' AND a.tipo = 'Glamping' THEN
        v_desc := 'Domo con cama king y jacuzzi privado';
      ELSIF v_tipo_hab = 'Suite' THEN
        v_desc := 'Suite con sala, minibar y vista al paisaje cafetero';
      ELSE
        v_desc := 'Cabaña independiente con cocina y zona de fogata';
      END IF;

      SELECT id INTO v_id_tipo FROM tipo_habitacion WHERE nombre = v_tipo_hab;

      INSERT INTO habitacion (numero, capacidad_maxima, descripcion, id_alojamiento, id_tipo_habitacion)
      VALUES (v_numero, v_cap, v_desc, a.id, v_id_tipo)
      RETURNING id INTO v_id_hab;

      -- Una tarifa por cada temporada (cruce habitación x temporada)
      INSERT INTO tarifa (valor_noche, id_habitacion, id_temporada)
      SELECT ROUND(v_base
                   * CASE tt.nombre WHEN 'Alta' THEN v_f_alta WHEN 'Media' THEN v_f_media ELSE v_f_baja END
                   * (1 + 0.07 * (EXTRACT(YEAR FROM tm.fecha_inicio) - 2024)), -3),
             v_id_hab,
             tm.id
        FROM temporada tm
        JOIN tipo_temporada tt ON tt.id = tm.id_tipo_temporada;

      v_total := v_total + 1;
    END LOOP;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Habitaciones: ' || v_total);
END;
/


/* ---------------------------------------------------------------------
   6. CLIENTES Y SUS TELÉFONOS
   3.000 clientes con nombres y apellidos colombianos. La ciudad de
   origen se elige con pesos: más clientes de Bogotá, Medellín y Cali,
   y una minoría del propio Quindío. El número de documento es único
   por construcción dentro de cada tipo de documento.
   --------------------------------------------------------------------- */
DECLARE
  TYPE t_txt IS TABLE OF VARCHAR2(40);
  TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

  c_hombres CONSTANT t_txt := t_txt('Andrés', 'Carlos', 'Juan', 'Santiago', 'Felipe', 'Sebastián', 'Mateo',
                                    'Daniel', 'Alejandro', 'Camilo', 'David', 'Jorge', 'Luis', 'Diego',
                                    'Julián', 'Miguel', 'Nicolás', 'Ricardo', 'Óscar', 'Esteban');
  c_mujeres CONSTANT t_txt := t_txt('María', 'Laura', 'Valentina', 'Daniela', 'Camila', 'Sofía', 'Juliana',
                                    'Natalia', 'Paula', 'Carolina', 'Andrea', 'Mariana', 'Isabella', 'Gabriela',
                                    'Catalina', 'Ana', 'Diana', 'Luisa', 'Manuela', 'Sara');
  c_apellidos CONSTANT t_txt := t_txt('Gómez', 'Rodríguez', 'Martínez', 'López', 'García', 'Hernández', 'Ramírez',
                                      'Torres', 'Restrepo', 'Ospina', 'Giraldo', 'Cardona', 'Arango', 'Valencia',
                                      'Muñoz', 'Rojas', 'Castaño', 'Londoño', 'Jaramillo', 'Salazar', 'Quintero',
                                      'Mejía', 'Correa', 'Zapata', 'Henao', 'Marín', 'Osorio', 'Vargas', 'Duque', 'Pérez');
  c_dominios CONSTANT t_txt := t_txt('gmail.com', 'gmail.com', 'gmail.com', 'hotmail.com', 'outlook.com', 'yahoo.com');
  c_celular  CONSTANT t_txt := t_txt('300', '301', '302', '304', '305', '310', '311', '312', '313', '314',
                                     '315', '316', '317', '318', '320', '321', '323', '350');

  v_ciu_id     t_num;
  v_ciu_peso   t_num;
  v_n_ciu      PLS_INTEGER := 0;
  v_peso_total NUMBER := 0;
  v_acum       NUMBER;
  v_r          NUMBER;
  v_id_cc      NUMBER;
  v_id_ce      NUMBER;
  v_id_pas     NUMBER;
  v_tipo_doc   NUMBER;
  v_doc        VARCHAR2(20);
  v_lista      t_txt;
  v_k          PLS_INTEGER;
  v_nombre1    VARCHAR2(40);
  v_nombres    VARCHAR2(60);
  v_ape1       VARCHAR2(40);
  v_ape2       VARCHAR2(40);
  v_correo     VARCHAR2(100);
  v_ciudad     NUMBER;
  v_id_cli     NUMBER;
  v_tel        VARCHAR2(20);
BEGIN
  DBMS_RANDOM.SEED(2026002);

  SELECT id INTO v_id_cc  FROM tipo_documento WHERE nombre = 'Cédula de ciudadanía';
  SELECT id INTO v_id_ce  FROM tipo_documento WHERE nombre = 'Cédula de extranjería';
  SELECT id INTO v_id_pas FROM tipo_documento WHERE nombre = 'Pasaporte';

  -- Peso de cada ciudad como origen de los clientes
  FOR c IN (SELECT id, nombre FROM ciudad ORDER BY id) LOOP
    v_n_ciu := v_n_ciu + 1;
    v_ciu_id(v_n_ciu) := c.id;
    v_ciu_peso(v_n_ciu) := CASE c.nombre
                             WHEN 'Bogotá'       THEN 25
                             WHEN 'Medellín'     THEN 12
                             WHEN 'Cali'         THEN 12
                             WHEN 'Pereira'      THEN 6
                             WHEN 'Armenia'      THEN 6
                             WHEN 'Manizales'    THEN 4
                             WHEN 'Barranquilla' THEN 4
                             WHEN 'Bucaramanga'  THEN 3
                             WHEN 'Ibagué'       THEN 3
                             ELSE 1
                           END;
    v_peso_total := v_peso_total + v_ciu_peso(v_n_ciu);
  END LOOP;

  FOR i IN 1 .. 3000 LOOP
    -- Tipo y número de documento
    v_r := DBMS_RANDOM.VALUE;
    IF v_r < 0.90 THEN
      v_tipo_doc := v_id_cc;
      IF DBMS_RANDOM.VALUE < 0.40 THEN
        v_doc := TO_CHAR(10000000 + i * 3001 + TRUNC(DBMS_RANDOM.VALUE * 3000));        -- 8 dígitos
      ELSE
        v_doc := TO_CHAR(1000000000 + i * 313003 + TRUNC(DBMS_RANDOM.VALUE * 313000));  -- 10 dígitos
      END IF;
    ELSIF v_r < 0.95 THEN
      v_tipo_doc := v_id_ce;
      v_doc := TO_CHAR(100000 + i * 293 + TRUNC(DBMS_RANDOM.VALUE * 290));
    ELSE
      v_tipo_doc := v_id_pas;
      v_doc := 'AW' || TO_CHAR(100000 + i * 311 + TRUNC(DBMS_RANDOM.VALUE * 300));
    END IF;

    -- Uno o dos nombres (distintos) y dos apellidos
    IF DBMS_RANDOM.VALUE < 0.50 THEN
      v_lista := c_hombres;
    ELSE
      v_lista := c_mujeres;
    END IF;
    v_k := 1 + TRUNC(DBMS_RANDOM.VALUE * v_lista.COUNT);
    v_nombre1 := v_lista(v_k);
    IF DBMS_RANDOM.VALUE < 0.40 THEN
      v_nombres := v_nombre1 || ' ' || v_lista(MOD(v_k + TRUNC(DBMS_RANDOM.VALUE * (v_lista.COUNT - 1)), v_lista.COUNT) + 1);
    ELSE
      v_nombres := v_nombre1;
    END IF;
    v_ape1 := c_apellidos(1 + TRUNC(DBMS_RANDOM.VALUE * c_apellidos.COUNT));
    v_ape2 := c_apellidos(1 + TRUNC(DBMS_RANDOM.VALUE * c_apellidos.COUNT));

    -- Correo sin tildes: nombre.apellido + consecutivo
    v_correo := LOWER(TRANSLATE(v_nombre1 || '.' || v_ape1, 'ÁÉÍÓÚáéíóúÑñÜü', 'AEIOUaeiouNnUu'))
                || i || '@' || c_dominios(1 + TRUNC(DBMS_RANDOM.VALUE * c_dominios.COUNT));

    -- Ciudad de origen según los pesos
    v_r := DBMS_RANDOM.VALUE * v_peso_total;
    v_acum := 0;
    v_ciudad := v_ciu_id(v_n_ciu);
    FOR k IN 1 .. v_n_ciu LOOP
      v_acum := v_acum + v_ciu_peso(k);
      IF v_r < v_acum THEN
        v_ciudad := v_ciu_id(k);
        EXIT;
      END IF;
    END LOOP;

    INSERT INTO cliente (numero_documento, nombres, apellidos, correo_electronico, id_tipo_documento, id_ciudad)
    VALUES (v_doc, v_nombres, v_ape1 || ' ' || v_ape2, v_correo, v_tipo_doc, v_ciudad)
    RETURNING id INTO v_id_cli;

    -- Uno o dos celulares
    FOR t IN 1 .. CASE WHEN DBMS_RANDOM.VALUE < 0.70 THEN 1 ELSE 2 END LOOP
      v_tel := c_celular(1 + TRUNC(DBMS_RANDOM.VALUE * c_celular.COUNT))
               || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE * 10000000)), 7, '0');
      INSERT INTO telefono_cliente (numero, id_cliente) VALUES (v_tel, v_id_cli);
    END LOOP;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Clientes: 3000');
END;
/


/* ---------------------------------------------------------------------
   7. CONTACTOS DE LOS ALOJAMIENTOS, SERVICIOS Y USUARIOS
   Cada alojamiento tiene de 1 a 3 teléfonos y de 0 a 2 correos. Los
   180 servicios se reparten según la lista c_srv (más en hoteles y
   fincas): cada alojamiento toma, en orden, los primeros servicios del
   catálogo de su tipo, con precio ajustado a su nivel.
   --------------------------------------------------------------------- */
DECLARE
  TYPE t_lista IS TABLE OF PLS_INTEGER;
  TYPE t_txt   IS TABLE OF VARCHAR2(300);
  TYPE t_val   IS TABLE OF NUMBER;

  -- Servicios por alojamiento, en el orden de inserción de la sección 4 (suman 180)
  c_srv CONSTANT t_lista := t_lista(
    4, 3, 3, 3, 3, 2, 3, 3, 1, 2, 1, 6, 5, 5, 6, 5, 5, 1, 2, 1,
    1, 3, 4, 3, 3, 2, 3, 2, 2, 1, 3, 3, 3, 3, 6, 5, 3, 4, 3, 3,
    5, 3, 1, 3, 3, 3, 5, 2, 3, 3, 2, 1, 5, 3, 1, 3, 1, 3, 3, 3);

  -- Catálogo de servicios por tipo de alojamiento: tipo, nombre, descripción y precio base
  c_s_tipo CONSTANT t_txt := t_txt(
    'Hotel', 'Hotel', 'Hotel', 'Hotel', 'Hotel', 'Hotel',
    'Finca cafetera', 'Finca cafetera', 'Finca cafetera', 'Finca cafetera',
    'Glamping', 'Glamping', 'Glamping',
    'Hostal', 'Hostal');
  c_s_nombre CONSTANT t_txt := t_txt(
    'Desayuno buffet', 'Transporte al aeropuerto', 'Spa y masajes', 'Tour del café',
    'Tour al Valle del Cocora', 'Lavandería',
    'Desayuno típico', 'Tour del café en la finca', 'Cabalgata', 'Avistamiento de aves',
    'Desayuno a la carta', 'Cena romántica', 'Jacuzzi privado',
    'Desayuno continental', 'Alquiler de bicicletas');
  c_s_desc CONSTANT t_txt := t_txt(
    'Desayuno buffet con productos de la región',
    'Traslado de ida o regreso al aeropuerto El Edén',
    'Sesión de masaje relajante de 60 minutos',
    'Recorrido por una finca cafetera con degustación',
    'Excursión guiada de día completo al Valle del Cocora',
    'Lavado y planchado de prendas por bolsa',
    'Desayuno campesino con arepa, huevos y chocolate',
    'Recorrido por el cultivo y el proceso del café',
    'Paseo a caballo por senderos cafeteros',
    'Recorrido guiado de avistamiento de aves al amanecer',
    'Desayuno servido en el domo o la cabaña',
    'Cena a la luz de las velas para dos personas',
    'Uso del jacuzzi privado durante dos horas',
    'Café, pan, fruta y jugo',
    'Bicicleta por día con casco');
  c_s_precio CONSTANT t_val := t_val(
    35000, 80000, 150000, 90000, 120000, 25000,
    28000, 70000, 85000, 95000,
    40000, 180000, 120000,
    18000, 45000);

  v_i       PLS_INTEGER := 0;
  v_k       PLS_INTEGER;
  v_r       NUMBER;
  v_tel     VARCHAR2(20);
  v_slug    VARCHAR2(100);
  v_calidad NUMBER;
  v_nombre  VARCHAR2(60);
  v_desc    VARCHAR2(300);
  v_precio  NUMBER;
BEGIN
  DBMS_RANDOM.SEED(2026003);

  FOR a IN (SELECT al.id, al.nombre_comercial, ta.nombre AS tipo
              FROM alojamiento al
              JOIN tipo_alojamiento ta ON ta.id = al.id_tipo_alojamiento
             ORDER BY al.id)
  LOOP
    v_i := v_i + 1;

    -- Teléfonos: fijo del Quindío (indicativo 606) o celular
    FOR t IN 1 .. 1 + TRUNC(DBMS_RANDOM.VALUE * 3) LOOP
      IF DBMS_RANDOM.VALUE < 0.50 THEN
        v_tel := '606' || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE * 10000000)), 7, '0');
      ELSE
        v_tel := '31' || LPAD(TO_CHAR(TRUNC(DBMS_RANDOM.VALUE * 100000000)), 8, '0');
      END IF;
      INSERT INTO telefono_alojamiento (numero, id_alojamiento) VALUES (v_tel, a.id);
    END LOOP;

    -- Correos: reservas@ (85 %) e info@ (30 %), con el nombre sin espacios ni tildes
    v_slug := LOWER(TRANSLATE(a.nombre_comercial, 'ÁÉÍÓÚáéíóúÑñÜü ', 'AEIOUaeiouNnUu'));
    v_r := DBMS_RANDOM.VALUE;
    IF v_r >= 0.15 THEN
      INSERT INTO correo_alojamiento (correo, id_alojamiento) VALUES ('reservas@' || v_slug || '.com', a.id);
    END IF;
    IF v_r >= 0.70 THEN
      INSERT INTO correo_alojamiento (correo, id_alojamiento) VALUES ('info@' || v_slug || '.com', a.id);
    END IF;

    -- Servicios: los primeros c_srv(v_i) del catálogo de su tipo
    v_calidad := DBMS_RANDOM.VALUE(0.85, 1.25);
    v_k := 0;
    FOR s IN 1 .. c_s_tipo.COUNT LOOP
      IF c_s_tipo(s) = a.tipo AND v_k < c_srv(v_i) THEN
        v_k := v_k + 1;
        v_nombre := c_s_nombre(s);
        v_desc   := c_s_desc(s);
        v_precio := ROUND(c_s_precio(s) * v_calidad, -3);
        INSERT INTO servicio (nombre, descripcion, precio, id_alojamiento)
        VALUES (v_nombre, v_desc, v_precio, a.id);
      END IF;
    END LOOP;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Alojamientos con contactos y servicios: ' || v_i);
END;
/

-- Usuarios: 2 administradores de la plataforma (sin alojamiento) y
-- 2 encargados por tipo de alojamiento (los dos primeros de cada tipo).
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) VALUES ('admin.valencia', 'Juliana Valencia Ríos', 'juliana.valencia@turismouq.co', 'S', 'ADMINISTRADOR', NULL);
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) VALUES ('admin.cardona', 'Andrés Cardona Gil', 'andres.cardona@turismouq.co', 'S', 'ADMINISTRADOR', NULL);
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.ospina', 'Carolina Ospina Mejía', 'carolina.ospina@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Finca El Mirador';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.restrepo', 'Mateo Restrepo Duque', 'mateo.restrepo@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Finca La Palma de Cera';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.giraldo', 'Laura Giraldo Henao', 'laura.giraldo@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Glamping Monteverde';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.arango', 'Santiago Arango Ríos', 'santiago.arango@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Glamping La Aurora';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.londono', 'Natalia Londoño Vélez', 'natalia.londono@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Hostal La Esperanza';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.henao', 'Felipe Henao Castaño', 'felipe.henao@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Hostal Altos del Valle';
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.zapata', 'Daniela Zapata Ruiz', 'daniela.zapata@turismouq.co', 'S', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Hotel La Cascada';
-- Encargado inactivo
INSERT INTO usuario_sistema (username, nombre, correo, activo, rol, id_alojamiento) SELECT 'enc.marin', 'Camilo Marín Ocampo', 'camilo.marin@turismouq.co', 'N', 'ENCARGADO', id FROM alojamiento WHERE nombre_comercial = 'Hotel Bambú Real';


/* ---------------------------------------------------------------------
   8. RESERVAS, NOCHES, SERVICIOS CONTRATADOS, PAGOS Y RESEÑAS
   Se generan 25.500 reservas entre el 1-ene-2024 y el 31-dic-2026.
   Cada intento:
     a) Sortea un día de check-in y lo acepta con más probabilidad en
        temporada alta, en fin de semana y en los años más recientes
        (estacionalidad y crecimiento).
     b) Elige el alojamiento con un peso que combina su tamaño, el
        atractivo del municipio y un factor propio (unos venden más).
     c) Sortea las noches (1 a 7, casi siempre 2 o 3) y las habitaciones
        (12 % de las reservas tienen 2 a 4).
     d) Fija el estado según la fecha de corte (30-sep-2026).
     e) Busca habitaciones libres: una línea activa no puede solaparse
        con otra línea activa de la misma habitación. Las líneas
        canceladas no ocupan la habitación. Si la primera habitación no
        encuentra cupo, el intento se descarta.
     f) Inserta la reserva, sus líneas y una fila por noche con la tarifa
        de la temporada de esa noche. valor_estadia = suma de sus noches.
     g) Agrega servicios del mismo alojamiento, el cobro total y los
        pagos, y una reseña para la mitad de las reservas completadas.
   Reglas de pagos:
     - Completada: pago único (55 %) o anticipo de 30-50 % + saldo al
       llegar. A veces hay un intento fallido antes del pago bueno.
     - Confirmada: pago completo (40 %) o solo anticipo; a veces el
       saldo queda como pago pendiente para el día del check-in.
     - Pendiente: sin pagos o con un pago pendiente.
     - Cancelada: el 75 % había pagado un anticipo. Si canceló con más de
       5 días de anticipación, recibe un reembolso del 80 % de lo pagado
       (un pago nuevo con estado 'reembolsado'); si no, lo pierde.
   --------------------------------------------------------------------- */
DECLARE
  -- Parámetros
  c_corte   CONSTANT DATE := DATE '2026-09-30';   -- fecha de corte de los datos
  c_ini     CONSTANT DATE := DATE '2024-01-01';   -- primer check-in posible
  c_fin     CONSTANT DATE := DATE '2026-12-31';   -- último check-in posible
  c_origen  CONSTANT DATE := DATE '2023-12-01';   -- origen de las llaves por fecha
  c_meta    CONSTANT PLS_INTEGER := 25500;        -- reservas a generar
  c_max_int CONSTANT PLS_INTEGER := 400000;       -- tope de intentos

  TYPE t_num   IS TABLE OF NUMBER       INDEX BY PLS_INTEGER;
  TYPE t_txt   IS TABLE OF VARCHAR2(10) INDEX BY PLS_INTEGER;
  TYPE t_fecha IS TABLE OF DATE         INDEX BY PLS_INTEGER;
  TYPE t_ids   IS TABLE OF NUMBER;
  TYPE t_coms  IS TABLE OF VARCHAR2(200);

  -- Temporada de cada noche (llave: fecha - c_origen)
  g_temp       t_num;
  g_temp_tipo  t_txt;
  -- Tarifa de cada habitación en cada temporada (llave: id_habitacion * 1000 + id_temporada)
  g_tar_id     t_num;
  g_tar_valor  t_num;
  -- Noches ocupadas (llave: id_habitacion * 10000 + (fecha - c_origen))
  g_ocupada    t_num;
  -- Alojamientos (posición 1..60)
  g_al_id      t_num;
  g_al_peso    t_num;   -- peso acumulado para elegir alojamiento
  g_al_media   t_num;   -- calificación media de sus reseñas
  g_al_hab1    t_num;   -- posición de su primera habitación en g_hab_id
  g_al_nhab    t_num;
  g_al_srv1    t_num;   -- posición de su primer servicio en g_srv_id
  g_al_nsrv    t_num;
  g_n_al       PLS_INTEGER := 0;
  -- Habitaciones y servicios, agrupados por alojamiento
  g_hab_id     t_num;
  g_hab_cap    t_num;
  g_srv_id     t_num;
  g_srv_precio t_num;
  -- Clientes
  g_cli_id     t_num;
  -- Carga de tarifas en bloque
  v_t_id       t_ids;
  v_t_hab      t_ids;
  v_t_temp     t_ids;
  v_t_val      t_ids;
  -- Líneas de la reserva en construcción
  l_hab        t_num;
  l_cap        t_num;
  l_canc       t_num;
  l_ci         t_fecha;
  l_co         t_fecha;

  -- Comentarios de reseñas según la calificación
  c_com_buenos CONSTANT t_coms := t_coms(
    'Excelente atención y una vista increíble del paisaje cafetero.',
    'Todo muy limpio y el desayuno delicioso. Volveríamos sin dudarlo.',
    'El personal fue muy amable y nos recomendó lugares hermosos.',
    'Ideal para descansar en familia, muy tranquilo.',
    'La habitación muy cómoda y el tour del café valió la pena.',
    'Gran ubicación y excelente relación entre calidad y precio.');
  c_com_medios CONSTANT t_coms := t_coms(
    'Buena estadía, aunque el wifi fallaba con frecuencia.',
    'El lugar es bonito, pero el servicio fue algo lento.',
    'Cumplió lo esperado, sin nada especial.',
    'La habitación estaba bien, pero se escuchaba mucho ruido.');
  c_com_malos CONSTANT t_coms := t_coms(
    'La habitación no coincidía con las fotos publicadas.',
    'Tuvimos problemas con el agua caliente todas las noches.',
    'Atención deficiente y demoras en el check-in.',
    'No volveríamos: el lugar necesita mantenimiento.');

  -- Ids de los catálogos
  v_er_pend  NUMBER;  v_er_conf  NUMBER;  v_er_canc  NUMBER;  v_er_comp  NUMBER;
  v_ep_exi   NUMBER;  v_ep_fal   NUMBER;  v_ep_pen   NUMBER;  v_ep_ree   NUMBER;
  v_ept_pen  NUMBER;  v_ept_abo  NUMBER;  v_ept_pag  NUMBER;  v_ept_ree  NUMBER;  v_ept_can NUMBER;
  v_mp_cre   NUMBER;  v_mp_deb   NUMBER;  v_mp_pse   NUMBER;  v_mp_tra   NUMBER;  v_mp_efe  NUMBER;

  -- Variables de trabajo
  v_res      PLS_INTEGER := 0;   -- reservas creadas
  v_int      PLS_INTEGER := 0;   -- intentos
  v_d        DATE;
  v_peso     NUMBER;
  v_r        NUMBER;
  v_al       PLS_INTEGER;
  v_id_al    NUMBER;
  v_cli      NUMBER;
  v_noches   PLS_INTEGER;
  v_nlin     PLS_INTEGER;
  v_ci       DATE;
  v_co       DATE;
  v_estado   NUMBER;
  v_crea     DATE;
  v_fcan     DATE;
  v_lci      DATE;
  v_lco      DATE;
  v_lcanc    PLS_INTEGER;
  v_lest     NUMBER;
  v_lfcan    DATE;
  v_hab      NUMBER;
  v_usada    BOOLEAN;
  v_off      PLS_INTEGER;
  v_pos      PLS_INTEGER;
  v_llave    PLS_INTEGER;
  v_id_res   NUMBER;
  v_id_lin   NUMBER;
  v_id_pt    NUMBER;
  v_val      NUMBER;
  v_tar_id   NUMBER;
  v_tar_val  NUMBER;
  v_hu       PLS_INTEGER;
  v_hu_tot   PLS_INTEGER;
  v_nsrv     PLS_INTEGER;
  v_cant     PLS_INTEGER;
  v_srv      NUMBER;
  v_precio   NUMBER;
  v_subtotal NUMBER;
  v_anticipo NUMBER;
  v_metodo   NUMBER;
  v_ept      NUMBER;
  v_plan     VARCHAR2(20);
  v_fecha    DATE;
  v_cal      PLS_INTEGER;
  v_coment   VARCHAR2(200);

  -- Llave numérica de una fecha
  FUNCTION llave(p_fecha DATE) RETURN PLS_INTEGER IS
  BEGIN
    RETURN p_fecha - c_origen;
  END llave;

  -- ¿La habitación está libre todas las noches entre p_ci y p_co - 1?
  FUNCTION habitacion_libre(p_hab NUMBER, p_ci DATE, p_co DATE) RETURN BOOLEAN IS
  BEGIN
    FOR x IN 0 .. p_co - p_ci - 1 LOOP
      IF g_ocupada.EXISTS(p_hab * 10000 + llave(p_ci + x)) THEN
        RETURN FALSE;
      END IF;
    END LOOP;
    RETURN TRUE;
  END habitacion_libre;

  -- Método de pago según el momento del pago
  FUNCTION metodo(p_momento VARCHAR2) RETURN NUMBER IS
    r NUMBER := DBMS_RANDOM.VALUE;
  BEGIN
    IF p_momento = 'LLEGADA' THEN            -- saldo pagado en el alojamiento
      RETURN CASE WHEN r < 0.40 THEN v_mp_efe WHEN r < 0.70 THEN v_mp_cre ELSE v_mp_deb END;
    ELSIF p_momento = 'ANTICIPO' THEN
      RETURN CASE WHEN r < 0.35 THEN v_mp_cre WHEN r < 0.65 THEN v_mp_pse WHEN r < 0.85 THEN v_mp_tra ELSE v_mp_deb END;
    ELSE                                     -- pago único en línea
      RETURN CASE WHEN r < 0.40 THEN v_mp_cre WHEN r < 0.70 THEN v_mp_pse WHEN r < 0.85 THEN v_mp_tra ELSE v_mp_deb END;
    END IF;
  END metodo;

  PROCEDURE pagar(p_pago_total NUMBER, p_fecha DATE, p_monto NUMBER, p_metodo NUMBER, p_estado NUMBER) IS
  BEGIN
    INSERT INTO pago (fecha, monto, id_pago_total, id_metodo_pago, id_estado_pago)
    VALUES (p_fecha, p_monto, p_pago_total, p_metodo, p_estado);
  END pagar;

BEGIN
  DBMS_RANDOM.SEED(2026004);

  -- Ids de los catálogos
  SELECT id INTO v_er_pend FROM estado_reserva WHERE descripcion = 'pendiente';
  SELECT id INTO v_er_conf FROM estado_reserva WHERE descripcion = 'confirmada';
  SELECT id INTO v_er_canc FROM estado_reserva WHERE descripcion = 'cancelada';
  SELECT id INTO v_er_comp FROM estado_reserva WHERE descripcion = 'completada';
  SELECT id INTO v_ep_exi  FROM estado_pago WHERE descripcion = 'exitoso';
  SELECT id INTO v_ep_fal  FROM estado_pago WHERE descripcion = 'fallido';
  SELECT id INTO v_ep_pen  FROM estado_pago WHERE descripcion = 'pendiente';
  SELECT id INTO v_ep_ree  FROM estado_pago WHERE descripcion = 'reembolsado';
  SELECT id INTO v_ept_pen FROM estado_pago_total WHERE descripcion = 'pendiente';
  SELECT id INTO v_ept_abo FROM estado_pago_total WHERE descripcion = 'abonado';
  SELECT id INTO v_ept_pag FROM estado_pago_total WHERE descripcion = 'pagado';
  SELECT id INTO v_ept_ree FROM estado_pago_total WHERE descripcion = 'reembolsado';
  SELECT id INTO v_ept_can FROM estado_pago_total WHERE descripcion = 'cancelado';
  SELECT id INTO v_mp_cre  FROM metodo_pago WHERE nombre = 'Tarjeta de crédito';
  SELECT id INTO v_mp_deb  FROM metodo_pago WHERE nombre = 'Tarjeta débito';
  SELECT id INTO v_mp_pse  FROM metodo_pago WHERE nombre = 'PSE';
  SELECT id INTO v_mp_tra  FROM metodo_pago WHERE nombre = 'Transferencia';
  SELECT id INTO v_mp_efe  FROM metodo_pago WHERE nombre = 'Efectivo';

  -- Temporada y tipo de temporada de cada noche
  FOR t IN (SELECT tm.id, tm.fecha_inicio, tm.fecha_fin, tt.nombre AS tipo
              FROM temporada tm
              JOIN tipo_temporada tt ON tt.id = tm.id_tipo_temporada)
  LOOP
    FOR x IN 0 .. t.fecha_fin - t.fecha_inicio LOOP
      g_temp(llave(t.fecha_inicio + x))      := t.id;
      g_temp_tipo(llave(t.fecha_inicio + x)) := t.tipo;
    END LOOP;
  END LOOP;

  -- Tarifas en memoria
  SELECT id, id_habitacion, id_temporada, valor_noche
    BULK COLLECT INTO v_t_id, v_t_hab, v_t_temp, v_t_val
    FROM tarifa;
  FOR k IN 1 .. v_t_id.COUNT LOOP
    v_llave := v_t_hab(k) * 1000 + v_t_temp(k);
    g_tar_id(v_llave)    := v_t_id(k);
    g_tar_valor(v_llave) := v_t_val(k);
  END LOOP;

  -- Alojamientos con su peso, su calificación media, sus habitaciones y sus servicios
  FOR a IN (SELECT al.id, c.nombre AS municipio,
                   (SELECT COUNT(*) FROM habitacion h WHERE h.id_alojamiento = al.id) AS nhab
              FROM alojamiento al
              JOIN ciudad c ON c.id = al.id_ciudad
             ORDER BY al.id)
  LOOP
    g_n_al := g_n_al + 1;
    g_al_id(g_n_al) := a.id;
    v_peso := a.nhab
              * CASE a.municipio
                  WHEN 'Salento'    THEN 1.40
                  WHEN 'Filandia'   THEN 1.30
                  WHEN 'Montenegro' THEN 1.25
                  WHEN 'Quimbaya'   THEN 1.15
                  WHEN 'Armenia'    THEN 1.00
                  WHEN 'Calarcá'    THEN 0.90
                  WHEN 'Circasia'   THEN 0.90
                  WHEN 'La Tebaida' THEN 0.85
                  WHEN 'Buenavista' THEN 0.70
                  WHEN 'Pijao'      THEN 0.60
                  ELSE 0.50                       -- Córdoba y Génova
                END
              * DBMS_RANDOM.VALUE(0.5, 1.6);
    IF g_n_al = 1 THEN
      g_al_peso(g_n_al) := v_peso;
    ELSE
      g_al_peso(g_n_al) := g_al_peso(g_n_al - 1) + v_peso;
    END IF;
    g_al_media(g_n_al) := DBMS_RANDOM.VALUE(2.8, 4.8);

    g_al_hab1(g_n_al) := g_hab_id.COUNT + 1;
    g_al_nhab(g_n_al) := 0;
    FOR h IN (SELECT id, capacidad_maxima FROM habitacion WHERE id_alojamiento = a.id ORDER BY id) LOOP
      v_pos := g_hab_id.COUNT + 1;
      g_hab_id(v_pos)  := h.id;
      g_hab_cap(v_pos) := h.capacidad_maxima;
      g_al_nhab(g_n_al) := g_al_nhab(g_n_al) + 1;
    END LOOP;

    g_al_srv1(g_n_al) := g_srv_id.COUNT + 1;
    g_al_nsrv(g_n_al) := 0;
    FOR s IN (SELECT id, precio FROM servicio WHERE id_alojamiento = a.id ORDER BY id) LOOP
      v_pos := g_srv_id.COUNT + 1;
      g_srv_id(v_pos)     := s.id;
      g_srv_precio(v_pos) := s.precio;
      g_al_nsrv(g_n_al) := g_al_nsrv(g_n_al) + 1;
    END LOOP;
  END LOOP;

  -- Clientes
  SELECT id BULK COLLECT INTO g_cli_id FROM cliente ORDER BY id;

  WHILE v_res < c_meta LOOP
    v_int := v_int + 1;
    IF v_int > c_max_int THEN
      RAISE_APPLICATION_ERROR(-20002, 'No se alcanzaron ' || c_meta || ' reservas en ' || c_max_int || ' intentos.');
    END IF;

    -- a) Día de check-in con estacionalidad (MOD(...,7): 0 = lunes ... 4 = viernes, 5 = sábado, 6 = domingo)
    v_d := c_ini + TRUNC(DBMS_RANDOM.VALUE * (c_fin - c_ini + 1));
    v_peso := CASE g_temp_tipo(llave(v_d)) WHEN 'Alta' THEN 1 WHEN 'Media' THEN 0.55 ELSE 0.32 END
            * CASE EXTRACT(YEAR FROM v_d) WHEN 2024 THEN 0.80 WHEN 2025 THEN 0.92 ELSE 1 END
            * CASE MOD(v_d - DATE '2024-01-01', 7) WHEN 4 THEN 1 WHEN 5 THEN 0.80 WHEN 3 THEN 0.55 WHEN 6 THEN 0.45 ELSE 0.40 END;
    IF DBMS_RANDOM.VALUE > v_peso THEN
      CONTINUE;
    END IF;

    -- b) Alojamiento según su peso acumulado
    v_r := DBMS_RANDOM.VALUE * g_al_peso(g_n_al);
    v_al := g_n_al;
    FOR k IN 1 .. g_n_al LOOP
      IF v_r < g_al_peso(k) THEN
        v_al := k;
        EXIT;
      END IF;
    END LOOP;
    v_id_al := g_al_id(v_al);

    -- c) Noches y número de habitaciones
    v_r := DBMS_RANDOM.VALUE;
    v_noches := CASE WHEN v_r < 0.14 THEN 1 WHEN v_r < 0.48 THEN 2 WHEN v_r < 0.73 THEN 3
                     WHEN v_r < 0.85 THEN 4 WHEN v_r < 0.92 THEN 5 WHEN v_r < 0.97 THEN 6 ELSE 7 END;
    v_r := DBMS_RANDOM.VALUE;
    v_nlin := CASE WHEN v_r < 0.88 THEN 1 WHEN v_r < 0.96 THEN 2 WHEN v_r < 0.99 THEN 3 ELSE 4 END;
    v_nlin := LEAST(v_nlin, g_al_nhab(v_al));
    v_ci := v_d;
    v_co := v_d + v_noches;

    -- d) Estado según la fecha de corte
    IF v_co <= c_corte THEN                          -- estadía terminada
      v_estado := CASE WHEN DBMS_RANDOM.VALUE < 0.15 THEN v_er_canc ELSE v_er_comp END;
    ELSIF v_ci <= c_corte THEN                       -- estadía en curso
      v_estado := v_er_conf;
    ELSE                                             -- estadía futura
      v_r := DBMS_RANDOM.VALUE;
      v_estado := CASE WHEN v_r < 0.10 THEN v_er_canc WHEN v_r < 0.30 THEN v_er_pend ELSE v_er_conf END;
    END IF;

    -- e) Habitación de cada línea
    l_hab.DELETE;  l_cap.DELETE;  l_canc.DELETE;  l_ci.DELETE;  l_co.DELETE;
    FOR k IN 1 .. v_nlin LOOP
      -- A veces alguien del grupo llega un día después
      IF k > 1 AND v_noches >= 2 AND DBMS_RANDOM.VALUE < 0.25 THEN
        v_lci := v_ci + 1;
      ELSE
        v_lci := v_ci;
      END IF;
      v_lco := v_co;
      -- En reservas con varias habitaciones, a veces se cancela solo una
      IF v_estado = v_er_canc THEN
        v_lcanc := 1;
      ELSIF v_estado IN (v_er_comp, v_er_conf) AND k > 1 AND DBMS_RANDOM.VALUE < 0.10 THEN
        v_lcanc := 1;
      ELSE
        v_lcanc := 0;
      END IF;

      -- Recorre las habitaciones del alojamiento desde una posición al azar
      v_hab := NULL;
      v_off := TRUNC(DBMS_RANDOM.VALUE * g_al_nhab(v_al));
      FOR q IN 0 .. g_al_nhab(v_al) - 1 LOOP
        v_pos := g_al_hab1(v_al) + MOD(v_off + q, g_al_nhab(v_al));
        v_usada := FALSE;
        FOR z IN 1 .. l_hab.COUNT LOOP
          IF l_hab(z) = g_hab_id(v_pos) THEN
            v_usada := TRUE;
          END IF;
        END LOOP;
        IF NOT v_usada AND (v_lcanc = 1 OR habitacion_libre(g_hab_id(v_pos), v_lci, v_lco)) THEN
          v_hab := g_hab_id(v_pos);
          EXIT;
        END IF;
      END LOOP;
      EXIT WHEN v_hab IS NULL;                       -- no quedan habitaciones libres

      l_hab(k)  := v_hab;
      l_cap(k)  := g_hab_cap(v_pos);
      l_canc(k) := v_lcanc;
      l_ci(k)   := v_lci;
      l_co(k)   := v_lco;
    END LOOP;

    IF l_hab.COUNT = 0 THEN
      CONTINUE;                                      -- sin cupo: se descarta el intento
    END IF;

    -- f) Fechas de creación y de cancelación
    v_crea := v_ci - (1 + TRUNC(POWER(DBMS_RANDOM.VALUE, 2) * 75));
    IF g_temp_tipo(llave(v_ci)) = 'Alta' THEN
      v_crea := v_crea - TRUNC(DBMS_RANDOM.VALUE * 30);   -- en temporada alta se reserva con más anticipación
    END IF;
    IF v_crea > c_corte THEN
      v_crea := c_corte - TRUNC(DBMS_RANDOM.VALUE * 15);
    END IF;
    IF v_estado = v_er_canc THEN
      v_fcan := v_crea + TRUNC(DBMS_RANDOM.VALUE * (LEAST(v_ci - 1, c_corte) - v_crea + 1));
    ELSE
      v_fcan := NULL;
    END IF;

    v_cli := g_cli_id(1 + TRUNC(g_cli_id.COUNT * POWER(DBMS_RANDOM.VALUE, 1.6)));   -- unos clientes reservan más que otros

    INSERT INTO reserva (fecha_creacion, fecha_check_in, fecha_check_out, fecha_cancelacion,
                         id_cliente, id_alojamiento, id_estado_reserva)
    VALUES (v_crea, v_ci, v_co, v_fcan, v_cli, v_id_al, v_estado)
    RETURNING id INTO v_id_res;

    -- Líneas y su detalle noche por noche
    v_subtotal := 0;
    v_hu_tot := 0;
    FOR k IN 1 .. l_hab.COUNT LOOP
      v_hab := l_hab(k);
      v_lci := l_ci(k);
      v_lco := l_co(k);

      -- valor de la estadía = suma de la tarifa vigente cada noche
      v_val := 0;
      FOR x IN 0 .. v_lco - v_lci - 1 LOOP
        v_val := v_val + g_tar_valor(v_hab * 1000 + g_temp(llave(v_lci + x)));
      END LOOP;

      v_hu := 1 + TRUNC(DBMS_RANDOM.VALUE * l_cap(k));
      v_hu_tot := v_hu_tot + v_hu;

      IF l_canc(k) = 1 THEN
        v_lest := v_er_canc;
        IF v_estado = v_er_canc THEN
          v_lfcan := v_fcan;
        ELSE
          v_lfcan := LEAST(v_crea + TRUNC(DBMS_RANDOM.VALUE * (v_lci - v_crea)), c_corte);
        END IF;
      ELSE
        v_lest := v_estado;
        v_lfcan := NULL;
      END IF;

      INSERT INTO reserva_habitacion (fecha_check_in, fecha_check_out, numero_huespedes, valor_estadia,
                                      fecha_cancelacion, id_reserva, id_habitacion, id_estado_reserva)
      VALUES (v_lci, v_lco, v_hu, v_val, v_lfcan, v_id_res, v_hab, v_lest)
      RETURNING id INTO v_id_lin;

      FOR x IN 0 .. v_lco - v_lci - 1 LOOP
        v_llave   := v_hab * 1000 + g_temp(llave(v_lci + x));
        v_tar_id  := g_tar_id(v_llave);
        v_tar_val := g_tar_valor(v_llave);
        v_fecha   := v_lci + x;
        INSERT INTO reserva_noche (fecha, valor_noche, id_reserva_habitacion, id_tarifa)
        VALUES (v_fecha, v_tar_val, v_id_lin, v_tar_id);
        IF l_canc(k) = 0 THEN
          g_ocupada(v_hab * 10000 + llave(v_fecha)) := 1;   -- las líneas canceladas no ocupan
        END IF;
      END LOOP;

      -- En una reserva activa no se cobran las líneas canceladas
      IF l_canc(k) = 0 OR v_estado = v_er_canc THEN
        v_subtotal := v_subtotal + v_val;
      END IF;
    END LOOP;

    -- g) Servicios del mismo alojamiento, sin repetir
    v_r := DBMS_RANDOM.VALUE;
    v_nsrv := CASE WHEN v_r < 0.08 THEN 0 WHEN v_r < 0.32 THEN 1 WHEN v_r < 0.62 THEN 2 WHEN v_r < 0.84 THEN 3 ELSE 4 END;
    v_nsrv := LEAST(v_nsrv, g_al_nsrv(v_al));
    v_off := TRUNC(DBMS_RANDOM.VALUE * GREATEST(g_al_nsrv(v_al), 1));
    FOR q IN 0 .. v_nsrv - 1 LOOP
      v_pos := g_al_srv1(v_al) + MOD(v_off + q, g_al_nsrv(v_al));
      v_srv := g_srv_id(v_pos);
      v_precio := g_srv_precio(v_pos);
      v_cant := 1 + TRUNC(DBMS_RANDOM.VALUE * LEAST(4, v_hu_tot));
      INSERT INTO reserva_servicio (cantidad, precio_unitario, id_reserva, id_servicio)
      VALUES (v_cant, v_precio, v_id_res, v_srv);
      v_subtotal := v_subtotal + v_cant * v_precio;
    END LOOP;

    -- Plan de pagos y estado del cobro total
    v_r := DBMS_RANDOM.VALUE;
    IF v_estado = v_er_comp THEN
      v_plan := CASE WHEN v_r < 0.55 THEN 'UNICO' ELSE 'ANTICIPO+SALDO' END;
      v_ept := v_ept_pag;
    ELSIF v_estado = v_er_conf THEN
      v_plan := CASE WHEN v_r < 0.40 THEN 'UNICO' ELSE 'ANTICIPO' END;
      v_ept := CASE WHEN v_r < 0.40 THEN v_ept_pag ELSE v_ept_abo END;
    ELSIF v_estado = v_er_pend THEN
      v_plan := CASE WHEN v_r < 0.50 THEN 'PENDIENTE' ELSE 'NINGUNO' END;
      v_ept := v_ept_pen;
    ELSIF v_r < 0.75 THEN                            -- cancelada que había pagado anticipo
      v_plan := 'ANTICIPO';
      v_ept := CASE WHEN v_ci - v_fcan > 5 THEN v_ept_ree ELSE v_ept_can END;
    ELSE                                             -- cancelada sin pagos
      v_plan := 'NINGUNO';
      v_ept := v_ept_can;
    END IF;

    -- Sin descuentos ni impuestos: total = subtotal
    INSERT INTO pago_total (subtotal, total, id_reserva, id_estado_pago_total)
    VALUES (v_subtotal, v_subtotal, v_id_res, v_ept)
    RETURNING id INTO v_id_pt;

    v_anticipo := ROUND(v_subtotal * DBMS_RANDOM.VALUE(0.30, 0.50), -2);
    IF v_plan = 'UNICO' THEN
      v_fecha := v_crea + TRUNC(DBMS_RANDOM.VALUE * LEAST(3, v_ci - v_crea));
      v_metodo := metodo('UNICO');
      IF DBMS_RANDOM.VALUE < 0.04 THEN                -- intento fallido antes del pago bueno
        pagar(v_id_pt, v_fecha, v_subtotal, metodo('UNICO'), v_ep_fal);
      END IF;
      pagar(v_id_pt, v_fecha, v_subtotal, v_metodo, v_ep_exi);

    ELSIF v_plan = 'ANTICIPO+SALDO' THEN
      v_metodo := metodo('ANTICIPO');
      IF DBMS_RANDOM.VALUE < 0.04 THEN
        pagar(v_id_pt, v_crea, v_anticipo, metodo('ANTICIPO'), v_ep_fal);
      END IF;
      pagar(v_id_pt, v_crea, v_anticipo, v_metodo, v_ep_exi);
      pagar(v_id_pt, v_ci, v_subtotal - v_anticipo, metodo('LLEGADA'), v_ep_exi);

    ELSIF v_plan = 'ANTICIPO' AND v_estado = v_er_canc THEN
      v_metodo := metodo('ANTICIPO');
      v_fecha := v_crea + TRUNC(DBMS_RANDOM.VALUE * (v_fcan - v_crea + 1));
      pagar(v_id_pt, v_fecha, v_anticipo, v_metodo, v_ep_exi);
      IF v_ci - v_fcan > 5 THEN                     -- regla: más de 5 días antes => reembolso del 80 % de lo pagado
        v_fecha := LEAST(v_fcan + 1 + TRUNC(DBMS_RANDOM.VALUE * 5), c_corte);
        pagar(v_id_pt, v_fecha, ROUND(v_anticipo * 0.8, -2), v_metodo, v_ep_ree);
      END IF;

    ELSIF v_plan = 'ANTICIPO' THEN                   -- confirmada con anticipo
      pagar(v_id_pt, v_crea, v_anticipo, metodo('ANTICIPO'), v_ep_exi);
      IF DBMS_RANDOM.VALUE < 0.25 THEN               -- saldo programado para el check-in
        pagar(v_id_pt, v_ci, v_subtotal - v_anticipo, metodo('LLEGADA'), v_ep_pen);
      END IF;

    ELSIF v_plan = 'PENDIENTE' THEN
      pagar(v_id_pt, v_crea, v_anticipo, metodo('ANTICIPO'), v_ep_pen);
    END IF;

    -- Reseña: la mitad de las reservas completadas. La calificación gira
    -- alrededor de la media del alojamiento (unos salen mejor que otros).
    IF v_estado = v_er_comp AND DBMS_RANDOM.VALUE < 0.50 THEN
      v_cal := LEAST(5, GREATEST(1, ROUND(g_al_media(v_al) + DBMS_RANDOM.VALUE(-1.3, 1.3))));
      v_r := DBMS_RANDOM.VALUE;
      IF v_r < 0.25 THEN
        v_coment := NULL;                            -- comentario opcional
      ELSIF v_cal >= 4 THEN
        v_coment := c_com_buenos(1 + TRUNC(DBMS_RANDOM.VALUE * c_com_buenos.COUNT));
      ELSIF v_cal = 3 THEN
        v_coment := c_com_medios(1 + TRUNC(DBMS_RANDOM.VALUE * c_com_medios.COUNT));
      ELSE
        v_coment := c_com_malos(1 + TRUNC(DBMS_RANDOM.VALUE * c_com_malos.COUNT));
      END IF;
      v_fecha := LEAST(v_co + TRUNC(DBMS_RANDOM.VALUE * 10), c_corte);
      INSERT INTO resena (calificacion, comentario, fecha, id_reserva)
      VALUES (v_cal, v_coment, v_fecha, v_id_res);
    END IF;

    v_res := v_res + 1;
    IF MOD(v_res, 5000) = 0 THEN
      DBMS_OUTPUT.PUT_LINE('  ' || v_res || ' reservas...');
    END IF;
  END LOOP;

  DBMS_OUTPUT.PUT_LINE('Reservas: ' || v_res || ' (intentos: ' || v_int || ')');
END;
/


/* ---------------------------------------------------------------------
   9. CONFIRMACIÓN
   --------------------------------------------------------------------- */
COMMIT;


/* ---------------------------------------------------------------------
   10. VERIFICACIÓN
   10.1 Volumen de cada tabla frente al mínimo del enunciado.
   --------------------------------------------------------------------- */
SELECT tabla, filas, minimo,
       CASE WHEN filas >= minimo THEN 'OK' ELSE 'REVISAR' END AS estado
  FROM (SELECT 1 AS orden, 'CIUDAD (municipios del Quindío)' AS tabla,
               (SELECT COUNT(*) FROM ciudad c JOIN departamento d ON d.id = c.id_departamento WHERE d.nombre = 'Quindío') AS filas,
               12 AS minimo FROM dual
        UNION ALL SELECT 2,  'TIPO_ALOJAMIENTO',   (SELECT COUNT(*) FROM tipo_alojamiento),   4     FROM dual
        UNION ALL SELECT 3,  'ALOJAMIENTO',        (SELECT COUNT(*) FROM alojamiento),        60    FROM dual
        UNION ALL SELECT 4,  'HABITACION',         (SELECT COUNT(*) FROM habitacion),         400   FROM dual
        UNION ALL SELECT 5,  'TEMPORADA',          (SELECT COUNT(*) FROM temporada),          6     FROM dual
        UNION ALL SELECT 6,  'TARIFA (habitación x temporada)', (SELECT COUNT(*) FROM tarifa),
                             (SELECT COUNT(*) FROM habitacion) * (SELECT COUNT(*) FROM temporada) FROM dual
        UNION ALL SELECT 7,  'CLIENTE',            (SELECT COUNT(*) FROM cliente),            3000  FROM dual
        UNION ALL SELECT 8,  'RESERVA',            (SELECT COUNT(*) FROM reserva),            25000 FROM dual
        UNION ALL SELECT 9,  'RESERVA_HABITACION', (SELECT COUNT(*) FROM reserva_habitacion), 25000 FROM dual
        UNION ALL SELECT 10, 'PAGO',               (SELECT COUNT(*) FROM pago),               25000 FROM dual
        UNION ALL SELECT 11, 'SERVICIO',           (SELECT COUNT(*) FROM servicio),           30    FROM dual
        UNION ALL SELECT 12, 'RESERVA_SERVICIO',   (SELECT COUNT(*) FROM reserva_servicio),   40000 FROM dual
        UNION ALL SELECT 13, 'RESENA (% de reservas completadas)',
                             ROUND(100 * (SELECT COUNT(*) FROM resena)
                                       / (SELECT COUNT(*) FROM reserva r JOIN estado_reserva e ON e.id = r.id_estado_reserva
                                           WHERE e.descripcion = 'completada'), 1),
                             40 FROM dual
        UNION ALL SELECT 14, 'USUARIO_SISTEMA',    (SELECT COUNT(*) FROM usuario_sistema),    10    FROM dual
        UNION ALL SELECT 15, 'RESERVA_NOCHE (agregada)',    (SELECT COUNT(*) FROM reserva_noche),       1 FROM dual
        UNION ALL SELECT 16, 'PAGO_TOTAL (agregada)',       (SELECT COUNT(*) FROM pago_total),          1 FROM dual
        UNION ALL SELECT 17, 'TELEFONO_CLIENTE (agregada)', (SELECT COUNT(*) FROM telefono_cliente),    1 FROM dual
        UNION ALL SELECT 18, 'TELEFONO_ALOJAMIENTO (agregada)', (SELECT COUNT(*) FROM telefono_alojamiento), 1 FROM dual
        UNION ALL SELECT 19, 'CORREO_ALOJAMIENTO (agregada)',   (SELECT COUNT(*) FROM correo_alojamiento),   1 FROM dual)
 ORDER BY orden;

/* ---------------------------------------------------------------------
   10.2 Reglas de negocio sobre los datos cargados. Todas deben dar 0.
   --------------------------------------------------------------------- */
SELECT 'Habitaciones con dos líneas activas solapadas' AS verificacion, COUNT(*) AS casos
  FROM reserva_habitacion a
  JOIN reserva_habitacion b ON b.id_habitacion = a.id_habitacion
                           AND b.id > a.id
                           AND a.fecha_check_in < b.fecha_check_out
                           AND b.fecha_check_in < a.fecha_check_out
  JOIN estado_reserva ea ON ea.id = a.id_estado_reserva
  JOIN estado_reserva eb ON eb.id = b.id_estado_reserva
 WHERE ea.descripcion <> 'cancelada'
   AND eb.descripcion <> 'cancelada'
UNION ALL
SELECT 'Líneas cuyo valor_estadia no es la suma de sus noches', COUNT(*)
  FROM reserva_habitacion rh
  LEFT JOIN (SELECT id_reserva_habitacion, SUM(valor_noche) AS valor, COUNT(*) AS noches
               FROM reserva_noche
              GROUP BY id_reserva_habitacion) n ON n.id_reserva_habitacion = rh.id
 WHERE n.valor IS NULL
    OR n.valor <> rh.valor_estadia
    OR n.noches <> rh.fecha_check_out - rh.fecha_check_in
UNION ALL
SELECT 'Noches con una tarifa que no corresponde', COUNT(*)
  FROM reserva_noche n
  JOIN reserva_habitacion rh ON rh.id = n.id_reserva_habitacion
  JOIN tarifa t ON t.id = n.id_tarifa
  JOIN temporada tm ON tm.id = t.id_temporada
 WHERE t.id_habitacion <> rh.id_habitacion
    OR n.fecha NOT BETWEEN tm.fecha_inicio AND tm.fecha_fin
    OR n.valor_noche <> t.valor_noche
UNION ALL
SELECT 'Días de 2024 a enero de 2027 sin temporada o con más de una', COUNT(*)
  FROM (SELECT DATE '2024-01-01' + LEVEL - 1 AS dia
          FROM dual
       CONNECT BY LEVEL <= DATE '2027-01-15' - DATE '2024-01-01' + 1) d
 WHERE (SELECT COUNT(*) FROM temporada t WHERE d.dia BETWEEN t.fecha_inicio AND t.fecha_fin) <> 1
UNION ALL
SELECT 'Líneas con una habitación de otro alojamiento', COUNT(*)
  FROM reserva_habitacion rh
  JOIN reserva r ON r.id = rh.id_reserva
  JOIN habitacion h ON h.id = rh.id_habitacion
 WHERE h.id_alojamiento <> r.id_alojamiento
UNION ALL
SELECT 'Servicios contratados de otro alojamiento', COUNT(*)
  FROM reserva_servicio rs
  JOIN reserva r ON r.id = rs.id_reserva
  JOIN servicio s ON s.id = rs.id_servicio
 WHERE s.id_alojamiento <> r.id_alojamiento
UNION ALL
SELECT 'Líneas con más huéspedes que la capacidad', COUNT(*)
  FROM reserva_habitacion rh
  JOIN habitacion h ON h.id = rh.id_habitacion
 WHERE rh.numero_huespedes > h.capacidad_maxima
UNION ALL
SELECT 'Reseñas de reservas no completadas', COUNT(*)
  FROM resena rs
  JOIN reserva r ON r.id = rs.id_reserva
  JOIN estado_reserva e ON e.id = r.id_estado_reserva
 WHERE e.descripcion <> 'completada'
UNION ALL
SELECT 'Cobros totales que no cuadran con estadías y servicios', COUNT(*)
  FROM pago_total pt
  JOIN reserva r ON r.id = pt.id_reserva
  JOIN estado_reserva er ON er.id = r.id_estado_reserva
  LEFT JOIN (SELECT rh.id_reserva,
                    SUM(CASE WHEN e.descripcion <> 'cancelada' THEN rh.valor_estadia ELSE 0 END) AS activas,
                    SUM(rh.valor_estadia) AS todas
               FROM reserva_habitacion rh
               JOIN estado_reserva e ON e.id = rh.id_estado_reserva
              GROUP BY rh.id_reserva) l ON l.id_reserva = r.id
  LEFT JOIN (SELECT id_reserva, SUM(cantidad * precio_unitario) AS valor
               FROM reserva_servicio
              GROUP BY id_reserva) s ON s.id_reserva = r.id
 WHERE pt.subtotal <> CASE WHEN er.descripcion = 'cancelada' THEN l.todas ELSE l.activas END + NVL(s.valor, 0)
    OR pt.total <> pt.subtotal
UNION ALL
SELECT 'Reservas completadas cuyos pagos exitosos no cubren el total', COUNT(*)
  FROM pago_total pt
  JOIN reserva r ON r.id = pt.id_reserva
  JOIN estado_reserva e ON e.id = r.id_estado_reserva
  LEFT JOIN (SELECT p.id_pago_total, SUM(p.monto) AS pagado
               FROM pago p
               JOIN estado_pago ep ON ep.id = p.id_estado_pago
              WHERE ep.descripcion = 'exitoso'
              GROUP BY p.id_pago_total) s ON s.id_pago_total = pt.id
 WHERE e.descripcion = 'completada'
   AND NVL(s.pagado, 0) < pt.total
UNION ALL
SELECT 'Cobros cuyo reembolso no sigue la regla (80 % si cancela con más de 5 días)', COUNT(*)
  FROM pago_total pt
  JOIN reserva r ON r.id = pt.id_reserva
  JOIN estado_reserva er ON er.id = r.id_estado_reserva
  LEFT JOIN (SELECT p.id_pago_total,
                    SUM(CASE WHEN ep.descripcion = 'exitoso'     THEN p.monto ELSE 0 END) AS pagado,
                    SUM(CASE WHEN ep.descripcion = 'reembolsado' THEN p.monto ELSE 0 END) AS reembolsado
               FROM pago p
               JOIN estado_pago ep ON ep.id = p.id_estado_pago
              GROUP BY p.id_pago_total) s ON s.id_pago_total = pt.id
 WHERE NVL(s.reembolsado, 0) <> CASE WHEN er.descripcion = 'cancelada'
                                      AND r.fecha_check_in - r.fecha_cancelacion > 5
                                     THEN ROUND(NVL(s.pagado, 0) * 0.8, -2)
                                     ELSE 0
                                END
UNION ALL
SELECT 'Cobros en estado reembolsado sin reembolso, o con reembolso en otro estado', COUNT(*)
  FROM pago_total pt
  JOIN estado_pago_total ept ON ept.id = pt.id_estado_pago_total
 WHERE CASE WHEN ept.descripcion = 'reembolsado' THEN 1 ELSE 0 END
    <> CASE WHEN EXISTS (SELECT 1
                           FROM pago p
                           JOIN estado_pago ep ON ep.id = p.id_estado_pago
                          WHERE p.id_pago_total = pt.id
                            AND ep.descripcion = 'reembolsado') THEN 1 ELSE 0 END;