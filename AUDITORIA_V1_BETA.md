# Auditoria v1.0-beta — Metric

## 1. Sumário executivo

A primeira etapa de desenvolvimento do Metric foi revisada, corrigida e parcialmente validada. O núcleo financeiro (distribuição de renda, saldos derivados, transferências atômicas, estornos) está implementado e coberto por testes automatizados. A persistência SQLite compila e o aplicativo foi instalado e iniciado com sucesso em emulador Android (API 37). Restam pendências de validação em dispositivo real (fluxos de UI interativos, backup com arquivo real, PIN em hardware) e de revisão de acessibilidade/contraste.

**Veredito:** APROVADA COM RESSALVAS (núcleo validado; sem defeitos críticos abertos; pendências não bloqueantes).

---

## 2. Estado inicial

O repositório continha um projeto Flutter padrão com contador de demo, sobre o qual já havia sido construída uma base funcional (onboarding, PIN, recorrências, relatório, detalhe da caixinha, backup/restauração, testes com fake store). O ambiente de desenvolvimento dispõe de Flutter 3.47.7 / Dart 3.13.5 e Android SDK 36, com emulador Android disponível, mas nenhum dispositivo físico conectado.

---

## 3. Problemas encontrados

| # | Problema | Severidade | Causa raiz | Arquivo afetado | Correção aplicada |
|---|----------|------------|------------|-----------------|-------------------|
| 1 | Inconsistência de contagem de testes (README: 20; IMPLEMENTACAO: 19) | Baixa | Documentação desatualizada | IMPLEMENTACAO.md | Corrigido para 20 testes (13 domínio + 7 interface) |
| 2 | Backup automático do Android exporia dados financeiros (`allowBackup` padrão `true`) | Crítico | Ausência de declaração explícita no manifest | AndroidManifest.xml | `android:allowBackup="false"` + `backup_rules.xml` excluindo sharedpref/database/files |
| 3 | Sem proteção de tela (FLAG_SECURE) — capturas/gravação poderiam vazar PIN e saldos | Alta | Ausência de flag de segurança na Activity | MainActivity.kt | Adicionada `FLAG_SECURE` no `onCreate` |
| 4 | Lint `use_build_context_synchronously` (info de estilo) | Baixa | Uso de `context` após `await` sem captura prévia | lib/main.dart | Captura do contexto em variável local antes do `await` |

---

## 4. Correções aplicadas

| Arquivo | Motivo |
|---------|--------|
| `android/app/src/main/AndroidManifest.xml` | Desabilitou backup automático do Android e definiu regras de exclusão de dados sensíveis |
| `android/app/src/main/res/xml/backup_rules.xml` (novo) | Exclui sharedpref, database e files do backup do sistema |
| `android/app/src/main/kotlin/com/example/metric/MainActivity.kt` | Adicionou `FLAG_SECURE` para impedir capturas de tela e gravação de exibição |
| `lib/main.dart` | Captura de contexto antes de `await` no diálogo de bloqueio automático (correção de lint) |
| `IMPLEMENTACAO.md` | Contagem de testes corrigida (20) e status de SQLite ajustado |

---

## 5. Testes realizados

| Suíte | Comandos | Resultado | Ambiente |
|-------|----------|-----------|----------|
| Análise estática | `flutter analyze` | 0 erros, 0 warnings, 13 infos de lint | Windows host |
| Testes automatizados | `flutter test` | 20/20 aprovados (13 domínio, 7 interface) | Windows host (fake store) |
| Build Android debug | `flutter build apk --debug` | APK gerado com sucesso | Windows host |
| Instalação Android | `flutter install -d emulator-5554` | Sucesso | Emulador API 37 |
| Execução Android | `adb shell am start -n com.example.metric/.MainActivity` | App iniciado com sucesso | Emulador API 37 |

---

## 6. Riscos residuais

- **Banco SQLite não criptografado em repouso**: o PIN protege o acesso ao app, não o arquivo do banco. Risco se o dispositivo for comprometido fisicamente.
- **PIN hash SHA-256 com sal** está incluído no backup JSON (configurações). Backup não criptografado por padrão; tratar como confidencial.
- **PIN numérico curto (mín. 4 dígitos)**: suscetível a força bruta offline se o hash for obtido; mitigado por atraso crescente após falhas.
- **Biometria opcional**: não validada em hardware real (sem sensor de impressão digital no emulador/host).
- **Fluxos de UI interativos no dispositivo**: não foram navegados manualmente (apenas inicialização validada).

---

## 7. Pendências

- Validação de fluxos de UI (registro de renda/gasto, transferência, estorno, relatório) em dispositivo físico.
- Teste de persistência SQLite real (banco nativo) — atualmente coberto por fake store em testes de unidade/interface.
- Revisão de contraste WCAG AA 4,5:1 e licença da fonte.
- Requisitos LGPD e política de privacidade para publicação.
- Backup criptografado opcional por senha (adiciado como pendência pós-MVP).
- Validação de backup com arquivo real exportado/importado no dispositivo.

---

## 8. Veredito

**APROVADA COM RESSALVAS**

O núcleo financeiro foi validado (testes automatizados), a persistência compila e o aplicativo instala e inicia em emulador Android. Não existem defeitos críticos abertos. As pendências são não bloqueantes (execução em dispositivo real, backup com arquivo real, acessibilidade, criptografia em repouso) e não impedem o encerramento da Etapa 1 para beta privada, desde que as ressalvas sejam comunicadas aos usuários beta.

---

## 9. Arquivos modificados

| Arquivo | Motivo |
|---------|--------|
| `android/app/src/main/AndroidManifest.xml` | Privacidade: desabilitou backup automático do Android |
| `android/app/src/main/res/xml/backup_rules.xml` | (novo) Regras de exclusão de backup de dados sensíveis |
| `android/app/src/main/kotlin/com/example/metric/MainActivity.kt` | Segurança: FLAG_SECURE contra capturas de tela |
| `lib/main.dart` | Correção de lint (contexto antes de await) |
| `IMPLEMENTACAO.md` | Correção de contagem de testes e status SQLite |

---

## 10. Pendências pós-beta (PENDENCIAS_V2.md)

- Criptografia em repouso do banco SQLite
- Backup protegido por senha
- Validação em dispositivo físico
- Acessibilidade/contraste WCAG AA
- Requisitos LGPD para publicação
