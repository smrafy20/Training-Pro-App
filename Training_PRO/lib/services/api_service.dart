
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Singleton setup
  static final ApiService _instance = ApiService._internal();
  factory ApiService() {
    return _instance;
  }
  ApiService._internal();


  final String _baseUrl = 'https://training-pro-redis.vercel.app/api';
  String? _cookie;

  Future<void> _saveCookie(http.Response response) async {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      _cookie = rawCookie;
    }
  }

  Future<Map<String, dynamic>> register(String fullName, String phone, String password, String confirmPassword, String role) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/register'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'fullName': fullName,
        'phone': phone,
        'password': password,
        'confirmPassword': confirmPassword,
        'role': role,
      }),
    );
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> login(String identifier, String password, String role) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'name': identifier,
        'password': password,
        'role': role,
      }),
    );

    if (response.statusCode == 200 && jsonDecode(response.body)['success']) {
      await _saveCookie(response);
    }
    return jsonDecode(response.body);
  }

  Future<void> logout() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/logout'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );

    if (response.statusCode == 200) {
      _cookie = null;
    } else {
      throw Exception('Failed to logout');
    }
  }

  Future<Map<String, dynamic>> getSessionInfo() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/get_session_info'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get session info');
    }
  }

  Future<List<dynamic>> getCourses() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/courses'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load courses');
    }
  }

  Future<Map<String, dynamic>> createCourse(String title) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/courses'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
      body: jsonEncode(<String, String>{
        'courseName': title,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create course: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> deleteCourse(String courseId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/courses/$courseId'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to delete course: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> uploadFile(
      List<int> fileBytes, String filename, String fileType, String courseId) async {
    final String endpoint;
    switch (fileType) {
      case 'video':
        endpoint = 'upload';
        break;
      case 'pdf':
        endpoint = 'upload_pdf';
        break;
      case 'docx':
        endpoint = 'upload_docx';
        break;
      case 'audio':
        endpoint = 'upload_audio';
        break;
      default:
        throw Exception('Unsupported file type: $fileType');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/$endpoint'),
    );

    request.headers.addAll({
      if (_cookie != null) 'cookie': _cookie!,
    });

    request.fields['courseId'] = courseId;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to upload $fileType: ${response.body}');
    }
  }

  Future<List<dynamic>> getFiles(String fileType, String courseId) async {
    final String endpoint;
    switch (fileType) {
      case 'video':
        endpoint = 'videos';
        break;
      case 'pdf':
        endpoint = 'pdfs';
        break;
      case 'docx':
        endpoint = 'docx_files';
        break;
      case 'audio':
        endpoint = 'audio_files';
        break;
      default:
        throw Exception('Unsupported file type: $fileType');
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/$endpoint?courseId=$courseId'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load $fileType files: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> deleteFile(String fileType, String filename) async {
    final String endpoint;
    switch (fileType) {
      case 'video':
        endpoint = 'video';
        break;
      case 'pdf':
        endpoint = 'pdf';
        break;
      case 'docx':
        endpoint = 'docx';
        break;
      case 'audio':
        endpoint = 'audio';
        break;
      default:
        throw Exception('Unsupported file type: $fileType');
    }

    final response = await http.delete(
      Uri.parse('$_baseUrl/$endpoint/$filename'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to delete $fileType file: ${response.body}');
    }
  }

  // --- Audio Progress Tracking ---
  Future<double> getAudioProgress(String studentName, String filename) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/progress_audio/$studentName/$filename'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['progress'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0; // treat missing as 0
  }

  Future<void> setAudioProgress(String studentName, String filename, double progressPercent) async {
    await http.post(
      Uri.parse('$_baseUrl/progress_audio/$studentName/$filename'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
      body: jsonEncode({'progress': progressPercent}),
    );
  }

  // --- Video Progress Tracking ---
  Future<double> getVideoProgress(String studentName, String filename) async {
    final encodedFile = Uri.encodeComponent(filename);
    final response = await http.get(
      Uri.parse('$_baseUrl/progress/$studentName/$encodedFile'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['progress'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  Future<void> setVideoProgress(String studentName, String filename, double progressPercent) async {
    final encodedFile = Uri.encodeComponent(filename);
    await http.post(
      Uri.parse('$_baseUrl/progress/$studentName/$encodedFile'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (_cookie != null) 'cookie': _cookie!,
      },
      body: jsonEncode({'progress': progressPercent}),
    );
  }
}
