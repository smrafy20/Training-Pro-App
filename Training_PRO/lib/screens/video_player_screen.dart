import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:lms_app/services/api_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String filename;
  final String url;
  const VideoPlayerScreen({super.key, required this.filename, required this.url});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  final ApiService _api = ApiService();

  bool _initialized = false;
  bool _loading = true;
  bool _isSeekingResume = false;
  double _maxProgressPercent = 0; // highest watched percent
  String? _studentName;
  bool _showControls = true;
  double _playbackSpeed = 1.0;
  double _volume = 1.0; // logical volume (0-1), video_player uses setVolume(0-1)
  bool _initFailed = false;
  String? _errorMessage;
  // scrubbing flag removed (not needed now)

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final session = await _api.getSessionInfo();
      if (session['success'] == true) {
        _studentName = session['name'];
      }
    } catch (_) {}

    if (_studentName == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not authenticated')));
        Navigator.pop(context);
      }
      return;
    }

    try { _maxProgressPercent = await _api.getVideoProgress(_studentName!, widget.filename); } catch (_) {}

  // Use network (String) constructor for broader plugin compatibility (Windows implementation may not support networkUrl yet)
  _controller = VideoPlayerController.network(widget.url);

    try {
      await _controller.initialize();
      _initialized = true;
      if (_maxProgressPercent > 0 && _maxProgressPercent < 100) {
        _promptResume();
      }
      _controller.addListener(_videoListener);
      _controller.play();
    } catch (e) {
      _initFailed = true;
      _errorMessage = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _videoListener() {
    if (!_controller.value.isInitialized) return;
    final duration = _controller.value.duration;
    final position = _controller.value.position;
    if (duration.inMilliseconds > 0) {
      final currentPercent = (position.inMilliseconds / duration.inMilliseconds) * 100;
      bool changed = false;
      if (currentPercent > _maxProgressPercent) {
        _maxProgressPercent = currentPercent;
        changed = true;
        _maybeScheduleProgressSave();
      }
      if (_controller.value.position >= duration && _maxProgressPercent < 100) {
        _maxProgressPercent = 100;
        changed = true;
        _saveProgress();
      }
      if (changed && mounted) {
        setState(() {}); // rebuild to update progress text
      }
    }
  }

  DateTime? _lastSavedAt;
  double _lastSavedPercent = 0;
  void _maybeScheduleProgressSave() {
    final now = DateTime.now();
    final since = _lastSavedAt == null ? const Duration(days: 1) : now.difference(_lastSavedAt!);
    if ((_maxProgressPercent - _lastSavedPercent) >= 5 || since.inSeconds >= 10) {
      _lastSavedAt = now;
      _lastSavedPercent = _maxProgressPercent;
      _saveProgress();
    }
  }

  Future<void> _promptResume() async {
    if (_isSeekingResume) return;
    _isSeekingResume = true;
    if (!mounted) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resume Video?'),
        content: Text('You watched ${_maxProgressPercent.toStringAsFixed(1)}%. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start Over')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (resume == true && _controller.value.isInitialized) {
      final duration = _controller.value.duration.inMilliseconds;
      final targetMs = (_maxProgressPercent / 100) * duration;
      await _controller.seekTo(Duration(milliseconds: targetMs.round()));
    } else if (resume == false) {
      _maxProgressPercent = 0;
      _saveProgress();
    }
  }

  Future<void> _saveProgress() async {
    final name = _studentName; if (name == null) return;
  final clamped = _maxProgressPercent.clamp(0, 100);
  try { await _api.setVideoProgress(name, widget.filename, double.parse(clamped.toStringAsFixed(4))); } catch (_) {}
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2,'0')}:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    _saveProgress();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_initialized) return;
    if (_controller.value.isPlaying) {
      await _controller.pause();
      _saveProgress();
    } else {
      await _controller.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekRelative(int seconds) async {
    if (!_initialized) return;
    final pos = _controller.value.position + Duration(seconds: seconds);
    final clamped = pos < Duration.zero ? Duration.zero : pos;
    final dur = _controller.value.duration;
    final target = clamped > dur ? dur : clamped;
    await _controller.seekTo(target);
    if (mounted) setState(() {});
  }

  Future<void> _changeSpeed() async {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final current = _playbackSpeed;
    final idx = speeds.indexOf(current);
    final next = speeds[(idx + 1) % speeds.length];
    _playbackSpeed = next;
    await _controller.setPlaybackSpeed(next);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        await _saveProgress();
        Navigator.pop(context, _maxProgressPercent);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.filename),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _saveProgress();
              Navigator.pop(context, _maxProgressPercent);
            },
          ),
          actions: [
            if (_initialized)
              IconButton(
                tooltip: 'Playback speed',
                icon: Text('${_playbackSpeed}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _changeSpeed,
              ),
          ],
        ),
    body: _loading
      ? const Center(child: CircularProgressIndicator())
      : _initFailed
        ? _buildInitFailed()
        : LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTap: () => setState(() => _showControls = !_showControls),
                    child: Column(
                      children: [
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _initialized ? _controller.value.aspectRatio : 16 / 9,
                              child: Stack(
                                children: [
                                  if (_initialized)
                                    VideoPlayer(_controller)
                                  else
                                    const Center(child: CircularProgressIndicator()),
                                  if (_showControls)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black45,
                                        child: Center(
                                          child: IconButton(
                                            iconSize: 72,
                                            color: Colors.white,
                                            icon: Icon(_controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle),
                                            onPressed: _togglePlay,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_showControls)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: _buildControlsBar(),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Progress: ${_maxProgressPercent.toStringAsFixed(1)}%'),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Reset Progress'),
                                    onPressed: () async {
                                      final reset = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Reset Progress'),
                                          content: const Text('Reset watched progress to 0%?'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                                          ],
                                        ),
                                      );
                                      if (reset == true) {
                                        _maxProgressPercent = 0;
                                        await _controller.seekTo(Duration.zero);
                                        await _controller.pause();
                                        setState(() {});
                                        _saveProgress();
                                      }
                                    },
                                  ),
                                  if (_maxProgressPercent > 0 && _maxProgressPercent < 100)
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.play_circle_fill),
                                      label: const Text('Continue'),
                                      onPressed: () async {
                                        if (_controller.value.isInitialized) {
                                          final duration = _controller.value.duration.inMilliseconds;
                                          final targetMs = (_maxProgressPercent / 100) * duration;
                                          await _controller.seekTo(Duration(milliseconds: targetMs.round()));
                                          await _controller.play();
                                          setState(() {});
                                        }
                                      },
                                    ),
                                ],
                              ),
                              if (!_initialized && !_initFailed)
                                const Padding(
                                  padding: EdgeInsets.only(top: 16.0),
                                  child: Text('Initializing video...', style: TextStyle(color: Colors.grey)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildInitFailed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('Failed to initialize video', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage ?? 'Unknown error', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: () {
                setState(() {
                  _loading = true; _initFailed = false; _errorMessage = null; _initialized = false;
                });
                _init();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    final posMs = position.inMilliseconds.toDouble();
  final durMs = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_format(position), style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(),
              Text(_format(duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          Slider(
            min: 0,
            max: durMs,
            value: posMs.clamp(0, durMs).toDouble(),
            onChanged: (v) async {
              await _controller.seekTo(Duration(milliseconds: v.round()));
              setState(() {});
            },
            activeColor: Colors.redAccent,
            inactiveColor: Colors.white30,
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                onPressed: _togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () => _seekRelative(-10),
              ),
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () => _seekRelative(10),
              ),
              IconButton(
                icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                onPressed: () {
                  setState(() {
                    if (_volume == 0) {
                      _volume = 1.0; _controller.setVolume(1.0);
                    } else {
                      _volume = 0; _controller.setVolume(0);
                    }
                  });
                },
              ),
              Expanded(
                child: Slider(
                  value: _volume,
                  min: 0,
                  max: 1,
                  divisions: 100,
                  onChanged: (v) {
                    setState(() { _volume = v; });
                    _controller.setVolume(v);
                  },
                ),
              ),
              TextButton(
                onPressed: _changeSpeed,
                child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
