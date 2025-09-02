import 'package:flutter/material.dart';
import 'package:lms_app/services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'audio_player_screen.dart';
import 'video_player_screen.dart';
import 'docx_viewer_screen.dart';

class CourseMaterialsScreen extends StatefulWidget {
  final String courseId;
  final String courseName;

  const CourseMaterialsScreen({
    Key? key,
    required this.courseId,
    required this.courseName,
  }) : super(key: key);

  @override
  _CourseMaterialsScreenState createState() => _CourseMaterialsScreenState();
}

class _CourseMaterialsScreenState extends State<CourseMaterialsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiService _apiService = ApiService();

  // Upload tab controllers
  String? _selectedFileType;
  PlatformFile? _selectedFile;
  bool _isUploading = false;

  // View Materials tab data
  List<dynamic> _videos = [];
  List<dynamic> _pdfs = [];
  List<dynamic> _docxs = [];
  List<dynamic> _audios = [];
  bool _isLoadingMaterials = true;
  String? _userName; // Current logged-in user's name
  String? _role; // Current logged-in user's role
  final Map<String, double> _audioProgress = {}; // audio filename -> percent
  final Map<String, double> _videoProgress = {}; // video filename -> percent
  final Map<String, double> _docxProgress = {}; // docx filename -> percent

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Load session info (user name and role) and then materials. Errors are non-fatal.
    try {
      final sessionInfo = await _apiService.getSessionInfo();
      if (sessionInfo['success'] == true) {
        setState(() {
          _userName = sessionInfo['name'];
          _role = sessionInfo['role'];
        });
      }
    } catch (e) {
      // Silently ignore; user might be unauthenticated
    } finally {
      _loadMaterials();
    }
  }

  bool get _isInstructor => _role == 'instructor';

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _getAllowedExtensions(),
      withData: true, // Ensure bytes are included to avoid null bytes on upload
    );

    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  List<String> _getAllowedExtensions() {
    switch (_selectedFileType) {
      case 'video':
        return ['mp4', 'avi', 'mov', 'mkv'];
      case 'pdf':
        return ['pdf'];
      case 'docx':
        return ['docx'];
      case 'audio':
        return ['mp3', 'wav', 'ogg'];
      default:
        return [];
    }
  }

  Future<void> _uploadFile() async {
    if (!_isInstructor) return; // safety
    if (_selectedFile == null || _selectedFileType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file and file type.')),
      );
      return;
    }

    // Safely obtain file bytes
    final bytes = _selectedFile!.bytes;
    if (bytes == null) {
      // This should not happen with withData: true, but guard just in case
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read the selected file. Please re-select it.')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final response = await _apiService.uploadFile(
        bytes,
        _selectedFile!.name,
        _selectedFileType!,
        widget.courseId,
      );

      if (response['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded successfully!')),
        );
        setState(() {
          _selectedFile = null;
          _selectedFileType = null;
        });
        _loadMaterials(); // Refresh materials list
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to upload file')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _loadMaterials() async {
    setState(() => _isLoadingMaterials = true);
    try {
  final videos = await _apiService.getFiles('video', widget.courseId);
      final pdfs = await _apiService.getFiles('pdf', widget.courseId);
      final docxs = await _apiService.getFiles('docx', widget.courseId);
      final audios = await _apiService.getFiles('audio', widget.courseId);

      setState(() {
        _videos = videos;
        _pdfs = pdfs;
        _docxs = docxs;
        _audios = audios;
      });

      // Load media progress for student users (non-instructors)
      if (!_isInstructor && _userName != null) {
        _loadAudioProgresses();
        _loadVideoProgresses();
  _loadDocxProgresses();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load materials: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoadingMaterials = false);
    }
  }

  Future<void> _loadAudioProgresses() async {
    // Avoid refetching if list empty
    if (_audios.isEmpty) return;
    final localUser = _userName;
    if (localUser == null) return;
    try {
      // Fetch sequentially (audio list likely small). Could optimize with Future.wait.
      for (final a in _audios) {
        final filename = a['filename'];
        if (filename is String) {
          try {
            final p = await _apiService.getAudioProgress(localUser, filename);
            _audioProgress[filename] = p;
          } catch (_) {}
        }
      }
      if (mounted) setState(() {}); // trigger rebuild to show progress
    } catch (_) {
      // Silent fail — progress display just omitted
    }
  }

  Future<void> _loadVideoProgresses() async {
    if (_videos.isEmpty) return;
    final localUser = _userName; if (localUser == null) return;
    try {
      for (final v in _videos) {
        final filename = v['filename'];
        if (filename is String) {
          try {
            final p = await _apiService.getVideoProgress(localUser, filename);
            _videoProgress[filename] = p;
          } catch (_) {}
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadDocxProgresses() async {
    if (_docxs.isEmpty) return;
    final localUser = _userName; if (localUser == null) return;
    try {
      for (final d in _docxs) {
        final filename = d['filename'];
        if (filename is String) {
          try {
            final p = await _apiService.getDocxProgress(localUser, filename);
            _docxProgress[filename] = p;
          } catch (_) {}
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _deleteMaterial(String fileType, String filename) async {
    if (!_isInstructor) return; // safety
    final bool? confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Material'),
        content: Text('Are you sure you want to delete "$filename"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _apiService.deleteFile(fileType, filename);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$filename" deleted successfully!')),
        );
        _loadMaterials(); // Refresh materials list
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete material: $e')),
        );
      }
    }
  }

  Future<void> _launchURL(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not launch $url')),
      );
    }
  }

  Widget _buildMaterialList(List<dynamic> materials, String fileType) {
    if (_isLoadingMaterials) return const Center(child: CircularProgressIndicator());
    if (materials.isEmpty) return Center(child: Text('No ${fileType}s uploaded yet.'));
    return ListView.builder(
      itemCount: materials.length,
      itemBuilder: (context, index) {
        final material = materials[index];
        final filename = material['filename'] ?? 'Unknown File';
        final url = material['url'];
        final instructorName = material['instructor_name'];
        final bool canDelete = _isInstructor && _userName != null && instructorName == _userName;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(filename),
            subtitle: fileType == 'audio'
                ? Builder(
                    builder: (context) {
                      final prog = _audioProgress[filename];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Uploaded by: $instructorName'),
                          if (prog != null)
                            Text('Progress: ${prog.toStringAsFixed(1)}%'),
                        ],
                      );
                    },
                  )
                : fileType == 'video'
                    ? Builder(
                        builder: (context) {
                          final prog = _videoProgress[filename];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Uploaded by: $instructorName'),
                              if (prog != null)
                                Text('Progress: ${prog.toStringAsFixed(1)}%'),
                            ],
                          );
                        },
                      )
                    : fileType == 'docx'
                        ? Builder(
                            builder: (context) {
                              final prog = _docxProgress[filename];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Uploaded by: $instructorName'),
                                  if (prog != null)
                                    Text('Progress: ${prog.toStringAsFixed(1)}%'),
                                ],
                              );
                            },
                          )
                        : Text('Uploaded by: $instructorName'),
            trailing: canDelete ? IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteMaterial(fileType, filename),
              tooltip: 'Delete Material',
            ) : null,
            onTap: () {
              if (url == null) return;
              if (fileType == 'audio') {
                Navigator.of(context).push<double>(
                  MaterialPageRoute(
                    builder: (_) => AudioPlayerScreen(
                      filename: filename,
                      url: url,
                    ),
                  ),
                ).then((percent) {
                  if (percent != null && !_isInstructor) {
                    setState(() { _audioProgress[filename] = percent; });
                  } else if (!_isInstructor && percent == null) {
                    // Fallback: re-fetch just this one if not present
                    _refreshSingleAudioProgress(filename);
                  }
                });
              } else if (fileType == 'video') {
                Navigator.of(context).push<double>(
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(
                      filename: filename,
                      url: url,
                    ),
                  ),
                ).then((percent) async {
                  if (percent != null && !_isInstructor) {
                    setState(() { _videoProgress[filename] = percent; });
                  } else if (!_isInstructor && percent == null) {
                    // refresh single video progress
                    _refreshSingleVideoProgress(filename);
                  }
                });
              } else if (fileType == 'docx') {
                Navigator.of(context).push<double>(
                  MaterialPageRoute(
                    builder: (_) => DocxViewerScreen(
                      filename: filename,
                      url: url,
                    ),
                  ),
                ).then((percent) async {
                  if (percent != null && !_isInstructor) {
                    setState(() { _docxProgress[filename] = percent; });
                  } else if (!_isInstructor && percent == null) {
                    _refreshSingleDocxProgress(filename);
                  }
                });
              } else {
                _launchURL(url);
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _refreshSingleAudioProgress(String filename) async {
    final localUser = _userName; if (localUser == null) return;
    try {
      final p = await _apiService.getAudioProgress(localUser, filename);
      if (mounted) setState(() { _audioProgress[filename] = p; });
    } catch (_) {}
  }

  Future<void> _refreshSingleVideoProgress(String filename) async {
    final localUser = _userName; if (localUser == null) return;
    try {
      final p = await _apiService.getVideoProgress(localUser, filename);
      if (mounted) setState(() { _videoProgress[filename] = p; });
    } catch (_) {}
  }

  Future<void> _refreshSingleDocxProgress(String filename) async {
    final localUser = _userName; if (localUser == null) return;
    try {
      final p = await _apiService.getDocxProgress(localUser, filename);
      if (mounted) setState(() { _docxProgress[filename] = p; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final viewTab = DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Videos'), Tab(text: 'PDFs'), Tab(text: 'DOCXs'), Tab(text: 'Audios'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _buildMaterialList(_videos, 'video'),
              _buildMaterialList(_pdfs, 'pdf'),
              _buildMaterialList(_docxs, 'docx'),
              _buildMaterialList(_audios, 'audio'),
            ]),
          ),
        ],
      ),
    );

    // If user is NOT an instructor, show only view materials (no upload tab at all)
    if (!_isInstructor) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Materials for ${widget.courseName}'),
        ),
        body: viewTab,
      );
    }

    // Instructor UI (upload + view)
    final uploadTab = Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedFileType,
            hint: const Text('Select File Type'),
            items: const [
              DropdownMenuItem(value: 'video', child: Text('Video')),
              DropdownMenuItem(value: 'pdf', child: Text('PDF')),
              DropdownMenuItem(value: 'docx', child: Text('DOCX')),
              DropdownMenuItem(value: 'audio', child: Text('Audio')),
            ],
            onChanged: (value) { setState(() { _selectedFileType = value; _selectedFile = null; }); },
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.attach_file),
            label: Text(_selectedFile?.name ?? 'Pick File'),
          ),
          const SizedBox(height: 16),
          _isUploading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(
            onPressed: _uploadFile,
            child: const Text('Upload Material'),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Materials for ${widget.courseName}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [ Tab(text: 'Upload'), Tab(text: 'View Materials') ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [uploadTab, viewTab],
      ),
    );
  }
}
