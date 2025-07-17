class SurveyResponse {
  final String questionId;
  final String answer;

  SurveyResponse({required this.questionId, required this.answer});

  factory SurveyResponse.fromJson(Map<String, dynamic> json) {
    return SurveyResponse(
      questionId: json['questionId'],
      answer: json['answer'],
    );
  }

  Map<String, dynamic> toJson() {
    return {'questionId': questionId, 'answer': answer};
  }
}
