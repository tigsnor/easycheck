import 'package:flutter/material.dart';

enum ConditionEditAction { keep, change, clear }

Widget conditionEditAction(
        {required String field,
        required String keyName,
        required ConditionEditAction value,
        required ValueChanged<ConditionEditAction> onChanged,
        String? clearLabel}) =>
    DropdownButtonFormField<ConditionEditAction>(
        key: ValueKey(keyName),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: field),
        items: [
          const DropdownMenuItem(
              value: ConditionEditAction.keep, child: Text('기존 값 유지')),
          const DropdownMenuItem(
              value: ConditionEditAction.change, child: Text('입력값으로 변경')),
          if (clearLabel != null)
            DropdownMenuItem(
                value: ConditionEditAction.clear, child: Text(clearLabel)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        });
