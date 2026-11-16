SELECT nro_transferencia, fecha_confeccion, estado
  FROM transferencia
 WHERE id_sala = 1
   AND estado <> 'procesado'
 ORDER BY fecha_confeccion;
