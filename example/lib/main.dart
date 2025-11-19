import 'package:flutter/material.dart';
import 'package:kvideo/kvideo.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final urls = [
    "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
  ];
  final controller = PlayerController(androidViewMode: AndroidViewMode.texture);
  controller.initialize().then((_) {
    controller.play(Media(url: urls[0]));
  });

  // runApp(Center(child: PlayerView(controller)));
  runApp(MaterialApp(home: DesignScreen(child: PlayerView(controller))));
}

class DesignScreen extends StatefulWidget {
  final Widget child;

  const DesignScreen({Key? key, required this.child}) : super(key: key);

  @override
  State<DesignScreen> createState() => _DesignScreenState();
}

class _DesignScreenState extends State<DesignScreen> {
  Offset _offset = Offset.zero;
  bool show = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("kVideo")),
      body: GestureDetector(
        child: Stack(
          children: [
            Positioned(top: 100, child: Text("Behind")),
            Positioned(
              top: _offset.dy,
              left: _offset.dx,
              child: SizedBox(
                height: 200,
                width: 200,
                child: Hero(
                  tag: "v",
                  child: ClipRRect(
                    borderRadius: BorderRadiusGeometry.circular(100),
                    child: show ? widget.child : SizedBox(),
                  ),
                ),
              ),
            ),

            Positioned(bottom: 100, child: Text("Above")),

            Center(
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    show = false;
                  });

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => Hero(tag: "v", child: widget.child),
                    ),
                  ).whenComplete(() {
                    setState(() {
                      show = true;
                    });
                  });
                },
                child: Text("Hero"),
              ),
            ),
          ],
        ),
        onPanUpdate: (details) {
          setState(() {
            _offset = Offset(
              _offset.dx + details.delta.dx,
              _offset.dy + details.delta.dy,
            );
          });
        },
      ),
    );
  }
}
