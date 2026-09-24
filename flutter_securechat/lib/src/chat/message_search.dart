import 'dart:convert';

/// Search only user-visible text, never transport records, paths or voter IDs.
String messageSearchText({
  required String content,
  required String contentType,
  required bool isViewOnce,
  String? caption,
}) {
  if (isViewOnce) return '';
  switch (contentType) {
    case 'text':
      return content;
    case 'image':
      return caption?.trim() ?? '';
    case 'file':
      final name = content
          .split('|')
          .first
          .replaceAll('\\', '/')
          .split('/')
          .last;
      return '$name\n${caption?.trim() ?? ''}';
    case 'poll':
      try {
        final value = jsonDecode(content);
        if (value is! Map ||
            value['question'] is! String ||
            value['options'] is! List)
          return '';
        final question = value['question'] as String;
        final options = (value['options'] as List)
            .whereType<String>()
            .map((s) => s.trim())
            .toList();
        if (question.trim().isEmpty ||
            question.trim().length > 500 ||
            options.length < 2 ||
            options.length > 4 ||
            options.any((s) => s.isEmpty || s.length > 200))
          return '';
        return [question, ...options].join('\n');
      } catch (_) {
        return '';
      }
    default:
      return '';
  }
}
