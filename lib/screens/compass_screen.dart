import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:sensors_plus/sensors_plus.dart';
import '../models/drop.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../theme/rm_theme.dart';
import 'drop_detail_screen.dart';

/// A simple magnetometer-based compass that also points toward the
/// nearest locked drop, so it can stand in for "walk this way" guidance
/// now that the dedicated AR/Map tabs are gone.
class CompassScreen extends StatefulWidget {
  CompassScreen({super.key});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  StreamSubscription<MagnetometerEvent>? _compassSub;
  StreamSubscription<geo.Position>? _positionSub;
  double _heading = 0;
  geo.Position? _position;
  List<Drop> _nearbyLocked = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _compassSub = magnetometerEventStream().listen((event) {
      final heading = math.atan2(event.y, event.x) * (180 / math.pi);
      if (mounted) setState(() => _heading = (heading + 360) % 360);
    });

    try {
      final position =
          await LocationService.instance.getCurrentPosition();
      if (mounted) setState(() => _position = position);
      await _fetchNearby(position);

      _positionSub = LocationService.instance.watchPosition().listen((pos) {
        if (mounted) setState(() => _position = pos);
        _fetchNearby(pos);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchNearby(geo.Position position) async {
    try {
      final drops = await SupabaseService.instance.fetchNearbyDrops(
        lat: position.latitude,
        lng: position.longitude,
      );
      if (mounted) {
        setState(() =>
            _nearbyLocked = drops.where((d) => !d.isUnlocked).toList());
      }
    } catch (_) {}
  }

  /// Bearing from the current position to a target lat/lng, in degrees
  /// from true north — the classic great-circle initial bearing formula.
  double _bearingTo(double lat1, double lng1, double lat2, double lng2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaLambda = (lng2 - lng1) * math.pi / 180;
    final y = math.sin(deltaLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(deltaLambda);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }

  Drop? get _nearestLocked =>
      _nearbyLocked.isEmpty ? null : _nearbyLocked.first;

  @override
  Widget build(BuildContext context) {
    final target = _nearestLocked;
    double? targetBearing;
    if (target != null &&
        _position != null &&
        target.dropLat != null &&
        target.dropLng != null) {
      targetBearing = _bearingTo(
        _position!.latitude,
        _position!.longitude,
        target.dropLat!,
        target.dropLng!,
      );
    }

    return Scaffold(
      backgroundColor: RMColors.background,
      appBar: AppBar(
        title: Text('Compass'),
        backgroundColor: RMColors.background,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: RMColors.primary))
          : SafeArea(
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: RMColors.textSecondary)),
                    ),
                  Expanded(
                    child: Center(
                      child: _CompassRose(
                        heading: _heading,
                        targetBearing: targetBearing,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, 0, 24, 28),
                    child: target == null
                        ? Text(
                            'No locked drops nearby right now.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: RMColors.textSecondary),
                          )
                        : GestureDetector(
                            onTap: () {
                              if (_position == null) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => DropDetailScreen(
                                    drop: target,
                                    currentLat: _position!.latitude,
                                    currentLng: _position!.longitude,
                                  ),
                                ),
                              );
                            },
                            child: Column(
                              children: [
                                Text(
                                  'Nearest locked drop',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  target.distanceLabel,
                                  style: TextStyle(
                                    color: RMColors.primary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The rose itself: a fixed amber "you" arrow at the top, a rotating
/// dial of cardinal directions, and — if a target bearing is known — a
/// violet needle pointing toward the nearest locked drop.
class _CompassRose extends StatelessWidget {
  final double heading;
  final double? targetBearing;

  const _CompassRose({required this.heading, this.targetBearing});

  @override
  Widget build(BuildContext context) {
    const size = 260.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: RMColors.surface,
              border: Border.all(color: RMColors.border, width: 1.5),
            ),
          ),
          // Rotating dial with N/E/S/W — rotates opposite the heading
          // so the labeled direction always faces the way it actually is.
          Transform.rotate(
            angle: -heading * math.pi / 180,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _cardinal('N', 0, size, RMColors.textPrimary),
                  _cardinal('E', 90, size, RMColors.textSecondary),
                  _cardinal('S', 180, size, RMColors.textSecondary),
                  _cardinal('W', 270, size, RMColors.textSecondary),
                  if (targetBearing != null)
                    Transform.rotate(
                      angle: targetBearing! * math.pi / 180,
                      child: Align(
                        alignment: Alignment(0, -0.62),
                        child: Icon(Icons.navigation_rounded,
                            color: RMColors.primary, size: 30),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Fixed "you are here" pointer — always points up (device-forward).
          Icon(Icons.navigation_rounded, color: RMColors.accent, size: 22),
        ],
      ),
    );
  }

  Widget _cardinal(String label, double angleDeg, double size, Color color) {
    return Transform.rotate(
      angle: angleDeg * math.pi / 180,
      child: Align(
        alignment: Alignment(0, -0.86),
        child: Transform.rotate(
          angle: -angleDeg * math.pi / 180,
          child: Text(
            label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w800, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
