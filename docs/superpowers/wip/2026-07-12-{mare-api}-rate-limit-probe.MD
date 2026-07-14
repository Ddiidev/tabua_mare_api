# API - Probe de rate-limit por IP

Gerado em: 2026-07-12
Sessao/contexto: mare-api-rate-limit-probe
Tipo de registro: validação operacional

## Pedido Do Usuario

Executar 5 requisições `curl` simultâneas do IP atual para verificar bloqueio por IP e confirmar liberação na janela seguinte. Criar também um script reproduzível.

## Validacao Manual

Alvo configurado: `http://localhost:3330/api/v2/states` (`URL_ENV` local).

Burst inicial com 5 `curl` simultâneos:

- 4 respostas `200 OK`.
- 1 resposta `429 Too Many Requests`.
- Resposta bloqueada informou `Retry-After: 60` e `Limite por minuto excedido`.

Após a janela de 60 segundos, nova requisição retornou `200 OK` com JSON dos 17 estados.

## Script

- Criado [rate_limit_probe.py](../../../scripts/rate_limit_probe.py).
- Usa somente biblioteca padrão Python.
- Executa burst concorrente configurável (`--requests`).
- Exibe status, tempo, `Retry-After` e resumo JSON.
- `--wait-after` aguarda a janela indicada e faz uma nova requisição.

Exemplo:

```bash
python3 scripts/rate_limit_probe.py --url http://localhost:3330/api/v2/states --requests 5 --wait-after
```

## Escopo

- Nenhuma alteração em API/backend; somente ferramenta de validação local.
- Nenhum teste unitário de interface criado.
