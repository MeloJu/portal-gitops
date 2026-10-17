# Plataforma do cluster local

Peças que a aplicação assume que existem no cluster. Todas entram pelo app-of-apps
(`bootstrap/apps/local`) e são sincronizadas pelo ArgoCD, no projeto `platform`.

| Peça | Origem | Versão | Papel |
| --- | --- | --- | --- |
| Sealed Secrets | `platform/sealed-secrets` | chart 2.20.0 | segredos no Git ([detalhes](sealed-secrets.md)) |
| cert-manager | `platform/cert-manager` | chart v1.21.2 | certificados TLS |
| Traefik | embutido no K3s + `platform/traefik/config` | v3.6.13 | Ingress; só ajustamos a configuração |
| metrics-server | embutido no K3s | — | métricas de CPU para o HPA |

> **Escopo:** só o cluster local. O ambiente Oracle (domínio público, Let's Encrypt, SealedSecret
> de produção) foi adiado e não está implementado.

## cert-manager e TLS

O chart instala os CRDs (`crds.keep: true`: apagar o chart não apaga os Certificates). O `ClusterIssuer`
`selfsigned` fica numa Application separada (`cert-manager-issuers`), porque um ClusterIssuer só é
válido depois que os CRDs existem.

O Ingress do overlay `local` pede o certificado com a annotation
`cert-manager.io/cluster-issuer: selfsigned` e `tls.secretName: l2-tls`; o cert-manager cria o
`Certificate` e o Secret sozinho. **O navegador avisa que o certificado não é confiável: é esperado**,
porque o emissor é self-signed. O HTTP continua respondendo, sem redirect, para a demo não depender do aviso.

Verificado no cluster:

| Verificação | Resultado |
| --- | --- |
| `ClusterIssuer selfsigned` | `Ready=True` |
| `Certificate l2-tls` | `Ready=True`, Secret `kubernetes.io/tls` criado |
| Certificado servido em `https://l2.localhost` | SAN `DNS:l2.localhost`, validade 90 dias (não é o certificado padrão do Traefik) |
| `GET https://l2.localhost/` e `GET http://l2.localhost/` | 200 nos dois |

## Traefik: IP real do cliente

A API usa o IP do visitante no **rate limit** (60 req/min por IP) e no país da Viagem (GeoIP), lendo
`X-Forwarded-For`. Por padrão o Traefik não confia em ninguém e **substitui** esse cabeçalho pelo IP de
quem conectou: todo visitante pareceria ter o IP do proxy e todos dividiriam o mesmo balde.

`platform/traefik/config/helmchartconfig.yaml` (um `HelmChartConfig`, objeto do helm-controller do
K3s) faz duas coisas:

- `externalTrafficPolicy: Local`: preserva o IP de origem, sem NAT do kube-proxy;
- `forwardedHeaders.trustedIPs` só com redes **privadas** (`127.0.0.1/32`, `10/8`, `172.16/12`,
  `192.168/16`): o Traefik confia no `X-Forwarded-For` de um balanceador interno, mas um cliente da
  internet não consegue forjar o IP que a API enxerga.

Verificado (rajada de 120 logins numa só conexão, API com 1 réplica):

| Cenário | Resultado |
| --- | --- |
| IP `203.0.113.10` (via `X-Forwarded-For`) | ~64 respostas `401`, depois **56 × `429 RATE_LIMIT`** |
| IP `203.0.113.20`, logo em seguida | `401`, **não** barrado: balde próprio |

Ou seja, a API distingue clientes pelo cabeçalho. **Limite do teste:** foi feito só com a configuração
nova (sem um controle "antes"), e o salto confiável aqui é a rede do Docker; num ambiente real com um
balanceador na frente, os IPs do balanceador precisam estar em `trustedIPs`.

> Cuidado ao testar o rate limit: o balde recarrega **1 token por segundo**. Uma sequência de
> `curl` separados (cada um leva mais de 1 s) nunca o esvazia. Use uma rajada numa única conexão.

## metrics-server

O K3s já instala. O HPA da API lê a CPU real (`cpu: 15%/50%`). Sem ele o alvo ficaria em `<unknown>`.
