class POI {
  final String name;
  final String category;
  final String type;
  final String? cuisine;
  final String? shopType;
  final double lat;
  final double lon;
  final double? distance;

  POI({
    required this.name,
    required this.category,
    required this.type,
    this.cuisine,
    this.shopType,
    required this.lat,
    required this.lon,
    this.distance,
  });

  factory POI.fromJson(Map<String, dynamic> json) {
    // Helper to safely get tags
    final tags = json['tags'] ?? {};
    
    // Determine category (logic from openstreetmap.js)
    String category = 'landmark';
    if (tags['tourism'] != null) category = 'attraction';
    else if (tags['historic'] != null) category = 'historic';
    else if (tags['amenity'] == 'restaurant' || tags['amenity'] == 'cafe' || tags['amenity'] == 'bar') category = 'food';
    else if (tags['shop'] != null) category = 'shop';
    else if (tags['leisure'] != null) category = 'recreation';
    else if (tags['amenity'] != null) category = 'amenity';

    // Determine type
    String type = tags['tourism'] ??
                  tags['historic'] ??
                  tags['amenity'] ??
                  tags['shop'] ??
                  tags['leisure'] ??
                  'landmark';

    return POI(
      name: tags['name'] ?? 'Unknown',
      category: category,
      type: type,
      cuisine: tags['cuisine'],
      shopType: tags['shop'],
      lat: json['lat'] ?? json['center']['lat'],
      lon: json['lon'] ?? json['center']['lon'],
      distance: json['distance'], // This will be calculated locally if needed or passed in
    );
  }
  
  POI copyWithDistance(double distance) {
    return POI(
      name: name,
      category: category,
      type: type,
      cuisine: cuisine,
      shopType: shopType,
      lat: lat,
      lon: lon,
      distance: distance,
    );
  }

  String get displayName {
    String label = name;
    if (category == 'food' && cuisine != null) {
      label += ' ($cuisine $type)';
    } else if (category == 'shop' && shopType != null) {
      label += ' ($shopType)';
    } else if (type != category) {
      label += ' ($type)';
    }
    return label;
  }
}
