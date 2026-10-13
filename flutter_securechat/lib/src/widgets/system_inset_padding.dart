import 'package:flutter/widgets.dart';

/// Kaydirilabilir bir listenin [base] dolgusuna sistem gezinme cubugunun
/// yuksekligini ekler.
///
/// Uygulama kenardan kenara cizer. `ListView`'a acik bir `padding`
/// verildiginde liste alttaki sistem boslugunu artik kendisi eklemez ve son
/// ogeler (cogu zaman ekranin tek eylem dugmesi) uc tuslu gezinme cubugunun
/// altinda kalir (QA 2026-10-13 T11).
EdgeInsets withSystemBottomInset(BuildContext context, EdgeInsets base) =>
    base.copyWith(bottom: base.bottom + MediaQuery.paddingOf(context).bottom);
