"""Testes rápidos do handler, sem Docker: python -m pytest tests -q"""
import base64
import importlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "hello_world"))
import app  # noqa: E402


def evento(body, base64_encoded=False):
    texto = json.dumps(body)
    if base64_encoded:
        texto = base64.b64encode(texto.encode()).decode()
    return {"body": texto, "isBase64Encoded": base64_encoded}


def setup_function():
    importlib.reload(app)  # zera o contador global entre os testes


def test_gera_guia_com_evento_do_sam():
    with open(pathlib.Path(__file__).resolve().parents[1] / "events" / "pedido.json") as f:
        ev = json.load(f)
    resp = app.lambda_handler(ev, None)
    guia = json.loads(resp["body"])
    assert resp["statusCode"] == 201
    assert guia["guia"] == "G-R-001"
    assert guia["hospital"] == "H-Recife"
    assert guia["bolsas"] == ["O-NEG-0142"]


def test_body_em_texto_como_no_start_api():
    resp = app.lambda_handler(evento({"requisicaoId": "R-002", "hospital": "H-Caruaru"}), None)
    assert resp["statusCode"] == 201
    assert json.loads(resp["body"])["bolsas"] == []


def test_sem_requisicao_id_devolve_400():
    resp = app.lambda_handler(evento({"hospital": "H-Recife"}), None)
    assert resp["statusCode"] == 400


def test_contador_sobe_no_mesmo_ambiente():
    for esperado in (1, 2, 3):
        resp = app.lambda_handler(evento({"requisicaoId": "R-002"}), None)
        assert json.loads(resp["body"])["invocacaoNesteAmbiente"] == esperado
