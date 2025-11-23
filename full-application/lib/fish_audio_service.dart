// // import 'dart:convert';
// // import 'dart:io';
// // import 'package:http/http.dart' as http;
// // import 'package:path_provider/path_provider.dart';
// // import 'package:audioplayers/audioplayers.dart';
// //
// // class FishAudioService {
// //   final String apiKey;
// //   final AudioPlayer _audioPlayer = AudioPlayer();
// //
// //   FishAudioService(this.apiKey);
// //
// //   /// Convert text to speech using Fish Audio API and play it
// //   Future<void> textToSpeech(String text) async {
// //     if (text.isEmpty) {
// //       print("No text to convert to speech");
// //       return;
// //     }
// //
// //     try {
// //       print("Converting text to speech: $text");
// //
// //       // Call Fish Audio API
// //       final response = await http.post(
// //         Uri.parse('https://api.fish.audio/v1/tts'),
// //         headers: {
// //           'Authorization': 'Bearer $apiKey',
// //           'Content-Type': 'application/json',
// //         },
// //         body: jsonEncode({
// //           'text': text,
// //           'reference_id': '8ef4a238714b45718ce04243307c57a7', // Same as Python code
// //           'format': 'mp3',
// //         }),
// //       );
// //
// //       if (response.statusCode == 200) {
// //         // Save audio to temporary file
// //         final directory = await getTemporaryDirectory();
// //         final audioFile = File('${directory.path}/output.mp3');
// //         await audioFile.writeAsBytes(response.bodyBytes);
// //
// //         print("Audio saved to ${audioFile.path}");
// //
// //         // Play the audio
// //         await _audioPlayer.play(DeviceFileSource(audioFile.path));
// //         print("Playing audio...");
// //       } else {
// //         print("Fish Audio API error: ${response.statusCode} - ${response.body}");
// //       }
// //     } catch (e) {
// //       print("Error in text-to-speech: $e");
// //     }
// //   }
// //
// //   /// Stop audio playback
// //   Future<void> stopAudio() async {
// //     await _audioPlayer.stop();
// //   }
// //
// //   /// Dispose of resources
// //   void dispose() {
// //     _audioPlayer.dispose();
// //   }
// // }
//
// import 'dart:convert';
// import 'dart:io';
// import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
// import 'package:audioplayers/audioplayers.dart';
//
// class FishAudioService {
//   final String apiKey;
//   final AudioPlayer _audioPlayer = AudioPlayer();
//   bool isPlaying = false; // Exposed state
//
//   FishAudioService(this.apiKey);
//
//   /// Convert text to speech.
//   /// If [interrupt] is true, it stops current audio before playing new audio.
//   Future<void> textToSpeech(String text, {bool interrupt = false}) async {
//     if (text.isEmpty) return;
//
//     if (interrupt) {
//       await stopAudio();
//     } else if (isPlaying) {
//       // If we are already talking and this isn't an emergency, ignore this request
//       // (Prevents Gemini from talking over itself)
//       print("Audio skipped: Already playing");
//       return;
//     }
//
//     try {
//       final response = await http.post(
//         Uri.parse('https://api.fish.audio/v1/tts'),
//         headers: {
//           'Authorization': 'Bearer $apiKey',
//           'Content-Type': 'application/json',
//         },
//         body: jsonEncode({
//           'text': text,
//           'reference_id': '8ef4a238714b45718ce04243307c57a7',
//           'format': 'mp3',
//         }),
//       );
//
//       if (response.statusCode == 200) {
//         final directory = await getTemporaryDirectory();
//         final audioFile = File('${directory.path}/output_${DateTime.now().millisecondsSinceEpoch}.mp3');
//         await audioFile.writeAsBytes(response.bodyBytes);
//
//         isPlaying = true;
//         await _audioPlayer.play(DeviceFileSource(audioFile.path));
//
//         // Listen for when audio finishes
//         _audioPlayer.onPlayerComplete.listen((event) {
//           isPlaying = false;
//         });
//       }
//     } catch (e) {
//       print("Error in text-to-speech: $e");
//       isPlaying = false;
//     }
//   }
//
//   /// Immediately stop any currently playing audio
//   Future<void> stopAudio() async {
//     await _audioPlayer.stop();
//     isPlaying = false;
//   }
//
//   void dispose() {
//     _audioPlayer.dispose();
//   }
// }

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class FishAudioService {
  final String apiKey;
  final AudioPlayer _audioPlayer = AudioPlayer();

  // THE QUEUE SYSTEM
  final List<String> _queue = [];
  bool _isSpeaking = false;

  FishAudioService(this.apiKey) {
    // When one clip finishes, check if there is another one waiting
    _audioPlayer.onPlayerComplete.listen((event) {
      _isSpeaking = false;
      _playNextInQueue();
    });
  }

  /// Main entry point.
  /// [interrupt]: If true (Danger), clears queue and speaks immediately.
  /// If false (Env/POI), adds to queue and waits turn.
  Future<void> textToSpeech(String text, {bool interrupt = false}) async {
    if (text.isEmpty) return;

    if (interrupt) {
      // EMERGENCY: Clear everything and shout
      _queue.clear();
      await _audioPlayer.stop();
      _isSpeaking = false;
      await _processAndPlay(text); // Play immediately
    } else {
      // NORMAL: Add to line
      _queue.add(text);
      // If nobody is talking, start the line
      if (!_isSpeaking) {
        _playNextInQueue();
      }
    }
  }

  Future<void> _playNextInQueue() async {
    if (_queue.isEmpty || _isSpeaking) return;

    String nextText = _queue.removeAt(0);
    _isSpeaking = true;
    await _processAndPlay(nextText);
  }

  Future<void> _processAndPlay(String text) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.fish.audio/v1/tts'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'text': text,
          'reference_id': '73cd7d4e28a14635b583f6cb20e1a040',
          'format': 'mp3',
        }),
      );

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        // Unique filename so they don't overwrite each other
        final audioFile = File('${directory.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await audioFile.writeAsBytes(response.bodyBytes);

        await _audioPlayer.play(DeviceFileSource(audioFile.path));
      } else {
        print("Fish API Error: ${response.statusCode}");
        _isSpeaking = false;
        _playNextInQueue(); // Skip to next if this failed
      }
    } catch (e) {
      print("Audio Error: $e");
      _isSpeaking = false;
      _playNextInQueue(); // Skip to next
    }
  }

  /// Hard stop (Stop Button pressed)
  Future<void> stopAudio() async {
    _queue.clear();
    await _audioPlayer.stop();
    _isSpeaking = false;
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}