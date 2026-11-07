-- =====================================================================
-- db_tests.sql - Bodegas del Atuel
--
-- Suite de Pruebas de Reglas de Negocio (RN-01 a RN-15) - Etapa 2
--
-- Propósito:
--   Proveer el esqueleto estandarizado para la verificación y testing de
--   las reglas de negocio implementadas en la base de datos (restricciones,
--   triggers, funciones y procedimientos almacenados).
--
-- Ejecución recomendada:
--   docker compose exec -T db psql -U <usuario> -d <base> -v ON_ERROR_STOP=0 < /ruta/db_tests.sql
--   O montando el archivo en el contenedor:
--   docker compose exec -T db psql -U <usuario> -d <base> -v ON_ERROR_STOP=0 -f /ruta/db_tests.sql
--
-- NOTA sobre ON_ERROR_STOP=0:
--   Se utiliza intencionalmente ON_ERROR_STOP=0 debido a que los casos de
--   prueba de tipo "DEBE FALLAR" provocan errores esperados de PostgreSQL
--   (violaciones de CHECK, FOREIGN KEY, UNIQUE, excepciones de triggers, etc.)
--   para comprobar que las defensas de la base de datos reaccionan correctamente.
--
-- Convenciones de diseño de las pruebas:
--   1. Aislamiento transaccional:
--      Cada caso de prueba se ejecuta dentro de un bloque BEGIN ... ROLLBACK
--      para asegurar que ninguna prueba deje datos residuales ni contamine
--      el estado de la base de datos para los casos siguientes.
--   2. Estructura de comentarios por caso:
--      -- CASO: <identificador único, ej. RN-01-OK o RN-01-FAIL>
--      -- TIPO: DEBE FUNCIONAR | DEBE FALLAR
--      -- ESPERADO: <comportamiento esperado: inserción exitosa o mensaje de error>
--      -- SQLSTATE esperado: <código de 5 caracteres PostgreSQL, ej. 23514> (solo en casos DEBE FALLAR)
--   3. Estructura de cada bloque de regla:
--      Cada bloque cita la regla de negocio, el mecanismo de base de datos
--      utilizado y el archivo de migración donde reside la implementación.
--   4. Verificación de errores esperados:
--      En los casos DEBE FALLAR se especifica el código SQLSTATE y/o el mensaje
--      de error esperado como referencia obligatoria para que el rol Datos
--      confirme que el fallo se debe a la restricción testeada y no a un error no previsto.
-- =====================================================================

-- =====================================================================
-- REGLA RN-01: Precio de vino único y > 0
-- Mecanismo: Atributo en vino + CHECK (precio > 0)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-01-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción exitosa de un registro de vino con precio estrictamente positivo (> 0).
BEGIN;
  -- TODO: Insertar un vino con precio válido (> 0) y confirmar persistencia temporal.
ROLLBACK;

-- CASO: RN-01-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar insertar un vino con precio igual a 0 o negativo.
-- SQLSTATE esperado: 23514 (check_violation)
BEGIN;
  -- TODO: Insertar un vino con precio 0 o menor que 0 para disparar la restricción CHECK.
ROLLBACK;


-- =====================================================================
-- REGLA RN-02: Sala en una sola localidad; localidad con único encargado
-- Mecanismo: FK + diseño en Tercera Forma Normal (3FN)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-02-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción exitosa de una sala de venta vinculada a una localidad existente y válida.
BEGIN;
  -- TODO: Insertar una sala de venta asignándole el ID de una localidad existente.
ROLLBACK;

-- CASO: RN-02-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla por clave foránea al intentar registrar una sala en una localidad inexistente.
-- SQLSTATE esperado: 23503 (foreign_key_violation)
BEGIN;
  -- TODO: Insertar una sala de venta con localidad_id inexistente (ej. -9999).
ROLLBACK;


-- =====================================================================
-- REGLA RN-03: Empleado trabaja en una sola sala
-- Mecanismo: Clave foránea con restricción NOT NULL (FK NOT NULL)
-- Archivo de migración: db/migrations/001_esquema.sql / db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-03-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción o actualización exitosa de un empleado asignado a una sala válida.
BEGIN;
  -- TODO: Registrar un empleado asociándolo correctamente a una sala existente.
ROLLBACK;

-- CASO: RN-03-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar crear un empleado sin sala (NULL) o con sala inexistente.
-- SQLSTATE esperado: 23502 (not_null_violation) o 23503 (foreign_key_violation)
BEGIN;
  -- TODO: Insertar empleado con id_sala NULL o ID de sala inexistente.
ROLLBACK;


-- =====================================================================
-- REGLA RN-04: Parcela con una sola cepa; una cosecha por parcela y campaña
-- Mecanismo: FK a cepa + restricción de unicidad UNIQUE (id_parcela, anio_campana)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-04-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción exitosa de un lote de uva para una parcela y campaña sin cosecha previa.
BEGIN;
  -- TODO: Insertar un lote de uva para una combinación nueva de (parcela, campaña).
ROLLBACK;

-- CASO: RN-04-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar insertar un segundo lote de uva para la misma parcela y campaña.
-- SQLSTATE esperado: 23505 (unique_violation)
BEGIN;
  -- TODO: Insertar dos lotes de uva sucesivos con idéntica parcela y misma campaña.
ROLLBACK;


-- =====================================================================
-- REGLA RN-05: Porcentajes de corte suman 100
-- Mecanismo: Constraint trigger diferido (DEFERRABLE INITIALLY DEFERRED)
-- Archivo de migración: db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-05-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción de corte de cepas cuya suma de porcentajes alcanza exactamente 100 al COMMIT.
BEGIN;
  -- TODO: Insertar registros en vino_cepa sumando exactamente 100% y validar que el COMMIT prospere.
ROLLBACK;

-- CASO: RN-05-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al hacer COMMIT si la suma de porcentajes de corte es distinta de 100 (el error aparece al COMMIT, no al INSERT).
-- SQLSTATE esperado: P0001 (raise_exception)
BEGIN;
  -- TODO: Insertar registros en vino_cepa que sumen distinto de 100% (ej. 80%) y ejecutar COMMIT para disparar error.
ROLLBACK;


-- =====================================================================
-- REGLA RN-06: Descuento por tipo de cliente: socio 10, distribuidor 20, exportador 30
-- Mecanismo: Función de descuento + CHECK de rango
-- Archivo de migración: db/migrations/002_constraints.sql / db/migrations/003_funciones.sql
-- =====================================================================

-- CASO: RN-06-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Aplicación o cálculo exitoso de descuento según el tipo de cliente (socio: 10, distribuidor: 20, exportador: 30).
BEGIN;
  -- TODO: Validar función/cálculo de descuento según tipo de cliente con valores permitidos.
ROLLBACK;

-- CASO: RN-06-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar registrar o calcular un descuento fuera del rango o porcentaje permitido.
-- SQLSTATE esperado: 23514 (check_violation)
BEGIN;
  -- TODO: Intentar registrar o asignar un descuento inválido (ej. 15% o 50%) para forzar fallo.
ROLLBACK;


-- =====================================================================
-- REGLA RN-07: Exportador con varios permisos; vencimiento posterior a emisión
-- Mecanismo: Tabla de permisos + CHECK entre columnas (fecha_vencimiento > fecha_emision)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-07-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción exitosa de permiso de exportación con fecha_vencimiento estrictamente posterior a fecha_emision.
BEGIN;
  -- TODO: Insertar permiso de exportación con fecha_emision = CURRENT_DATE y fecha_vencimiento = CURRENT_DATE + 30.
ROLLBACK;

-- CASO: RN-07-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al insertar permiso con fecha de vencimiento menor o igual a fecha de emisión.
-- SQLSTATE esperado: 23514 (check_violation)
BEGIN;
  -- TODO: Insertar permiso de exportación con fecha_vencimiento <= fecha_emision.
ROLLBACK;


-- =====================================================================
-- REGLA RN-08: Total del comprobante = suma de renglones con descuento; no se carga a mano
-- Mecanismo: Función de cálculo + trigger de sincronización
-- Archivo de migración: db/migrations/003_funciones.sql / db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-08-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Al insertar renglones con descuento, el total del comprobante se calcula automáticamente como la suma de sus subtotales.
BEGIN;
  -- TODO: Insertar comprobante y renglones asociados; comprobar recálculo automático del total.
ROLLBACK;

-- CASO: RN-08-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla o rechazo al intentar asignar manualmente el total del comprobante (o forzar inconsistencia con sus renglones).
-- SQLSTATE esperado: P0001 (raise_exception) o verificación de recálculo forzoso (a definir con Datos)
BEGIN;
  -- TODO: Intentar UPDATE o INSERT directo de monto total arbitrario en comprobante para comprobar rechazo.
ROLLBACK;


-- =====================================================================
-- REGLA RN-09: No vender más que el stock de la sala; stock nunca negativo
-- Mecanismo: Trigger BEFORE INSERT + CHECK (cantidad >= 0 / stock >= 0)
-- Archivo de migración: db/migrations/002_constraints.sql / db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-09-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Venta de renglón con cantidad menor o igual al stock disponible en la sala; descuenta stock correctamente.
BEGIN;
  -- TODO: Insertar renglón de comprobante con cantidad <= stock_disponible de la sala.
ROLLBACK;

-- CASO: RN-09-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar vender un renglón con cantidad mayor al stock disponible de la sala.
-- SQLSTATE esperado: P0001 (raise_exception en trigger) o 23514 (check_violation en stock)
BEGIN;
  -- TODO: Insertar renglón solicitando cantidad superior al stock existente para forzar rechazo.
ROLLBACK;


-- =====================================================================
-- REGLA RN-10: Ingreso: en_confeccion -> terminado -> procesado, sin retrocesos; solo terminado impacta el depósito
-- Mecanismo: ENUM (estado_documento) + trigger de transiciones de estado + procedimiento
-- Archivo de migración: db/migrations/004_procedimientos.sql / db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-10-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Flujo secuencial correcto de ingreso (en_confeccion -> terminado -> procesado) con acreditación de stock al procesar.
BEGIN;
  -- TODO: Registrar ingreso en confección, avanzar a terminado y luego procesar actualizando stock.
ROLLBACK;

-- CASO: RN-10-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar retroceder un estado (ej. terminado -> en_confeccion) o procesar un ingreso no terminado.
-- SQLSTATE esperado: P0001 (raise_exception)
BEGIN;
  -- TODO: Intentar transicionar de 'procesado' a 'en_confeccion' o forzar retroceso inválido de estado.
ROLLBACK;


-- =====================================================================
-- REGLA RN-11: Idem RN-10 para transferencias; fecha de confección = actual e inmodificable; no procesa sin stock
-- Mecanismo: Trigger de transiciones de estado y de fecha + procedimiento de procesamiento
-- Archivo de migración: db/migrations/004_procedimientos.sql / db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-11-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Transferencia creada con fecha actual, avance secuencial de estado y procesamiento exitoso habiendo stock en origen.
BEGIN;
  -- TODO: Crear transferencia, cambiar a terminada y procesar verificando egreso en origen e ingreso en destino.
ROLLBACK;

-- CASO: RN-11-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar modificar la fecha de confección, retroceder de estado o procesar sin stock suficiente en sala origen (debe revertir todo).
-- SQLSTATE esperado: P0001 (raise_exception)
BEGIN;
  -- TODO: Ejecutar UPDATE alterando la fecha_confeccion o intentar procesar sin stock suficiente en origen.
ROLLBACK;


-- =====================================================================
-- REGLA RN-12: Documento que no está en confección no admite agregar/modificar/quitar renglones
-- Mecanismo: Trigger BEFORE INSERT/UPDATE/DELETE sobre los renglones
-- Archivo de migración: db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-12-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción, modificación o eliminación exitosa de renglones mientras el documento permanezca en 'en_confeccion'.
BEGIN;
  -- TODO: Insertar o actualizar renglones en un ingreso/transferencia/comprobante en confección.
ROLLBACK;

-- CASO: RN-12-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar insertar, modificar o borrar renglones en un documento terminado o procesado.
-- SQLSTATE esperado: P0001 (raise_exception)
BEGIN;
  -- TODO: Intentar INSERT de un renglón en un documento con estado 'terminado' o 'procesado'.
ROLLBACK;


-- =====================================================================
-- REGLA RN-13: Todo cambio de precio queda auditado (fecha, usuario, precio anterior y nuevo)
-- Mecanismo: Trigger AFTER UPDATE en vino + inserción en tabla auditoria_precio
-- Archivo de migración: db/migrations/005_triggers.sql
-- =====================================================================

-- CASO: RN-13-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Una modificación de precio mediante UPDATE genera automáticamente una nueva fila en auditoria_precio con los valores exactos.
BEGIN;
  -- TODO: Actualizar precio de un vino y consultar que exista una fila correspondiente en auditoria_precio.
ROLLBACK;

-- CASO: RN-13-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Verificación o rechazo (a definir con Datos: UPDATE de otra columna NO genera fila en auditoría, o el rol de aplicación tiene denegado el DELETE/UPDATE sobre auditoria_precio).
-- SQLSTATE esperado: 42501 (insufficient_privilege) o verificación de no generación de fila
BEGIN;
  -- TODO: Intentar DELETE en la tabla auditoria_precio o probar que actualizar otra columna no genera fila de auditoría.
ROLLBACK;


-- =====================================================================
-- REGLA RN-14: No borrar transportista, bodega ni vino con movimientos
-- Mecanismo: Claves foráneas con acción referencial ON DELETE RESTRICT (o NO ACTION por defecto)
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-14-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Eliminación exitosa de un vino, bodega o transportista que no posee movimientos ni registros hijos asociados.
BEGIN;
  -- TODO: Insertar un vino nuevo sin movimientos y borrarlo confirmando eliminación limpia.
ROLLBACK;

-- CASO: RN-14-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar borrar un vino, bodega o transportista que tiene movimientos o relaciones activas.
-- SQLSTATE esperado: 23503 (foreign_key_violation)
BEGIN;
  -- TODO: Intentar DELETE de un vino que posea renglones de comprobante o stock asociado.
ROLLBACK;


-- =====================================================================
-- REGLA RN-15: Cantidades, superficies, kilos y precios > 0; graduación entre 5 y 20
-- Mecanismo: Restricciones CHECK en tablas respectivas
-- Archivo de migración: db/migrations/002_constraints.sql
-- =====================================================================

-- CASO: RN-15-OK
-- TIPO: DEBE FUNCIONAR
-- ESPERADO: Inserción exitosa de registros con cantidades, superficies, kilos y precios positivos, y graduación alcohólica entre 5.0 y 20.0.
BEGIN;
  -- TODO: Insertar vino con graduación 14.5 y precios/cantidades > 0 en las tablas respectivas.
ROLLBACK;

-- CASO: RN-15-FAIL
-- TIPO: DEBE FALLAR
-- ESPERADO: Falla al intentar registrar graduación fuera de rango (ej. 4 o 21) o valores de cantidad/superficie/kilos <= 0.
-- SQLSTATE esperado: 23514 (check_violation)
BEGIN;
  -- TODO: Insertar vino con graduacion_alcoholica = 4.0 o 21.0, o superficie <= 0 en parcela.
ROLLBACK;


-- =====================================================================
-- RESUMEN Y PENDIENTES
-- =====================================================================
--
-- Matriz de Trazabilidad: Regla -> Mecanismo -> Casos de Prueba
--
-- | Regla | Mecanismo Implementado                        | Caso OK    | Caso FAIL    | Estado    |
-- |-------|-----------------------------------------------|------------|--------------|-----------|
-- | RN-01 | Atributo en vino + CHECK (precio > 0)         | RN-01-OK   | RN-01-FAIL   | PENDIENTE |
-- | RN-02 | FK + diseño 3FN                               | RN-02-OK   | RN-02-FAIL   | PENDIENTE |
-- | RN-03 | FK NOT NULL                                   | RN-03-OK   | RN-03-FAIL   | PENDIENTE |
-- | RN-04 | FK + UNIQUE (parcela, campaña)                | RN-04-OK   | RN-04-FAIL   | PENDIENTE |
-- | RN-05 | Constraint trigger diferido                   | RN-05-OK   | RN-05-FAIL   | PENDIENTE |
-- | RN-06 | Función de descuento + CHECK de rango         | RN-06-OK   | RN-06-FAIL   | PENDIENTE |
-- | RN-07 | Tabla permisos + CHECK entre columnas         | RN-07-OK   | RN-07-FAIL   | PENDIENTE |
-- | RN-08 | Función de cálculo + trigger                  | RN-08-OK   | RN-08-FAIL   | PENDIENTE |
-- | RN-09 | Trigger BEFORE INSERT + CHECK (cantidad >= 0) | RN-09-OK   | RN-09-FAIL   | PENDIENTE |
-- | RN-10 | ENUM + trigger de estados + procedimiento     | RN-10-OK   | RN-10-FAIL   | PENDIENTE |
-- | RN-11 | Trigger de estados y fecha + procedimiento    | RN-11-OK   | RN-11-FAIL   | PENDIENTE |
-- | RN-12 | Trigger sobre renglones de documentos         | RN-12-OK   | RN-12-FAIL   | PENDIENTE |
-- | RN-13 | Trigger AFTER UPDATE + tabla auditoría        | RN-13-OK   | RN-13-FAIL   | PENDIENTE |
-- | RN-14 | FK con ON DELETE RESTRICT                     | RN-14-OK   | RN-14-FAIL   | PENDIENTE |
-- | RN-15 | Restricciones CHECK de rangos y valores > 0   | RN-15-OK   | RN-15-FAIL   | PENDIENTE |
--
-- ---------------------------------------------------------------------
-- Dudas y Puntos a Definir con el Rol Datos (Pendientes de Coordinación):
--
-- 1. RN-08 (Total de comprobante):
--    - ¿El trigger debe rechazar explícitamente mediante RAISE EXCEPTION si se
--      intenta proveer un total manual discrepante (caso FAIL clásico con error)?
--    - ¿O bien debe sobreescribir silenciosamente el valor manual recalculándolo
--      en base a los renglones (caso de verificación de recálculo automático)?
--
-- 2. RN-13 (Auditoría de cambios de precio):
--    - Definir cuál es el caso FAIL canónico:
--      a) Intentar actualizar una columna distinta de precio (ej. nombre_vino)
--         y verificar que NO se inserte fila en auditoria_precio.
--      b) Verificar permisos de seguridad (GRANT/REVOKE): intentar eliminar o
--         modificar filas de auditoria_precio con un usuario de aplicación y
--         esperar SQLSTATE 42501 (insufficient_privilege).
--
-- 3. RN-03 (Empleado en una sola sala):
--    - Identificar cuál prueba de fallo es la principal para el rol Datos:
--      violación NOT NULL (SQLSTATE 23502) al omitir la sala, o violación
--      de foreign key (SQLSTATE 23503) al pasar un ID inexistente.
--
-- 4. RN-09 (Stock de sala nunca negativo):
--    - La defensa opera en dos niveles: un trigger que verifica antes de insertar
--      el renglón (SQLSTATE P0001) y una restricción CHECK en stock_sala (SQLSTATE 23514).
--      Conviene que el rol Datos defina si se prueba la excepción del trigger
--      o la violación de la restricción CHECK en caso de omisión del trigger.
--
-- 5. RN-10 y RN-11 (Procesamiento de documentos de ingreso y transferencia):
--    - Precisar la interfaz de ejecución: ¿el cambio a estado 'procesado' se
--      invoca mediante un procedimiento almacenado (ej. CALL procesar_ingreso(id))
--      o mediante un UPDATE directo sobre el estado que dispara un trigger?
-- =====================================================================
