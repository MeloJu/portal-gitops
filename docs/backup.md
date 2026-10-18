# Backup e restauração do Postgres

O banco roda num único pod com um volume `ReadWriteOnce`. O volume sobrevive à morte do pod, mas não a um
`kubectl delete pvc`, a um bug de migração ou a um `DELETE` errado. Por isso há backup, e o backup só conta
se **restaurar**.

## Como funciona

`apps/l2/base/postgres-backup.yaml`: um `CronJob` que roda todo dia às 3h (America/Sao_Paulo).

| Decisão | Por quê |
| --- | --- |
| `pg_dump --format=custom` | compactado e restaurável tabela a tabela com `pg_restore` |
| Conecta como **`l2_app`** | é a dona do banco e das tabelas: dump completo sem usar o superuser |
| Valida com `pg_restore --list` antes de aceitar | um dump corrompido falha aqui, não no dia em que você precisar dele |
| Escreve em `.tmp` e só renomeia no fim | um dump pela metade nunca aparece como "o último" |
| Mantém os 7 mais recentes | uma semana de pontos de restauração num PVC de 2 Gi |
| `concurrencyPolicy: Forbid` | dois backups não disputam o mesmo volume |
| Mesma imagem do banco (por digest) | `pg_dump` e servidor na mesma major (18) |
| NetworkPolicy própria | o pod do backup só sai para o Postgres; ninguém entra |

O smoke e2e (`tests/smoke.sh`, passo 6) roda um backup de verdade no cluster efêmero a cada PR.

## Rodar um backup agora

Antes de uma mudança arriscada (uma migração nova, por exemplo):

```bash
kubectl -n l2 create job --from=cronjob/postgres-backup backup-manual-$(date +%s)
kubectl -n l2 logs -f job/backup-manual-<id>     # "backup ok: /backup/l2-<data>.dump (236K)"
```

## Restaurar

Sempre num **banco novo** primeiro, para conferir antes de mexer no de produção.

```bash
# 1. banco vazio, dono l2_app
kubectl -n l2 exec deploy/postgres -c postgres -- \
  psql -U postgres -d postgres -c "CREATE DATABASE l2_restore OWNER l2_app"

# 2. um pod com o label postgres-backup (é o que a NetworkPolicy libera até o banco), montando o PVC
#    de backup, roda:
#      pg_restore -h postgres -U l2_app -d l2_restore --no-owner --exit-on-error /backup/l2-<data>.dump

# 3. conferir e só então decidir trocar (DROP/RENAME DATABASE, com a API parada)
```

## O que foi comprovado (cluster k3d)

Backup disparado na hora e restaurado num banco novo (`l2_restore_drill`), tabela por tabela:

| Tabela | Original | Restaurado |
| --- | --- | --- |
| `links` | 6 | 6 |
| `travels` | 18 453 | 18 453 |
| `users` | 12 | 12 |
| `blocked_events` | 7 | 7 |
| `flyway_schema_history` | 2 | 2 |

## Pegadinha encontrada

O primeiro backup falhou com `Connection refused` mesmo com a NetworkPolicy certa. Um pod **novo** sob
NetworkPolicy leva alguns segundos até o kube-router liberar o IP dele, e o `pg_dump` conectava na hora.
O `backoffLimit` não ajudava: cada nova tentativa do Job é um pod novo, na mesma corrida. O script espera o
banco aceitar a conexão (`pg_isready`, até 60 s) antes de começar. Vale para qualquer Job que fale com outro
serviço logo ao nascer.

## Limites

- O backup fica **no mesmo cluster** (um PVC). Protege contra erro humano e bug, não contra perder o nó ou o
  cluster. O próximo passo seria copiar o dump para fora (bucket de objetos), junto com o ambiente de produção.
