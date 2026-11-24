import base64, json, time

contador = 0     # variável global: só sobrevive se o ambiente for reaproveitado


def ler_corpo(event):
    """Devolve o body da requisição como dict.

    O evento gerado por `sam local generate-event` vem com o body em base64
    (isBase64Encoded = true). Já o `sam local start-api` manda o JSON em texto.
    Por isso decodifico quando precisa, antes do json.loads.
    """
    corpo = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        corpo = base64.b64decode(corpo).decode("utf-8")
    return json.loads(corpo)


def lambda_handler(event, context):
    global contador
    contador += 1
    pedido = ler_corpo(event)
    if "requisicaoId" not in pedido:
        return {"statusCode": 400,
                "body": json.dumps({"erro": "requisicaoId obrigatório"})}
    if pedido.get("demorar"):
        time.sleep(5)  # passa do Timeout de 3 s do template
    guia = {"guia": "G-" + pedido["requisicaoId"],
            "hospital": pedido.get("hospital"),
            "bolsas": pedido.get("bolsas", []),
            "invocacaoNesteAmbiente": contador}
    return {"statusCode": 201, "body": json.dumps(guia)}
