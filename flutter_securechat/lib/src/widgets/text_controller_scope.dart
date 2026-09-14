import 'package:flutter/material.dart';

/// Bir dialog/bottom-sheet icin [TextEditingController] olusturur ve onu
/// route TAMAMEN kaldirilana kadar yasatir.
///
/// Neden gerekli: `showDialog` / `showModalBottomSheet` Future'i route pop
/// edilir edilmez tamamlanir, ancak **cikis animasyonu devam eder** ve
/// icerideki `TextField` bu sure boyunca hala mount'ludur. Cagiran tarafta
/// `await`'ten hemen sonra `controller.dispose()` cagirmak, dispose edilmis
/// bir `ChangeNotifier`a listener baglanmasina yol acar:
///
/// ```
/// ChangeNotifier.addListener (disposed)
///   _MergingListenable.addListener
///     _AnimatedState.didUpdateWidget  (transitions.dart)
/// ```
///
/// Sonuc kullaniciya kirmizi hata ekrani olarak yansiyordu. Controller'i bu
/// widget'a devretmek sorunu kokten cozer: dispose'u Flutter, route gercekten
/// yok edildiginde cagirir.
class TextControllerScope extends StatefulWidget {
  const TextControllerScope({
    super.key,
    required this.builder,
    this.initialText = '',
  });

  final String initialText;
  final Widget Function(BuildContext context, TextEditingController controller)
  builder;

  @override
  State<TextControllerScope> createState() => _TextControllerScopeState();
}

class _TextControllerScopeState extends State<TextControllerScope> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

/// Iki metin alani gerektiren dialoglar icin (ornegin parola + tekrari).
class DualTextControllerScope extends StatefulWidget {
  const DualTextControllerScope({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    TextEditingController first,
    TextEditingController second,
  )
  builder;

  @override
  State<DualTextControllerScope> createState() =>
      _DualTextControllerScopeState();
}

class _DualTextControllerScopeState extends State<DualTextControllerScope> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _first, _second);
}
