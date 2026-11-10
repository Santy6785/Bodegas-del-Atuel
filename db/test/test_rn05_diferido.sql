-- =====================================================================
-- test_rn05_diferido.sql
-- RN-05 diferido: la composicion se valida al COMMIT, no al INSERT.
-- Ejecutar con ON_ERROR_STOP=0, porque el caso 1 debe fallar en el COMMIT.
-- =====================================================================

-- Preparacion (autocommit): bodega y cepas de prueba.
INSERT INTO bodega (cuit, razon_social, domicilio)
VALUES ('99999999971', 'Bodega RN05 Diferido', 'Dir')
ON CONFLICT DO NOTHING;

INSERT INTO cepa (nombre, tipo)
VALUES ('Cepa RN05 Diferido 1', 'tinta'),
       ('Cepa RN05 Diferido 2', 'blanca')
ON CONFLICT DO NOTHING;

-- Caso 1: suma 60. El COMMIT DEBE FALLAR con el mensaje de RN-05.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino RN05 Diferido', 'tinto', 2021, 750, 14.0, 10000, '99999999971');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
SELECT v.cod_vino, c.id_cepa, 60
  FROM vino v, cepa c
 WHERE v.nombre = 'Vino RN05 Diferido'
   AND c.nombre = 'Cepa RN05 Diferido 1';

COMMIT;  -- DEBE FALLAR: "La composicion del vino ... suma 60.00 ... (RN-05)"

SELECT 'RN-05-DIFERIDO-FAIL' AS caso, count(*) AS vinos_residuales  -- esperado: 0
  FROM vino WHERE nombre = 'Vino RN05 Diferido';

-- Caso 2: suma 100 (60 + 40). El COMMIT DEBE PASAR.
BEGIN;
SET CONSTRAINTS ALL DEFERRED;

INSERT INTO vino (nombre, tipo, anada, volumen_ml, graduacion, precio, cuit_bodega)
VALUES ('Vino RN05 Diferido', 'tinto', 2021, 750, 14.0, 10000, '99999999971');

INSERT INTO vino_cepa (cod_vino, id_cepa, porcentaje)
SELECT v.cod_vino, c.id_cepa,
       CASE c.nombre WHEN 'Cepa RN05 Diferido 1' THEN 60 ELSE 40 END
  FROM vino v, cepa c
 WHERE v.nombre = 'Vino RN05 Diferido'
   AND c.nombre IN ('Cepa RN05 Diferido 1', 'Cepa RN05 Diferido 2');

COMMIT;  -- DEBE PASAR

SELECT 'RN-05-DIFERIDO-OK' AS caso, sum(vc.porcentaje) AS suma_composicion  -- esperado: 100.00
  FROM vino_cepa vc
  JOIN vino v ON v.cod_vino = vc.cod_vino
 WHERE v.nombre = 'Vino RN05 Diferido';

-- Limpieza (la FK en cascada borra vino_cepa).
DELETE FROM vino WHERE nombre = 'Vino RN05 Diferido';