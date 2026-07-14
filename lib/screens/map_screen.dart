import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;
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
  Drop? _selectedDrop;
  bool _loadingRoute = false;

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
      GesturesSettings(rotateEnabled: true, pitchEnabled: false),
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
    await _setupLayers();

    if (_position != null) {
      await _updateDropPins();
      await _flyToUser();
    }
  }

  Future<void> _setupLayers() async {
    final map = _mapboxMap;
    if (map == null) return;

    // ── Drop pins source ──────────────────────────────────────────
    await map.style.addSource(GeoJsonSource(
      id: 'drops-source',
      data: json.encode(_buildDropGeoJson([])),
    ));

    // Locked drops — grey circle
    await map.style.addLayer(CircleLayer(
      id: 'drops-locked',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], false],
      circleRadius: 14.0,
      circleColor: 0xFF757575,
      circleStrokeWidth: 2.5,
      circleStrokeColor: 0xFFFFFFFF,
    ));

    // Unlocked drops — purple circle
    await map.style.addLayer(CircleLayer(
      id: 'drops-unlocked',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], true],
      circleRadius: 14.0,
      circleColor: 0xFF6C4FF6,
      circleStrokeWidth: 2.5,
      circleStrokeColor: 0xFFFFFFFF,
    ));

    // Distance label above each pin
    await map.style.addLayer(SymbolLayer(
      id: 'drops-distance-label',
      sourceId: 'drops-source',
      textField: ['get', 'distance_label'],
      textSize: 11.0,
      textOffset: [0.0, -2.2],
      textColor: 0xFFFFFFFF,
      textHaloColor: 0xFF000000,
      textHaloWidth: 1.5,
      textAllowOverlap: false,
      textIgnorePlacement: false,
    ));

    // Lock icon on locked pins
    await map.style.addLayer(SymbolLayer(
      id: 'drops-lock-icon',
      sourceId: 'drops-source',
      filter: ['==', ['get', 'unlocked'], false],
      textField: '🔒',
      textSize: 10.0,
      textOffset: [0.0, 0.0],
      textAllowOverlap: true,
    ));

    // ── Route source + layer ──────────────────────────────────────
    await map.style.addSource(GeoJsonSource(
      id: 'route-source',
      data: json.encode({'type': 'FeatureCollection', 'features': []}),
    ));

    await map.style.addLayer(LineLayer(
      id: 'route-line',
      sourceId: 'route-source',
      lineColor: 0xFF6C4FF6,
      lineWidth: 5.0,
      lineOpacity: 0.85,
      lineCap: LineCap.ROUND,
      lineJoin: LineJoin.ROUND,
    ));

    // Tap listener
    map.onMapTapListener = _handleMapTap;
  }

  Future<void> _handleMapTap(MapContentGestureContext tapCtx) async {
    final map = _mapboxMap;
    final pos = _position;
    if (map == null || pos == null) return;

    final features = await map.queryRenderedFeatures(
      RenderedQueryGeometry.fromScreenCoordinate(tapCtx.touchPosition),
      RenderedQueryOptions(layerIds: ['drops-locked', 'drops-unlocked']),
    );

    if (features.isEmpty) {
      // Tapped empty area — clear route and selection
      await _clearRoute();
      setState(() => _selectedDrop = null);
      return;
    }

    final rawProps = features.first?.queriedFeature.feature['properties'];
    if (rawProps == null) return;
    final props = rawProps as Map<String, Object?>;
    final dropId = props['id'] as String?;
    if (dropId == null) return;

    try {
      final drop = _drops.firstWhere((d) => d.id == dropId);
      setState(() => _selectedDrop = drop);
      await _drawRoute(pos, drop);
    } catch (_) {}
  }

  /// Fetches the walking route from user to drop using Mapbox Directions API
  /// and draws it on the map.
  Future<void> _drawRoute(geo.Position from, Drop to) async {
    if (to.dropLat == null || to.dropLng == null) return;
    setState(() => _loadingRoute = true);

    try {
      final token = dotenv.env['MAPBOX_ACCESS_TOKEN']!;
      final url = Uri.parse(
        'https://api.mapbox.com/directions/v5/mapbox/walking/'
        '${from.longitude},${from.latitude};'
        '${to.dropLng},${to.dropLat}'
        '?geometries=geojson&overview=full&access_token=$token',
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return;

      final geometry = routes.first['geometry'] as Map<String, dynamic>;

      // Update route source with the returned LineString
      await _mapboxMap?.style.setStyleSourceProperty(
        'route-source',
        'data',
        json.encode({
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'geometry': geometry,
              'properties': {},
            }
          ],
        }),
      );

      // Fit camera to show both user and drop
      await _fitCameraToRoute(from, to);
    } catch (e) {
      debugPrint('Route error: $e');
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  Future<void> _fitCameraToRoute(geo.Position from, Drop to) async {
    final map = _mapboxMap;
    if (map == null || to.dropLat == null || to.dropLng == null) return;

    final minLat = [from.latitude, to.dropLat!].reduce((a, b) => a < b ? a : b);
    final maxLat = [from.latitude, to.dropLat!].reduce((a, b) => a > b ? a : b);
    final minLng = [from.longitude, to.dropLng!].reduce((a, b) => a < b ? a : b);
    final maxLng = [from.longitude, to.dropLng!].reduce((a, b) => a > b ? a : b);

    await map.cameraForCoordinateBounds(
      CoordinateBounds(
        southwest: Point(coordinates: Position(minLng - 0.001, minLat - 0.001)),
        northeast: Point(coordinates: Position(maxLng + 0.001, maxLat + 0.001)),
        infiniteBounds: false,
      ),
      MbxEdgeInsets(top: 80, left: 40, bottom: 200, right: 40),
      null,
      null,
      null,
      null,
    ).then((camera) async {
      await map.flyTo(camera, MapAnimationOptions(duration: 800));
    });
  }

  Future<void> _clearRoute() async {
    await _mapboxMap?.style.setStyleSourceProperty(
      'route-source',
      'data',
      json.encode({'type': 'FeatureCollection', 'features': []}),
    );
  }

  Future<void> _updateDropPins() async {
    final map = _mapboxMap;
    if (map == null || !_ready) return;
    try {
      await map.style.setStyleSourceProperty(
        'drops-source',
        'data',
        json.encode(_buildDropGeoJson(_drops)),
      );
    } catch (e) {
      debugPrint('Pin update error: $e');
    }
  }

  Map<String, dynamic> _buildDropGeoJson(List<Drop> drops) {
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
                  'distance_label': d.distanceLabel,
                  'distance_m': d.distanceM,
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
        center: Point(coordinates: Position(pos.longitude, pos.latitude)),
        zoom: 15.5,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Satellite map style
          MapWidget(
            onMapCreated: _onMapCreated,
            styleUri: MapboxStyles.SATELLITE_STREETS,
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(
                  _position?.longitude ?? 36.8219,
                  _position?.latitude ?? -1.2921,
                ),
              ),
              zoom: 14.0,
            ),
          ),

          // Drop count badge
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

          // Route loading indicator
          if (_loadingRoute)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 6),
                    Text('Finding route...',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // Selected drop bottom sheet
          if (_selectedDrop != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 12)
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _selectedDrop!.isUnlocked
                              ? Icons.lock_open
                              : Icons.lock_outline,
                          color: _selectedDrop!.isUnlocked
                              ? Colors.greenAccent
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedDrop!.isUnlocked
                                ? (_selectedDrop!.caption ?? 'Drop')
                                : 'Locked Drop',
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await _clearRoute();
                            setState(() => _selectedDrop = null);
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Icon(Icons.directions_walk,
                            size: 16, color: Colors.purple),
                        const SizedBox(width: 4),
                        Text(
                          _selectedDrop!.distanceLabel,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Text('by ${_selectedDrop!.creatorUsername}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _position == null
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => DropDetailScreen(
                                          drop: _selectedDrop!,
                                          currentLat: _position!.latitude,
                                          currentLng: _position!.longitude,
                                        ),
                                      ),
                                    ),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open drop'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _loadingRoute || _position == null
                              ? null
                              : () => _drawRoute(_position!, _selectedDrop!),
                          icon: const Icon(Icons.alt_route, size: 18),
                          label: const Text('Route'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Re-center button
          Positioned(
            bottom: _selectedDrop != null ? 180 : 100,
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
