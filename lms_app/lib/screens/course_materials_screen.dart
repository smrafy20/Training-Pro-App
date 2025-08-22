
import 'package:flutter/material.dart';
import 'package:lms_app/services/api_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

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
    // Load session info (user name) and then materials. Errors are non-fatal.
    try {
      final sessionInfo = await _apiService.getSessionInfo();
      if (sessionInfo['success'] == true) {
        setState(() {
          _userName = sessionInfo['name'];
        });
      }
    } catch (e) {
      // Silently ignore; user might be unauthenticated
    } finally {
      _loadMaterials();
    }
  }

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
    if (_selectedFile == null || _selectedFileType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a file and file type.')),
      );
      return;
    }

    // Safely obtain file bytes
    final bytes = _selectedFile!.bytes;
    if (bytes == null) {
      // This should not happen with withData: true, but guard just in case
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read the selected file. Please re-select it.')),
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
          SnackBar(content: Text('File uploaded successfully!')),
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
        SnackBar(content: Text('Error uploading file: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  Future<void> _loadMaterials() async {
    setState(() {
      _isLoadingMaterials = true;
    });
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load materials: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoadingMaterials = false;
      });
    }
  }

  Future<void> _deleteMaterial(String fileType, String filename) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Material'),
          content: Text('Are you sure you want to delete "$filename"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Delete'),
            ),
          ],
        );
      },
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
          SnackBar(content: Text('Failed to delete material: ${e.toString()}')),
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
    if (_isLoadingMaterials) {
      return Center(child: CircularProgressIndicator());
    }
    if (materials.isEmpty) {
      return Center(child: Text('No ${fileType}s uploaded yet.'));
    }
    return ListView.builder(
      itemCount: materials.length,
      itemBuilder: (context, index) {
        final material = materials[index];
        final filename = material['filename'] ?? 'Unknown File';
        final url = material['url'];
        final instructorName = material['instructor_name'];
  final bool canDelete = _userName != null && instructorName == _userName;

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            title: Text(filename),
            subtitle: Text('Uploaded by: $instructorName'),
            trailing: canDelete
                ? IconButton(
                    icon: Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteMaterial(fileType, filename),
                    tooltip: 'Delete Material',
                  )
                : null,
            onTap: () {
              if (url != null) {
                _launchURL(url);
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Materials for ${widget.courseName}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Upload'),
            Tab(text: 'View Materials'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Upload Tab Content
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _selectedFileType,
                  hint: Text('Select File Type'),
                  items: const [
                    DropdownMenuItem(value: 'video', child: Text('Video')),
                    DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                    DropdownMenuItem(value: 'docx', child: Text('DOCX')),
                    DropdownMenuItem(value: 'audio', child: Text('Audio')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedFileType = value;
                      _selectedFile = null; // Clear selected file on type change
                    });
                  },
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: Icon(Icons.attach_file),
                  label: Text(_selectedFile != null
                      ? _selectedFile!.name
                      : 'Pick File'),
                ),
                SizedBox(height: 16),
                _isUploading
                    ? Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _uploadFile,
                        child: Text('Upload Material'),
                      ),
              ],
            ),
          ),
          // View Materials Tab Content
          DefaultTabController(
            length: 4, // Videos, PDFs, DOCXs, Audios
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Videos'),
                    Tab(text: 'PDFs'),
                    Tab(text: 'DOCXs'),
                    Tab(text: 'Audios'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildMaterialList(_videos, 'video'),
                      _buildMaterialList(_pdfs, 'pdf'),
                      _buildMaterialList(_docxs, 'docx'),
                      _buildMaterialList(_audios, 'audio'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
