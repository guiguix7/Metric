# Changelog — Metric

## v1.0.0-beta.1 (atual)

### Adicionado
- Cinco caixinhas virtuais (Essenciais, Livre, Reserva, Investido, Metas)
- Onboarding guiado: boas-vindas, renda líquida, divisão de renda (presets e personalizada), saldos iniciais opcionais, criação de PIN
- Registro de renda com pré-visualização da divisão e resto de centavos para caixinha de maior percentual
- Registro de gasto por categoria com classificação essencial/não essencial
- Transferência entre caixinhas (atômica, não conta como receita/despesa)
- Extrato de lançamentos com filtros por caixinha e estorno de gasto
- Detalhe da caixinha com gráfico de evolução mensal, ajuste de saldo e transferência
- Recorrências e assinaturas (criar, pausar, encerrar; lançamento automático na data de vencimento)
- Relatório mensal: receitas, gastos, saldo, gasto por categoria, essencial × não essencial, evolução do saldo, exportação CSV
- Backup/exportação JSON e importação com validação de versão e conferência de saldos
- Bloqueio por PIN (hash SHA-256 com sal, atraso crescente após falhas)
- Biometria opcional com PIN como fallback obrigatório
- Bloqueio automático após tempo configurável em segundo plano
- Tema claro/escuro/sistema persistido
- FLAG_SECURE (impede captura de tela e gravação)
- Desabilitação de backup automático do Android (allowBackup="false")

### Alterado
- Contagem de testes corrigida na documentação (20 testes, não 19)
- main.dart: captura de contexto antes de `await` (correção de lint)

### Corrigido
- `use_build_context_synchronously` no diálogo de bloqueio automático

### Removido
- Nenhuma

### Depreciado
- Nenhuma

### Notas
- Banco SQLite não criptografado em repouso (risco residual documentado)
- Backup JSON não criptografado por padrão (tratar como confidencial)
- Execução Android validada em emulador API 37 (apenas inicialização; fluxos de UI não navegados manualmente)
