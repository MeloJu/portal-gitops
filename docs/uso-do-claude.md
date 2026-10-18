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
| 13 | "vai fazendo, vai fazendo" (depois de conferir os PRs do André e o #69 do portal-app) | Merge do #69 (CD) e dos #8, #9 e #10 do André, resolvendo o conflito de `uso-do-claude.md`; validação no cluster do O4 e do Q5; marcação das tasks |
| 14 | "foi, pode ir" / "pode fazer os merge você mesmo" | Re-execução do bump, PR #70 só de documentação para gerar um commit novo, e validação do primeiro deploy 100% automático (portal-app #70 → gitops #13 → ArgoCD) |
| 15 | "sim, pode ir indo" (os 2 P0 que sobravam) | C1: Checkov em hard-fail com skips justificados, provado com sabotagem; A8: rota pública `/otlp` com 4 camadas de proteção, testada no cluster |

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
| Token do bump (`GITOPS_TOKEN`) sem escrita | O primeiro bump automático falhou no `git push`: `403 Permission denied`. O checkout do `portal-gitops` passou porque o repositório é público, então o job parecia saudável até o push. As imagens já tinham sido publicadas | Marquei X2/D1/D2 como parciais (não como feitas) e pedi ao dono do token para conferir *Contents* e *Pull requests* em *Read and write* |
| Conflito de `uso-do-claude.md` entre PRs paralelos | Três PRs do André editando a mesma tabela: o primeiro entra limpo, os outros dois conflitam | Merge da `develop` nas branches, mantendo as linhas dos dois lados, e comentário em cada PR avisando o que foi mexido na branch dele |
| "Sucesso" do job de bump que não provava nada | Ao re-executar depois do bump manual, o job passou sem abrir PR ("nada a propor"): as tags já eram as mesmas. Quase marquei X2 como feito por isso | Gerei um commit novo na `develop` (PR #70, só README) para exercitar de verdade a criação do PR, e só então marquei |
| Sabotagem do Checkov com Python | O `exit=0` do teste de sabotagem **não valia**: o Python do Windows não enxerga o `/tmp` do Git Bash, o arquivo estragado nunca foi criado e o Checkov rodou num arquivo inexistente | Refiz com `sed` no mesmo ambiente; só então vi `exit=1` com a sabotagem e `exit=0` sem ela |
| Plano de `/otlp` sobrescrevendo `service.name` no Collector inteiro | Para impedir que o browser se passe pela API, o processor teria que rodar no pipeline único, e **também apagaria o `service.name` da própria API** (mesmo receiver) | Receiver separado (`otlp/browser`, porta 4319) com pipeline próprio; só ele passa pelo `resource/browser` |
| Chart do Collector deixava jaeger, zipkin e prometheus ligados | Ao ler o `values.yaml`, para expor uma rota pública de um componente com superfície que ninguém usava | Receivers, portas e pipelines de métricas/logs desligados; o Service expõe só 4317, 4318 e 4319 |
| G1 marcada como feita | O usuário perguntou se as Gs estavam prontas; a `main` não existia | Status corrigido para parcial |
| `demo-load.sh` lendo o `code` do link com `grep '"code":"'` | Contra um servidor falso (JSON com espaço depois do `:`) o setup saiu com código 1 e sem mensagem: o `grep` sem match derrubou o script pelo `pipefail` | Regex tolerante a espaço e `\|\| true`, para o erro cair no `die` com a resposta da API |
| Critério do O7 "deletar um pod faz o contador de reinícios subir" | Testado no k3d: depois do `kubectl delete pod`, `kube_pod_container_status_restarts_total` ficou em 0 (o pod novo nasce com `restartCount` 0); só subiu com `kill 1` no container | Painel "Reinícios" com dois números: containers reiniciados (crash/OOM/liveness) e pods recriados (delete, rollout, HPA) |
| PodMonitor do Traefik aplicado direto pelo `root` (O4) | O `revisor-pr` apontou que, num cluster novo, o apply roda antes de o kube-prometheus-stack instalar o CRD e criar o namespace; `SkipDryRunOnMissingResource` só pula o dry-run, e o `root` (sem `retry`) ficaria em `Failed` até o próximo commit | PodMonitor movido para `platform/observability/monitors/`, sincronizado pela Application `observability-monitors` (`project: platform`, `CreateNamespace`, `retry`), no padrão dos Issuers do cert-manager |

## Decisões que o Claude propôs e a equipe aceitou ou mudou

- **Secret no local criado pelo script, não SealedSecret**: um SealedSecret só abre no cluster que o
  selou, então commitar um para o cluster local não serviria aos outros membros.
- **tools-api incluída**: o nginx do frontend não sobe se o host do upstream não resolve.
- **Janela de 60 s no scale-up do HPA**: o boot da JVM (Spring + Flyway) gerava scale-up em cascata.
- **Limite de viagens alto só no overlay `local`** (`APP_RATELIMIT_TRAVEL_CAPACITY`): o padrão de 60/min
  por IP trava o loop de cliques antes de gerar CPU para o HPA. Login e cadastro ficam no padrão.
- **Rajada de login repetida a cada 61 s no `demo-load.sh ameaca`**: lido no `RateLimiter` do
  portal-app, só a primeira recusa de cada janela (1 min) por rota + IP + pod vira evento e incrementa
  `l2_threats_blocked_total{reason="RATE_LIMIT"}`. Uma rajada só, por maior que seja, soma 1 por pod.
  O tamanho padrão (240 logins, 20 em paralelo) esvazia o balde de 60 mesmo com 3 réplicas.
- **User-Agent de navegador no loop de cliques**: com `curl` toda viagem conta como bot e a curva de
  cliques humanos fica zerada. O padrão é um Chrome; `--user-agent` mostra a curva de bots.
- **Exemplars (métrica → trace) pelo span-metrics do Tempo, não pelo Micrometer**: o `/actuator/prometheus` responde
  em OpenMetrics, mas sem nenhum exemplar, porque o agente Java do OTel não entrega SpanContext ao Micrometer. Em vez
  de esperar uma mudança no `portal-app`, o Tempo envia os exemplars das métricas que gera dos spans
  (`send_exemplars`), o Prometheus os guarda (`exemplar-storage`) e o painel de latência ganhou um p95 "dos traces"
  com exemplars, ao lado do p95 do Micrometer. O label do exemplar é `traceID` (o que o Tempo grava), não `trace_id`.
- **Métricas do Traefik por PodMonitor, não ServiceMonitor** (O4): a porta `metrics` (9100) fica fora
  do Service do Traefik (`expose.default: false`) para não ir parar no LoadBalancer; o Prometheus lê
  direto do pod, por dentro do cluster, como faz com o Actuator. Junto, `asDefault: true` em `web` e
  `websecure`, para as rotas dos Ingress não entrarem também nos entrypoints internos.

## Próximas entradas

Observabilidade (OpenTelemetry, Tempo, Prometheus, Grafana), overlay `oracle`, Terraform e o pipeline
de imagens do `portal-app`: registrar aqui conforme forem feitos.
