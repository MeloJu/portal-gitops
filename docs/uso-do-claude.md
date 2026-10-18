# Claude como parceiro de arquitetura

O enunciado do hackathon prevê o Kiro como copiloto; a organização liberou o **Claude (Claude Code)**
no lugar. Aqui ele não foi usado para "gerar código e torcer": foi um **parceiro de estratégia de
arquitetura**. A equipe trazia o objetivo e as restrições (prazo, crédito da Azure, o que a banca
avalia); o Claude lia o código, propunha caminhos com custo e risco, implementava em branch e
**provava o que afirmava num cluster real**. Quem decidia era a equipe.

Este documento registra como a parceria funcionou: o combinado, as decisões com as alternativas que
ficaram de fora, as conversas que mudaram o rumo e **o que o Claude errou e como o erro foi pego**.
É atualizado junto com o trabalho, não no fim.

## Como a parceria funciona

| Quem | Papel |
| --- | --- |
| **Equipe** (Juan, André, Eduardo) | Define objetivo e restrições, **decide**, revisa e aprova PRs. É dona das ações de alto impacto: credenciais, gasto de crédito, exposição na internet, proteção de branch |
| **Claude** | Lê antes de propor; apresenta **opções com trade-offs** e recomenda uma; implementa em branch; valida em cluster real; registra o que provou e o que **não** provou |

Regras que seguimos (e que o Claude cumpre sem precisar ser lembrado):

1. **Ler antes de escrever.** Os três repositórios e o PDF do desafio foram lidos antes do primeiro plano.
2. **Opções, não uma resposta só.** Toda decisão relevante chega com alternativas, custo e uma
   recomendação justificada.
3. **Nada é "feito" sem prova.** No `TASKS.md` uma task só vira `[x]` depois de validada; o que só
   renderiza ou só passa em teste fica `◐ parcial`, com o que falta dito.
4. **Mudança só pelo Git.** Um `kubectl patch` à mão é desfeito pelo ArgoCD, então a correção vai por
   PR, e cada PR diz **como foi validado** (comando e resultado).
5. **Alto impacto exige autorização explícita do dono.** `terraform apply` (gasta crédito), login na
   Azure (feito pelo próprio dono, nenhuma credencial passou pelo Claude), expor o Grafana na
   internet, enviar a chave do VirusTotal para a nuvem, trocar a proteção de branch ou a branch
   padrão. Em vários desses casos o Claude parou e pediu, em vez de seguir adiante.
6. **Revisão humana vale mais que a do Claude.** O André pegou uma falha de segurança que o Claude
   deixou passar (ver a tabela de erros). Desde então o Claude confere o diff inteiro antes de mergear.

## Registro de decisões

Formato resumido de ADR: o que estava em jogo, o que foi considerado, o que foi escolhido e **por quê**.

| # | Decisão | Alternativas consideradas | Escolha e motivo | Quem decidiu | Prova |
| --- | --- | --- | --- | --- | --- |
| D1 | Kubernetes: **k3d/K3s** local e K3s na VM | `kind`, minikube, AKS | O K3s já traz Traefik, metrics-server e aplica NetworkPolicy; a **mesma versão** (v1.35.5+k3s1) roda no local e na nuvem. O AKS exigiria ao menos 2 VMs, o dobro do custo num crédito de estudante. O `kind` ficou só no CI (cluster descartável) | Equipe, sobre proposta do Claude | Mesma versão nos dois ambientes; smoke test passando em ambos |
| D2 | Postgres como **Deployment + PVC, `strategy: Recreate`** | StatefulSet, operador (CloudNativePG) | Arquitetura trazida pela equipe. O Claude mostrou que o PVC é `ReadWriteOnce`: com rolling update o pod novo esperaria um volume que o antigo ainda segura. **Alta disponibilidade ficou fora e é dita como limitação** | Equipe | Smoke test mata o pod do banco e o dado sobrevive |
| D3 | Segredos: **script no local, SealedSecret na nuvem** | SealedSecret em tudo, SOPS, Secret no Git | Um SealedSecret só abre no cluster que o selou, então não serve para o cluster local de cada pessoa | Claude propôs, equipe aceitou | SealedSecret aberto na VM real; escopo e perda/restauração da chave testados |
| D4 | Entrega: **PR de bump com auto-merge** | Push direto na `develop`, atualizador automático de imagem | Push direto pediria uma exceção na proteção de branch. Com PR o deploy passa pelos mesmos checks e fica registrado: **rastreabilidade acima de simplicidade** | Claude propôs, equipe aceitou; o dono ajustou o token | portal-app #70 → portal-gitops #13, sem comando manual |
| D5 | Rota pública **`/otlp`** com 4 camadas | Não expor; sobrescrever `service.name` no pipeline único | Só a rota de traces, limite de taxa, limite de corpo e um **receiver separado** que força `service.name`. Sobrescrever no pipeline único apagaria também o nome da API | Claude desenhou, equipe revisou | Enviado `service.name=l2-api`; o Tempo guardou `l2-frontend` |
| D6 | **Rate limit em duas camadas** | Só Traefik, só na API | Traefik (grosso, 200 req/s) protege o cluster; a API (fino, 60/min) gera o evento de "Ameaça" no painel. Limite da API é por pod: **limitação dita** | Claude propôs, equipe aceitou | Rajada acima do limite recebe `429` no Traefik; logins errados em sequência recebem `429` na API e aparecem no painel de Ameaças |
| D7 | **Rede deny-by-default**; a tools-api só sai para IP público | Liberar tudo | A tools-api busca URLs que o usuário escolhe: é o maior risco de SSRF | Equipe | Alcança `example.com`; bloqueada para Postgres, Actuator, metadados de nuvem e API do Kubernetes |
| D8 | Nuvem: **Azure** (o Oracle foi descartado) | Oracle Free Tier | Decisão da equipe (assinatura estudantil). O Claude **mediu** SKU, quota e preço na conta real e corrigiu a própria recomendação (ver discussão 1) | Equipe | `terraform apply` real: 10 recursos, nó `Ready` |
| D9 | NSG na **sub-rede**, com `depends_on` | NSG na NIC | O Trivy apontou e o `terraform graph` mostrou o problema real: a VM, com IP público, podia subir antes do firewall | Claude, a partir do achado | Grafo corrigido; o resto do alerta virou falso positivo justificado no código |
| D10 | **A nuvem segue a `main`; o local segue a `develop`** | Ambos na `develop`; bump automático também na nuvem | Produção só muda por PR de release. As imagens são promovidas por script (`promover-imagens-azure.sh`), nunca vão direto | Ideia do dono, implementada pelo Claude | Correção do Grafana: #47 → release #48 → ArgoCD da nuvem aplicou sozinho |
| D11 | **Grafana público com login; Prometheus e Tempo só por túnel** | Tudo público; nada público | O dono quis ver os gráficos no navegador. O Prometheus aceita escrita (`remote-write`) e nenhum dos dois tem login, então só o Grafana sai, com HTTPS e senha aleatória | Dono, depois de discutir os riscos | `https://…/grafana/login` responde 200 com certificado válido |
| D12 | Domínio: **DuckDNS**, com o nome da Azure de reserva | Domínio pago, Student Pack, is-a.dev | A Azure não vende domínio com crédito estudante; o uso é de poucos dias. O mesmo certificado cobre os dois nomes | Dono | Let's Encrypt emitido para ambos; `shortUrl` sai no domínio novo |

## Conversas que mudaram o rumo

**1. "Qual VM a gente usa?"** O Claude recomendou a `Standard_B2ms`, com preços de calculadoras de
terceiros. Ao medir na assinatura real, a série B **nem existe** em `brazilsouth`, o preço lá é ~2× o
dos EUA, o crédito dura 27 dias com a VM ligada 24 h, e as famílias novas têm quota zero. A
recomendação mudou para a `Standard_D2s_v4`, a VM passou a **nascer desligável** (auto-shutdown às
23h) e a regra virou: *meça antes de recomendar*.

**2. "O SSH pode ficar aberto?"** O Claude escreveu uma validação que recusava `0.0.0.0/0` e afirmou, no
PR, que o SSH aberto ao mundo era barrado. O **André revisou e mostrou** que `0.0.0.0/1` (metade da
internet), `1.2.3.4/0` e qualquer `/8` passavam. A regra passou a aceitar só IPv4 de `/24` a `/32`, com
14 testes, que o Claude colocou no CI. A lição ficou como prática: testar a *classe* do problema, não só o exemplo.

**3. "Push direto ou PR?"** O push direto era mais simples, mas exigiria deixar o robô pular a proteção de
branch. Escolhemos o PR com auto-merge: mais lento, porém o deploy passa pelo mesmo crivo de um humano.
A discussão voltou quando o primeiro bump falhou por permissão do token (o dono corrigiu) e quando um
"sucesso" do job se mostrou vazio ("nada a propor"): só um commit novo provou a criação do PR.

**4. "Expor telemetria do navegador não é um risco?"** É, e a conversa foi sobre **onde** colocar cada
defesa. O desenho final tem quatro camadas (rota única, taxa, tamanho e receiver separado) e foi
testado tentando se passar pela API.

**5. "Dá para ver o Grafana no navegador?"** Dá, mas é uma tela de administração pública. Conversamos
sobre o risco (varredura automática, tentativa de senha, informação interna), as defesas (HTTPS, senha
aleatória, bloqueio de conta) e a alternativa (túnel SSH). O dono decidiu abrir **só o Grafana**.

**6. "Qual branch a produção segue?"** A ideia de a nuvem seguir a `main` veio do dono e corresponde ao
que se faz em produção: o que chega lá passou por um release. O Claude implementou e mostrou a
consequência: um merge na `develop` **não** vai mais direto à nuvem. É o objetivo, com um passo a mais.

## Como validamos

- **Cluster real antes de PR.** O Claude testa em k3d (e depois na VM) o que escreve. Foi assim que se
  achou o `Prefix` do Traefik tratando prefixo como texto e roubando links curtos.
- **Sabotar para provar.** Os checks são testados quebrando de propósito: com a sabotagem o Checkov
  sai com `exit 1`; sem ela, `exit 0`. Um teste que nunca falhou não prova nada.
- **Teste de regressão para cada bug.** A ordem dos imports da telemetria, a validação do CIDR e os
  alertas (`promtool`) têm teste que falha se o problema voltar.
- **Honestidade sobre o limite.** O que não foi provado vai dito: `terraform plan` com credencial falsa
  "quase validou"; o Claude disse o que **não** tinha verificado.

## Linha do tempo dos pedidos

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
| 16 | "sim, continue" (span do browser) | OTel JS no frontend (portal-app #71 e #72), validado num Chromium headless real; `scripts/check-browser-trace.sh` |
| 17 | "consegue me ajudar a ver alguma máquina da Azure pra subir esse projeto? eu tenho o plano estudantil" e "consegue fazer o terraform pra essa que você recomendou?" | Dimensionamento a partir do consumo **medido** no cluster local (4,1 GB de RAM, 0,9 vCPU) → `Standard_B2ms`; Terraform da VM com K3s, validado sem criar nada na conta (`terraform/`) |
| 18 | "instala o Azure CLI e também pode fazer essas coisas aí, só me fala onde colocar as credenciais" | CLI instalada; login feito **por você** no navegador (nenhuma credencial passou por mim); consulta das regras da assinatura; registro dos provedores; chave SSH, `terraform.tfvars` ignorado pelo Git e `terraform plan` real |
| 19 | "pode dar o apply, depois me ensina a rodar o projeto" e "pode fazer essas coisas e ensina a ver na nuvem" | `terraform apply` real (10 recursos, K3s `Ready`); overlay, app-of-apps, Let's Encrypt e scripts de acesso por túnel SSH (PRs #37 a #39); SealedSecret do primeiro uso real; smoke test completo contra a VM |
| 20 | "tem o .env na pasta do desafio3, precisa subir isso?" e "testa se a API do VirusTotal está funcionando" | O Claude listou **só os nomes** das variáveis (sem os valores) e concluiu que o `.env` nunca vai para o Git; o que faltava era a `VT_API_KEY` no cluster. Selá-la para a nuvem foi **bloqueado pelo modo automático** (origem sensível) e ficou como decisão do usuário |
| 21 | "vou pegar o DuckDNS, preciso do HTTPS" e "linka o Argo com a `main` pras mudanças irem automaticamente" | Certificado Let's Encrypt para o DuckDNS e para o nome da Azure (PR #50); a nuvem passa a seguir a `main`, com script de promoção de imagens (PR #44, release #45); correção do Grafana (OOM) chegando à nuvem só pelo fluxo de release |
| 22 | "tira o `CLAUDE.md` e o `PITCH.md` do repositório" | Os dois saem do Git (PR #52, release #53), com os links do README e do `TASKS.md` corrigidos |
| 23 | "refaz o README dos dois repositórios e refaz o que o Claude fez, como parceiro de arquitetura" | Este documento e os dois READMEs, no molde do desafio de referência |

## O que o Claude errou (e como foi pego)

Registrar os erros é o ponto: o copiloto acelera, mas **a validação em cluster real e a revisão
humana pegaram falhas que o código gerado escondia**.

| Erro | Como apareceu | Correção |
| --- | --- | --- |
| `wait_api` com `kubectl get --raw /readyz` | O primeiro `bootstrap-azure.sh` real falhou com "API não respondeu" **com o túnel funcionando**: o Git Bash do Windows converte `/readyz` num caminho do disco | Trocado por `kubectl get nodes`, com o motivo num comentário |
| Overlay `azure` sem NetworkPolicy para o desafio do Let's Encrypt | Na VM real, o certificado ficou `False` com `wrong status code '502'`: o `default-deny` do namespace impedia o Traefik de falar com o pod do HTTP-01. No local o emissor é self-signed e o problema nunca existiu | `allow-acme-solver`: só Traefik, só a porta 8089, só o pod com o label do solver (PR #39) |
| SealedSecret barrado pelo gitleaks | O texto cifrado virou "generic-api-key" e o check ficou vermelho | Allowlist **só** para `overlays/*/sealed-secret.yaml`; o job de Secret em claro continua barrando `kind: Secret` |
| Sincronização do ArgoCD presa a uma versão antiga | O `l2-azure` esperava um PVC (`WaitForFirstConsumer`) de uma operação iniciada **antes** do SealedSecret existir, e ignorava o commit novo | Operação encerrada (`operation: null`) e novo sync; registrado em `docs/azure.md` |
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
| Telemetria ligada no corpo do `main.tsx` | Só apareceu no navegador real: o primeiro `/api/me` de cada página saía sem `traceparent`, porque o router dispara os loaders na importação do `App` (os imports rodam antes do corpo do `main.tsx`). Os testes unitários passavam | Módulo `telemetry-init.ts` importado primeiro + teste de regressão que falha se a ordem mudar |
| Commitei o `main.tsx` sabotado | Para provar o teste de regressão movi o import de propósito; o backup foi para `/tmp/main.bak` e a restauração leu `main.bak` (local), falhou em silêncio, e o arquivo errado foi commitado e enviado. Vi no `head` logo depois | Commit de restauração no mesmo PR, comentário no PR explicando, CI verde antes do merge |
| Chromium headless sem chegar no `l2.localhost` | `ERR_CONNECTION_REFUSED`: o Chromium resolve `*.localhost` sempre para o próprio loopback e ignora o `/etc/hosts`; depois o `getent` deu IPv6; depois o script travou sem timeout | `--host-resolver-rules` com o IPv4 do balanceador do k3d, rede `k3d-l2` e timeouts em tudo |
| Preços da Azure | Os valores de VM vieram de calculadoras de terceiros, e a B2ms (a recomendada) nem apareceu na busca | Dito na resposta como estimativa, com link para a calculadora oficial e o aviso de que o crédito dura ~6 semanas ligada 24 h |
| `NSG` associado à NIC, sem dependência no grafo | O Trivy reclamou (AZU-0068) e eu ia chamar de falso positivo. O `terraform graph` mostrou o problema real: nada obrigava a VM, com IP público, a esperar o firewall. Havia uma janela de alguns segundos | NSG na **sub-rede** + `depends_on` na NIC; só então o resto do achado virou falso positivo justificado no código |
| `terraform plan` "quase" validando | Com credenciais falsas o plano parou na autenticação, e o "1 to add" era só o `random_string` | Provei o que dava (variáveis recusadas, cloud-init com o validador oficial, Trivy) e deixei explícito que o `plan` e o `apply` reais não foram verificados |
| Heredoc do bash com aspas | Outra vez o comando inteiro falhou sem gravar nada; só percebi conferindo `ls` | Arquivos escritos um a um com a ferramenta de escrita |
| Validação do CIDR do SSH só recusava a string `0.0.0.0/0` | **Revisão do André (PR #30)**: `0.0.0.0/1` (metade da internet), `1.2.3.4/0`, qualquer `/8` e IPv6 passavam, embora o PR e o README afirmassem que o SSH aberto ao mundo era recusado. Eu só tinha testado o caso literal, e o scanner não cobre o buraco (a origem vem de variável) | O André corrigiu (IPv4 `/24` a `/32`) com 14 testes `terraform test`; eu coloquei esses testes **no CI** e provei que afrouxar a regex os faz falhar. Lição: testar a **classe** do problema, não só o exemplo óbvio |
| Mergeei o #30 sem ler as mudanças que entraram nele | O André tinha pedido mudanças, corrigido (PR #31) e aprovado; os arquivos mudaram no disco e eu só percebi pelos avisos | Li a revisão inteira depois, conferi os 14 testes e fechei o que sobrou (digests, `terraform test` no CI, nota do `tflint`). O merge foi seguro (aprovado, CI verde), mas **conferir o diff antes de mergear** é regra |
| Recomendei a `Standard_B2ms` e preços dos EUA | Medindo a assinatura real: **a série B não existe em `brazilsouth`**, os preços lá são ~2× os dos EUA (US$ 0,153/h, não 0,08) e o crédito dura **27 dias ligada 24 h**, não 6 semanas. As famílias novas (`v5`/`v6`/`v7`) têm **quota 0** | Padrão trocado para `Standard_D2s_v4` (a única de 2 vCPU/8 GB liberada e com quota), README com os números medidos e a recomendação de deixar a VM **desligada por padrão** |
| "Liberado" não é "posso criar" | `az vm list-skus` mostrava 77 tamanhos sem restrição, mas a **quota é por família** e a maioria tinha 0. Só a consulta de quota (que voltou vazia até eu registrar os provedores) mostrou isso | Conferir sempre SKU **e** quota da família, e registrar `Microsoft.Compute`/`Network`/`DevTestLab`/`Storage` antes |
| Login por código de dispositivo | A Azure bloqueou (`AADSTS530035`, security defaults) e a CLI mostrou "No subscriptions found", o que parecia conta errada. A conta estava certa: o método de login é que era barrado | Login interativo pelo navegador com `--tenant`; a assinatura apareceu `Enabled` |
| G1 marcada como feita | O usuário perguntou se as Gs estavam prontas; a `main` não existia | Status corrigido para parcial |
| `demo-load.sh` lendo o `code` do link com `grep '"code":"'` | Contra um servidor falso (JSON com espaço depois do `:`) o setup saiu com código 1 e sem mensagem: o `grep` sem match derrubou o script pelo `pipefail` | Regex tolerante a espaço e `\|\| true`, para o erro cair no `die` com a resposta da API |
| Critério do O7 "deletar um pod faz o contador de reinícios subir" | Testado no k3d: depois do `kubectl delete pod`, `kube_pod_container_status_restarts_total` ficou em 0 (o pod novo nasce com `restartCount` 0); só subiu com `kill 1` no container | Painel "Reinícios" com dois números: containers reiniciados (crash/OOM/liveness) e pods recriados (delete, rollout, HPA) |
| PodMonitor do Traefik aplicado direto pelo `root` (O4) | O `revisor-pr` apontou que, num cluster novo, o apply roda antes de o kube-prometheus-stack instalar o CRD e criar o namespace; `SkipDryRunOnMissingResource` só pula o dry-run, e o `root` (sem `retry`) ficaria em `Failed` até o próximo commit | PodMonitor movido para `platform/observability/monitors/`, sincronizado pela Application `observability-monitors` (`project: platform`, `CreateNamespace`, `retry`), no padrão dos Issuers do cert-manager |

## Decisões de detalhe (propostas pelo Claude; a equipe aceitou ou mudou)

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
- **C5 (check Terraform obrigatório) aplicada pelo dono, não pelo agente**: a task é configuração do GitHub
  (branch protection), fora do Git, e o agente não tem admin. Ele parou em vez de tentar contornar; o
  dono incluiu `Terraform (fmt, validate, scan)` nos `required_status_checks.contexts` de `develop` e `main`
  (9 checks) e o agente só registrou a evidência no `TASKS.md`.

