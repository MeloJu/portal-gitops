# Uso do Claude

O enunciado do hackathon prevê o Kiro como copiloto; a organização liberou o **Claude (Claude Code)**
no lugar. Este documento registra **o que foi pedido, o que foi decidido e o que o Claude errou**,
para o critério de uso do copiloto. É atualizado junto com o trabalho, não no fim.

## Como o trabalho foi conduzido

1. O Claude **lê antes de escrever**: os três repositórios (`portal-gitops` vazio, o desafio de
   referência `k8s-postgrest-challenge` e o `portal-app` na `develop`) e o PDF do desafio.
2. Gera um plano e **pede confirmação** das decisões que mudam o rumo.
3. Implementa em branch de feature, **valida num cluster real** e só então abre PR.
4. Os achados da validação voltam para o plano (`TASKS.md`) e para os comentários dos manifests.

## Prompts e resultados

| # | Pedido (resumo fiel) | Resultado |
| --- | --- | --- |
| 1 | "faz um md separando em tasks o que tem que ser feito [...] usando como base esse desafio já feito [...] segue o gitflow, ci/cd estruturado e afins" | [`TASKS.md`](../TASKS.md): épicos G/P/A/C/D/R/O/S/X/Q, prioridades, riscos. Leu o `portal-app` e descobriu o contrato do `release.yml` (caminho do overlay, nomes de imagem) |
| 2 | Colou a arquitetura combinada (Postgres em Deployment, namespace `l2`, overlays `local`/`oracle`, SealedSecret, `/otlp`, `terraform/`) | Plano reescrito. O Claude apontou o que a arquitetura não cobria (tools-api, nome de imagem, Postgres 18, `/otlp` público, rate limit) |
| 3 | "esses pontos que minha arquitetura não cobria você pode pensar nelas e depois faz o commit do md na develop" | Seção 3.1 do plano com seis decisões fechadas, lendo o código (limites de 60/min por IP, por pod) e commit na `develop` |
| 4 | "a gente usaria as stacks pedidas no desafio né? se sim pode começar as tasks" | Marco M1: manifests, overlays, bootstrap do ArgoCD, scripts e CI de PR, validados em k3d (PR #1) |
| 5 | "a gente não vai usar o OpenTelemetry?" | Esclareceu que o OTel é obrigatório e já está no plano; o Claude tinha escrito "observabilidade" onde devia dizer OpenTelemetry |
| 6 | "nós já fizemos as Gs?" | Resposta honesta: só em parte (sem `main`, sem proteção de branch). O Claude tinha marcado G1 como feita e corrigiu |
| 7 | "o README pega o do desafio [...] e adapta pra esse aqui" | Este README, no molde do desafio de referência, marcando 🚧 o que ainda não existe |
| 8 | "podemos continuar com as Gs, depois a gente faz as Ps" | Governança: `main`, proteção de branch, `CODEOWNERS`, template de PR, `CLAUDE.md` e um check de gitflow no CI |
| 9 | "adiciona esse André e Eduardo como code owner" (com print da lista de colaboradores) | O Claude leu os usuários no print (`drezix`, `eduardoberlink`) e **confirmou pela API** que ambos têm escrita antes de os pôr no `CODEOWNERS` |
| 10 | "sim pode, e depois pode ir para a próxima task" | README com a equipe; validação do app-of-apps `root` depois do merge do PR #1; task P2 (Sealed Secrets) |
| 11 | "não vai ter oracle por enquanto, pensa como se fosse local, mas pode continuar" | Escopo reduzido ao cluster local: P3 só com self-signed, Let's Encrypt adiado; P4 e P6 feitas |
| 12 | "corrige o que tá errado primeiro, depois vai para observabilidade" | PR #5 com o status real das tasks; depois a observabilidade completa (PR desta etapa) |

## O que o Claude errou (e como foi pego)

Registrar os erros é o ponto: o copiloto acelera, mas **a validação em cluster real e a revisão
humana pegaram falhas que o código gerado escondia**.

| Erro | Como apareceu | Correção |
| --- | --- | --- |
| Paths do Ingress como `/r` e `/api` | Teste ao vivo: `GET /rocket` caiu na API (401). O Traefik trata `Prefix` como prefixo de **texto**, ao contrário da spec do Kubernetes | Paths com barra final (`/r/`, `/api/`), com o motivo no comentário do manifest |
| Primeira correção feita com `kubectl patch` | O ArgoCD (`selfHeal`) **reverteu** o patch em segundos, e o teste foi inválido | Correção só pelo Git, que é a regra do GitOps |
| Nome de métrica `l2_links_created_total` no plano | Conferido em `/actuator/prometheus`: é `l2_links_total` | Plano corrigido |
| Imagem da tools-api "~1,5 GB" | `docker images`: 3,5 GB | Plano corrigido |
| Readiness da API incluindo o banco | Revisão do comportamento: um blip do Postgres derrubaria todos os pods ao mesmo tempo | Mantido o padrão do Spring (`readinessState`); o banco é checado no boot pelo Flyway |
| `bootstrap-local.sh` assumia o kubeconfig do k3d | No Docker Desktop (Windows) o k3d grava `host.docker.internal`, inacessível | O script reescreve para `127.0.0.1` |
| `PATH` montado com `C:/...` | `k3d` "não encontrado": o `:` do drive quebrou a lista | Caminho no formato `/c/...` |
| URL do repositório Helm do Sealed Secrets (`bitnami-labs.github.io`) | `curl` deu 404 ao buscar a versão do chart; o README upstream mostra `bitnami.github.io` | Repo e versão (2.20.0) conferidos no `index.yaml` antes de fixar |
| `kubectl apply -f <(git show ...)` | No Windows, a substituição de processo vira `/proc/.../fd` e falha | Aplicar do arquivo do working tree (verificado idêntico ao da `develop` com `git diff`) |
| PR empilhado sem CI | O workflow só dispara para PRs que miram `main`/`develop`; o #2 (base = branch de feature) ficou sem checks | Anotado no PR; depois do retarget os 5 checks passaram |
| Teste de rate limit com 65 `curl` em sequência | Nenhum `429`: o balde recarrega 1 token/s e cada `curl` levava mais de 1 s, então nunca esvaziava. Quase concluí que o Traefik estava errado | Li o filtro e o `RateLimiter`, vi o refill, e refiz com uma rajada de 120 numa conexão: 56 × `429` |
| `printf` montando JSON do patch do ArgoCD | `
` virou quebra de linha real, o `kubectl patch` falhou e o loop de espera rodou 5 min à toa | Patch montado com Python e aplicado via `--patch-file` |
| Gatilho do `pr-validate` só para base `main`/`develop` | O PR #4, retargetado para `develop` depois do merge do #3, ficou com os 4 checks obrigatórios em *Waiting for status* (o retarget dispara `edited`, que não estava na lista). O usuário achou que os testes tinham quebrado | Workflow passa a rodar em qualquer base e no evento `edited`; o #4 rodou e ficou verde |
| ConfigMap fixo para a config da API | Mudei `OTEL_SDK_DISABLED` para `false`, o ArgoCD aplicou, e o processo da API continuou com `true`: env de ConfigMap só é lido na partida | `configMapGenerator` com hash no nome: mudar a config dispara o rollout sozinho |
| Nome `MANAGEMENT_..._PERCENTILES_HISTOGRAM_...` | A API entrou em CrashLoop. Primeiro suspeitei do agente OTel deixando o boot lento; medi fora do cluster e o agente até acelerava o boot (22 s contra 35 s). O log mostrou o erro real de binding | `PERCENTILESHISTOGRAM` (o hífen some em variável de ambiente); testado com a imagem antes de commitar |
| Service graph do Tempo vazio | Painel "Mapa de serviços" sem dado | Li o chart: os processadores ficam em `overrides.defaults.metrics_generator` |
| Painel "cliques humanos" | Sob carga marcou 0: o `curl` é classificado como bot pelo User-Agent | Painel conta todas as viagens; a divisão bot/humano fica no gráfico ao lado |
| G1 marcada como feita | O usuário perguntou se as Gs estavam prontas; a `main` não existia | Status corrigido para parcial |
| Critério do O7 "deletar um pod faz o contador de reinícios subir" | Testado no k3d: depois do `kubectl delete pod`, `kube_pod_container_status_restarts_total` ficou em 0 (o pod novo nasce com `restartCount` 0); só subiu com `kill 1` no container | Painel "Reinícios" com dois números: containers reiniciados (crash/OOM/liveness) e pods recriados (delete, rollout, HPA) |

## Decisões que o Claude propôs e a equipe aceitou ou mudou

- **Secret no local criado pelo script, não SealedSecret**: um SealedSecret só abre no cluster que o
  selou, então commitar um para o cluster local não serviria aos outros membros.
- **tools-api incluída**: o nginx do frontend não sobe se o host do upstream não resolve.
- **Janela de 60 s no scale-up do HPA**: o boot da JVM (Spring + Flyway) gerava scale-up em cascata.
- **Limite de viagens alto só no overlay `local`** (`APP_RATELIMIT_TRAVEL_CAPACITY`): o padrão de 60/min
  por IP trava o loop de cliques antes de gerar CPU para o HPA. Login e cadastro ficam no padrão.
- **Exemplars (métrica → trace) adiados para o `portal-app`**: o `/actuator/prometheus` responde em OpenMetrics, mas sem
  nenhum exemplar, porque o agente Java do OTel não entrega SpanContext ao Micrometer. Ligar `exemplar-storage` e
  `exemplars: true` antes disso só criaria um botão que nunca aparece.

## Próximas entradas

Observabilidade (OpenTelemetry, Tempo, Prometheus, Grafana), overlay `oracle`, Terraform e o pipeline
de imagens do `portal-app`: registrar aqui conforme forem feitos.
