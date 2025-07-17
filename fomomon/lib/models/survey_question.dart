class SurveyQuestion {
  final String id;
  final String question;
  final String type; // 'text' or 'mcq'
  final List<String>? options;

  SurveyQuestion({
    required this.id,
    required this.question,
    required this.type,
    this.options,
  });

  factory SurveyQuestion.fromJson(Map<String, dynamic> json) {
    return SurveyQuestion(
      id: json['id'],
      question: json['question'],
      type: json['type'],
      options: (json['options'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'question': question,
      'type': type,
      if (options != null) 'options': options,
    };
  }
}
