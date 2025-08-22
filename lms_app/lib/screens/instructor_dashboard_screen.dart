import 'package:flutter/material.dart';
import 'package:lms_app/screens/create_course_screen.dart';
import 'package:lms_app/screens/login_screen.dart';
import 'package:lms_app/services/api_service.dart';

class InstructorDashboardScreen extends StatefulWidget {
  @override
  _InstructorDashboardScreenState createState() =>
      _InstructorDashboardScreenState();
}

class _InstructorDashboardScreenState extends State<InstructorDashboardScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _courses = [];
  bool _isLoading = true;
  String? _instructorName;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final sessionInfo = await _apiService.getSessionInfo();
      if (sessionInfo['success']) {
        _instructorName = sessionInfo['name'];
      } else {
        throw Exception('Could not fetch session info.');
      }

      final allCourses = await _apiService.getCourses();
      setState(() {
        _courses = allCourses
            .where((course) => course['instructor'] == _instructorName)
            .toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: ${e.toString()}')),
      );
      // If session is invalid, redirect to login
      if (e.toString().contains('session')) {
        _logout();
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _apiService.logout();
    } catch (e) {
      // Ignore logout errors
    } finally {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Instructor Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView.builder(
                itemCount: _courses.length,
                itemBuilder: (context, index) {
                  final course = _courses[index];
                  final title = course['name'] ?? 'No Title';
                  // The description does not exist in the data model from the backend.
                  final description = 'No description available.';

                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text(description),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => CreateCourseScreen()),
          );
          if (result == true) {
            _loadData(); // Refresh the list if a course was created
          }
        },
        child: Icon(Icons.add),
        tooltip: 'Create Course',
      ),
    );
  }
}