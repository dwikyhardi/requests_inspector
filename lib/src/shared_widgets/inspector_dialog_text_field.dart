import 'package:flutter/material.dart';
import 'package:requests_inspector_plus/requests_inspector_plus.dart';

class InspectorDialogTextField extends StatelessWidget {
  const InspectorDialogTextField({
    super.key,
    required this.text,
    required this.onChanged,
  });

  final String text;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = InspectorController().isDarkMode;
    final fillColor = isDarkMode
        ? const Color.fromARGB(255, 19, 19, 19)
        : const Color.fromARGB(255, 235, 235, 235);
    return TextField(
      decoration: InputDecoration(
        filled: true,
        fillColor: fillColor,
        border: const OutlineInputBorder(borderSide: BorderSide.none),
      ),
      maxLines: null,
      minLines: 2,
      scrollPhysics: const NeverScrollableScrollPhysics(),
      controller: TextEditingController(text: text),
      onChanged: onChanged,
    );
  }
}
