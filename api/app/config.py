"""Configuración global de la API Bodegas del Atuel."""

from functools import lru_cache
from psycopg.conninfo import make_conninfo
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración cargada desde variables de entorno."""

    # Conexión a PostgreSQL (rol app_rw, privilegios mínimos)
    db_host: str = "db"
    db_port: int = 5432
    db_name: str = "bodegas_atuel"
    db_user: str = "app_rw"
    db_password: str  # Sin valor por defecto para contraseñas
    db_sslmode: str = "prefer"
    db_pool_min: int = 1
    db_pool_max: int = 10

    # --- NUEVO: Timeouter de declaración de consulta ---
    # Tiempo máximo que una consulta puede ejecutarse antes de ser cancelada
    # Esto protege contra queries colgados o que devuelven resultados masivos
    db_statement_timeout: int = 60  # 60 segundos por defecto

    # API
    api_port: int = 8000
    cors_origins: str = "http://localhost:3000,http://localhost:5173"

    model_config = SettingsConfigDict(
        env_file=(".env", "../.env"),
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    @property
    def conninfo(self) -> str:
        """Cadena de conexión PostgreSQL armada con psycopg.conninfo.make_conninfo."""
        # Agregamos el statement_timeout a la conexión options
        options = f"-c statement_timeout={self.db_statement_timeout}"
        return make_conninfo(
            host=self.db_host,
            port=self.db_port,
            dbname=self.db_name,
            user=self.db_user,
            password=self.db_password,
            sslmode=self.db_sslmode,
            options=options,
        )


@lru_cache
def get_settings() -> Settings:
    """Devuelve la instancia singleton de la configuración."""
    return Settings()