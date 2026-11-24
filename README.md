Nome: Matheus Rodrigues Larré\
Curso: Análise e Desenvolvimento de Sistemas\
Instituição: CESAR School\
Turma: ADS - Regular\
Disciplina: Infraestrutura de Software\
Tema: Atividade individual 1 (Unidade II) · Serverless

# Rota Vital · Guia de transporte serverless

Função HTTP que recebe uma requisição do Rota Vital e devolve a guia de transporte das bolsas. Ela roda localmente com o AWS SAM CLI, que emula o AWS Lambda e o API Gateway dentro do Docker.

## Caminho escolhido

**Caminho A: AWS SAM CLI local**, sem conta na AWS. Runtime Python 3.12, pacote zip.

Como eu não tinha uma máquina com Docker disponível no dia, rodei os comandos do Caminho A numa máquina Linux do **GitHub Actions** (workflow `.github/workflows/experimentos.yml`). O SAM CLI continua rodando "local", só que nessa máquina, e não na AWS. O script `scripts/experimentos.sh` executa os Passos 2 a 5 na ordem do roteiro e salva cada comando com a sua saída em `evidencias/`. A execução fica registrada publicamente na aba Actions do repositório: [execução nº 1](https://github.com/matheus-larre/rota-vital-guias-serverless/actions/runs/45441413589).

| Ferramenta | Versão usada |
|---|---|
| SAM CLI | 1.174.0 |
| Docker | 29.4.2 |
| Python | 3.12.16 |
| Sistema | Ubuntu (runner do GitHub Actions), x86_64 |

## Estrutura

```
.
├── template.yaml          # função GuiaTransporteFunction, POST /guias, Timeout em Globals
├── samconfig.toml         # configuração do SAM (sem warm containers por padrão, ver "Ajustes")
├── hello_world/
│   └── app.py             # handler que gera a guia
├── events/
│   └── pedido.json        # evento API Gateway gerado com sam local generate-event
├── tests/
│   └── test_app.py        # testes do handler sem Docker (pytest)
├── scripts/
│   └── experimentos.sh    # roda os Passos 2 a 5 e grava as saídas em evidencias/
├── .github/workflows/
│   └── experimentos.yml   # executa o script no GitHub Actions a cada push
└── evidencias/            # saídas dos comandos (geradas pela execução)
```

## Pré-requisitos

- Docker Desktop rodando
- AWS SAM CLI (`sam --version`)
- Python 3.12
- No Windows, usar Git Bash ou WSL

## Como rodar

### 1. Build

```bash
sam build
```

Se a máquina não tiver Python 3.12, `sam build --use-container` faz o build dentro do Docker.

### 2. Invocar com evento (duas vezes, anotando o tempo)

O evento `events/pedido.json` já está no repositório. Para gerar de novo:

```bash
sam local generate-event apigateway aws-proxy --method POST --path guias \
    --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' \
    > events/pedido.json
```

```bash
time sam local invoke -e events/pedido.json
time sam local invoke -e events/pedido.json
```

Resposta esperada:

```json
{"statusCode": 201, "body": "{\"guia\": \"G-R-001\", \"hospital\": \"H-Recife\", \"bolsas\": [\"O-NEG-0142\"], \"invocacaoNesteAmbiente\": 1}"}
```

### 3. Acionar por HTTP

Terminal 1:

```bash
sam local start-api
```

Terminal 2, três vezes:

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
    -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
```

Depois parar o servidor (Ctrl+C), subir de novo reaproveitando o container e repetir as três chamadas:

```bash
sam local start-api --warm-containers LAZY
```

### 4. Limite de tempo

Com o servidor no ar:

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
    -d '{"requisicaoId":"R-003","demorar":true}'
```

Depois trocar `Timeout: 3` por `Timeout: 10` em `Globals` no `template.yaml`, rodar `sam build`, subir o `start-api` de novo e repetir a chamada. No repositório o template está com `Timeout: 3`, que é o valor do experimento.

### 5. Testes (opcional, sem Docker)

```bash
pip install pytest
python -m pytest tests -q
```

### Tudo de uma vez

```bash
bash scripts/experimentos.sh
```

Funciona em Linux, macOS, WSL ou Git Bash com Docker e SAM instalados. No GitHub, a aba **Actions → Experimentos serverless (SAM local) → Run workflow** roda o mesmo script e disponibiliza as saídas para download no artefato `evidencias` da execução.

## Ajustes em relação ao roteiro

1. **Body em base64.** O `sam local generate-event apigateway aws-proxy` grava o body codificado em base64, com `"isBase64Encoded": true`. Com o código do roteiro, o `json.loads` recebia o texto em base64 e a função quebrava com `JSONDecodeError`. Criei a função `ler_corpo` no `app.py`, que decodifica o body quando `isBase64Encoded` é verdadeiro. Assim o mesmo handler funciona com o evento gerado (Passo 3) e com o `curl` pelo `start-api` (Passo 4), que manda o JSON em texto. O resto do handler é o do roteiro.
2. **Warm containers no `samconfig.toml`.** O `sam init` atual cria o `samconfig.toml` com `warm_containers = "EAGER"` para o `start-api`. Com isso, mesmo rodando `sam local start-api` sem a opção, o container já seria reaproveitado e o experimento "sem reaproveitamento" não mostraria diferença. Tirei essas linhas para que o comportamento padrão seja um container novo por requisição.
3. **Nomes.** Renomeei o recurso `HelloWorldFunction` para `GuiaTransporteFunction` e o evento para `GerarGuia`. O caminho é `/guias` e o método é `post`, como pedido.

## Resultados

| Experimento | O que observei |
|---|---|
| `sam local invoke`, 1ª vez | 14,47 s no total (inclui montar a imagem de emulação); handler: 40,05 ms; `invocacaoNesteAmbiente: 1` |
| `sam local invoke`, 2ª vez | 2,10 s no total (imagem já pronta); handler: 39,49 ms; `invocacaoNesteAmbiente: 1` |
| `start-api` sem warm containers (3 chamadas) | `invocacaoNesteAmbiente`: 1, 1, 1; as três com `Init Duration` no REPORT (três cold starts); 0,93 s, 0,43 s, 0,39 s |
| `start-api --warm-containers LAZY` (3 chamadas) | `invocacaoNesteAmbiente`: 1, 2, 3; só a primeira com `Init Duration`; 0,78 s, depois 0,03 s e 0,03 s; handler de 39 ms caiu para ~1,2 ms |
| `demorar: true` com `Timeout: 3` | `Function 'GuiaTransporteFunction' timed out after 3 seconds`; `curl` recebeu HTTP 502 `{"message":"Internal server error"}` em 3,13 s |
| `demorar: true` com `Timeout: 10` | HTTP 201 em 5,93 s, guia `G-R-003` |

Na saída da 1ª invocação aparece a linha `[ERROR] ... LAMBDA_RUNTIME Failed to get next invocation`. Ela não é erro da função: a resposta 201 já tinha sido devolvida antes. É o runtime do emulador tentando buscar o próximo evento depois que o `sam local invoke` encerrou o container.

## Respostas

**Q1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**

A primeira levou 14,47 s e a segunda 2,10 s, no tempo total do comando. A diferença vem do que precisa existir antes de o handler rodar. Na fase de Init, a plataforma cria o ambiente de execução isolado, carrega o pacote com o código, inicia o runtime do Python e executa tudo o que está fora do handler: os imports e a linha `contador = 0`. Só depois vem a fase de Invoke, que é o `lambda_handler` em si. Na nuvem, quando outra chamada chega logo depois, o Lambda reaproveita o ambiente que ficou congelado (warm start) e pula o Init, por isso fica mais rápido.

No meu teste tem um detalhe: o `sam local invoke` cria um container novo a cada execução, tanto que as duas respostas vieram com `invocacaoNesteAmbiente: 1` e as duas têm `Init Duration` na linha REPORT. A primeira demorou muito mais porque o SAM ainda teve que montar a imagem de emulação do Python 3.12 no Docker ("Local image was not found... Building image"). Na segunda a imagem já estava pronta ("Local image is up-to-date") e sobrou só o custo de subir o container e fazer o Init. O handler em si levou cerca de 40 ms nas duas. O efeito do ambiente reaproveitado apareceu no `start-api` com `--warm-containers LAZY`: só a primeira chamada teve `Init Duration`, e nas seguintes o handler caiu de 39 ms para pouco mais de 1 ms e o `curl` de 0,78 s para 0,03 s.

**Q2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre guardar estado numa variável global?**

Sem `--warm-containers`, as três chamadas devolveram 1, porque o SAM subiu um container novo para cada requisição (as três tiveram `Init Duration`) e a variável global sempre começava do zero. Com `--warm-containers LAZY`, o container foi criado na primeira chamada e reaproveitado nas outras, e o campo foi 1, 2 e 3.

Isso mostra que a variável global só guarda alguma coisa enquanto aquele mesmo ambiente estiver vivo, e quem decide isso é a plataforma. O Lambda pode criar outros ambientes para atender chamadas em paralelo (cada um com o seu contador) ou descartar um ambiente parado a qualquer momento. Então a global serve como cache, por exemplo para reaproveitar uma conexão ou um cliente entre chamadas, mas não para estado de negócio. Se a guia precisasse de um número sequencial de verdade, ele teria que vir de um banco, como o PostgreSQL do Rota Vital ou um DynamoDB.

**Q3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?**

A função dorme 5 s, mas o template limita a execução a 3 s. O SAM interrompeu a função exatamente em 3 s (`Function 'GuiaTransporteFunction' timed out after 3 seconds`, com `Duration: 3000.00 ms` no REPORT), e o `curl` recebeu HTTP 502 com `{"message":"Internal server error"}`, sem guia. Ou seja, quem chamou não recebe nada útil, e os 3 s são cobrados mesmo assim. Depois de mudar o `Timeout` para 10 e rodar `sam build`, a mesma chamada demorou 5,93 s e devolveu a guia `G-R-003` com status 201.

No Lambda o máximo é 15 minutos (900 s) por execução. Para um trabalho mais longo, a saída é não fazer tudo numa função só: dividir em etapas orquestradas pelo Step Functions, colocar os itens numa fila (SQS) e processar em lotes menores, ou levar o processamento para um container no ECS/Fargate ou para o AWS Batch, que não têm esse limite.

**Q4. Quanto custam um milhão de execuções com 128 MB e 100 ms (us-east-1)?**

Requisições:

```
1.000.000 × (US$ 0,20 / 1.000.000) = US$ 0,20
```

Computação (GB-s = memória em GB × tempo em segundos):

```
128 MB = 128 / 1024 = 0,125 GB
0,125 GB × 0,1 s = 0,0125 GB-s por execução
0,0125 × 1.000.000 = 12.500 GB-s
12.500 × US$ 0,0000166667 = US$ 0,2083
```

Total:

```
US$ 0,20 + US$ 0,2083 ≈ US$ 0,41 por milhão de execuções
```

Esse é o preço cheio. Dentro da faixa sempre gratuita (1 milhão de requisições e 400 mil GB-s por mês), essa carga sairia de graça. Para comparar: se toda execução fosse como a do `demorar` (5 s com o mesmo 128 MB), seriam 625.000 GB-s, cerca de US$ 10,42 só de computação. No serverless o custo acompanha o tempo de execução, então uma função lenta pesa direto na conta.

**Q5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**

Faria sentido nas partes acionadas por evento e com uso irregular:

- gerar a guia de transporte quando uma requisição de hospital é aprovada, que é exatamente esta função;
- avisar o hospital e o motorista quando a guia sai;
- uma rotina agendada que, uma vez por dia, procura bolsas perto do vencimento para priorizar na fila FEFO;
- gerar relatórios ou PDFs sob demanda.

São tarefas curtas, sem estado próprio, e que passam boa parte do tempo sem chamada nenhuma, então pagar só pelo que executa compensa.

Não faria sentido no núcleo da API em Spring Boot. Ela mantém um pool de conexões com o PostgreSQL, que se perderia a cada cold start e poderia estourar o banco com muitos ambientes em paralelo. Também guarda em memória o grafo de rotas do Dijkstra e o heap da fila FEFO, ou seja, estado que precisa continuar existindo entre as chamadas. E uma aplicação Java com Spring tem um cold start bem mais pesado que esta função em Python. Para esse tipo de serviço, o container que já temos no `compose.yaml` encaixa melhor.

## Evidências

Cada arquivo em `evidencias/` traz o comando executado e a saída completa. Os arquivos `*-servidor.log` são o terminal do `sam local start-api` (onde aparecem as linhas START/END/REPORT e o timeout). O log completo também está na [execução do GitHub Actions](https://github.com/matheus-larre/rota-vital-guias-serverless/actions/runs/45441413589).

| Arquivo | O que mostra |
|---|---|
| [01-versoes.txt](evidencias/01-versoes.txt) | versões do SAM CLI, Docker e Python |
| [02-build.txt](evidencias/02-build.txt) | `sam build` com "Build Succeeded" |
| [03-invoke-1.txt](evidencias/03-invoke-1.txt) | 1ª invocação com evento e tempo |
| [04-invoke-2.txt](evidencias/04-invoke-2.txt) | 2ª invocação com evento e tempo |
| [05-http-sem-warm.txt](evidencias/05-http-sem-warm.txt) · [servidor](evidencias/05-http-sem-warm-servidor.log) | três `curl` sem warm containers (1, 1, 1) |
| [06-http-lazy.txt](evidencias/06-http-lazy.txt) · [servidor](evidencias/06-http-lazy-servidor.log) | três `curl` com `--warm-containers LAZY` (1, 2, 3) |
| [07-timeout-3s.txt](evidencias/07-timeout-3s.txt) · [servidor](evidencias/07-timeout-3s-servidor.log) | erro de tempo limite com `Timeout: 3` |
| [08-timeout-10s-build.txt](evidencias/08-timeout-10s-build.txt) · [08-timeout-10s.txt](evidencias/08-timeout-10s.txt) | `Timeout: 10`, novo build e a mesma chamada com status 201 |
| [09-testes.txt](evidencias/09-testes.txt) | `pytest` com os 4 testes passando |

## Vídeo

Não gravei o vídeo. As três execuções que ele mostraria (invocação com evento, chamada HTTP e erro de tempo limite) estão registradas com as saídas completas em `evidencias/` e no log da execução do GitHub Actions.

## Uso de IA

Conforme a PO-CESAR-021.

- **Ferramenta:** Claude (Anthropic).
- **Finalidade:** apoio para montar o projeto e o README, identificar o problema do body em base64 no evento gerado pelo SAM, escrever os testes em `tests/`, escrever o script e o workflow que rodam os experimentos no GitHub Actions e redigir as respostas e a conta de custo.
- **Como validei:** os experimentos foram executados de verdade com o SAM CLI e o Docker no GitHub Actions, e as saídas estão em `evidencias/` e no log público da execução. Conferi nessas saídas os valores de `invocacaoNesteAmbiente`, os tempos, o erro de timeout e os testes, refiz a conta de custo à mão e revisei as respostas com o conteúdo da Aula 007 e a documentação da AWS sobre o ciclo de vida do ambiente de execução e as cotas do Lambda.
