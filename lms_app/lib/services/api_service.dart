
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl = 'https://training-pro-redis.vercel.app/api'; // Replace with your deployed API URL

  static Future<Map<String, dynamic>> register(String fullName, String phone, String password, String confirmPassword, String role) async {
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

  static Future<Map<String, dynamic>> login(String identifier, String password, String role) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/login'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-T',
      },
      body: jsonEncode(<String, String>{
        'name': identifier,
        'password': password,
        'role': role,
      }),
    );

    return jsonDecode(response.body);
  }
}
