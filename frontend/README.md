# BoardVan

Aplicativo Flutter para gestão de empresas de transporte escolar, turismo e fretamento.

## Iniciar o backend

1. Copie `backend/.env.example` para `backend/.env` e configure `DATABASE_URL` e um `JWT_SECRET` aleatório com pelo menos 32 caracteres.
2. Use Node.js 20.13 ou superior e execute `npm install` dentro de `backend`.
3. Aplique as migrations com `npm run migrate` e gere o Prisma Client com `npx prisma generate`.
4. Inicie a API com `npm run dev`.

Execute `npm test` para validar as regras de intervalo financeiro e os tipos/conteúdo de comprovantes.

O cadastro do proprietário e da empresa é feito pelo aplicativo. Para popular a base com dados de demonstração, defina `SEED_OWNER_PASSWORD` e execute `node prisma/seed.js` dentro de `backend`. Para uma conta de demonstração isolada, defina `SEED_DEMO_EMAIL` e `SEED_DEMO_PASSWORD` com valores próprios e temporários antes de executar `node prisma/seed_demo.js`. Não reutilize senhas reais ou credenciais compartilhadas em conversas.

## Iniciar o aplicativo

Execute `flutter pub get` e depois `flutter run` dentro de `frontend`. Para Android, a API local usa o endereço especial `10.0.2.2`; para web e desktop, usa `localhost`. Em aparelhos físicos, informe a URL acessível da API, por exemplo `flutter run --dart-define=API_BASE_URL=https://api.suaempresa.com`.

Para gerar versões de publicação, use `flutter build web --release --dart-define=API_BASE_URL=https://api.suaempresa.com` ou `flutter build appbundle --release --dart-define=API_BASE_URL=https://api.suaempresa.com`. O pacote iOS deve ser compilado e assinado em macOS. Antes de publicar nas lojas, substitua os ícones e imagens padrão do Flutter pela identidade visual final e valide os fluxos em dispositivos reais.

## Operação do motorista

O proprietário cadastra o motorista e, opcionalmente, atribui uma van titular. O sistema mostra um código de ativação de uso único, válido por 24 horas; o motorista informa o código na tela de entrada e cria a própria senha. Não compartilhe senhas entre proprietário e motorista. Antes de iniciar uma rota, o motorista registra a inspeção pré-viagem; um item reprovado bloqueia o início. O motorista inicia a rota pelo aplicativo; a localização é transmitida enquanto a rota estiver ativa. No Android, a rota usa um serviço de localização em primeiro plano com notificação persistente; no iOS, usa atualizações de localização em background e o indicador do sistema. O motorista precisa permitir acesso “Sempre/O tempo todo” para compartilhar posição com a tela bloqueada. O compartilhamento termina ao encerrar a rota; encerramento forçado do app, reinicialização do dispositivo e restrições de bateria ainda podem suspender atualizações. Teste em dispositivos físicos antes de publicar.

Na **Agenda de serviços**, o proprietário pode agendar turismo, transfer de aeroporto ou transporte para eventos, escolhendo veículo e motorista, origem/destino, horário e valor. Cada fretamento tem um manifesto de passageiros limitado à capacidade da van; o motorista escalado pode registrar embarque, desembarque e ausência apenas durante a viagem. Os custos lançados no detalhe do serviço são vinculados ao fretamento, permitindo acompanhar receita realizada, despesas e margem. Ao encerrar um fretamento, o valor combinado é lançado como receita da viagem e da van.

O painel financeiro permite filtrar por últimos 30 dias, mês, ano ou todo o período, além do tipo escolar, turismo ou eventos. O lucro por van é calculado pelos lançamentos financeiros associados àquele veículo; despesas gerais sem van aparecem separadas e não são distribuídas arbitrariamente entre os veículos. Mensalidades escolares e despesas de operação podem ser registradas em **Lançamentos financeiros** e vinculadas à van correspondente. Combustível, manutenção, pneus e seguro exigem a seleção da van para manter os custos por veículo confiáveis. O comprovante é opcional: imagens JPG/PNG de até 5 MB são armazenadas no banco e servidas somente após autenticação e autorização do proprietário da empresa. Os totais usam agregação do banco para o período inteiro; a lista visual mostra até os 200 lançamentos mais recentes.

As transferências emergenciais são vinculadas a uma única viagem. A van titular do aluno não é alterada; a atribuição temporária termina com o histórico daquela viagem. As ofertas são encaminhadas à van escolar disponível mais próxima com assento livre e localização recente. O responsável pode receber um código temporário de acompanhamento, mediante confirmação de consentimento, válido por 12 horas e revogável pelo proprietário. Enquanto a tela estiver aberta, ela consulta a posição a cada 30 segundos. O código não substitui autorização legal nem deve ser publicado; compartilhe-o apenas com o responsável autorizado.

O mapa usa OpenStreetMap. O histórico de posições é limitado às últimas 24 horas na tela de operações e os pontos são removidos do banco após 30 dias. Alertas de falta de sinal são gerados para uma rota ativa sem atualização GPS por mais de três minutos. Documentos registrados guardam nome, categoria e validade, mas não armazenam anexos. As rotas escolares podem ser configuradas por dia da semana. Endereços e pontos GPS representam paradas; a linha entre pontos é um histórico/sequência visual e não oferece navegação curva a curva, ETA ou desvio calculado.

## Segurança e produção

Use [backend/.env.production.example](../backend/.env.production.example) como checklist, mas forneça valores reais somente no painel de segredos do host. Defina um `JWT_SECRET` aleatório e exclusivo fora do código-fonte e configure `NODE_ENV=production` e `ALLOWED_ORIGINS` com uma lista separada por vírgulas contendo somente as origens HTTPS do frontend. A API recusa iniciar em produção sem essa lista; login e cadastro têm limite de tentativas por IP, em memória, então uma implantação com várias réplicas deve configurar armazenamento compartilhado para o limitador. Se a API estiver atrás de um proxy, configure `TRUST_PROXY_HOPS` com o número exato de saltos confiáveis. O endpoint `/health/ready` verifica também a conexão com PostgreSQL. Ao gerar uma versão Flutter release, passe `--dart-define=API_BASE_URL=https://api.suaempresa.com`; em runtime, o app release recusa fazer chamadas se a URL estiver ausente ou não usar HTTPS. Execute migrations com `npm run migrate`, gere o Prisma Client e configure backup criptografado e teste de restauração do PostgreSQL (incluindo os comprovantes armazenados como `bytea`). Nunca exponha a API sem TLS nem mantenha credenciais de demonstração na base publicada.

Antes de liberar publicamente, ainda é necessário configurar e testar no provedor: TLS e domínio, banco gerenciado com backups/restore, monitoramento e alertas, rotação de segredos, política de privacidade/LGPD e testes do rastreamento em Android/iOS reais. A Apple exige justificar a localização contínua em segundo plano; a aprovação da loja e a confiabilidade após encerramento forçado não podem ser garantidas pelo código. Os códigos públicos são bearer credentials: sua posse permite consultar o escopo associado até expiração ou revogação.
