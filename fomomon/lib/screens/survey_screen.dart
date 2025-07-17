import 'package:flutter/material.dart';
import '../models/site.dart';
import '../models/survey_response.dart';
import '../models/captured_session.dart';
import '../services/local_session_storage.dart';
import '../models/survey_question.dart';
import '../screens/home_screen.dart';

class SurveyScreen extends StatefulWidget {
  final String userId;
  final Site site;
  final String portraitImagePath;
  final String landscapeImagePath;
  final DateTime timestamp;
  final String name;
  final String email;
  final String org;

  const SurveyScreen({
    super.key,
    required this.userId,
    required this.site,
    required this.portraitImagePath,
    required this.landscapeImagePath,
    required this.timestamp,
    required this.name,
    required this.email,
    required this.org,
  });

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final Map<String, String> _answers = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Survey')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ...widget.site.surveyQuestions.map(_buildQuestion),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitSurvey,
              child: const Text('Submit Survey'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(SurveyQuestion question) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.question,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (question.type == 'text')
            _buildTextField(question)
          else if (question.type == 'mcq')
            _buildDropdown(question),
        ],
      ),
    );
  }

  Widget _buildTextField(SurveyQuestion question) {
    // Update the answer map every time the user types a letter.
    return TextField(
      decoration: const InputDecoration(border: OutlineInputBorder()),
      onChanged: (value) => _answers[question.id] = value,
    );
  }

  Widget _buildDropdown(SurveyQuestion question) {
    final options = question.options ?? [];

    return DropdownButtonFormField<String>(
      value: _answers[question.id],
      items:
          options
              .map((opt) => DropdownMenuItem(value: opt, child: Text(opt)))
              .toList(),
      onChanged: (value) {
        if (value != null) setState(() => _answers[question.id] = value);
      },
      decoration: const InputDecoration(border: OutlineInputBorder()),
    );
  }

  void _submitSurvey() async {
    final responses =
        _answers.entries
            .map((e) => SurveyResponse(questionId: e.key, answer: e.value))
            .toList();

    final session = CapturedSession(
      sessionId: '${widget.userId}_${widget.timestamp.toIso8601String()}',
      siteId: widget.site.id,
      latitude: widget.site.lat,
      longitude: widget.site.lng,
      portraitImagePath: widget.portraitImagePath,
      landscapeImagePath: widget.landscapeImagePath,
      timestamp: widget.timestamp,
      responses: responses,
      userId: widget.userId,
    );

    await LocalSessionStorage.saveSession(session);
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder:
            (_) => HomeScreen(
              name: widget.name,
              email: widget.email,
              org: widget.org,
            ),
      ),
      (route) => false,
    );
  }
}
