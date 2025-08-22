
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Singleton setup
  static final ApiService _instance = ApiService._internal();
  factory ApiService() {
    return _instance;
  }
  ApiService._internal();

  // The backend server URL.
  // For Android emulator, '10.0.2.2' points to the host machine's localhost.
  // For iOS simulator, 'localhost' or '127.0.0.1' should work directly.
  // For physical devices, this must be the local IP address of the machine running the Flask server.
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
}
