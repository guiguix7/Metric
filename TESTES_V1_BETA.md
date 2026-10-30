# Testes v1.0-beta — Metric

## 1. Ambiente e versões

- Host: Windows 11 (25H2, build 26200.9711)
- Flutter: 3.47.7 (channel stable)
- Dart: 3.13.5
- Android SDK: 36.0.0
- Emulador: Medium_Phone_API_37.0 (emulator-5554, Android 17, x86_64)
- Dispositivo físico: nenhum conectado
- sqlite3.dll: não disponível no Windows de desenvolvimento (testes de persistência usam FakeFinanceStore em memória)

## 2. Comandos executados

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter install -d emulator-5554
adb -s emulator-5554 shell am start -n com.example.metric/.MainActivity
```

## 3. Resultados

### flutter analyze
- Erros: 0
- Warnings: 0
- Infos de lint: 13 (curly_braces_in_flow_control_structures, use_build_context_synchronously, deprecated_member_use)
- Status: sem erros nem warnings de compilação

### flutter test (suíte completa)
- Total descoberto: 20
- Total executado: 20
- Aprovado: 20
- Reprovado: 0
- Ignorado: 0

Distribuição:
- Testes de unidade (domínio, finance_test.dart): 13
  1. renda 1000,01 conserva centavos com maior percentual
  2. renda ímpar com empate no maior percentual vai para Essenciais
  3. percentuais abaixo de 100 preservam não alocado
  4. soma acima de 100 não é permitida
  5. percentuais inválidos (negativos ou >100 individual) não são permitidos
  6. distribuição com tudo zerado deixa tudo não alocado
  7. renda não positiva é rejeitada
  8. saldo negativo atravessa meses (+1500 −1650 +1500 = 1350)
  9. transferência não altera soma total dos saldos
  10. caixinha desconhecida no saldo lança erro
  11. parse dinheiro brasileiro aceita com e sem milhar
  12. parse dinheiro brasileiro rejeita formato inválido
  13. money formata reais com centavos, sinal negativo e ponto de milhar

- Testes de interface (widget_test.dart, FakeFinanceStore): 7
  1. início mostra as cinco caixinhas
  2. registrar renda divide o valor entre as caixinhas
  3. gasto reduz a caixinha sugerida e aparece no extrato
  4. transferência entre caixinhas não altera o total
  5. nova distribuição vale apenas para rendas futuras
  6. estornar gasto devolve o valor à caixinha
  7. backup e restauração preservam saldos

### flutter build apk --debug
- Resultado: APK gerado com sucesso (`build/app/outputs/flutter-apk/app-debug.apk`)
- Warnings de Gradle (KGP plugins, restricted method) não bloqueiam o build

### Instalação e execução Android
- `flutter install -d emulator-5554`: sucesso
- `adb shell am start -n com.example.metric/.MainActivity`: app iniciado com sucesso

## 4. Testes NÃO executados (limitação de ambiente)

- Testes de persistência contra SQLite nativo no host (sem sqlite3.dll).
- Testes instrumentados de UI no Android (não há ferramenta de automação de UI configurada; apenas inicialização validada).
- Validação de biometria em hardware real (sem sensor no emulador/host).
- Teste de backup com arquivo real exportado/importado no dispositivo (apenas teste de unidade com fake store).

## 5. Evidências reproduzíveis

- Suíte de testes: 20/20 aprovados (output acima).
- APK: `build/app/outputs/flutter-apk/app-debug.apk` gerado.
- Instalação: confirmação de "Installing app... 5,0s" e sucesso.
- Execução: "Starting: Intent { cmp=com.example.metric/.MainActivity }".

## 6. Falhas

Nenhuma falha de teste ou build registrada.
