# Evidências do Lumi Links

Esta pasta é o destino das capturas reais. **Nenhuma screenshot foi incluída nesta branch**:
o estado do cluster e dos workflows precisa ser observado no momento da captura. Não use imagens
de exemplo, telas reconstruídas ou resultados históricos como se fossem atuais.

Na raiz do repositório, execute `./scripts/capturar.sh` para ver a lista curta. O script é apenas
um roteiro: não consulta GitHub nem Kubernetes, não abre páginas, não cria arquivos e não altera
o cluster. As telas devem ser capturadas manualmente depois de confirmar cada estado abaixo.

## Antes de capturar

- Use o cluster local `k3d`/K3s e as interfaces/repositórios reais do projeto. O ambiente Azure
  ainda não foi aplicado e não é parte destas evidências.
- Anote a data, o commit/tag ou o identificador do workflow/PR na legenda. Uma captura prova
  somente o estado visível naquele momento.
- Não mostre credenciais, tokens, valores de Secrets, arquivos `.env`, cookies ou dados pessoais.
  Não execute `kubectl get secret` nem copie senhas para a tela.
- Não use `kubectl apply`, `patch`, `edit`, `scale`, `delete` ou qualquer comando que altere
  recursos. Os comandos `kubectl get` abaixo são somente leitura.
- `demo-load.sh` gera tráfego e grava dados da aplicação; use-o somente numa sessão de demo
  autorizada. Ele não aplica manifests nem altera recursos do Kubernetes. Não rode as cenas
  durante esta tarefa de documentação.
- Se uma página, serviço, alerta ou workflow não estiver disponível ou não mostrar o estado
  esperado, não capture como prova; deixe a evidência pendente.

## Capturas

| Arquivo sugerido | Fonte e como obter | O que a captura deve provar |
| --- | --- | --- |
| `01-argocd-synced.png` | ArgoCD > Applications; confirme `l2-api`, `frontend` e `tools-api`. | Estado `Synced` e `Healthy` visível para as Applications mostradas, no momento da captura. Não basta mostrar o dashboard do ArgoCD sem os estados. |
| `02-portal-app-actions.png` | GitHub Actions em `MeloJu/portal-app`; abra uma execução real bem-sucedida do fluxo CI/build. | Nome do workflow, referência (branch/commit) e conclusão bem-sucedida dos jobs relevantes. Não alegue que um CI de `portal-gitops` publicou imagens: a publicação é responsabilidade do CI do `portal-app`. |
| `03-gitops-pr-validation.png` | PR real de bump no `MeloJu/portal-gitops`; abra os checks concluídos. | PR de bump e checks obrigatórios concluídos com sucesso. Não use o PR desta documentação como se fosse um bump de imagem. |
| `04-grafana-hpa.png` | Grafana > dashboard **Lumi — Visão geral** durante a cena `cliques`; deixe o painel de réplicas/CPU legível. | Carga observada e mudança real nas réplicas da API. Para confirmar os limites do overlay local, use `kubectl -n l2 get hpa l2-api` (somente leitura); o overlay define mínimo 1 e máximo 3. Uma captura estática sem carga não prova escalonamento. |
| `05-tempo-browser-api-db.png` | Tempo, usando um trace recente gerado por uma navegação real instrumentada. | Um mesmo trace com spans do navegador (`l2-frontend`), Traefik, `l2-api` e a operação JDBC/SQL do banco. O span de banco aparece sob o serviço `l2-api`; não há `postgres_exporter` nem serviço Postgres instrumentado como serviço separado. |
| `06-alert-l2picoameacas.png` | Prometheus > Alerts ou o painel de alertas do Grafana, depois da cena `ameaca`. | `L2PicoDeAmeacas` em `FIRING` e o instante/valor visível. O PrometheusRule define o alerta quando há pelo menos três bloqueios por rate limit em cinco minutos. Alertmanager não está instalado; não descreva isto como uma notificação enviada. |

## Gerar os sinais para a demo

Faça isso apenas quando a infraestrutura local estiver disponível e aquecida, fora desta tarefa.
Os comandos geram tráfego/dados da aplicação, não alteram manifests nem recursos do cluster:

```bash
./scripts/demo-load.sh cliques --duration 180
./scripts/demo-load.sh ameaca --duration 150
./scripts/check-browser-trace.sh
```

`cliques` sem `--codes` executa o setup e imprime credenciais de demonstração. Faça o setup
antes da apresentação, fora da projeção; não capture nem compartilhe a saída. Para reaproveitar
links existentes, informe `--codes A,B,C`. Rode `cliques` e `ameaca` em momentos separados para
não misturar o sinal de tráfego com o painel de ameaças. O comando de trace usa o cluster local,
abre um `port-forward` temporário e faz chamadas de teste à aplicação; confirme que a execução
terminou antes de capturar.

## Legendas e revisão

Para cada imagem adicionada, inclua uma legenda curta com: data/hora, fonte (workflow/PR ou
cluster), commit/tag quando aplicável e a afirmação exata que a tela comprova. Remova da captura
qualquer informação sensível antes de adicioná-la ao Git. Preserve a imagem original somente
quando não contiver segredos nem dados pessoais.

Os arquivos de CI, ArgoCD, Grafana, Tempo e alertas dependem de serviços e execuções reais; a
ausência de uma captura nesta pasta significa que essa evidência ainda não foi coletada.
