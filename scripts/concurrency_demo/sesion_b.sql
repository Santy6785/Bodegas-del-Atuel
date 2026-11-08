-- Sesion B: Intento de bloqueo DESPUÉS de que A ya tiene el lock
-- Objetivo: Demostrar que B espera a A y luego ve el resultado final

-- Configurar variables de demo (deben coincidir con sesion A)
\set sala '7'
\set vino '9'

-- Mostrar información de inicio
SELECT '=== SESION B: INICIO ===' AS info;
SELECT clock_timestamp() AS inicio_sesion;
SELECT 'PID B: ' || pg_backend_pid() AS pid;

-- Verificar stock actual (antes de intentar bloqueo)
SELECT 'Stock actual (inicial):' AS label, cantidad FROM stock_sala WHERE id_sala = :'sala' AND cod_vino = :'vino';

-- BEGIN TRANSACCION - intentaremos bloquear la misma fila que A
BEGIN;

    -- PASO 1: Intentar bloquear la misma fila que A tiene bloqueada
    -- Esta sentencia BLOQUEARÁ hasta que A haga COMMIT o ROLLBOCK
    SELECT cantidad INTO v_stock_b 
    FROM stock_sala 
    WHERE id_sala = :'sala' AND cod_vino = :'vino'
    FOR UPDATE;

    -- Confirmar lo que leímos (después de que A confirmara)
    SELECT 'Stock visto por B DESPUÉS de A Commit:' AS label, v_stock_b AS valor;

    -- Simular un pequeño delay antes de decidir
    PERFORM pg_sleep(1);

    -- Decidir basada en el stock visto
    -- En este escenario, B verá stock = 0 después de que A confirme
    -- La decisión es hacer ROLLBACK ya que no hay stock para vender
    SELECT 'Decision: stock = ' || v_stock_b || ', haciendo ROLLBACK';

    -- Hacer ROLLBACK para limpiar la transaccion (no se vendió nada extra)
    ROLLBACK;

SELECT '=== SESION B: FIN ===' AS info;
SELECT clock_timestamp() AS fin_sesion;