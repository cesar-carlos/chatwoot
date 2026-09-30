# PWA — pendências e melhorias

Estado em 30/set/2026. Itens implementados no branch ainda precisam de publicação e validação no aparelho.

## Implementado no branch

- Manifesto white-label em `/manifest.webmanifest` e alias `/manifest.json`, com link presente mesmo quando `DISPLAY_MANIFEST=false`.
- Ícones PNG declarados em 192×192 e 512×512; URLs configuráveis em Custom Branding.
- Identidade da instalação no manifesto, com `id` estável e `display: standalone`.
- Fluxo de inscrição e remoção de Web Push por dispositivo, payload com corpo e ícone e clique que navega à conversa.
- Explicação de Push, Pop-up e instalação no iOS nas preferências.

## Pendente antes de considerar o incidente resolvido

| Prioridade | Item | Critério |
|------------|------|----------|
| P0 | Publicar o branch da PWA | `/manifest.webmanifest` retorna 200 e o HTML o referencia com `DISPLAY_MANIFEST=false` |
| P0 | Configurar os dois ícones Se7e | Manifesto aponta para PNGs 192×192 e 512×512 acessíveis na mesma origem |
| P0 | Eliminar manifesto estático e cache antigo | `/manifest.json` entrega o mesmo conteúdo dinâmico de `/manifest.webmanifest` |
| P0 | Validar instalação Android | Chrome oferece **Instalar** e o app abre em standalone |
| P0 | Validar instalação iOS | Atalho criado pelo Safari abre em standalone; Push é testado com o app fechado |
| P1 | Verificar entrega de Push real | Mensagem elegível aparece com o app fechado e o clique abre a conversa correta |

## Melhorias opcionais

| Item | Motivo |
|------|--------|
| Metadados Apple adicionais | Avaliar somente se um iOS suportado abrir com barras do Safari após instalação correta |
| Experiência offline | Requer projeto próprio para autenticação, APIs, cache e atualização; não é requisito para esta correção |
| Botão interno de instalação | O menu do Chrome já oferece instalação; avaliar depois de observar a experiência real |

Não adicionar handler `fetch` vazio nem registro antecipado do worker apenas para tentar satisfazer o critério do Chrome. Os bloqueios confirmados foram o manifesto ausente no HTML e a falta do ícone 512×512 no manifesto publicado.
