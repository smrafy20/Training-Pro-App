import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:lms_app/services/api_service.dart';

class AudioPlayerScreen extends StatefulWidget {
	final String filename; // original filename (used for progress key)
	final String url; // direct blob/url to stream

	const AudioPlayerScreen({super.key, required this.filename, required this.url});

	@override
	State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
	final AudioPlayer _player = AudioPlayer();
	final ApiService _api = ApiService();

	Duration _position = Duration.zero;
	Duration _duration = Duration.zero;
	double _maxProgressPercent = 0; // persisted highest percent listened
	bool _loading = true;
	String? _studentName;
	bool _seekingToResume = false;

	@override
	void initState() {
		super.initState();
		_init();
	}

	Future<void> _init() async {
		try {
			// Get session for student name
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

		// Load saved progress percent
		try {
			final saved = await _api.getAudioProgress(_studentName!, widget.filename);
			_maxProgressPercent = saved;
		} catch (_) {}

		// Configure player listeners
		_player.onDurationChanged.listen((d) {
			setState(() => _duration = d);
			if (_maxProgressPercent > 0 && _maxProgressPercent < 100 && !_seekingToResume) {
				// Ask user if they want to resume (once duration known)
				_promptResume();
			}
		});
		_player.onPositionChanged.listen((p) {
			setState(() {
				_position = p;
				final currentPercent = _duration.inMilliseconds == 0
						? 0.0
						: (p.inMilliseconds / _duration.inMilliseconds) * 100;
				if (currentPercent > _maxProgressPercent) {
					_maxProgressPercent = currentPercent;
				}
			});
		});
		_player.onPlayerComplete.listen((_) {
			setState(() {
				_position = _duration;
				_maxProgressPercent = 100;
			});
			_saveProgress();
		});

		await _player.setSourceUrl(widget.url);
		setState(() => _loading = false);
	}

	Future<void> _promptResume() async {
		_seekingToResume = true;
		if (!mounted) return;
		final resume = await showDialog<bool>(
			context: context,
			builder: (_) => AlertDialog(
				title: const Text('Resume?'),
				content: Text('You listened ${_maxProgressPercent.toStringAsFixed(1)}%. Continue?'),
				actions: [
					TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start Over')),
					TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
				],
			),
		);
		if (resume == true && _duration.inMilliseconds > 0) {
			final targetMs = (_maxProgressPercent / 100) * _duration.inMilliseconds;
			await _player.seek(Duration(milliseconds: targetMs.round()));
		} else if (resume == false) {
			_maxProgressPercent = 0; // reset locally
			_saveProgress();
		}
	}

	Future<void> _saveProgress() async {
		if (_studentName == null) return;
		try {
			await _api.setAudioProgress(_studentName!, widget.filename, _maxProgressPercent);
		} catch (_) {}
	}

	String _format(Duration d) {
		final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
		final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
		final h = d.inHours;
		if (h > 0) {
			return '${h.toString().padLeft(2, '0')}:$m:$s';
		}
		return '$m:$s';
	}

	@override
	void dispose() {
		_saveProgress();
		_player.dispose();
		super.dispose();
	}

	@override
	Widget build(BuildContext context) {
		final progressPercent = _maxProgressPercent.clamp(0, 100);
		return WillPopScope(
			onWillPop: () async {
				await _saveProgress();
				Navigator.pop(context, _maxProgressPercent);
				return false; // we manually popped
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
				),
				body: _loading
						? const Center(child: CircularProgressIndicator())
						: Padding(
								padding: const EdgeInsets.all(16.0),
								child: Column(
									crossAxisAlignment: CrossAxisAlignment.stretch,
									children: [
									Text('Progress: ${progressPercent.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.titleMedium),
									const SizedBox(height: 8),
									LinearProgressIndicator(value: progressPercent / 100),
									const SizedBox(height: 24),
									// Time + slider
									if (_duration > Duration.zero) ...[
										Row(
											mainAxisAlignment: MainAxisAlignment.spaceBetween,
											children: [
												Text(_format(_position)),
												Text(_format(_duration)),
											],
										),
										Slider(
											value: _position.inMilliseconds.toDouble().clamp(0, _duration.inMilliseconds.toDouble()),
											max: _duration.inMilliseconds.toDouble().clamp(1, double.infinity),
											onChanged: (v) async {
												final target = Duration(milliseconds: v.round());
												await _player.seek(target);
											},
										),
									],
									const SizedBox(height: 16),
									Wrap(
										spacing: 12,
										children: [
											ElevatedButton.icon(
												icon: const Icon(Icons.play_arrow),
												label: const Text('Play'),
												onPressed: () async { await _player.resume(); },
											),
											ElevatedButton.icon(
												icon: const Icon(Icons.pause),
												label: const Text('Pause'),
												onPressed: () async { await _player.pause(); _saveProgress(); },
											),
											ElevatedButton.icon(
												icon: const Icon(Icons.replay),
												label: const Text('Restart'),
												onPressed: () async {
													await _player.seek(Duration.zero);
													await _player.resume();
													setState(() { _position = Duration.zero; });
												},
											),
											ElevatedButton.icon(
												icon: const Icon(Icons.restore_from_trash),
												label: const Text('Reset Progress'),
												onPressed: () async {
													final reset = await showDialog<bool>(
														context: context,
														builder: (_) => AlertDialog(
															title: const Text('Reset Progress'),
															content: const Text('Are you sure you want to reset your progress?'),
															actions: [
																TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
																TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
															],
														),
													);
													if (reset == true) {
														setState(() { _maxProgressPercent = 0; });
														await _player.seek(Duration.zero);
														await _player.pause();
														_saveProgress();
													}
												},
											),
											if (_maxProgressPercent > 0 && _maxProgressPercent < 100)
												ElevatedButton.icon(
													icon: const Icon(Icons.play_circle_fill),
													label: const Text('Continue'),
													onPressed: () async {
														if (_duration.inMilliseconds > 0) {
															final targetMs = (_maxProgressPercent / 100) * _duration.inMilliseconds;
															await _player.seek(Duration(milliseconds: targetMs.round()));
															await _player.resume();
														}
													},
												),
										],
									),
									const SizedBox(height: 24),
									Expanded(
										child: Center(
											child: Icon(
												Icons.audiotrack,
												size: 120,
												color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
											),
										),
									),
								],
								),
							),
					),
			);
	}
}
