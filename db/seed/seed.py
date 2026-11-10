import sys
import psycopg
from psycopg.errors import UndefinedTable

def verificar_migraciones(conn: psycopg.Connection, tabla_esperada: str = "usuarios") -> None:
    """
    Verifica que la base de datos ya esté migrada antes de ejecutar el seed.
    Consulta la existencia de al menos una tabla creada por la aplicación.
    """
    nombre_completo = f"public.{tabla_esperada}"

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT to_regclass(%s)", (nombre_completo,))
            fila = cur.fetchone()
    except UndefinedTable:
        print(
            f"ERROR: La base de datos no está migrada. "
            f"No se encontró la tabla '{tabla_esperada}' en el esquema 'public'. "
            f"Ejecuta las migraciones primero antes de correr el seed.",
            file=sys.stderr,
        )
        sys.exit(1)
    except psycopg.Error as exc:
        print(
            f"ERROR: No se pudo verificar el estado de migración de la base de datos: {exc}",
            file=sys.stderr,
        )
        sys.exit(1)

    if fila is None or fila[0] is None:
        print(
            f"ERROR: La base de datos no está migrada. "
            f"No se encontró la tabla '{tabla_esperada}' en el esquema 'public'. "
            f"Ejecuta las migraciones primero antes de correr el seed.",
            file=sys.stderr,
        )
        sys.exit(1)

def verificar_usuario_propietario(conn: psycopg.Connection, usuario_esperado: str = "owner_bodegas") -> None:
    """
    Verifica que la conexión actual esté autenticada con el usuario propietario
    de la base de datos.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT current_user;")
        fila = cur.fetchone()

    usuario_actual = fila[0] if fila else None

    if usuario_actual != usuario_esperado:
        print(
            "ERROR: El seed debe ejecutarse con el usuario propietario de la "
            "base de datos para poder desactivar triggers durante la carga "
            "masiva.\n"
            f"Usuario detectado: {usuario_actual}\n"
            f"Usuario esperado:  {usuario_esperado}\n"
            "Conéctate como el propietario (owner_bodegas) y vuelve a ejecutar el seed.",
            file=sys.stderr,
        )
        sys.exit(1)

if __name__ == "__main__":
    try:
        print("Iniciando contenedor de Seed...")
        # psycopg lee automáticamente PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD del entorno
        with psycopg.connect() as conn:
            
            print("Verificando permisos de usuario...")
            verificar_usuario_propietario(conn, usuario_esperado="owner_bodegas")
            
            print("Verificando estado de las migraciones...")
            # IMPORTANTE: Cambia "usuarios" por una tabla real de tu esquema si es distinto
            verificar_migraciones(conn, tabla_esperada="usuarios")

            print("INFRAESTRUCTURA OK: Entorno validado correctamente.")
            print("TODO (Equipo DB): Agregar aquí la lógica de Faker")
            print("   y la inserción de datos usando catalogo.csv")
  
    except psycopg.OperationalError as e:
        print(f"ERROR: No se pudo conectar a PostgreSQL: {e}", file=sys.stderr)
        sys.exit(1)