import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:conductor_app/utils/location.dart';
import 'dart:async';
import 'dart:async';
import 'package:logger/logger.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage>
    with AutomaticKeepAliveClientMixin<MapPage> {
  @override
  bool get wantKeepAlive => true; // Keeps the state alive

  List<dynamic>? tours;
  double latitude = 0.0;
  double longitude = 0.0;

  // Kathmandu coordinates
  double sourceLatitude = 27.7172;
  double sourceLongitude = 85.3240;

// Bharatpur coordinates
  double destinationLatitude = 27.6766;
  double destinationLongitude = 84.4322;

  bool _locationFetched = false;
  double scale = 1.0;
  MapController mapController = MapController();

  //all urls
  final String baseUrl = dotenv.env['SITE_URL'] ?? '';
  String? tourSD;
  String? token;

  // Track the active bus for route display
  int? activeBusIndex;
  List<LatLng> routePoints = [];

  @override
  void initState() {
    super.initState();
    _initializeVariale();
    _updateBusPosition();
    _getCurrentLocation();
  }

  void _initializeVariale() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    token = prefs.getString('auth_token');
  }

  void _getCurrentLocation() async {
    Position position = await determinePosition();
    setState(() {
      latitude = position.latitude;
      longitude = position.longitude;
      _locationFetched = true;
    });
    mapController.mapEventStream.listen((event) {
      if (event is MapEventScrollWheelZoom ||
          event is MapEventScrollWheelZoom ||
          event is MapEventRotate) {
        setState(() {
          scale = 1 * mapController.camera.zoom * 0.15;
        });
      }
    });
  }

  Future<void> fetchRoute(LatLng source, LatLng destination) async {
    final apiKey =
        '5b3ce3597851110001cf6248966817b9279641689b1420ce56329a55'; // Replace with your API key
    final url =
        'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$apiKey&start=${source.longitude},${source.latitude}&end=${destination.longitude},${destination.latitude}';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coordinates = data['features'][0]['geometry']['coordinates'];

        setState(() {
          routePoints =
              coordinates.map((coord) => LatLng(coord[1], coord[0])).toList();
        });
      } else {
        Logger().e('Failed to fetch route: ${response.body}');
      }
    } catch (e) {
      Logger().e('Error fetching route: $e');
    }
  }

  void _updateBusPosition() async {
    final String toursURL = '$baseUrl/api/all-active-tour/';

    final response = await http.get(Uri.parse(toursURL), headers: {
      'Authorization': 'Token $token',
    });

    if (response.statusCode == 200) {
      setState(() {
        tours = jsonDecode(response.body)['data'];
      });
    } else {
      Logger().e('Failed to load tours');
    }

    Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final response = await http.get(Uri.parse(toursURL), headers: {
        'Authorization': 'Token $token',
      });

      if (response.statusCode == 200) {
        setState(() {
          tours = jsonDecode(response.body)['data'];
        });
      } else {
        print('Failed to load tours');
      }
    });
  }

  void _onBusClicked(int index, LatLng busPosition, int id) async {
    tourSD = '$baseUrl/api/tour/$id/source-destination-coords/';

    if (index == activeBusIndex) {
      // If the same bus is clicked, deactivate the route
      setState(() {
        activeBusIndex = null;
        routePoints = [];
      });
    } else {
      // If a different bus is clicked, fetch the route
      setState(() {
        activeBusIndex = index;
      });
      // Use your desired destination here
      final response = await http.get(Uri.parse(tourSD.toString()), headers: {
        'Authorization': 'Token $token',
      });

      final responseData = json.decode(response.body);
      Logger().i(responseData);
      LatLng source = LatLng(responseData['source']['latitude'],
          responseData['source']['longitude']);
      LatLng destination = LatLng(responseData['destination']['latitude'],
          responseData['destination']['longitude']);
      fetchRoute(source, destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Stack(
        children: [
          if (_locationFetched)
            FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: LatLng(latitude, longitude),
                initialZoom: 8,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/bright/{z}/{x}/{y}.png?key=ouwqfQklzvtVUJLrsxI6',
                  userAgentPackageName: 'com.example.app',
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: FloatingActionButton(
                    onPressed: () {
                      // _getCurrentLocation();
                      mapController.rotate(0);
                    },
                    child: Icon(Icons.navigation),
                  ),
                ),
                MarkerLayer(markers: [
                  for (int i = 0; i < (tours?.length ?? 0); i++)
                    Marker(
                      point: LatLng(
                        double.parse(tours![i]['latitude']),
                        double.parse(tours![i]['longitude']),
                      ),
                      child: GestureDetector(
                        onTap: () => {
                          _onBusClicked(
                              i,
                              LatLng(
                                double.parse(tours![i]['latitude']),
                                double.parse(tours![i]['longitude']),
                              ),
                              tours![i]['id'])
                        },
                        child: Transform.scale(
                          scale: scale,
                          child: Transform.rotate(
                            angle: double.parse(tours![i]['heading']),
                            child: Image(
                              image: AssetImage('./assets/bus.png'),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
                if (routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: routePoints,
                        strokeWidth: 4.0,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                if (routePoints.isNotEmpty)
                  MarkerLayer(markers: [
                    Marker(
                      point: routePoints.first,
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                      ),
                    ),
                    Marker(
                      point: routePoints.last,
                      child: Icon(
                        Icons.location_on,
                        color: Colors.green,
                      ),
                    ),
                  ]),
              ],
            )
          else
            Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
