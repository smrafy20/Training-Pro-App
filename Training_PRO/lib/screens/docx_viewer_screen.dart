import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_document_viewer/flutter_document_viewer.dart';
import 'package:lms_app/services/api_service.dart';
import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class DocxViewerScreen extends StatefulWidget {
  final String filename; // raw filename used as key
  final String url; // remote blob url
  const DocxViewerScreen({super.key, required this.filename, required this.url});

  @override
  State<DocxViewerScreen> createState() => _DocxViewerScreenState();
}

class _DocxViewerScreenState extends State<DocxViewerScreen> {
  final ApiService _api = ApiService();
  late final FlutterDocumentViewerController _controller;
  String? _studentName;
  bool _loading = true;
  bool _ready = false; // viewer ready (embedded or fallback)
  bool _resumePromptShown = false;
  double _maxProgressPercent = 0; // persisted highest percent
  int _totalPages = 0;
  int _currentPage = 1;
  DateTime? _lastSavedAt;
  double _lastSavedPercent = 0;
  bool _useFallback = false; // when embedded viewer not supported
  List<String> _fallbackPages = const [];

  @override
  void initState() {
    super.initState();
    _useFallback = !_supportsEmbeddedDocxViewer;
    _controller = FlutterDocumentViewerController(
      onReady: () { if (!_useFallback) setState(() { _ready = true; }); },
      onPageChanged: (page, total) {
        if (_useFallback) return; // fallback handled manually
        _currentPage = page; _totalPages = total; _updateProgressFromPage();
      },
    );
    _init();
  }

  bool get _supportsEmbeddedDocxViewer {
    if (kIsWeb) return true; // web iframe
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false; // desktop fallback
    }
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

    try { _maxProgressPercent = await _api.getDocxProgress(_studentName!, widget.filename); } catch (_) {}
    if (_useFallback) {
      await _loadFallbackDocx();
    }
    if (!_useFallback) {
      // embedded viewer progress resume handled in page change listener
    }
    setState(() { _loading = false; });
  }

  Future<void> _loadFallbackDocx() async {
    try {
      final resp = await http.get(Uri.parse(widget.url));
      if (resp.statusCode == 200) {
        final archive = ZipDecoder().decodeBytes(resp.bodyBytes, verify: false);
        final documentXml = archive.files.firstWhere(
          (f) => f.name == 'word/document.xml',
          orElse: () => throw Exception('document.xml not found in DOCX'),
        );
        final xmlDoc = xml.XmlDocument.parse(utf8.decode(documentXml.content as List<int>));
        final paragraphs = xmlDoc.findAllElements('w:p');
        final buffer = StringBuffer();
        for (final p in paragraphs) {
          for (final t in p.findAllElements('w:t')) { buffer.write(t.text); }
          buffer.writeln('\n');
        }
        final fullText = buffer.toString().trim();
        const chunkSize = 1200; // heuristic page size
        final pages = <String>[];
        for (var i = 0; i < fullText.length; i += chunkSize) {
          pages.add(fullText.substring(i, i + chunkSize > fullText.length ? fullText.length : i + chunkSize));
        }
        _fallbackPages = pages.isEmpty ? ['(Empty Document)'] : pages;
        _totalPages = _fallbackPages.length;
        _ready = true;
        if (_maxProgressPercent > 0 && _maxProgressPercent < 100) {
          WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _promptResume(); });
        }
      } else {
        _fallbackPages = ['Failed to load DOCX (HTTP ${resp.statusCode})'];
        _totalPages = 1; _ready = true;
      }
    } catch (e) {
      _fallbackPages = ['Error parsing DOCX: $e'];
      _totalPages = 1; _ready = true;
    }
  }

  void _updateProgressFromPage() {
    if (_totalPages <= 0) return;
    final percent = (_currentPage / _totalPages) * 100.0;
    bool changed = false;
    if (percent > _maxProgressPercent) {
      _maxProgressPercent = percent;
      changed = true;
    }
    if (_currentPage == _totalPages && _maxProgressPercent < 100) {
      _maxProgressPercent = 100;
      changed = true;
    }
    if (changed) {
      _maybeSaveProgress();
      setState(() {}); // refresh UI
    }
    // Show resume prompt only once after we know total pages & have prior progress
    if (!_resumePromptShown && _maxProgressPercent > 0 && _maxProgressPercent < 100) {
      _resumePromptShown = true; // mark before async dialog to avoid duplicates
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptResume());
    }
  }

  Future<void> _promptResume() async {
    if (!mounted || _totalPages == 0) return;
    final resume = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Resume Reading?'),
        content: Text('You read ${_maxProgressPercent.toStringAsFixed(1)}% of this document. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Start Over')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (!mounted) return;
    if (resume == true) {
      final targetPage = (_maxProgressPercent / 100 * _totalPages).clamp(1, _totalPages.toDouble()).round();
      if (targetPage > 1) {
        if (_useFallback) {
          setState(() { _currentPage = targetPage; _updateProgressFromPage(); });
        } else { _controller.gotoPage(targetPage); }
      }
    } else if (resume == false) {
      _maxProgressPercent = 0; _saveProgress(); setState(() {});
      if (_useFallback) { setState(() { _currentPage = 1; _updateProgressFromPage(); }); }
      else { _controller.gotoPage(1); }
    }
  }

  void _maybeSaveProgress() {
    final now = DateTime.now();
    final since = _lastSavedAt == null ? const Duration(days: 1) : now.difference(_lastSavedAt!);
    if ((_maxProgressPercent - _lastSavedPercent) >= 5 || since.inSeconds >= 10 || _maxProgressPercent == 100) {
      _lastSavedAt = now;
      _lastSavedPercent = _maxProgressPercent;
      _saveProgress();
    }
  }

  Future<void> _saveProgress() async {
    final name = _studentName; if (name == null) return;
    try { await _api.setDocxProgress(name, widget.filename, double.parse(_maxProgressPercent.clamp(0, 100).toStringAsFixed(4))); } catch (_) {}
  }

  @override
  void dispose() {
    _saveProgress();
    super.dispose();
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
            if (_ready)
              IconButton(
                tooltip: 'First Page',
                icon: const Icon(Icons.first_page),
                onPressed: () => _controller.gotoPage(1),
              ),
            if (_ready && _totalPages > 0)
              IconButton(
                tooltip: 'Last Page',
                icon: const Icon(Icons.last_page),
                onPressed: () => _controller.gotoPage(_totalPages),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: _useFallback
                        ? _buildFallbackViewer()
                        : FlutterDocumentViewer(
                            url: widget.url,
                            controller: _controller,
                            showControls: true,
                            onPageChanged: (currentPage, totalPages) {
                              _currentPage = currentPage; _totalPages = totalPages; _updateProgressFromPage();
                            },
                          ),
                  ),
                  _buildFooter(),
                ],
              ),
      ),
    );
  }
  Widget _buildFallbackViewer() {
    if (_fallbackPages.isEmpty) {
      return const Center(child: Text('Loading document...'));
    }
    final text = _fallbackPages[_currentPage - 1];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: SelectableText(text, style: const TextStyle(fontSize: 16, height: 1.4)),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Page: $_currentPage / $_totalPages'),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: _maxProgressPercent.clamp(0, 100) / 100,
            backgroundColor: Colors.grey.shade300,
          ),
          const SizedBox(height: 4),
          Text('Progress: ${_maxProgressPercent.toStringAsFixed(1)}%'),
          const SizedBox(height: 8),
          if (_useFallback)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous Page',
                  onPressed: _currentPage > 1 ? () { setState(() { _currentPage--; _updateProgressFromPage(); }); } : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next Page',
                  onPressed: _currentPage < _totalPages ? () { setState(() { _currentPage++; _updateProgressFromPage(); }); } : null,
                ),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: _totalPages.toDouble().clamp(1, double.infinity),
                    divisions: _totalPages > 1 ? _totalPages - 1 : 1,
                    value: _currentPage.toDouble(),
                    onChanged: (v) { setState(() { _currentPage = v.round(); _updateProgressFromPage(); }); },
                  ),
                ),
              ],
            ),
          Wrap(
            spacing: 12,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('Reset Progress'),
                onPressed: () async {
                  final reset = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Reset Progress'),
                      content: const Text('Reset reading progress to 0%?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                      ],
                    ),
                  );
                  if (reset == true) {
                    _maxProgressPercent = 0;
                    if (_useFallback) { setState(() { _currentPage = 1; _updateProgressFromPage(); }); }
                    else { _controller.gotoPage(1); }
                    _saveProgress();
                  }
                },
              ),
              if (_maxProgressPercent > 0 && _maxProgressPercent < 100)
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Continue'),
                  onPressed: () {
                    final targetPage = (_maxProgressPercent / 100 * _totalPages).clamp(1, _totalPages.toDouble()).round();
                    if (_useFallback) { setState(() { _currentPage = targetPage; _updateProgressFromPage(); }); }
                    else { _controller.gotoPage(targetPage); }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
