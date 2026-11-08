import sys
sys.path.insert(0, "api")
from app.config import get_settings
import psycopg
from psycopg.rows import dict_row

settings = get_settings()
conn = psycopg.connect(settings.conninfo, row_factory=dict_row)

cur = conn.cursor()
cur.execute("SELECT id_cliente, apellido_razon_social, nro_documento FROM cliente WHERE nro_documento = '99888777665'")
print("Found client:", cur.fetchall())

try:
    with conn.transaction():
        conn.execute("DELETE FROM permiso_exportacion WHERE id_cliente IN (SELECT id_cliente FROM cliente WHERE nro_documento = '99888777665')")
        conn.execute("DELETE FROM cliente_exportador WHERE id_cliente IN (SELECT id_cliente FROM cliente WHERE nro_documento = '99888777665')")
        conn.execute("DELETE FROM cliente WHERE nro_documento = '99888777665'")
    print("Deleted successfully!")
except Exception as e:
    print("Delete error:", type(e), e)
