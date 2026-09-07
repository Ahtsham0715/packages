import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'generator_screen.dart';

/// Opens the generator as a sheet and returns the chosen value.
///
/// The editor uses this so generating a password never navigates away from a
/// half-filled form — leaving and coming back is where unsaved entries get
/// lost.
Future<String?> showGeneratorSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
            Space.xl, 0, Space.xl, Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Generate a password',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: Space.xl),
            GeneratorPanel(
              onUse: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
    ),
  );
}
