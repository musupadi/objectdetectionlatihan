import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  MyApp(this.cameras);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: LiveDetection(cameras: cameras),
    );
  }
}

class LiveDetection extends StatefulWidget {
  final List<CameraDescription> cameras;

  LiveDetection({required this.cameras});

  @override
  _LiveDetectionState createState() => _LiveDetectionState();
}

class _LiveDetectionState extends State<LiveDetection> {
  CameraController? cameraController;
  bool isDetecting = false;
  var _recognitions = [];
  String result = '';

  @override
  void initState() {
    super.initState();
    loadModel();
    initializeCamera();
  }

  Future<void> loadModel() async {
    await Tflite.loadModel(
      model: "assets/model_unquant.tflite",
      labels: "assets/labels.txt",
    );
  }

  void initializeCamera() {
    cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
    );

    cameraController!.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});

      cameraController!.startImageStream((CameraImage img) {
        if (!isDetecting) {
          isDetecting = true;

          detectImage(img);
        }
      });
    });
  }

  Future<void> detectImage(CameraImage image) async {
    int startTime = DateTime.now().millisecondsSinceEpoch;

    var recognitions = await Tflite.runModelOnFrame(
      bytesList: image.planes.map((plane) {
        return plane.bytes;
      }).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      numResults: 6,
      threshold: 0.05,
      imageMean: 127.5,
      imageStd: 127.5,
    );

    setState(() {
      _recognitions = recognitions!;
      result = recognitions.isNotEmpty ? recognitions.toString() : "No object detected";
    });

    int endTime = DateTime.now().millisecondsSinceEpoch;
    print("Inference took ${endTime - startTime}ms");
    isDetecting = false;
  }

  @override
  void dispose() {
    cameraController?.dispose();
    Tflite.close();
    super.dispose();
  }

  // Fungsi untuk menggambar kotak berdasarkan deteksi objek
  List<Widget> renderBoxes(Size screen) {
    if (_recognitions.isEmpty) return [];

    return _recognitions.map<Widget>((recog) {
      // Pastikan rect tidak null dan memiliki data yang valid
      if (recog["rect"] == null || recog["rect"]["x"] == null || recog["rect"]["y"] == null || recog["rect"]["w"] == null || recog["rect"]["h"] == null) {
        return Container();
      }

      // Ambil nilai confidence
      double confidence = recog["confidenceInClass"] ?? 0.0;

      // Hanya tampilkan jika confidence > 80%
      if (confidence * 100 < 80) {
        return Container();
      }

      // Mengambil nilai x, y, w, dan h dari hasil deteksi
      var _x = recog["rect"]["x"];
      var _y = recog["rect"]["y"];
      var _w = recog["rect"]["w"];
      var _h = recog["rect"]["h"];

      // Pastikan bahwa x, y, w, dan h berada dalam rentang 0 hingga 1
      if (_x < 0 || _y < 0 || _w < 0 || _h < 0 || _x > 1 || _y > 1 || _w > 1 || _h > 1) {
        return Container();
      }

      // Mengatur skala sesuai ukuran layar
      var scaleW = screen.width;
      var scaleH = screen.height;

      return Positioned(
        left: _x * scaleW,
        top: _y * scaleH,
        width: _w * scaleW,
        height: _h * scaleH,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red, width: 2),
          ),
          child: Text(
            "${recog["detectedClass"] ?? 'Unknown'} ${(confidence * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              color: Colors.white,
              backgroundColor: Colors.red,
              fontSize: 14,
            ),
          ),
        ),
      );
    }).toList();
  }




  @override
  Widget build(BuildContext context) {
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return Center(child: CircularProgressIndicator());
    }

    var size = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(title: Text('Live Detection')),
      body: Stack(
        children: <Widget>[
          CameraPreview(cameraController!),
          Stack(
            children: renderBoxes(size),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: EdgeInsets.all(10),
              color: Colors.black.withOpacity(0.5),
              child: Text(
                result,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
