SELECT id_cliente, apellido_razon_social
  FROM cliente
 WHERE LOWER(apellido_razon_social) = 'perez';
