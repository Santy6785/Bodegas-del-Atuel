UPDATE cliente_exportador e
   SET porcentaje_descuento = 35
 WHERE (SELECT count(*) FROM permiso_exportacion p
         WHERE p.id_cliente = e.id_cliente) > 3;