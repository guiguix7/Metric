# Privacidade — Metric v1.0.0-beta.1

Este documento descreve como o Metric trata as informações do usuário. Ele é baseado no **comportamento real do aplicativo** nesta versão e **não** declara conformidade jurídica definitiva com a LGPD ou qualquer outra legislação de privacidade.

## O que o Metric é

O Metric é um **organizador financeiro pessoal**. Ele:

- Não é um banco, carteira digital, corretora ou plataforma de investimentos.
- Não movimenta dinheiro real.
- Não possui integração bancária, Open Finance nem conexão com serviços externos.
- Não requer cadastro, conta de usuário, e-mail ou número de telefone.

## Onde os dados ficam

Todas as informações inseridas pelo usuário (rendas, gastos, categorias, percentuais de divisão, saldos, recorrências, notas e configurações) são armazenadas **apenas no aparelho**, em um banco de dados SQLite local.

## O que o Metric não faz

- Não coleta dados pessoais automaticamente.
- Não envia informações para servidores remotos.
- Não possui telemetria, analytics nem rastreamento de uso.
- Não compartilha dados com terceiros.
- Não exibe publicidade.
- Não acessa contatos, localização, câmera, microfone nem arquivos de mídia do aparelho (além da escolha explícita do usuário ao exportar ou importar um arquivo de backup).

## Permissões

O aplicativo **não declara permissão de internet** no manifesto do Android. As únicas interações com arquivos ocorrem quando o usuário escolhe explicitamente exportar ou importar um backup, usando os seletores de arquivo nativos do sistema.

## Backup e exportação

O usuário pode exportar:

- **Backup completo** (formato JSON): contém todas as informações do aplicativo (configurações, caixinhas, regras, rendas, lançamentos, categorias, recorrências).
- **Relatório mensal** (formato CSV): contém lançamentos e totais do período selecionado.

Ambos os arquivos são **legíveis e não criptografados por padrão**. O usuário é avisado na interface de que o arquivo de backup contém dados financeiros legíveis e deve ser armazenado com cuidado. A responsabilidade pela custódia e exclusão desses arquivos é do usuário.

## Exclusão de dados

O usuário pode apagar todos os dados do aparelho a qualquer momento, por meio da opção nas configurações, com confirmação explícita. Essa ação é irreversível e remove todas as informações locais do aplicativo.

## Riscos de privacidade conhecidos

| Risco | Descrição | Mitigação |
|-------|-----------|-----------|
| Banco SQLite não criptografado | Dados armazenados localmente podem ser lidos se o aparelho for comprometido fisicamente | PIN protege o acesso ao app, mas não o arquivo do banco (risco aceito para beta; reavaliar para produção) |
| Backup JSON não criptografado | Arquivo exportado contém dados financeiros legíveis | Aviso explícito na interface; responsabilidade de custódia do usuário |
| Backup do Android | Desabilitado (`allowBackup="false"`) | Impede que o sistema faça backup automático dos dados sensíveis |

## LGPD e legislação

Este documento **não** constitui declaração de conformidade com a Lei Geral de Proteção de Dados (LGPD) ou qualquer outra legislação de proteção de dados. O desenvolvedor do Metric não possui responsabilidade como controlador ou operador de dados pessoais, pois não coleta, armazena nem processa dados fora do aparelho do usuário.

Se você pretende usar o Metric em contexto sujeito à LGPD, consulte um profissional jurídico qualificado.

## Contato

Para dúvidas sobre esta política de privacidade ou sobre o tratamento de dados no Metric, consulte o canal de suporte informado na seção "Sobre" do aplicativo.

## Atualizações

Este documento reflete a versão v1.0.0-beta.1 do Metric. Poderá ser revisado em versões futuras à medida que novas funcionalidades forem implementadas.
