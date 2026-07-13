import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../models/drop.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import 'drop_detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  geo.Position? _position;
  List<Drop> _drops = [];
  StreamSubscription<geo.Position>? _positionSub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    MapboxOptions.setAccessToken(dotenv.env['MAPBOX_ACCESS_TOKEN']!);
    _initLocation();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final position = await LocationService.instance.getCurrentPosition();
      setState(() => _position = position);
      await _loadDrops(position);

      _positionSub = LocationService.instance.watchPosition().listen((pos) {
        setState(() => _position = pos);
      });
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _loadDrops(geo.Position position) async {
    try {
      final drops = await SupabaseService.instance.fetchNearbyDrops(
        lat: position.latitude,
        lng: position.longitude,
        radiusM: 10000,
      );
      setState(() => _drops = drops);
      if (_mapboxMap != null && _ready) {
        await _updateDropPins();
      }
    } catch (e) {
      debugPrint('Drops load error: $e');
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    await mapboxMap.gestures.updateSettings(
      GesturesSettings(rotateEnabled: false, pitchEnabled: false),
    );

    await mapboxMap.logo.updateSettings(LogoSettings(enabled: false));
    await mapboxMap.attribution
        .updateSettings(AttributionSettings(enabled: false));

    await mapboxMap.location.updateSettings(LocationComponentSettings(
      enabled: true,
      pulsingEnabled: true,
      pulsingColor: 0xFF6C4FF6,
    ));

    setState(() => _ready = true);
    await _setupDropLayers();

    if (_position != null) {
      await _updateDropPins();
      await _flyToUser();
    }
  }

  Future<void> _setupDropLayers() async {
    final map = _mapboxMap;
    if (map == null) return;

    await map.style.addSource(GeoJsonSource(
      id: 'drops-source',
      data: json.encode(_buildGeoJson([])),
    ));

    await map.style.addLayer(CircleLayer(
      id: 'drops-locked',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], false],
      circleRadius: 12.0,
      circleColor: 0xFF9E9E9E,
      circleStrokeWidth: 2.0,
      circleStrokeColor: 0xFFFFFFFF,
    ));

    await map.style.addLayer(CircleLayer(
      id: 'drops-unlocked',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], true],
      circleRadius: 14.0,
      circleColor: 0xFF6C4FF6,
      circleStrokeWidth: 2.0,
      circleStrokeColor: 0xFFFFFFFF,
    ));

    await map.style.addLayer(SymbolLayer(
      id: 'drops-locked-icon',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], false],
      textField: '🔒',
      textSize: 10.0,
      textAllowOverlap: true,
    ));

    // Register tap listener
    map.onMapTapListener = _handleMapTap;
  }

  void _handleMapTap(MapContentGestureContext context) async {
    final map = _mapboxMap;
    final pos = _position;
    if (map == null || pos == null) return;

    final features = await map.queryRenderedFeatures(
      RenderedQueryGeometry.fromScreenCoordinate(context.touchPosition),
      RenderedQueryOptions(layerIds: ['drops-locked', 'drops-unlocked']),
    );

    if (features.isEmpty) return;

    // properties is Object? — cast safely to Map
    final rawProps = features.first?.queriedFeature.feature['properties'];
    if (rawProps == null) return;
    final props = rawProps as Map<Object?, Object?>;

    final dropId = props['id']?.toString();
    if (dropId == null) return;

    Drop? drop;
    try {
      drop = _drops.firstWhere((d) => d.id == dropId);
    } catch (_) {
      return;
    }

    if (!mounted) return;
    await Navigator.of(this.context).push(
      MaterialPageRoute(
        builder: (_) => DropDetailScreen(
          drop: drop!,
          currentLat: pos.latitude,
          currentLng: pos.longitude,
        ),
      ),
    );
    await _loadDrops(pos);
  }

  Future<void> _updateDropPins() async {
    final map = _mapboxMap;
    if (map == null || !_ready) return;
    try {
      await map.style.setStyleSourceProperty(
        'drops-source',
        'data',
        json.encode(_buildGeoJson(_drops)),
      );
    } catch (e) {
      debugPrint('Pin update error: $e');
    }
  }

  Map<String, dynamic> _buildGeoJson(List<Drop> drops) {
    return {
      'type': 'FeatureCollection',
      'features': drops
          .where((d) => d.dropLat != null && d.dropLng != null)
          .map((d) => {
                'type': 'Feature',
                'geometry': {
                  'type': 'Point',
                  'coordinates': [d.dropLng!, d.dropLat!],
                },
                'properties': {
                  'id': d.id,
                  'unlocked': d.isUnlocked,
                  'caption': d.caption ?? '',
                  'distance': d.distanceM,
                },
              })
          .toList(),
    };
  }

  Future<void> _flyToUser() async {
    final map = _mapboxMap;
    final pos = _position;
    if (map == null || pos == null) return;

    await map.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(pos.longitude, pos.latitude),
        ),
        zoom: 15.0,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _position;
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            onMapCreated: _onMapCreated,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(
                  pos?.longitude ?? 36.8219,
                  pos?.latitude ?? -1.2921,
                ),
              ),
              zoom: 14.0,
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_drops.length} drops nearby',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              onPressed: _flyToUser,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
