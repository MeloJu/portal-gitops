# Dados de demo (seed)

Para a demo começar com usuário, links e gráficos preenchidos, sem cadastro manual, rode o modo
`seed` do [`scripts/demo-load.sh`](../scripts/demo-load.sh) depois que o cluster estiver no ar:

```bash
DEMO_EMAIL=demo@example.com DEMO_PASSWORD='<senha>' ./scripts/demo-load.sh seed
```

O `seed` faz o `setup` e uma rodada curta de cliques pelo Ingress público:

1. Cadastra o usuário (`POST /api/auth/register`). Se o e-mail já existe (HTTP 409 `EMAIL_TAKEN`),
   entra com login e segue.
2. Garante `--links` links ativos (padrão: 5): reaproveita os que o usuário já tem e cria só os que
   faltam. Rodar de novo não duplica links.
3. Dispara `GET /r/{code}` por 30 s com 2 workers, o bastante para o painel
   **"Cliques (viagens) por segundo"** do Grafana ter dados, sem acionar o HPA.

Com `DEMO_EMAIL`/`DEMO_PASSWORD` definidos o seed é reproduzível e pode rodar quantas vezes for
preciso; a senha informada não é impressa. Sem eles, cada execução cria um usuário novo com senha
aleatória e mostra as credenciais no final (mantenha essa saída fora da projeção).

Ajustes comuns:

```bash
./scripts/demo-load.sh seed --duration 60 --links 8     # rodada mais longa, mais links
BASE_URL=https://<fqdn> ./scripts/demo-load.sh seed     # ambiente Azure
./scripts/demo-load.sh --help                           # todas as opções e modos
```

A senha não fica no repositório: use um valor só seu no lugar de `<senha>` (o gitleaks do CI
acusa senhas literais).
