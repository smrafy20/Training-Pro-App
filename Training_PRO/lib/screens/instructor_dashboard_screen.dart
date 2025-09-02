import 'package:flutter/material.dart';
import 'package:lms_app/screens/create_course_screen.dart';
import 'package:lms_app/screens/login_screen.dart';
import 'package:lms_app/screens/course_materials_screen.dart';
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
  String? _userName;

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
      // Fetch session info to get user's name
      final sessionInfo = await _apiService.getSessionInfo();
      if (sessionInfo['success']) {
        setState(() {
          _userName = sessionInfo['name'];
        });
      }

      final allCourses = await _apiService.getCourses();
      setState(() {
        _courses = allCourses;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load data: ${e.toString()}')),
      );
      if (e.toString().contains('Unauthorized')) {
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

  Future<void> _confirmAndDeleteCourse(String courseId, String courseName) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Course'),
          content: Text('Are you sure you want to delete "$courseName"?'),
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
        await _apiService.deleteCourse(courseId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Course "$courseName" deleted successfully!')),
        );
        _loadData(); // Refresh the list
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete course: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('All Courses'),
        actions: [
          if (_userName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: Text('Hi, $_userName'),
              ),
            ),
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
                  final instructor = course['instructor'] ?? 'Unknown Instructor';
                  final description = 'Taught by: $instructor'; // Using subtitle for instructor name
                  final courseId = course['id'];

                  final bool canDelete = _userName != null && instructor == _userName;

                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text(description),
                      trailing: canDelete
                          ? IconButton(
                              icon: Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmAndDeleteCourse(courseId, title),
                              tooltip: 'Delete Course',
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CourseMaterialsScreen(
                              courseId: courseId,
                              courseName: title,
                            ),
                          ),
                        );
                      },
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