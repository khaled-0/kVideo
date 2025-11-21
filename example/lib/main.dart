import 'package:flutter/material.dart';
import 'package:kvideo/kvideo.dart';

final controller = PlayerController(androidViewMode: AndroidViewMode.texture);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final urls = [
    "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
  ];
  controller.initialize().then((_) {
    controller.play(Media(url: urls[0]));
  });

  // runApp(Center(child: PlayerView(controller)));
  runApp(MaterialApp(home: PlayerScreen(child: PlayerView(controller))));
}

class PlayerScreen extends StatefulWidget {
  final Widget child;

  const PlayerScreen({super.key, required this.child});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
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
                height: 400,
                width: 400,
                child: Hero(
                  tag: "v",
                  child: ClipRRect(
                    borderRadius: BorderRadiusGeometry.circular(100),
                    child: show ? Center(child: widget.child) : SizedBox(),
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

            FutureBuilder(
              future: controller.getTracks(),
              builder: (context, snapshot) {
                return Column(
                  children: [
                    TextButton(
                      child: Text("Auto"),
                      onPressed: () {
                        controller.setTrackPreference(null);
                      },
                    ),
                    for (final track in snapshot.data ?? <TrackData>[])
                      TextButton(
                        child: Text(
                          "${track.type} ${track.height} ${track.label} ${track.language} ${track.bitrate}",
                        ),
                        onPressed: () {
                          controller.setTrackPreference(track);
                        },
                      ),
                  ],
                );
              },
            ),

            Positioned(
              bottom: 100,
              right: 40,
              child: ElevatedButton(
                onPressed: () {
                  controller.enterPiPMode();
                },
                child: Text("PIP"),
              ),
            ),

            Positioned(
              bottom: 100,
              left: 40,
              child: ElevatedButton(
                onPressed: () {
                  controller.play(
                    Media(
                      url:
                          "https://stream.mux.com/3x5wDUHxkd8NkEfspLUK3OpSQEJe3pom.m3u8?redundant_streams=true",
                    ),
                  );
                },
                child: Text("MUX"),
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
