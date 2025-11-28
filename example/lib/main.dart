import 'package:flutter/material.dart';
import 'package:kvideo/kvideo.dart';

final controller = PlayerController(androidViewMode: AndroidViewMode.texture);
final downloader = DownloadManagerApi();

class EventListener implements DownloadEventListener {
  @override
  void onCompletion(String id, String location) {
    print("Completed: $id $location");
    controller.play(
      Media(
        url: location,
        subtitles: [
          "https://gist.githubusercontent.com/matibzurovski/d690d5c14acbaa399e7f0829f9d6888e/raw/63578ca30e7430be1fa4942d4d8dd599f78151c7/example.srt",
        ],
      ),
    );
  }

  @override
  void onError(String id, String error) {
    print("Error: $id $error");
  }

  @override
  void onProgress(String id, double progress) {
    print("Progress: $id $progress");
  }

  @override
  List<TrackData> requestTrackSelection(List<TrackData> tracks) {
    // TODO: implement requestTrackSelection
    throw UnimplementedError();
  }
}

final urls = [
  "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8",
  "https://stream.mux.com/3x5wDUHxkd8NkEfspLUK3OpSQEJe3pom.m3u8?redundant_streams=true",
  "file:///Users/khaled/Library/Developer/CoreSimulator/Devices/6E752C2C-3292-4A6C-BDC7-7A18E9ADF1DE/data/Containers/Data/Application/E30770F1-DB9D-4477-864B-AEEED0941C98/Library/com.apple.UserManagedAssets.TEmS2h/90DBCC88-C397-4337-989F-4EFFF89E01EC_1361158C02C80F53.movpkg",
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  DownloadEventListener.setUp(EventListener());

  final id = await downloader.download(Media(url: urls[1]));
  print(id);

  // downloader.cancel("C689AC7D-7C26-4BAE-B2D2-420A4E51245F");

  controller.initialize().then((_) {
    // controller.play(
    //   Media(
    //     url: urls[2],
    //     subtitles: [
    //       "https://gist.githubusercontent.com/matibzurovski/d690d5c14acbaa399e7f0829f9d6888e/raw/63578ca30e7430be1fa4942d4d8dd599f78151c7/example.srt",
    //     ],
    //   ),
    // );
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
                      controller.setFit(BoxFitMode.fill);
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
                      controller.setFit(BoxFitMode.fit);
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
                  controller.play(Media(url: urls[1]));
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
