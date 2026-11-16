SELECT s.id_sala, s.calle, s.numero,
       COALESCE(SUM(c.total), 0)::NUMERIC(12,2) AS monto_total
  FROM sala_venta s
  LEFT JOIN comprobante c
    ON c.id_sala = s.id_sala
   AND c.fecha >= CURRENT_DATE - INTERVAL '3 months'
 GROUP BY s.id_sala, s.calle, s.numero
 ORDER BY monto_total DESC, s.id_sala ASC;
