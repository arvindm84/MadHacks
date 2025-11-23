import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../models/poi.dart';

class OSMService {
  final String overpassEndpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<POI>> getNearbyPOIs(double lat, double lon, {double radiusMeters = 100}) async {
    try {
      final query = '''
        [out:json][timeout:25];
        (
            node(around:$radiusMeters,$lat,$lon)["tourism"="attraction"];
            way(around:$radiusMeters,$lat,$lon)["tourism"="attraction"];
            node(around:$radiusMeters,$lat,$lon)["historic"];
            way(around:$radiusMeters,$lat,$lon)["historic"];
            node(around:$radiusMeters,$lat,$lon)["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
            way(around:$radiusMeters,$lat,$lon)["amenity"~"museum|theatre|cinema|library|restaurant|cafe|bar|pub|fast_food"];
            node(around:$radiusMeters,$lat,$lon)["shop"];
            way(around:$radiusMeters,$lat,$lon)["shop"];
            node(around:$radiusMeters,$lat,$lon)["leisure"~"park|playground|garden"];
            way(around:$radiusMeters,$lat,$lon)["leisure"~"park|playground|garden"];
        );
        out body;
        >;
        out skel qt;
      ''';

      final response = await http.post(
        Uri.parse(overpassEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'data=${Uri.encodeComponent(query)}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final elements = data['elements'] as List;

        List<POI> pois = elements
            .where((el) => el['tags'] != null && el['tags']['name'] != null)
            .map((el) => POI.fromJson(el))
            .toList();

        // Calculate distances and sort
        for (var i = 0; i < pois.length; i++) {
          double distance = Geolocator.distanceBetween(lat, lon, pois[i].lat, pois[i].lon);
          pois[i] = pois[i].copyWithDistance(distance);
        }

        pois.sort((a, b) => (a.distance ?? 0).compareTo(b.distance ?? 0));

        return pois;
      } else {
        print('Overpass error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('POI query error: $e');
      return [];
    }
  }
}
