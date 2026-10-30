import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'store.dart';
import 'theme.dart';

/// Tela de PIN: criação (modo criar) ou validação (modo desbloquear).
/// O PIN nunca viaja em texto claro: a loja guarda somente hash com sal.
class PinScreen extends StatefulWidget {
  /// 'criar' -> cadastra/altera o PIN e devolve o PIN digitado via Navigator.
  /// 'desbloquear' -> valida contra o PIN armazenado e devolve booleano.
  final String mode;
  final FinanceStore store;
  final bool biometriaDisponivel;
  const PinScreen({
    super.key,
    required this.mode,
    required this.store,
    this.biometriaDisponivel = false,
  });

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _digitado = '';
  String? _erro;
  bool _confirmando = false;
  String? _primeiro;
  bool _bloqueado = false;
  final _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    if (widget.mode == 'desbloquear') _verificarBloqueio();
  }

  Future<void> _verificarBloqueio() async {
    if (!(await widget.store.podeTentarPin())) {
      setState(() => _bloqueado = true);
    } else if (widget.biometriaDisponivel) {
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'Desbloqueie o Metric para acessar suas caixinhas',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: false,
          ),
        );
        if (ok && mounted) Navigator.pop(context, true);
      } catch (_) {}
    }
  }

  String get _titulo {
    if (widget.mode == 'criar') {
      return _confirmando ? 'Confirme o PIN' : 'Crie um PIN de acesso';
    }
    return 'Desbloqueie o Metric';
  }

  String get _subtitulo {
    if (widget.mode == 'criar') {
      return _confirmando
          ? 'Digite o mesmo PIN novamente.'
          : 'Escolha um PIN de ao menos 4 dígitos para proteger seus dados.';
    }
    return 'Seus dados financeiros ficam protegidos neste aparelho.';
  }

  void _digito(String d) {
    setState(() {
      _erro = null;
      if (_digitado.length < 6) _digitado += d;
    });
  }

  void _apagar() {
    setState(() {
      _erro = null;
      if (_digitado.isNotEmpty)
        _digitado = _digitado.substring(0, _digitado.length - 1);
    });
  }

  Future<void> _enviar() async {
    if (_digitado.length < 4) {
      setState(() => _erro = 'O PIN precisa de ao menos 4 dígitos.');
      return;
    }
    if (widget.mode == 'criar') {
      if (!_confirmando) {
        setState(() {
          _primeiro = _digitado;
          _digitado = '';
          _confirmando = true;
        });
        return;
      }
      if (_digitado != _primeiro) {
        setState(() {
          _erro = 'Os PINs não conferem. Tente novamente.';
          _digitado = '';
          _confirmando = false;
          _primeiro = null;
        });
        return;
      }
      try {
        await widget.store.setPin(_digitado);
        if (mounted) Navigator.pop(context, _digitado);
      } catch (e) {
        setState(() => _erro = '$e');
      }
    } else {
      final stored = await widget.store.pinStored();
      if (stored == null || !widget.store.verificaPin(_digitado, stored)) {
        await widget.store.registraFalhaPin();
        final bloqueado = !(await widget.store.podeTentarPin());
        setState(() {
          _erro = 'PIN incorreto.';
          _digitado = '';
          _bloqueado = bloqueado;
        });
        return;
      }
      await widget.store.resetaTentativasPin();
      if (mounted) Navigator.pop(context, true);
    }
  }

  Widget _campo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        final preenchido = i < _digitado.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: preenchido ? kDestaque : const Color(0xFFE5E7EB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: preenchido
              ? const Icon(Icons.check, color: Colors.white, size: 24)
              : null,
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teclado = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['<', '0', 'OK'],
    ];
    return Scaffold(
      backgroundColor: kFundo,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text(
              _titulo,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: kTextoPrincipal,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kTextoSecundario),
              ),
            ),
            const SizedBox(height: 40),
            _campo(),
            if (_erro != null) ...[
              const SizedBox(height: 12),
              Text(
                _erro!,
                style: const TextStyle(color: kNegativo, fontSize: 13),
              ),
            ],
            const Spacer(),
            if (widget.mode == 'criar' &&
                widget.biometriaDisponivel &&
                !_confirmando)
              TextButton.icon(
                onPressed: _bloqueado
                    ? null
                    : () async {
                        final ok = await _auth.authenticate(
                          localizedReason:
                              'Use a biometria para criar o PIN do Metric',
                          options: const AuthenticationOptions(
                            biometricOnly: false,
                          ),
                        );
                        if (ok && mounted) {
                          // biometria apenas isenta da digitação na tela do aparelho;
                          // o PIN ainda precisa ser criado para funcionar como fallback.
                          setState(() => _bloqueado = false);
                        }
                      },
                icon: const Icon(Icons.fingerprint, size: 20),
                label: const Text('Usar biometria também'),
              ),
            if (_bloqueado && widget.mode == 'desbloquear')
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Muitas tentativas. Tente novamente mais tarde.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kNegativo),
                ),
              ),
            const SizedBox(height: 30),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: 12,
              itemBuilder: (_, i) {
                if (i == 9) return _tecla('<', onTap: _apagar);
                if (i == 10) return _tecla('0', onTap: () => _digito('0'));
                if (i == 11)
                  return _tecla('OK', onTap: _enviar, estilo: kDestaque);
                return _tecla(
                  teclado[i ~/ 3][i % 3],
                  onTap: () => _digito(teclado[i ~/ 3][i % 3]),
                );
              },
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _tecla(String texto, {VoidCallback? onTap, Color? estilo}) {
    return Material(
      color: kSuperficie,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _bloqueado || onTap == null ? null : onTap,
        child: Center(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 22,
              color: estilo ?? kTextoPrincipal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
