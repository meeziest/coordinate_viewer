import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:mizu_one/custom_image_painter/lib/image_painter.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_windows/path_provider_windows.dart' as path_provider_windows;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Coordinates viewer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var _imageKey = GlobalKey<ImagePainterState>();
  File? _fileImage;
  Offset _startedPosition = const Offset(0.00, 0.00);
  Offset _endedPosition = const Offset(0.00, 0.00);
  List<CoordinateInfo> _recsHistory = [];
  CoordinateInfo _recInfo = CoordinateInfo.empty();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Expanded(
              flex: 3,
              child: _fileImage != null
                  ? ImagePainter.file(
                      key: _imageKey,
                      _fileImage!,
                      initialPaintMode: PaintMode.rect,
                      customFunctionBack: () => _onBack(),
                      customFunctionClose: () => _onClose(),
                      onTapStart: (details) => _onFirstTap(details),
                      onTapEnd: (details) => _onSecondTap(details),
                      controlsAtTop: true,
                    )
                  : const Center(child: Text('no image picked'))),
          Expanded(
              flex: 1,
              child: Material(
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CoordinateDataWidget(
                            name: 'start point dx: ', data: _recInfo.dx1.toString()),
                        CoordinateDataWidget(
                            name: 'start point dy: ', data: _recInfo.dy1.toString()),
                        CoordinateDataWidget(name: 'end point dx: ', data: _recInfo.dx2.toString()),
                        CoordinateDataWidget(name: 'end point dy: ', data: _recInfo.dy2.toString()),
                        const Divider(),
                        Column(
                          children: [
                            CoordinateDataWidget(name: 'width: ', data: _recInfo.width.toString()),
                            CoordinateDataWidget(
                                name: 'height: ', data: _recInfo.height.toString()),
                            CoordinateDataWidget(
                                name: 'midpoint dx: ', data: _recInfo.midpointX.toString()),
                            CoordinateDataWidget(
                                name: 'midpoint dy: ', data: _recInfo.midpointY.toString()),
                          ],
                        ),
                        if (_fileImage != null)
                          ElevatedButton(
                              onPressed: () => _downloadFile(),
                              child: const SizedBox(
                                width: double.infinity,
                                child: Text('Download'),
                              ))
                      ],
                    ),
                  ))),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickFile(),
        tooltip: 'File picker',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }

  void _onFirstTap(Offset details) {
    setState(() {
      _startedPosition = details;
      _recInfo.dx1 = details.dx;
      _recInfo.dy1 = details.dy;
    });
  }

  void _onSecondTap(Offset details) {
    setState(() {
      _endedPosition = details;
      _recInfo.dx2 = details.dx;
      _recInfo.dy2 = details.dy;
      _computeWidth();
      _computeHeight();
      _computeMidpointX();
      _computeMidpointY();
      _recsHistory.add(CoordinateInfo.clone(_recInfo));
    });
  }

  void _onBack() {
    setState(() {
      _recsHistory.removeLast();
      if (_recsHistory.isNotEmpty) {
        _recInfo = _recsHistory.last;
      } else {
        _recInfo = CoordinateInfo.empty();
      }
    });
  }

  void _onClose() {
    setState(() {
      _startedPosition = const Offset(0, 0);
      _endedPosition = const Offset(0, 0);
      _recsHistory.clear();
    });
  }

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String? mimeStr = lookupMimeType(file.path);
      if (mimeStr != null) {
        var fileType = mimeStr.split('/');
        bool isImage = false;
        setState(() {
          isImage = fileType.first == 'image';
        });
        if (isImage && !(await _checkImageCorrupted(file))) {
          setState(() {
            _imageKey = GlobalKey<ImagePainterState>();
            _fileImage = file;
            _recsHistory.clear();
            _recInfo = CoordinateInfo.empty();
          });
        }
      }
    }
  }

  void _downloadFile() async {
    Uint8List? byteArray = await _imageKey.currentState?.exportImage();
    String? savePathDirectory = await _getWindowsDownloadsDirectory();
    if (savePathDirectory != null && byteArray != null && _fileImage != null) {
      String name = path.basenameWithoutExtension(_fileImage!.path);
      String ext = path.extension(_fileImage!.path);
      String fileName = await _getNumericalFileName(name, ext, savePathDirectory);
      await FileSaver.instance.saveFile(
        fileName,
        byteArray,
        ext,
      );
    }
  }

  Future<String> _getNumericalFileName(String filenameFrom, String ext, String downloadPath) async {
    String checkPath = [
      downloadPath,
      [filenameFrom, ext].join('.')
    ].join('/');
    bool isFileExists = await File(checkPath).exists();
    int count = 0;
    while (isFileExists) {
      count++;
      checkPath = [
        downloadPath,
        ['$filenameFrom($count)', ext].join('.')
      ].join('/');
      isFileExists = await File(checkPath).exists();
    }
    if (count > 0) {
      filenameFrom = [filenameFrom, '($count)'].join();
    }
    return filenameFrom;
  }

  Future<String?> _getWindowsDownloadsDirectory() async {
    String? downloadPath = '';
    try {
      if (Platform.isWindows) {
        path_provider_windows.PathProviderWindows pathWindows =
            path_provider_windows.PathProviderWindows();
        downloadPath = await pathWindows.getDownloadsPath();
        return downloadPath;
      }
    } catch (e) {
      //skip
    }
    return null;
  }

  Future<bool> _checkImageCorrupted(File file) async {
    final Uint8List fileBytes = await file.readAsBytes();
    img.Image image = img.Image(0, 0);
    try {
      await instantiateImageCodec(fileBytes);
      image = img.decodeImage(fileBytes.toList())!;
      image.getBytes();
      return false;
    } catch (e) {
      return true;
    }
  }

  void _computeWidth() {
    setState(() {
      _recInfo.width = (_startedPosition.dx - _endedPosition.dx).abs();
    });
  }

  void _computeHeight() {
    setState(() {
      _recInfo.height = (_startedPosition.dy - _endedPosition.dy).abs();
    });
  }

  void _computeMidpointX() {
    setState(() {
      _recInfo.midpointX = ((_startedPosition.dx + _endedPosition.dx) / 2).abs();
    });
  }

  void _computeMidpointY() {
    setState(() {
      _recInfo.midpointY = ((_startedPosition.dy + _endedPosition.dy) / 2).abs();
    });
  }
}

class CoordinateInfo {
  double dx1;
  double dy1;
  double dx2;
  double dy2;
  double width;
  double height;
  double midpointX;
  double midpointY;

  CoordinateInfo(
      {required this.dx1,
      required this.dy1,
      required this.dx2,
      required this.dy2,
      required this.width,
      required this.height,
      required this.midpointX,
      required this.midpointY});

  CoordinateInfo.clone(CoordinateInfo info)
      : this(
            dx1: info.dx1,
            dx2: info.dx2,
            dy1: info.dy1,
            dy2: info.dy2,
            height: info.height,
            width: info.width,
            midpointX: info.midpointX,
            midpointY: info.midpointY);

  CoordinateInfo.empty()
      : this(dx1: 0, dy1: 0, dx2: 0, dy2: 0, width: 0, height: 0, midpointX: 0, midpointY: 0);

  @override
  String toString() {
    return '${width.toString()} ${height.toString()}';
  }
}

class CoordinateDataWidget extends StatelessWidget {
  final String name;
  final String data;

  const CoordinateDataWidget({Key? key, required this.name, required this.data}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(name),
        Expanded(
          child: TextField(
            controller: TextEditingController(text: data),
            decoration: const InputDecoration(
              border: InputBorder.none,
            ),
            readOnly: true,
          ),
        ),
      ],
    );
  }
}
