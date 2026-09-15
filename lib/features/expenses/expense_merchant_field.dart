import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// A free-text field: selecting a past merchant never saves the expense itself.
class ExpenseMerchantField extends StatelessWidget {
  const ExpenseMerchantField({
    required this.controller,
    required this.history,
    required this.fieldKey,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.label,
    this.hint = 'Where?',
    this.onSubmit,
    super.key,
  });
  final FAutocompleteController controller;
  final List<String> history;
  final Key fieldKey;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final Widget? label;
  final String hint;
  final ValueChanged<String>? onSubmit;

  @override
  Widget build(BuildContext context) => FAutocomplete.textBuilder(
    key: fieldKey,
    control: FAutocompleteControl.managed(controller: controller),
    focusNode: focusNode,
    enabled: enabled,
    autofocus: autofocus,
    label: label,
    hint: hint,
    textInputAction: TextInputAction.next,
    onSubmit: onSubmit,
    filter: (query) => filterMerchants(history, query),
    contentBuilder: (context, query, values) => [
      for (final value in values)
        FAutocompleteItem<String>(
          value: value,
          title: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    contentEmptyBuilder: null,
  );
}

List<String> filterMerchants(List<String> history, String query) {
  final normalized = query.trim().toLowerCase();
  return [
    ...history.where((name) => name.toLowerCase().startsWith(normalized)),
    if (normalized.isNotEmpty)
      ...history.where(
        (name) =>
            !name.toLowerCase().startsWith(normalized) &&
            name.toLowerCase().contains(normalized),
      ),
  ].take(8).toList();
}
