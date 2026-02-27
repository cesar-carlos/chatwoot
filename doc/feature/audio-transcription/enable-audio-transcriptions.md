# Como habilitar transcrição de áudio (estado atual)

## Regra de habilitação

A transcrição manual de áudio é habilitada por **usuário**, com base no token Groq salvo no perfil.

- Requisito: `users.groq_token` preenchido para o usuário autenticado.
- Não depende de `account.audio_transcriptions`.
- Não depende de Captain.

## Configuração

1. Acesse **Settings → Profile**.
2. Preencha **Token da API Groq**.
3. Clique em **Salvar Token**.
4. Recarregue a página e valide se o campo permanece mascarado (`••••`), indicando valor carregado.

## Teste rápido

1. Abra uma conversa com anexo de áudio.
2. Clique no botão de transcrição (ícone de ouvido).
3. Confirme que o endpoint `POST /api/v1/accounts/:id/transcriptions` retorna sucesso.
4. Confirme que o texto transcrito aparece no card de áudio.

## Troubleshooting

Se ocorrer erro:
- Valide no banco se o usuário tem `groq_token` preenchido.
- Faça logout/login para renovar estado do usuário no frontend.
- Verifique logs do backend para status da chamada ao provedor.
