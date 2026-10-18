# Pitch Lumi Links — 15 minutos

Roteiro ensaiável para cinco pessoas. O cronômetro inclui **2 minutos para perguntas**: 13 minutos
de apresentação e demonstração, seguidos de 2 minutos de Q&A. Use o cluster local k3d/K3s
aquecido; Azure ainda não foi aplicado. Não apresente uma tela indisponível como se estivesse ao
vivo nem um estado histórico como se fosse atual.

## Preparação antes de começar

1. Confirme que a aplicação, ArgoCD, Grafana e Tempo estão acessíveis no cluster local:
   `kubectl -n argocd get applications`, `kubectl -n l2 get pods` e
   `kubectl -n l2 get hpa l2-api` são consultas somente leitura.
2. Abra previamente o dashboard **Lumi — Visão geral**, o Tempo e o app. Deixe a sessão do
   navegador autenticada com uma conta de demonstração, sem exibir credenciais.
3. Tenha links de demonstração prontos. Se precisar criá-los, faça o setup antes da fala e
   mantenha a saída de `./scripts/demo-load.sh setup` fora da projeção: o script imprime usuário
   e senha. Guarde somente os códigos dos links para passar `--codes`.
4. Aqueça os serviços antes de cronometrar. Rode e confira o trace com
   `./scripts/check-browser-trace.sh`; confira que o dashboard recebeu dados. Se a pré-checagem
   falhar, use o plano alternativo abaixo, sem alegar que a integração está funcionando ao vivo.
5. Em terminal separado, deixe preparado `kubectl -n l2 get hpa l2-api -w` (somente leitura).
   Não execute comandos de escrita no Kubernetes durante a apresentação.

## Cronograma e falas

| Tempo | Pessoa | Cena e fala sugerida |
| --- | --- | --- |
| 00:00–00:40 | Juan — negócio | **Problema:** “Compartilhar links e entender as visitas não deveria exigir infraestrutura própria para cada link. O Lumi Links centraliza a criação e o redirecionamento e nos permite observar o caminho da requisição.” |
| 00:40–02:00 | Gracekely — Lumi e identidade visual | **Origem da Lumi:** “A Lumi nasceu da experiência da Gracekely com seu ChatGPT, da inspiração em um personagem de Deadlock e do axolote. O Squad refinou a ideia e a identidade visual em conjunto.” Apresente a personagem como identidade do projeto, não como uma funcionalidade de IA do produto. |
| 02:00–03:00 | Juan — funcionalidades | **O que está confirmado:** “A aplicação permite cadastro/login, criação de links curtos e redirecionamento. A API registra viagens; o rate limit registra bloqueios. Vamos acompanhar um fluxo real e os sinais que ele produz.” |
| 03:00–03:45 | André — arquitetura e GitOps | **Diagrama/cluster:** “O navegador entra pelo Traefik; o frontend e a API rodam em Kubernetes, a API usa PostgreSQL, e ArgoCD sincroniza os manifests versionados. O HPA escala a API por CPU.” Mostre o diagrama do README; não afirme que o ambiente Azure está ativo. |
| 03:45–04:45 | Juan — negócio e funcionalidades | **Criar/mostrar link:** abra o app já autenticado e crie um link curto, ou mostre um link preparado. “Este código curto é o que vamos acessar repetidamente; cada acesso gera uma viagem observável.” Evite exibir dados pessoais da conta. |
| 04:45–05:15 | Eduardo — demonstração e observabilidade | **Começar a carga:** em um terminal Git Bash separado, rode `./scripts/demo-load.sh cliques --codes "$DEMO_CODES" --duration 180 --concurrency 8`. “A carga usa links já preparados e passa pelo Ingress público do app; não altera manifests.” `DEMO_CODES` deve conter códigos válidos separados por vírgula. |
| 05:15–07:30 | Eduardo — demonstração e observabilidade | **Grafana + HPA:** mostre no dashboard os cliques/CPU/réplicas e, se útil, a saída de `kubectl -n l2 get hpa l2-api -w`. “O overlay local permite de uma a três réplicas; só afirmamos que escalou se a leitura ao vivo mostrar a mudança.” |
| 07:30–10:15 | Eduardo — demonstração e observabilidade | **Trace:** abra no Tempo um trace recente da navegação. Mostre `l2-frontend → traefik → l2-api` e o span JDBC/SQL dentro do trace da API. “O span da query prova a operação no banco; o serviço Postgres não aparece como serviço instrumentado separado.” |
| 10:15–11:00 | André — arquitetura e GitOps | **Fechar o percurso:** retome o diagrama e conecte o request ao armazenamento e aos sinais. “A fonte de verdade é o Git; uma alteração de configuração não é feita com patch manual no cluster.” |
| 11:00–11:50 | Raul — CI/CD e segurança | **CI/CD:** mostre o fluxo documentado em [`docs/ci-cd.md`](docs/ci-cd.md): testes/checagens antes de publicar imagens imutáveis, PR de bump no GitOps e sincronização pelo ArgoCD. “A captura de Actions e do PR precisa ser de uma execução real; esta apresentação não presume um workflow rodando agora.” |
| 11:50–12:30 | Raul — CI/CD e segurança | **Segurança:** “O projeto valida manifests e segredos no CI; segredos de runtime não ficam em claro no Git. A porta Actuator não é publicada no Ingress.” Mostre apenas configuração/checagens públicas, nunca valores de Secrets. |
| 12:30–13:00 | Gracekely — Lumi e identidade visual | **Uso de IA e encerramento:** “O uso do Claude no desenvolvimento está registrado em `docs/uso-do-claude.md`; as decisões e a validação dos resultados foram do Squad.” Reforce que a história/personagem da Lumi foi refinada coletivamente. |
| 13:00–15:00 | Todos; Juan modera | **Perguntas:** Juan recebe a pergunta e direciona: negócio/funcionalidades a Juan; visual/personagem a Gracekely; demo/traces a Eduardo; arquitetura/GitOps a André; CI/CD/segurança a Raul. Se não houver pergunta, encerre aos 15:00 sem alongar a demo. |

## Controles de tempo

- Em 03:00, encerre a introdução mesmo que a história esteja incompleta; faça a transição para
  o diagrama.
- Em 07:30, saia do dashboard. Não espere mais réplicas se o HPA ainda não mudou: explique o
  que a leitura atual mostra e siga para o trace.
- Em 10:15, encerre a navegação no Tempo. Em 11:00, Raul inicia a parte de CI/CD.
- Não execute a cena `ameaca` no bloco principal: as rajadas e a janela do rate limit podem
  consumir o tempo e misturar sinais. Use-a separadamente para a evidência do alerta.

## Plano alternativo se algo falhar

| Falha | Ação segura e fala |
| --- | --- |
| App/Ingress indisponível | Não tente corrigir o cluster durante o pitch. Mostre o diagrama e explique o fluxo previsto; use uma captura real e datada de `docs/evidencias/` somente se existir. Diga claramente que a demonstração ao vivo está indisponível. |
| Grafana ou HPA sem dados | Consulte `kubectl -n l2 get hpa l2-api` (somente leitura), descreva o valor atual e siga para o Tempo. Não diga “escalou” sem observar a mudança. |
| Trace ausente | Não selecione um trace de outro fluxo como se fosse o da demonstração. Explique a instrumentação e mostre uma captura real com legenda, se disponível; caso contrário, pule a prova visual. |
| ArgoCD/Actions não acessível | Use o diagrama e a documentação do fluxo; se houver evidência estática real e datada, identifique-a como captura anterior. Não simule estados verdes nem use este PR como evidência de um bump. |
| Carga excessiva ou demora | Interrompa o gerador com `Ctrl+C` e siga adiante. Não altere réplicas nem faça `kubectl scale`; o ArgoCD é a fonte de verdade. |

## Depois do pitch: alerta de ameaças (opcional)

Para demonstrar `L2PicoDeAmeacas` fora dos 15 minutos, confirme a infraestrutura e rode
`./scripts/demo-load.sh ameaca --duration 150`. Capture somente se o alerta aparecer como
`FIRING` no Prometheus/Grafana. Alertmanager não está instalado, portanto não prometa entrega de
notificação. Consulte [as instruções de evidências](docs/evidencias/README.md).
