-- Sesion A: Bloqueo con FOR UPDATE (nivel READ COMMITTED por defecto)
-- Objetivo: Bloquear la ultima botella y demostrar que la segunda sesion espera

-- Configurar variables de demo (pueden ser reemplazadas por -v en el runner)
\set sala '7'
\set vino '9'

-- Mostrar información de inicio
SELECT '=== SESION A: INICIO ===' AS info;
SELECT clock_timestamp() AS inicio_sesion;
SELECT 'PID A: ' || pg_backend_pid() AS pid;

-- Verificar stock actual
SELECT 'Stock actual:' AS label, cantidad FROM stock_sala WHERE id_sala = :'sala' AND cod_vino = :'vino';

-- BEGIN TRANSACCION con bloqueo FOR UPDATE
BEGIN;

    -- PASO 1: Seleccionar y bloquear la fila con FOR UPDATE
    -- Esta sentencia bloquea la fila de stock_sala en modo EXCLUSIVE
    -- hasta que la transaccion haga COMMIT o ROLLBACK
    SELECT cantidad INTO v_stock_bloqueado 
    FROM stock_sala 
    WHERE id_sala = :'sala' AND cod_vino = :'vino'
    FOR UPDATE;

    -- Confirmar lo bloqueado
    SELECT 'Stock bloqueado por A:' AS label, v_stock_bloqueado AS valor;

    -- Simular un delay para mantener el lock durante unos segundos
    -- Esto obliga a la sesion B a esperar
    PERFORM pg_sleep(5);

    -- PASO 2: Actualizar el stock (restar 1 botella)
    UPDATE stock_sala 
    SET cantidad = cantidad - 1
    WHERE id_sala = :'sala' AND cod_vino = :'vino';

    -- Confirmar el resultado desues del update
    SELECT 'Stock despues de UPDATE de A:' AS label, cantidad FROM stock_sala WHERE id_sala = :'sala' AND cod_vino = :'vino';

    -- Mostrar hora de commit
    SELECT clock_timestamp() AS hora_commit;

COMMIT;

SELECT '=== SESION A: FIN ===' AS info;
SELECT clock_timestamp() AS fin_sesion;