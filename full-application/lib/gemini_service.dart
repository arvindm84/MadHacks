// import 'package:google_generative_ai/google_generative_ai.dart';
// import 'osm_service.dart';
//
// class GeminiService {
//   late final GenerativeModel _model;
//
//   GeminiService(String apiKey) {
//     _model = GenerativeModel(
//       model: 'gemini-2.5-flash',
//       apiKey: apiKey,
//     );
//   }
//
//   /// Converts a list of POIs into a conversational paragraph using Gemini API
//   Future<String> convertToConversation(List<POI> pois) async {
//     if (pois.isEmpty) {
//       return "I don't see any notable locations nearby at the moment.";
//     }
//
//     // Build the prompt with POI data
//     final prompt = _buildPrompt(pois);
//     print("Gemini: Sending prompt with ${pois.length} POIs");
//
//     try {
//       final content = [Content.text(prompt)];
//       final response = await _model.generateContent(content);
//
//       if (response.text != null && response.text!.isNotEmpty) {
//         print("Gemini: Successfully generated conversational text (${response.text!.length} chars)");
//         return response.text!;
//       } else {
//         print("Gemini: Empty response from API");
//         return "I couldn't generate a description at this time.";
//       }
//     } catch (e) {
//       print("Gemini API error: $e");
//       return "Unable to describe your surroundings right now.";
//     }
//   }
//
//   String _buildPrompt(List<POI> pois) {
//     final locationsText = StringBuffer();
//
//     for (int i = 0; i < pois.length; i++) {
//       final poi = pois[i];
//       locationsText.writeln('${i + 1}. ${poi.name} (${poi.category}) - ${poi.distance.round()}m away');
//     }
//
//     return '''You are a helpful navigation assistant. Here are some nearby locations around the user:
//
// $locationsText
// Convert this into a friendly, natural conversational paragraph (2-3 sentences) describing what's around the user. Be concise and helpful. Focus on the most interesting or useful locations.''';
//   }
// }


import 'dart:io';
import 'package:camera/camera.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'osm_service.dart';

class GeminiService {
  late final GenerativeModel _textModel;  // For POIs (Flash is faster/cheaper)
  late final GenerativeModel _visionModel; // For Images

  GeminiService(String apiKey) {
    // You can use the same model for both, or different ones.
    // 2.5-flash is great for both speed and vision.
    _textModel = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    _visionModel = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
  }

  // ==================== 1. LOCATION / POI DESCRIPTION ====================
  Future<String> convertToConversation(List<POI> pois) async {
    if (pois.isEmpty) return "I don't see any notable landmarks on the map right now.";

    final locationsText = StringBuffer();
    for (int i = 0; i < pois.length; i++) {
      locationsText.writeln('${i + 1}. ${pois[i].name} (${pois[i].category}) - ${pois[i].distance.round()}m');
    }

    print("🔹 GEMINI POI: Generating map summary...");
    final prompt = '''You are a helpful navigation assistant. Here are nearby locations:
$locationsText
Convert this into a natural, brief (1 sentence) update. Example: "There is a Starbucks 50 meters to your right."''';

    try {
      final response = await _textModel.generateContent([Content.text(prompt)]);
      print("✅ GEMINI POI RESULT: ${response.text}");
      return response.text ?? "";
    } catch (e) {
      print("❌ GEMINI POI ERROR: $e");
      return "";
    }
  }

  // ==================== 2. VISUAL / IMAGE DESCRIPTION (From Python) ====================
  Future<String> describeEnvironmentFromImage(XFile imageFile) async {
    print("🔹 GEMINI VISION: Reading image bytes...");

    // 1. Read bytes from the camera file
    final bytes = await imageFile.readAsBytes();

    // 2. The Exact Prompt from your Python Code
    final prompt = """You are a highly perceptive and efficient descriptive guide. Your task is 
    to provide a real-time, evocative audio description of the user's immediate surroundings. 
    The description must be delivered in a factual, stylish, and engaging manner, focusing 
    strictly on objects and elements that define the space.
    The entire description must be extremely concise—no more than a few seconds of spoken 
    word—to keep pace with the user's continuous movement.
    Describe the most striking, movable, or defining elements in the foreground (within three 
    steps) and the middle distance (up to 15 steps). Focus on textures, dominant colors, 
    and distinctive shapes of objects, people, or structures. Conclude with a single, 
    memorable summary of the current ambient feeling or setting (e.g., 'A lively outdoor 
    market,' 'The solemn geometry of office buildings'). Do NOT mention the weather, sky, or 
    any safety/navigational concerns.
    Create like a semi informal tone like a guide you know very well and is friendly. Don't begin with a greeting.

    If the image looks very similar to a generic street or if there isn't much happening, keep it extremely short.
    """;

    print("🔹 GEMINI VISION: Sending to API...");

    try {
      // 3. Send Image + Text to Gemini
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', bytes), // CameraX saves as JPEG by default
        ])
      ];

      final response = await _visionModel.generateContent(content);

      if (response.text != null && response.text!.isNotEmpty) {
        print("✅ GEMINI VISION RESULT: ${response.text}");
        return response.text!;
      } else {
        print("⚠️ GEMINI VISION: Empty response");
        return "";
      }
    } catch (e) {
      print("❌ GEMINI VISION ERROR: $e");
      return "";
    }
  }
}