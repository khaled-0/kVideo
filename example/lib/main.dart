import 'package:flutter/material.dart';
import 'package:kvideo/kvideo.dart';

final controller = PlayerController(androidViewMode: AndroidViewMode.texture);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final urls = [
    "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
  ];
  controller.initialize().then((_) {
    controller.play(
      Media(
        url: urls[0],
        subtitles: [
          "https://gist.githubusercontent.com/matibzurovski/d690d5c14acbaa399e7f0829f9d6888e/raw/63578ca30e7430be1fa4942d4d8dd599f78151c7/example.srt",
        ],
      ),
    );
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
            Align(
              child: ValueListenableBuilder(
                valueListenable: controller.state.error,
                builder: (context, value, child) {
                  return Text(value ?? "");
                },
              ),
            ),
            FutureBuilder(
              future: controller.getTracks(),
              builder: (context, snapshot) {
                return ListView(
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
              bottom: 8,
              right: 40,
              child: ElevatedButton(
                onPressed: () {
                  controller.enterPiPMode();
                },
                child: Text("PIP"),
              ),
            ),

            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () {
                      controller.setFit(BoxFit.cover);
                    },
                    child: Text("FILL"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        show = false;
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              Hero(tag: "v", child: widget.child),
                        ),
                      ).whenComplete(() {
                        setState(() {
                          show = true;
                        });
                      });
                    },
                    child: Text("Hero"),
                  ),

                  FilledButton(
                    onPressed: () {
                      controller.setFit(BoxFit.contain);
                    },
                    child: Text("FIT"),
                  ),
                ],
              ),
            ),

            Positioned(
              bottom: 8,
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

            Positioned(
              top: _offset.dy,
              left: _offset.dx,
              child: SizedBox(
                height: 200,
                width: 200,
                child: Hero(
                  tag: "v",
                  child: show ? Center(child: widget.child) : SizedBox(),
                ),
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
