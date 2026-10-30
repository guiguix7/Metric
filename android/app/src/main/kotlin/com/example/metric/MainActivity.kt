package com.example.metric

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE impede capturas de tela e gravação de exibição nas telas
        // do aplicativo, protegendo dados financeiros sensíveis (PIN, saldos,
        // extratos) contra vazamento na lista de aplicativos recentes e por
        // apps de captura de tela.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
