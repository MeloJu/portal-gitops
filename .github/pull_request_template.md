## O que muda
<!-- Uma ou duas frases. O "porquê" importa mais que o "o quê". -->

## Como foi validado
<!-- Cole o que você rodou e o que viu. "Funciona" não conta; um comando e a saída contam. -->
- [ ] `kubectl kustomize apps/l2/overlays/<env>` renderiza
- [ ] Aplicado num cluster (k3d) e o comportamento foi verificado
- [ ] ArgoCD ficou `Synced` / `Healthy`

## Checklist
- [ ] Nenhum Secret em claro (`kind: Secret` só no overlay `ci`; no resto, SealedSecret)
- [ ] Imagens com tag fixa ou digest (nada de `latest`)
- [ ] Container não-root, `readOnlyRootFilesystem`, `drop: ["ALL"]`
- [ ] Paths novos do Ingress terminam em `/` (o Traefik trata `Prefix` como prefixo de texto)
- [ ] Atualizei `TASKS.md` e/ou `docs/uso-do-claude.md` quando a mudança é relevante
- [ ] Branch e commits seguem o gitflow (`feature/*`, `fix/*`, `chore/*`; Conventional Commits)
