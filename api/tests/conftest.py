# Fixtures de pytest para tests de la API

import pytest
import httpx
from fastapi.testclient import TestClient

from api.app.main import app


@pytest.fixture
def client():
    """Cliente de pruebas HTTP usando TestClient de FastAPI."""
    return TestClient(app)


@pytest.fixture
def async_client():
    """Cliente asíncrono de pruebas usando httpx."""
    return httpx.AsyncClient(base_url="http://test", transport=httpx.ASGITransport(app=app))