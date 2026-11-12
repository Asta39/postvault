import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:postvault/ui/cream.dart';

void main() {
  testWidgets('toast shows, Undo runs the action and skips onClosed', (t) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    var undone = 0, closed = 0;
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    showToast(
      ctx,
      'Post deleted',
      actionLabel: 'Undo',
      onAction: () => undone++,
      onClosed: () => closed++,
    );
    await t.pump();
    expect(find.text('Post deleted'), findsOneWidget);
    await t.tap(find.text('UNDO'));
    await t.pump();
    expect(find.text('Post deleted'), findsNothing);
    expect([undone, closed], [1, 0]);

    showToast(ctx, 'Saved', onClosed: () => closed++);
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Saved'), findsNothing);
    expect(closed, 1);
    // Font loading errors are expected offline and unrelated to the toast.
    t.takeException();
  });
}
