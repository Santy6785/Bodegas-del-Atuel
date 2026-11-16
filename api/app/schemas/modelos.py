"""Modelos Pydantic de entrada/salida para la API Bodegas del Atuel."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Any, Literal

from pydantic import BaseModel, Field


class CepaVino(BaseModel):
    """Composición varietal de un vino (entrada)."""

    id_cepa: int = Field(gt=0)
    porcentaje: Decimal = Field(gt=0, le=100)


class VinoCreate(BaseModel):
    """Payload de alta de vino (POST /vinos)."""

    nombre: str = Field(min_length=1, max_length=80)
    tipo: str
    anada: int = Field(ge=1800, le=2100)
    volumen_ml: int = Field(gt=0)
    graduacion: Decimal = Field(ge=0, le=100)
    precio: Decimal  # RN-01/RN-15: precio > 0 lo aplica el CHECK de vino (23514 -> 422); el modelo no duplica la regla.
    cuit_bodega: str = Field(min_length=11, max_length=11)
    composicion: list[CepaVino] = Field(min_length=1)
    maridajes: list[int] = Field(default_factory=list)

    model_config = {
        "json_schema_extra": {
            "example": {
                "nombre": "Malbec Reserva",
                "tipo": "tinto",
                "anada": 2021,
                "volumen_ml": 750,
                "graduacion": "14.00",
                "precio": "12500.00",
                "cuit_bodega": "30123456789",
                "composicion": [
                    {"id_cepa": 1, "porcentaje": "85.00"},
                    {"id_cepa": 2, "porcentaje": "15.00"},
                ],
                "maridajes": [1, 2],
            }
        }
    }


class TransferenciaCreate(BaseModel):
    """Payload de alta de transferencia (POST /transferencias)."""

    id_sala: int = Field(gt=0)

    model_config = {"json_schema_extra": {"example": {"id_sala": 1}}}


class RenglonTransferenciaCreate(BaseModel):
    """Payload de renglón de transferencia (POST /transferencias/{nro}/renglones)."""

    cod_vino: int = Field(gt=0)
    cantidad: int = Field(gt=0)

    model_config = {
        "json_schema_extra": {"example": {"cod_vino": 10, "cantidad": 24}}
    }


class ComprobanteCreate(BaseModel):
    """Payload de venta (POST /comprobantes)."""

    id_cliente: int = Field(gt=0)
    id_sala: int = Field(gt=0)
    cod_vinos: list[int] = Field(min_length=1)
    cantidades: list[int] = Field(min_length=1)

    model_config = {
        "json_schema_extra": {
            "example": {
                "id_cliente": 1,
                "id_sala": 1,
                "cod_vinos": [10, 12],
                "cantidades": [6, 2],
            }
        }
    }


class PermisoExportacion(BaseModel):
    """Permiso de exportación para clientes exportadores."""

    codigo: str = Field(min_length=1, max_length=20)
    fecha_emision: date
    fecha_vencimiento: date


class DistribuidorData(BaseModel):
    """Datos específicos de cliente distribuidor."""

    zona_cobertura: str = Field(min_length=1, max_length=120)
    nro_habilitacion: str = Field(min_length=1, max_length=30)


class ExportadorData(BaseModel):
    """Datos específicos de cliente exportador."""

    pais_destino: str = Field(min_length=1, max_length=60)
    permisos: list[PermisoExportacion] = Field(default_factory=list)


class ClienteCreate(BaseModel):
    """Payload de alta o reemplazo completo de cliente (POST/PUT /clientes)."""

    apellido_razon_social: str = Field(min_length=1, max_length=150)
    nombre: str | None = Field(default=None, max_length=100)
    tipo_documento: Literal["DNI", "CUIT", "CUIL", "PASAPORTE"]
    nro_documento: str = Field(min_length=1, max_length=11)
    direccion: str = Field(min_length=1, max_length=200)
    codigo_postal: str = Field(min_length=1, max_length=8)
    tipo_cliente: Literal["socio", "distribuidor", "exportador"]
    distribuidor: DistribuidorData | None = None
    exportador: ExportadorData | None = None

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "apellido_razon_social": "Exportadora Sur S.A.",
                "nombre": None,
                "tipo_documento": "CUIT",
                "nro_documento": "30987654321",
                "direccion": "Av. Ejemplo 500",
                "codigo_postal": "M5600",
                "tipo_cliente": "exportador",
                "exportador": {
                    "pais_destino": "Brasil",
                    "permisos": [
                        {
                            "codigo": "PE-001",
                            "fecha_emision": "2026-01-01",
                            "fecha_vencimiento": "2027-01-01",
                        }
                    ],
                },
            }
        },
    }


class IngresoCreate(BaseModel):
    """Payload de alta de ingreso (POST /ingresos)."""

    fecha: date
    cod_transportista: int = Field(gt=0)
    cuit_bodega: str = Field(min_length=11, max_length=11)

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {
                "fecha": "2026-11-03",
                "cod_transportista": 3,
                "cuit_bodega": "30123456789",
            }
        },
    }


class RenglonIngresoCreate(BaseModel):
    """Payload de renglón de ingreso (POST /ingresos/{cod}/renglones)."""

    cod_vino: int = Field(gt=0)
    cantidad: int = Field(gt=0)

    model_config = {
        "extra": "forbid",
        "json_schema_extra": {
            "example": {"cod_vino": 10, "cantidad": 120}
        },
    }
