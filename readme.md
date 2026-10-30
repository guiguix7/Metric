# Metric — aplicativo financeiro pessoal offline

Organizador financeiro simples e preciso: divide cada renda em cinco caixinhas (Essenciais, Livre, Reserva de emergência, Investido, Metas) por percentuais definidos pelo usuário, registra gastos por categoria, distingue essencial de não essencial, e mostra quanto você realmente pode gastar — tudo no próprio aparelho, sem internet e sem conta.

> **Status:** MVP concluído e funcional. Build de debug gerado com sucesso (`flutter build apk --debug`). 20 testes automatizados passando.
> **Stack:** Flutter 3.47.7 + Dart 3.13.5, Android (foco) com compatibilidade iOS, banco local SQLite (sqflite).
> **Base:** três relatórios oficiais do projeto (Produto, Desenvolvimento, Design e UX).

---

## O que o aplicativo faz (MVP)

| Fluxo | Como funciona |
|-------|---------------|
| **Onboarding** | Boas-vindas com nota de privacidade, renda mensal líquida, divisão da renda (presets 50/30/10/5/5 ou 60/20/10/5/5, ou personalizada), saldos iniciais opcionais, criação de PIN. Ao concluir, registra a primeira renda com a regra de divisão vigente. |
| **Início** | Saldo da caixinha Livre em destaque ("quanto você pode gastar"), cinco caixinhas com saldo, gasto Essenciais × aporte, cobertura da reserva e alertas. |
| **Registrar renda** | Valor, data e fonte; pré-visualização da divisão por caixinha antes de confirmar (R$ 1.000,01 fecha exatamente em R$ 1.000,01 com resto de centavos para a caixinha de maior percentual). |
| **Registrar gasto** | Valor, categoria (com classificação essencial/não essencial), forma de pagamento, caixinha sugerida automaticamente; novo saldo exibido após salvar; aviso neutro se a caixinha ficar negativa. |
| **Transferir entre caixinhas** | Dois movimentos atômicos que somam zero (não é receita nem despesa). |
| **Lançamentos / Extrato** | Lista agrupada com filtros por caixinha; estorno de gasto com confirmação (devolve o valor à caixinha de origem, vinculado ao original). |
| **Caixinhas / Detalhe** | Saldo, gráfico de evolução mensal, extrato próprio, transferência para outra caixinha e ajuste de saldo com justificativa obrigatória. |
| **Recorrências / Assinaturas** | Criar, pausar e encerrar; lançamento gerado automaticamente quando a data de cobrança chega (anual entra na visão mensal como valor ÷ 12). |
| **Relatório mensal** | Seletor de mês; receitas, gastos, saldo do período; gasto por categoria; essencial × não essencial; evolução do saldo; exportação CSV. |
| **Mais** | Distribuição da renda, categorias, exportação/importação de backup (JSON), tema claro/escuro/sistema, bloqueio automático, privacidade. |
| **Segurança** | Bloqueio por PIN (hash com sal, nunca em texto claro; atraso crescente após falhas), biometria opcional como alternativa, PIN sempre como fallback; bloqueio automático ao voltar do segundo plano. |

---

## Regras financeiras implementadas (R1 §8)

- **Centavos inteiros:** todo valor é armazenado e calculado em centavos (`int`), nunca ponto flutuante.
- **Distribuição:** aporte = renda × percentual da caixinha na data da renda; truncamento ao centavo; resto de centavos vai para a caixinha de maior percentual (empate → Essenciais).
- **Não alocado:** se a soma dos percentuais for menor que 100%, a diferença aparece como "não alocado"; soma acima de 100% não é aceita.
- **Percentuais versionados:** mudanças valem apenas para rendas futuras; rendas já registradas mantêm a regra da data em que foram recebidas.
- **Saldo derivado:** saldo da caixinha = soma dos movimentos (aportes − gastos ± transferências ± ajustes). Nunca editado diretamente; correções entram como lançamento de ajuste.
- **Saldo negativo:** permitido e visível, sem bloquear o gasto. Exemplo: Essenciais +1.500 −1.650 +1.500 = 1.350.
- **Transferência:** não é receita nem despesa; o que sai de uma caixinha entra na outra, soma não muda.
- **Estorno:** devolve o valor à caixinha de origem, vinculado ao lançamento original.
- **Cartão de crédito:** a compra debita a caixinha na data da compra; pagar a fatura não é um novo gasto.
- **Cobertura da reserva:** saldo da reserva ÷ média mensal de gastos essenciais (exibe "dados insuficientes" com menos de um mês de histórico).
- **Mês financeiro:** começa no dia 1 por padrão, configurável pelo usuário; datas no fuso do aparelho.
- **Origem dos valores:** valores informados (renda, saldo inicial) e calculados (saldos, cobertura) são identificados na tela como tais.

---

## Estrutura do projeto

```
lib/
  finance.dart      # Domínio puro: distribuição, saldos, parsing/formatação pt-BR (sem Flutter nem banco)
  store.dart        # Contrato FinanceStore + SqfliteFinanceStore (SQLite, esquema v2, migração v1→v2, PIN com hash+sal, backup/restauração, recorrências, relatórios, CSV)
  theme.dart        # Sistema visual: cores semânticas (R3), cores e ícones das caixinhas
  main.dart         # MetricApp, gate onboarding → PIN → FinanceHome, navegação, bloqueio automático
  onboarding.dart   # Fluxo guiado de primeiro uso (R3 §6.1)
  pin_screen.dart   # Criação e validação de PIN, biometria opcional (R2 §5, R3 §6.12)
  caixa_detalhe.dart # Detalhe da caixinha, gráfico de evolução, extrato, transferência, ajuste (R3 §6.6)
  recorrencias_screen.dart # Recorrências e assinaturas (R3 §6.8)
  relatorio_mensal.dart    # Relatório mensal e exportação CSV (R3 §6.10)
  grafico_linha.dart       # Componente de linha sem animações nem eixo truncado (R3 §7)
test/
  finance_test.dart  # 13 testes de domínio (distribuição, saldos, transferências, parsing)
  fake_store.dart    # Fake in-memory de FinanceStore para testes de interface (sem sqlite3.dll no Windows de dev)
  widget_test.dart   # 7 testes de interface (início, renda, gasto, transferência, estorno, backup)
android/, ios/, linux/, macos/, web/, windows/  # Pastas padrão do Flutter
```

---

## Como executar

```bash
# 1. Instale o Flutter SDK (3.13.5 ou superior) e aceite as licenças
flutter doctor

# 2. Baixe as dependências
flutter pub get

# 3. Análise estática
flutter analyze

# 4. Testes (unidade + interface)
flutter test

# 5. Execute no emulador/dispositivo Android ou no Windows (requer Visual Studio para Windows)
flutter run

# 6. Gere o APK de debug
flutter build apk --debug
```

O APK de debug fica em `build/app/outputs/flutter-apk/app-debug.apk`.

---

## Decisões técnicas e provisórias (registro honesto)

- **Banco:** SQLite local via `sqflite`, criptografia em repouso **não implementada** (custo/complexidade avaliada e adiada; o PIN protege o acesso ao app, não o arquivo do banco). Reavaliar antes de usar com dados reais de produção.
- **Backup:** exportação produz JSON legível e CSV para relatórios. Não importar arquivos não confiáveis. Trate backup/export como informação confidencial. Mescla de backup e migração de versões antigas não implementadas.
- **Persistência em testes:** como o ambiente de desenvolvimento Windows não tem `sqlite3.dll`, os testes de interface usam `FakeFinanceStore` em memória. A implementação SQLite compila no build do APK e foi revisada por código.
- **PIN:** hash SHA-256 com sal (`package:crypto`); atraso crescente após falhas (5 falhas → 1 minuto, depois dobra); biometria opcional com PIN como alternativa obrigatória.
- **Flutter 3.47:** `TextInputType.decimal` não existe; usa-se `TextInputType.numberWithOptions(decimal: true)`.
- **Comparações de data:** usam `String.compareTo` (este Dart não define operadores de ordem em `String`).

---

## Escopo fora do MVP (documentado, não implementado)

Integração bancária, Open Finance, corretoras, recomendações de investimentos, automação fiscal completa, sincronização em nuvem, conta de usuário, metas detalhadas, patrimônio líquido, cartões e faturas, calculadoras financeiras.

---

## Testes

- `flutter analyze`: sem erros nem warnings.
- `flutter test`: 20 testes passando (13 de domínio, 7 de interface).
- Não foi possível instalar/executar em dispositivo Android nem rodar testes contra SQLite nativo neste ambiente (sem emulador/dispositivo físico e sem `sqlite3.dll` no Windows).

---

## Documentação de referência

- `IMPLEMENTACAO.md` — matriz consolidada de requisitos, decisões, desvios e limitações conhecidas.
- Três relatórios oficiais do projeto (Produto, Desenvolvimento, Design e UX) são a base dos requisitos implementados.

---

**Atenção:** este aplicativo organiza seu dinheiro em caixinhas virtuais; ele não movimenta dinheiro real, não é um banco, corretora nem ferramenta fiscal. Os dados ficam apenas no seu aparelho. Exporte um backup de vez em quando.