SELECT COUNT(*) AS comprobantes, COALESCE(SUM(total), 0) AS total
  FROM comprobante
 WHERE fecha >= CURRENT_DATE - INTERVAL '{{INTERVALO}}';
