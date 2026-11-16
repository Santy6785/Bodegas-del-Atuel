SELECT COUNT(*) AS comprobantes, COALESCE(SUM(total), 0) AS total
  FROM comprobante
 WHERE id_sala = 1
   AND fecha >= CURRENT_DATE - INTERVAL '3 months';
