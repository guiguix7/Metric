# Segurança — Metric v1.0.0-beta.1

Este documento descreve as medidas de segurança implementadas no Metric, seus limites e os riscos conhecidos. Ele **não** declara conformidade com nenhuma norma, legislação ou certificação de segurança.

## Princípio de funcionamento

O Metric é um aplicativo de organização financeira pessoal que:

- Funciona **100% offline**, sem conta e sem servidor.
- Não possui integração bancária, Open Finance, corretora nem qualquer integração com serviços externos.
- Não requer permissão de internet.
- Armazena todos os dados **apenas no aparelho** do usuário, em um banco de dados SQLite local.

## Controle de acesso (PIN)

- O usuário pode criar um PIN de acesso (mínimo de 4 dígitos numéricos).
- O PIN **nunca é guardado em texto claro**. Apenas um derivado (hash SHA-256 com sal criptograficamente seguro) é persistido nas configurações locais do aplicativo.
- O PIN é exigido sempre que o aplicativo for aberto, conforme opção do usuário.
- Após **5 falhas consecutivas**, há atraso crescente (1 minuto, depois dobrando) antes de novas tentativas.
- O bloqueio por atraso persiste entre reinicializações do aplicativo.
- O PIN pode ser alterado a qualquer momento nas configurações.

## Biometria

- A biometria (impressão digital / reconhecimento facial) é **opcional** e depende do suporte do aparelho.
- Quando disponível, pode ser usada como alternativa para desbloquear o aplicativo.
- O PIN permanece como **alternativa obrigatória**: o aplicativo nunca fica inacessível se a biometria falhar ou não estiver cadastrada.

## Bloqueio automático

- O aplicativo pode ser configurado para trancar automaticamente após um tempo configurável em segundo plano (padrão: 5 minutos).
- Ao retornar do segundo plano além desse limite, o PIN é solicitado novamente.

## Proteção de tela

- A flag `FLAG_SECURE` está ativada na Activity principal do Android, impedindo capturas de tela e gravação de exibição nas telas do aplicativo (incluindo a lista de aplicativos recentes).

## Backup do sistema Android

- O backup automático do Android está **desabilitado** (`android:allowBackup="false"`).
- Um arquivo `backup_rules.xml` exclui explicitamente shared preferences, banco de dados e arquivos do backup do sistema, evitando que dados financeiros saiam do aparelho sem ação explícita do usuário.

## Armazenamento local

- O banco de dados SQLite **não é criptografado em repouso** nesta versão.
- O PIN protege o acesso ao aplicativo, **não** o arquivo do banco. Se o aparelho for comprometido fisicamente (root, acesso ao armazenamento), os dados podem ser lidos diretamente do banco.
- Isso é um **risco residual conhecido** e será reavaliado antes de qualquer uso com dados financeiros reais de produção.

## Backups e exportação

- O usuário pode exportar um backup em formato JSON e um relatório em CSV.
- Esses arquivos **não são criptografados** por padrão e contêm dados financeiros legíveis.
- O usuário é avisado na interface de que o arquivo contém dados financeiros legíveis e deve ser guardado com cuidado.
- Não é recomendado importar backups de origens não confiáveis.

## Nenhuma credencial no código

- Não há senhas, tokens, chaves privadas ou credenciais reais incluídas no código, nos testes ou no repositório.
- O aplicativo não faz autenticação falsa nem simula conexões com servidores.

## Limites declarados

O Metric **não** oferece:

- Criptografia de banco de dados em repouso (versão beta).
- Autenticação multifator.
- Detecção de intrusão.
- Proteção contra análise forense do dispositivo.
- Sincronização em nuvem.

Essas funcionalidades, se necessárias, devem ser avaliadas para versões futuras (documentadas em `PENDENCIAS_V2.md`).

## Veredito de segurança da Etapa 1

O controle de acesso (PIN com hash+s sal, atraso crescente, fallback de biometria, bloqueio automático, FLAG_SECURE e desabilitação do backup do Android) foi implementado. O banco não criptografado e o backup não criptografado são riscos conhecidos e documentados, aceitos formalmente para o lançamento beta.
