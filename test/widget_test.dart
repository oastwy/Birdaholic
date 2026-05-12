import 'package:bird_flashcard/models/audio_info.dart';
import 'package:bird_flashcard/models/species.dart';
import 'package:bird_flashcard/widgets/bird_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder test', () {
    expect(1 + 1, 2);
  });

  testWidgets('learning audio prompt shows audio answer instead of image first',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BirdCard(
            species: Species(
              cn: '测试鸟',
              en: 'Test Bird',
              sci: 'Testus birdus',
              audios: [
                AudioInfo(type: 'song', file: 'sounds/test.mp3'),
              ],
              image: 'images/test.jpg',
            ),
            audioPaths: ['/tmp/test.mp3'],
            audioLabels: ['鸣唱 song'],
            promptMode: PromptMode.audio,
            initiallyShowAnswer: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.zoom_out_map), findsNothing);
  });
}
