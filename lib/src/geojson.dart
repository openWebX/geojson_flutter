import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:geopoint/geopoint.dart';
import 'package:geodesy/geodesy.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:iso/iso.dart';
import 'models.dart';
import 'deserializers.dart';
import 'exceptions.dart';

/// The main geojson class
class GeoJson {
  /// Default constructor
  GeoJson()
      : features = <GeoJsonFeature>[],
        points = <GeoJsonPoint>[],
        multipoints = <GeoJsonMultiPoint>[],
        lines = <GeoJsonLine>[],
        multilines = <GeoJsonMultiLine>[],
        polygons = <GeoJsonPolygon>[],
        multipolygons = <GeoJsonMultiPolygon>[],
        _processedFeaturesController = StreamController<GeoJsonFeature>(),
        _processedPointsController = StreamController<GeoJsonPoint>(),
        _processedMultipointsController = StreamController<GeoJsonMultiPoint>(),
        _processedLinesController = StreamController<GeoJsonLine>(),
        _processedMultilinesController = StreamController<GeoJsonMultiLine>(),
        _processedPolygonsController = StreamController<GeoJsonPolygon>(),
        _processedMultipolygonsController =
            StreamController<GeoJsonMultiPolygon>(),
        _endSignalController = StreamController<bool>();

  /// All the features
  List<GeoJsonFeature> features;

  /// All the points
  List<GeoJsonPoint> points;

  /// All the multipoints
  List<GeoJsonMultiPoint> multipoints;

  /// All the lines
  List<GeoJsonLine> lines;

  /// All the multilines
  List<GeoJsonMultiLine> multilines;

  /// All the polygons
  List<GeoJsonPolygon> polygons;

  /// All the multipolygons
  List<GeoJsonMultiPolygon> multipolygons;

  StreamController<GeoJsonFeature> _processedFeaturesController;
  StreamController<GeoJsonPoint> _processedPointsController;
  StreamController<GeoJsonMultiPoint> _processedMultipointsController;
  StreamController<GeoJsonLine> _processedLinesController;
  StreamController<GeoJsonMultiLine> _processedMultilinesController;
  StreamController<GeoJsonPolygon> _processedPolygonsController;
  StreamController<GeoJsonMultiPolygon> _processedMultipolygonsController;
  StreamController<bool> _endSignalController;

  /// Stream of features that are coming in as they are parsed
  /// Useful for handing the featues faster if the file is big
  Stream<GeoJsonFeature> get processedFeatures =>
      _processedFeaturesController.stream;

  /// Stream of points that are coming in as they are parsed
  Stream<GeoJsonPoint> get processedPoints => _processedPointsController.stream;

  /// Stream of multipoints that are coming in as they are parsed
  Stream<GeoJsonMultiPoint> get processedMultipoints =>
      _processedMultipointsController.stream;

  /// Stream of lines that are coming in as they are parsed
  Stream<GeoJsonLine> get processedLines => _processedLinesController.stream;

  /// Stream of multilines that are coming in as they are parsed
  Stream<GeoJsonMultiLine> get processedMultilines =>
      _processedMultilinesController.stream;

  /// Stream of polygons that are coming in as they are parsed
  Stream<GeoJsonPolygon> get processedPolygons =>
      _processedPolygonsController.stream;

  /// Stream of multipolygons that are coming in as they are parsed
  Stream<GeoJsonMultiPolygon> get processedMultipolygons =>
      _processedMultipolygonsController.stream;

  /// The stream indicating that the parsing is finished
  /// Use it to dispose the class if not needed anymore after parsing
  Stream<bool> get endSignal => _endSignalController.stream;

  /// Parse the data from a file
  Future<void> parseFile(String path,
      {String nameProperty, bool verbose = false, GeoJsonQuery query}) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw ("The file ${file.path} does not exist");
    }
    String data;
    try {
      data = await file.readAsString();
    } catch (e) {
      throw ("Can not read file $e");
    }
    if (verbose) {
      print("Parsing file ${file.path}");
    }
    await _parse(data,
        nameProperty: nameProperty, verbose: verbose, query: query);
  }

  /// Parse the data
  Future<void> parse(String data,
      {String nameProperty, bool verbose = false}) async {
    return await _parse(data, nameProperty: nameProperty, verbose: verbose);
  }

  Future<void> _parse(String data,
      {String nameProperty, bool verbose, GeoJsonQuery query}) async {
    final finished = Completer<Null>();
    Iso iso;
    iso = Iso(_processFeatures, onDataOut: (dynamic data) {
      if (data is GeoJsonFeature) {
        switch (data.type) {
          case GeoJsonFeatureType.point:
            final item = data.geometry as GeoJsonPoint;
            points.add(item);
            _processedPointsController.sink.add(item);
            break;
          case GeoJsonFeatureType.multipoint:
            final item = data.geometry as GeoJsonMultiPoint;
            multipoints.add(item);
            _processedMultipointsController.sink.add(item);
            break;
          case GeoJsonFeatureType.line:
            final item = data.geometry as GeoJsonLine;
            lines.add(item);
            _processedLinesController.sink.add(item);
            break;
          case GeoJsonFeatureType.multiline:
            final item = data.geometry as GeoJsonMultiLine;
            multilines.add(item);
            _processedMultilinesController.sink.add(item);
            break;
          case GeoJsonFeatureType.polygon:
            final item = data.geometry as GeoJsonPolygon;
            polygons.add(item);
            _processedPolygonsController.sink.add(item);
            break;
          case GeoJsonFeatureType.multipolygon:
            final item = data.geometry as GeoJsonMultiPolygon;
            multipolygons.add(item);
            _processedMultipolygonsController.sink.add(item);
        }
        _processedFeaturesController.sink.add(data);
        features.add(data);
      } else {
        iso.dispose();
        finished.complete();
      }
    }, onError: (dynamic e) {
      print("ERROR $e / ${e.runtimeType}");
      throw (e);
    });
    final dataToProcess = _DataToProcess(
        data: data, nameProperty: nameProperty, verbose: verbose, query: query);
    unawaited(iso.run(<dynamic>[dataToProcess]));
    await finished.future;
    _endSignalController.sink.add(true);
  }

  /// Search a [GeoJsonFeature] by prpperty from a file
  Future<void> searchInFile(String path,
      {@required GeoJsonQuery query,
      String nameProperty,
      bool verbose = false}) async {
    await parseFile(path,
        nameProperty: nameProperty, verbose: verbose, query: query);
  }

  /// Search a [GeoJsonFeature] by prpperty.
  ///
  /// If the string data is not provided the existing features will be used
  /// to search
  Future<void> search(
      {String data,
      @required GeoJsonQuery query,
      String nameProperty,
      bool verbose = false}) async {
    if (data == null && features.isEmpty) {
      throw (ArgumentError("Provide data or parse some to run a search"));
    }
    if (data != null) {
      await _parse(data,
          nameProperty: nameProperty, verbose: verbose, query: query);
    }
  }

  /// Find all the [GeoJsonPoint] located in a [GeoJsonPolygon]
  /// from a list of points
  Future<List<GeoJsonPoint>> geofence(
      {@required GeoJsonPolygon polygon,
      @required List<GeoJsonPoint> points}) async {
    final geodesy = Geodesy();
    final geoFencedPoints = <GeoJsonPoint>[];
    for (final point in points) {
      for (final geoSerie in polygon.geoSeries) {
        if (geodesy.isGeoPointInPolygon(
            point.geoPoint.toLatLng(ignoreErrors: true),
            geoSerie.toLatLng(ignoreErrors: true))) {
          geoFencedPoints.add(point);
        }
      }
    }
    return geoFencedPoints;
  }

  /// Dispose the class when finished using it
  void dispose() {
    _processedFeaturesController.close();
    _processedPointsController.close();
    _processedMultipointsController.close();
    _processedLinesController.close();
    _processedMultilinesController.close();
    _processedPolygonsController.close();
    _processedMultipointsController.close();
    _endSignalController.close();
  }

  static void _processFeatures(IsoRunner iso) {
    final List<dynamic> args = iso.args;
    final dataToProcess = args[0] as _DataToProcess;
    final String data = dataToProcess.data;
    final String nameProperty = dataToProcess.nameProperty;
    final bool verbose = dataToProcess.verbose;
    final GeoJsonQuery query = dataToProcess.query;
    final Map<String, dynamic> decoded =
        json.decode(data) as Map<String, dynamic>;
    final feats = decoded["features"] as List<dynamic>;
    for (final dfeature in feats) {
      final feat = dfeature as Map<String, dynamic>;
      var properties = <String, dynamic>{};
      if (feat.containsKey("properties")) {
        properties = feat["properties"] as Map<String, dynamic>;
      }
      final geometry = feat["geometry"] as Map<String, dynamic>;
      final geomType = geometry["type"].toString();
      GeoJsonFeature feature;
      switch (geomType) {
        case "MultiPolygon":
          feature = GeoJsonFeature<GeoJsonMultiPolygon>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.multipolygon;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.multipolygon) {
                continue;
              }
            }
          }
          feature.geometry = getMultipolygon(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        case "Polygon":
          feature = GeoJsonFeature<GeoJsonPolygon>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.polygon;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.polygon) {
                continue;
              }
            }
          }
          feature.geometry = getPolygon(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        case "MultiLineString":
          feature = GeoJsonFeature<GeoJsonMultiLine>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.multiline;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.multiline) {
                continue;
              }
            }
          }
          feature.geometry = getMultiLine(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        case "LineString":
          feature = GeoJsonFeature<GeoJsonLine>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.line;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.line) {
                continue;
              }
            }
          }
          feature.geometry = getLine(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        case "MultiPoint":
          feature = GeoJsonFeature<GeoJsonMultiPoint>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.multipoint;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.multipoint) {
                continue;
              }
            }
          }
          feature.geometry = getMultiPoint(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        case "Point":
          feature = GeoJsonFeature<GeoJsonPoint>();
          feature.properties = properties;
          feature.type = GeoJsonFeatureType.point;
          if (query != null) {
            if (query.geometryType != null) {
              if (query.geometryType != GeoJsonFeatureType.point) {
                continue;
              }
            }
          }
          feature.geometry = getPoint(
              feature: feature,
              nameProperty: nameProperty,
              coordinates: geometry["coordinates"] as List<dynamic>);
          break;
        default:
          final e = FeatureNotSupported(geomType);
          throw (e);
      }
      if (query != null && properties != null) {
        if (!_checkProperty(properties, query)) {
          continue;
        }
      }
      iso.send(feature);
      if (verbose == true) {
        print("${feature.type} ${feature.geometry.name} : " +
            "${feature.length} points");
      }
    }
    iso.send("end");
  }

  static bool _checkProperty(
      Map<String, dynamic> properties, GeoJsonQuery query) {
    bool isPropertyOk = true;
    if (query.property != null) {
      if (properties.containsKey(query.property)) {
        switch (query.searchType) {
          case GeoSearchType.exact:
            if (properties[query.property] != query.value) {
              isPropertyOk = false;
            }
            break;
          case GeoSearchType.startsWith:
            final prop = properties[query.property] as String;
            if (!prop.startsWith(query.value as String)) {
              isPropertyOk = false;
            }
            break;
          case GeoSearchType.contains:
            final prop = properties[query.property] as String;
            if (!prop.contains(query.value as String)) {
              isPropertyOk = false;
            }
            break;
        }
      }
    }
    return isPropertyOk;
  }
}

class _DataToProcess {
  _DataToProcess(
      {@required this.data,
      @required this.nameProperty,
      @required this.verbose,
      @required this.query});

  final String data;
  final String nameProperty;
  final bool verbose;
  final GeoJsonQuery query;
}
