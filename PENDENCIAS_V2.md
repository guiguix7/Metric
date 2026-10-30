# Pendências v2 — Metric

Documenta melhorias futuras, funcionalidades fora do escopo, riscos aceitos e itens adiados. Não esconde bugs críticos.

## Melhorias futuras (pós-MVP)

1. Criptografia em repouso do banco SQLite (sqlcipher ou similar) — atualmente não implementada; o PIN protege o acesso ao app, não o arquivo do banco.
2. Backup protegido por senha (criptografia autenticada com derivação de chave adequada).
3. Mesclagem ("merge") de backups com estratégia explícita para IDs e duplicatas (desativada por risco de integridade).
4. Migração de formato de backup de versões antigas.
5. Tela de bloqueio e PIN validadas em dispositivo físico com sensor de biometria.
6. Revisão de contraste WCAG AA 4,5:1 e licença da fonte.
7. Requisitos LGPD e política de privacidade para publicação nas lojas.
8. Notificações locais de lembrete de backup e assinatura.

## Funcionalidades fora do escopo do MVP (Etapa 2+)

- Integração bancária / Open Finance
- Corretoras e recomendações de investimentos
- Automação fiscal completa
- Sincronização em nuvem / conta de usuário
- Metas detalhadas, patrimônio líquido, cartões e faturas
- Calculadoras financeiras (juros compostos, parcelamento, inflação)

## Riscos aceitos formalmente

| Risco | Impacto | Decisão |
|-------|---------|---------|
| Banco SQLite não criptografado | Dados acessíveis se dispositivo comprometido | Aceito para beta; reavaliar antes de dados reais de produção |
| PIN numérico curto (mín. 4 dígitos) | Força bruta offline se hash obtido | Mitigado por atraso crescente; aceito para beta |
| Backup JSON não criptografado | Dados legíveis no arquivo de exportação | Aviso explícito na UI; tratar como confidencial |
| Fluxos de UI não navegados em dispositivo real | Comportamento de toque não validado | Inicialização validada em emulador; UI coberta por testes de widget |

## Funcionalidades adiadas

- Estorno acessível diretamente na lista de lançamentos: IMPLEMENTADO (UI com ícone de restaurar + confirmação).
- Filtros por caixinha em Lançamentos: IMPLEMENTADO (chips de filtro).
- Desfazer ações recentes: não implementado (estorno serve como mecanismo de correção; desfazer seria redundante para lançamentos financeiros).
- Proteção de informações na tela de recentes: IMPLEMENTADO via FLAG_SECURE.
- Lembrete periódico de backup: não implementado (adiado para v2).

## Itens bloqueantes resolvidos nesta etapa

- Backup automático do Android exporia dados → corrigido (allowBackup="false").
- Sem proteção de tela → corrigido (FLAG_SECURE).
- Inconsistência de contagem de testes → corrigida (20).
- Lint de contexto assíncrono → corrigido.

## Itens bloqueantes restantes

Nenhum bloqueante crítico aberto.
