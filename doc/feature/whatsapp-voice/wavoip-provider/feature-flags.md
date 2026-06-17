# Feature flags fork — Wavoip

Adicionar em `custom/config/features.yml` (overlay fork — não editar `config/features.yml` upstream sem `# FORK:`):

```yaml
- name: channel_wavoip
  display_name: Wavoip Voice Channel
  enabled: false
  premium: true
```

## Gates

| UI | Condição |
|----|----------|
| Tile `wavoip` ativo | `channel_voice` **e** (`channel_wavoip` ou piloto encerrado) |
| Durante piloto | `ChannelItem.vue`: `channel_voice && channel_wavoip` |
| GA | Remover gate `channel_wavoip` ou `enabled: true` no YAML |

## Habilitar conta piloto

```ruby
account.enable_features!('channel_voice', 'channel_wavoip')
```

Ver [operations-runbook.md](./operations-runbook.md) · [official-docs.md](./official-docs.md).
