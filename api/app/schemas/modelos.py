"""Modelos Pydantic de entrada/salida para la API Bodegas del Atuel."""

from __future__ import annotations

from decimal import Decimal
from typing import Any

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
    precio: Decimal
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
