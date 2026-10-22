# Email de boas-vindas

O callback Google envia boas-vindas somente quando cria uma conta. A criação de usuário e identidade é transacional; callbacks da mesma identidade são serializados no PostgreSQL, inclusive entre A/B. Logins posteriores não reenviam a mensagem.

O envio roda em uma thread após emitir o cookie de sessão. Falha no Resend não altera o login. Sem chave configurada, o envio fica desativado. Não existe fila persistente ou retentativa automática: encerramento do processo ou falha de envio pode perder a mensagem; habilitar a chave depois não envia emails retroativos.

## Configuração

Configure em **ambas as aplicações A/B no Coolify**, ou no `.env` local:

```dotenv
RESEND_API_KEY=re_...
RESEND_FROM=Tábua de Marés API <contato@tabuamare.api.br>
RESEND_REPLY_TO=contato@tabuamare.api.br
URL_ENV=https://tabuamare.api.br
```

`EMAIL_RESEND` continua aceito como alias legado da chave. `RESEND_API_KEY` tem precedência. Use chave com permissão de envio, restrita ao domínio quando possível. Não versionar valores reais.

1. Em [Resend → Domains](https://resend.com/domains), adicione `tabuamare.api.br`.
2. Adicione no DNS os registros exatos exibidos pelo Resend para autenticar o envio e aguarde a verificação. Preserve os registros de recebimento existentes.
3. Crie a API key e configure as variáveis nas duas aplicações.
4. Publique a versão e reinicie/recrie as instâncias para aplicar as variáveis.

Depois de verificar o domínio, **não é necessário cadastrar `contato@` separadamente como remetente**. Para receber respostas, configure uma caixa postal ou encaminhamento para esse endereço no provedor de email. A verificação de envio por si só não cria uma caixa postal. Se o recebimento for em outro endereço, ajuste `RESEND_REPLY_TO`.

Referências: [remetentes](https://resend.com/docs/knowledge-base/how-do-I-create-an-email-address-or-sender-in-resend), [domínios](https://resend.com/docs/dashboard/domains/introduction).

## Conteúdo e imagem

- Template: `shareds/email/resend/welcome.html`; versão texto e preparação do payload: `welcome.v` no mesmo módulo.
- Imagem: `pages/assets/images/welcome-banner.jpg`, com identidade visual do footer, nome e domínio.
- Imagem e template são incorporados no binário durante a compilação. A imagem segue como anexo Base64 com `content_id=welcome-banner`; o HTML referencia `cid:welcome-banner`. Não depende de uma URL de imagem publicada. Recompilar ao alterar o template ou a imagem.
- Links usam a origem definida em `URL_ENV`, sem caminho, query ou fragmento. A mensagem mantém conteúdo e ações em texto mesmo com imagens bloqueadas.
- HTML usa tabelas e estilos inline; validar no cliente de email usado antes de aceitar a entrega visual final.

Referência: [imagens inline](https://resend.com/docs/dashboard/emails/embed-inline-images).

## Verificação e limites

```powershell
v test tests/resend_email_test.v
# Somente com banco de teste:
$env:RUN_POSTGRES_TEST='1'
$env:POSTGRESQL_CONN_STR='postgresql://.../base_de_teste'
v test tests/auth_registration_test.v
```

Os testes HTTP usam apenas mock local. Cobrem Bearer, payload, CID, idempotência, sucesso, erro HTTP, resposta inválida, timeout e bloqueio de redirects. O teste PostgreSQL cobre concorrência, primeiro cadastro, login posterior e rollback.

O envio usa `Idempotency-Key: welcome-user/<user_id>`. O Resend mantém essas chaves por 24 horas; o controle permanente de não reenviar em logins é `is_new_user`, não essa janela. A aplicação não executa retries automáticos.

O log `[email] boas-vindas aceito ... resend_id=...` confirma somente aceite na API. Erros registram status HTTP ou categoria de falha sem payload, chave ou email do destinatário. Para confirmar entrega, consulte o evento correspondente no Resend e a caixa de entrada de um destinatário de teste autorizado. Não confundir preview local, aceite da API e recebimento real.

Referência: [idempotência](https://resend.com/docs/dashboard/emails/idempotency-keys).
