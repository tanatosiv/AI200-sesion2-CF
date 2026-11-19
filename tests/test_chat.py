"""Tests de rutas que no crean respuestas simuladas del modelo."""
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps' / 'chat'))
from main import app
from fastapi.testclient import TestClient

def test_health():
    client = TestClient(app)
    assert client.get('/health').json()['status'] == 'ok'

def test_config_does_not_leak_secrets():
    os.environ['LAB_DEMO_SECRET'] = 'do-not-leak-this'
    body = TestClient(app).get('/config').text
    assert 'do-not-leak-this' not in body

def test_chat_validates_empty_question():
    resp = TestClient(app).post('/api/chat', json={'question':''})
    assert resp.status_code == 422
