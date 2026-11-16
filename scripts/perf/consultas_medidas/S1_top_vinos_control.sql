SELECT rc.cod_vino, v.nombre,
       COALESCE(SUM(rc.cantidad), 0)::BIGINT AS botellas_vendidas
  FROM renglon_comprobante rc
  JOIN vino v ON v.cod_vino = rc.cod_vino
 GROUP BY rc.cod_vino, v.nombre
 ORDER BY botellas_vendidas DESC, rc.cod_vino ASC
 LIMIT 10;
