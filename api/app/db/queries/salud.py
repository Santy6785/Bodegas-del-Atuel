"""Consulta de verificación de conectividad con la base de datos."""

import psycopg


def verificar_conexion(conn: psycopg.Connection) -> bool:
    """Ejecuta SELECT 1 y devuelve True si la base responde."""
    row = conn.execute("SELECT 1 AS ok").fetchone()
    return row is not None
