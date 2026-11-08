-- U6-R. Exportadores con más de 3 permisos de exportación y su descuento vigente.
-- Enunciado: reformulación de la consigna U6 (antes: subir el descuento al 35 %).
-- Estrategia: JOIN a cliente_exportador, LEFT JOIN a permiso_exportacion con
--   agregación, HAVING sobre el conteo de todos los permisos cargados.
--   El descuento se obtiene de fn_descuento_cliente, no se calcula aquí.
SELECT c.id_cliente,
       c.apellido_razon_social,
       c.nombre,
       COUNT(p.codigo) AS cantidad_permisos,
       fn_descuento_cliente(c.id_cliente) AS descuento_pct
  FROM cliente c
  JOIN cliente_exportador e ON e.id_cliente = c.id_cliente
  LEFT JOIN permiso_exportacion p ON p.id_cliente = c.id_cliente
 GROUP BY c.id_cliente, c.apellido_razon_social, c.nombre
HAVING COUNT(p.codigo) > 3
 ORDER BY c.id_cliente;