import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPage extends StatefulWidget {
  final File videoFile;

  const VideoPlayerPage({
    super.key,
    required this.videoFile,
  });

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _controller;

  double _playbackSpeed = 1.0;
  final int _fps = 240;

  int _currentFrame = 0;
  int _totalFrames = 0;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        _totalFrames =
            (_controller.value.duration.inMilliseconds * _fps ~/ 1000);
        setState(() {});
        _controller.play();
      });

    _controller.addListener(_updateFrameCount);
  }

  void _updateFrameCount() {
    if (!_controller.value.isInitialized) return;

    final position = _controller.value.position.inMilliseconds;

    setState(() {
      _currentFrame = (position * _fps ~/ 1000);
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  void _seekToFrame(double frame) {
    final milliseconds = (frame / _fps * 1000).toInt();
    _controller.seekTo(Duration(milliseconds: milliseconds));
  }

  void _seekToTime(double value) {
    final duration = _controller.value.duration;
    final newPosition =
        Duration(milliseconds: (duration.inMilliseconds * value).toInt());
    _controller.seekTo(newPosition);
  }

  @override
  void dispose() {
    _controller.removeListener(_updateFrameCount);
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _controller.value.isPlaying
          ? _controller.pause()
          : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _controller.value.isInitialized
          ? Column(
              children: [
                /// 🎥 VIDEO
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),

                /// 🎚 SPEED SLIDER (UP TO 5X)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text(
                        "Speed",
                        style: TextStyle(color: Colors.white),
                      ),
                      Expanded(
                        child: Slider(
                          min: 0.1,
                          max: 5.0,
                          divisions: 49,
                          value: _playbackSpeed,
                          activeColor: Colors.redAccent,
                          inactiveColor: Colors.white38,
                          onChanged: (value) {
                            setState(() {
                              _playbackSpeed = value;
                              _controller.setPlaybackSpeed(value);
                            });
                          },
                        ),
                      ),
                      Text(
                        "${_playbackSpeed.toStringAsFixed(1)}x",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),

                /// 🎞 FRAME SCRUBBER (THICK + SLIDABLE)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 12,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 8),
                        ),
                        child: Slider(
                          min: 0,
                          max: _totalFrames.toDouble(),
                          value: _currentFrame
                              .clamp(0, _totalFrames)
                              .toDouble(),
                          activeColor: Colors.blueAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (value) {
                            _seekToFrame(value);
                          },
                        ),
                      ),
                      Text(
                        "Frame $_currentFrame / $_totalFrames",
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                /// ⏱ TIME SLIDER WITH CIRCLE
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 6,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          min: 0,
                          max: 1,
                          value: _controller.value.position.inMilliseconds /
                              _controller.value.duration.inMilliseconds,
                          activeColor: Colors.redAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (value) {
                            _seekToTime(value);
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                                _controller.value.position),
                            style: const TextStyle(color: Colors.white),
                          ),
                          Text(
                            _formatDuration(
                                _controller.value.duration),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                /// ▶ PLAY BUTTON
                IconButton(
                  iconSize: 60,
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  onPressed: _togglePlayPause,
                ),

                const SizedBox(height: 20),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}