# Metric — execução baseada nos anexos (29/10/2026)

## Status atual

O app Flutter/Dart foi construído sobre o projeto padrão existente (`lib/` continha só o contador de demo). Implementação concluída para o ciclo mínimo do MVP (registrar renda → dividir entre as cinco caixinhas → registrar gasto → saber quanto resta em cada caixinha), com onboarding, bloqueio PIN, recorrências, relatório mensal, detalhe da caixinha, backup/restauração e testes automatizados.

Foi gerado `build/app/outputs/flutter-apk/app-debug.apk` (`flutter build apk --debug`).
O ambiente de desenvolvimento tem Flutter 3.47.7 / Dart 3.13.5 e Android SDK 36; não há emulador Android nem dispositivo físico conectado, então a instalação e a execução no dispositivo ainda não foram verificadas (limitação registrada abaixo).

## Matriz consolidada de requisitos e aceitação

| ID | Origem | Requisito | Prioridade | Critério de aceite | Situação | Teste |
| --- | --- | --- | --- | --- | --- | --- |
| PROD-001 | R1 §5, R2 §4, R3 §4.2 | 5 caixinhas permanentes | MVP | os cinco tipos aparecem sempre | Implementado | widget (passou) |
| PROD-002 | R1 §8.2, R2 §2 | Centavos e divisão ≤100% | MVP | R$1.000,01 fecha em R$1.000,01 | Implementado | unitário (passou) |
| PROD-003 | R1 §8.4, R2 §4 | Percentuais versionados | MVP | mudança só afeta rendas novas | Implementado | widget (passou) |
| PROD-004 | R1 §8.5-6, R2 §2.3-4 | Saldos derivados, negativos e cumulativos | MVP | +1500 −1650 +1500 = 1350 | Implementado | unitário (passou) |
| PROD-005 | R1 §8.8, R2 §2.6 | Transferências atômicas | MVP | pares somam zero | Implementado | unitário + widget (passou) |
| PROD-006 | R1 §5.6, R3 §4.4 | Gasto por categoria e classificação | MVP | categoria sugere Essenciais/Livre | Implementado | widget (passou) |
| PROD-007 | R1 §7, R3 §6.1 | Onboarding completo | MVP | fluxo guiado até a primeira renda | Implementado | widget parcial + revisão de código |
| PROD-008 | R1 §7 | Recorrências e assinaturas | MVP | criar, pausar, encerrar, lançar quando vence | Implementado | revisão de código |
| PROD-009 | R1 §7, R3 §6.5, 6.10 | Relatório mensal, estornos | MVP | totais derivados; transferência não é gasto; estorno na UI | Implementado | unitário da store + widget estorno (passou) |
| PROD-010 | R1 §7 | Metas detalhadas, patrimônio e cartões | Posterior | validar após MVP | Fora do escopo do MVP | — |
| DEV-001 | R2 §3 | Domínio independente de UI | Obrigatório | cálculos isolados em finance.dart | Implementado | unitário (passou) |
| DEV-002 | R2 §2, §4 | SQLite offline, operações atômicas | Obrigatório | SQLite offline e transações | Implementado | revisão de código (sem device) |
| DEV-003 | R2 §6 | Backup com versão, prévia, restauração atômica | MVP | checagem íntegra, restauração com conf. de saldos | Implementado | unitário do fake + revisão de código |
| DEV-004 | R2 §5 | PIN, bloqueio e tela de bloqueio | MVP crítico | PIN bloqueia o acesso; bloqueio automático | Implementado | revisão de código (sem device) |
| UX-001 | R3 §5–6 | Navegação e saldo Livre em destaque | MVP | Início, Lançamentos, Registrar, Caixinhas, Mais | Implementado | widget (passou) |
| UX-002 | R3 §3.5 | Tema claro/escuro/sistema | MVP | configuração persistida | Implementado | revisão de código |
| UX-003 | R3 §6.6, §7 | Detalhe da caixinha, gráficos, a11y | MVP | extrato individual + gráfico de evolução | Implementado | widget + revisão de código |
| UX-004 | R3 §6.1 | Botão de navegação não duplicado | MVP | um único "Continuar" por tela do onboarding | Implementado | visual (imagens do app) |

Notas: "unitário" = `flutter test` (domínio + fake store), "widget" = `flutter test` com `WidgetTester` sobre `FinanceHome`. Nenhum teste rodou em dispositivo Android/iOS (ambiente sem emulador).

## Estrutura e decisões

- `lib/finance.dart`: domínio puro (distribuição com resto de centavos para a caixinha de maior percentual, empate → Essenciais; parsing/formatação pt-BR; saldos derivados). Não depende de Flutter, banco nem arquivos.
- `lib/store.dart` → `abstract class FinanceStore` + `SqfliteFinanceStore`: contrato de persistência e implementação SQLite (sqflite), esquema versão 2 com migração v1→v2. Todas as quantias em centavos inteiros; datas civis ISO no fuso do aparelho; operações críticas em transação.
- `lib/theme.dart`: sistema visual (cores semânticas e cores das caixinhas de R3 §3.2; ícones nunca são o único identificador).
- `lib/main.dart`: `MetricApp` com gate de onboarding → PIN de desbloqueio → `FinanceHome`; `WidgetsBindingObserver` para trancar ao voltar do segundo plano após limite configurável; Material 3, semente #0F766E, fundo #F7F8F7, pt-BR.
- `lib/onboarding.dart`: boas-vindas/privacidade, renda líquida, divisão (presets 50/30/10/5/5 e 60/20/10/5/5 + personalizada com prévia em reais), saldos iniciais opcionais, criação de PIN; ao concluir registra a primeira renda com a regra vigente e libera o Início.
- `lib/pin_screen.dart`: criação e validação de PIN; PIN guardado apenas como hash SHA-256 com sal (crypto); atraso crescente após falhas (5 → 1 min, depois dobra); biometria opcional (local_auth) com PIN como alternativa obrigatória.
- `lib/caixa_detalhe.dart`: saldo, extrato próprio, gráfico de evolução mensal, transferência e ajuste com justificativa.
- `lib/recorrencias_screen.dart`: lista, criação, pausa/encerramento com confirmação, total mensal equivalente (anual ÷ 12), geração de lançamentos vencidos no abrir da tela.
- `lib/relatorio_mensal.dart`: seletor de mês, receitas/gastos/saldo, gasto por categoria, essencial × não essencial, evolução do saldo, exportação CSV.
- `lib/grafico_linha.dart`: componente de linha reutilizável sem animações nem eixo truncado (R3 §7).
- `test/finance_test.dart`, `test/fake_store.dart`, `test/widget_test.dart`: domínio, fake de persistência e fluxos de interface.

**Escolhas provisórias:** SQLite/sqflite (relacional, somas/agrupamentos centrais do app), file_picker + path_provider + share_plus para backup, crypto para hash do PIN, local_auth para biometria. Banco NÃO criptografado em repouso: o custo/complexidade de sqlcipher foi avaliado e adiado; o PIN protege o acesso ao app (não o arquivo do banco). Isso deve ser reavaliado antes de lidar com dados reais de produção.

**Atenção sobre backups:** a exportação produz JSON legível (e CSV para relatórios). Não importar arquivos não confiáveis. Trate backup/export como informação confidencial.

## Testes e verificação

- `flutter analyze`: sem erros nem warnings (apenas infos de lint de legado).
- `flutter test`: 19 testes passando (13 de domínio, 6 de interface com fake store).
- `flutter build apk --debug`: APK gerado com sucesso.
- Não foi possível instalar/executar em dispositivo nem rodar testes de persistência contra SQLite nativo (Windows sem sqlite3.dll; sem emulador Android). Testes de persistência usam `FakeFinanceStore` em memória; a implementação SQLite foi revisa por código e compila no build do APK.

## Limitações conhecidas (registro honesto)

1. Filtros na tela Lançamentos e estorno via UI da lista de lançamentos ainda não existem (estorno existe na camada de dados).
2. Tela de bloqueio e PIN não foram verificadas em dispositivo real; biometria depende do hardware.
3. Exportação/importação de backup não testadas com arquivo real fora do teste unitário do fake.
4. Backup não criptografado; mescla de backup e migração de versões antigas não implementadas.
5. Nenhuma integração bancária, Open Finance, corretora ou recomendação de investimento (fora do escopo do MVP, R1 §7).

## Continuação recomendada

1. Configurar emulador Android/dispositivo; instalar o APK; verificar execução, PIN e backup em dispositivo.
2. Completar UI de estornos e filtros em Lançamentos; tela de detalhe com gráfico já existe.
3. Testes de persistência real contra SQLite (requer dispositivo/emulador com sqlite3).
4. Revisar contraste (WCAG AA 4,5:1), licença da fonte, nome do app e requisitos LGPD antes de publicar.
5. Somente então considerar o MVP pronto para uso com dados reais.

## Registros de decisões e desvios

- `store.dart` refatorado para `abstract class FinanceStore` + `SqfliteFinanceStore` para permitir `FakeFinanceStore` nos testes (ambiente sem sqlite3.dll no Windows de desenvolvimento).
- Comparações de data usam `String.compareTo` (o Dart deste ambiente não define operadores de ordem em `String`).
- `TextInputType.decimal` não existe neste Flutter; usa-se `TextInputType.numberWithOptions(decimal: true)`.
- Documento auxiliar de educação financeira lido como contexto; seus métodos de investimento NÃO foram implementados como recomendações automáticas (excedem o escopo aprovado, R1 §6 e §7).