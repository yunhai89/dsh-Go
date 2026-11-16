import 'package:dsh_app/state/artifact_files.dart';
import 'package:dsh_app/state/artifacts.dart' show FilesChannel;
import 'package:dsh_app/ui/chat/render/markdown_body.dart';
import 'package:dsh_app/ui/chat/render/markdown_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

class _Reader implements WorkspaceImageReader {
  final calls = <String>[];

  @override
  Future<LoadedImage> read(String sessionId, String path) async {
    calls.add(path);
    return RasterImage(MemoryImage(tinyPng));
  }
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('a tall reply reads only the images near the viewport', (tester) async {
    usePhoneView(tester);
    final reader = _Reader();
    await tester.pumpWidget(
      testApp(
        Scaffold(
          body: MarkdownImageScope(
            sessionId: 's1',
            child: SingleChildScrollView(
              child: Column(
                children: const [
                  MarkdownBody(text: '![first](/root/work/first.png)', selectable: false),
                  SizedBox(height: 1800),
                  MarkdownBody(text: '![second](/root/work/second.png)', selectable: false),
                ],
              ),
            ),
          ),
        ),
        overrides: [
          artifactFilesProvider.overrideWithValue(
            ArtifactFiles(connection: fakeConnection, channel: const FilesChannel()),
          ),
          workspaceImageReaderProvider.overrideWithValue(CachedImageReader(reader)),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(reader.calls, ['/root/work/first.png']);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -1700));
    await tester.pumpAndSettle();
    expect(reader.calls, ['/root/work/first.png', '/root/work/second.png']);
    expect(tester.takeException(), isNull);
  });
}
