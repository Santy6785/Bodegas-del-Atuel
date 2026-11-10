import sys
import psycopg
from psycopg.errors import UndefinedTable

def verificar_migraciones(conn: psycopg.Connection, tabla_esperada: str = "usuarios") -> None:
    """
    Verifica que la base de datos ya esté migrada consultando una tabla clave.
    """
    nombre_completo = f"public.{tabla_esperada}"

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT to_regclass(%s)", (nombre_completo,))
            fila = cur.fetchone()
    except UndefinedTable:
        print(
            f"ERROR: La base de datos no está migrada. "
            f"No se encontró la tabla '{tabla_esperada}'. "
            f"Ejecuta las migraciones primero antes de correr el seed.",
            file=sys.stderr,
        )
        sys.exit(1)
    except psycopg.Error as exc:
        print(f"ERROR al verificar migraciones: {exc}", file=sys.stderr)
        sys.exit(1)

    if fila is None or fila[0] is None:
        print(
            f"ERROR: La base de datos no está migrada. "
            f"No se encontró la tabla '{tabla_esperada}'. "
            f"Ejecuta las migraciones primero antes de correr el seed.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    # psycopg lee automáticamente PGHOST, PGPORT, PGDATABASE, etc. del entorno
    try:
        print("Iniciando contenedor de Seed...")
        with psycopg.connect() as conn:
            # OJO: Asegúrate de que "usuarios" sea una tabla que realmente 
            # deba existir en tu proyecto. Cámbiala por "bodegas" o la que corresponda.
            verificar_migraciones(conn, tabla_esperada="usuarios")
            
            print("=========================================")
            print("✅ INFRAESTRUCTURA OK: Base de datos verificada y lista.")
            print("⏳ TODO (Equipo DB): Agregar aquí la lógica de Faker")
            print("   y la inserción de datos usando catalogo.csv")
            print("=========================================")
            
    except psycopg.OperationalError as e:
        print(f"ERROR: No se pudo conectar a PostgreSQL: {e}", file=sys.stderr)
        sys.exit(1)