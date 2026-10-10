import 'visit_flow_kind.dart';

class VisitReportDetails {
  const VisitReportDetails({
    this.title = '',
    this.category,
    this.categoryOther = '',
    this.details = '',
    this.description = '',
    this.occurredAt,
    this.location = '',
    this.peopleInvolved = '',
    this.attentionToPropertyManagement = false,
    this.attentionToNps = false,
  });

  final String title;
  final String? category;
  final String categoryOther;
  final String details;
  final String description;
  final DateTime? occurredAt;
  final String location;
  final String peopleInvolved;
  final bool attentionToPropertyManagement;
  final bool attentionToNps;

  static const issueOtherCategory = 'Other';

  static const issueCategories = <String>[
    'Suspicious Activity',
    'Suspicious Person',
    'Suspicious Vehicle',
    'Trespassing',
    'Unauthorized Access',
    'Homeless / Encampment',
    'Theft / Attempted Theft',
    'Vandalism / Property Damage',
    'Disturbance / Fight',
    'Noise Complaint',
    'Safety Hazard',
    'Medical Emergency',
    'Fire / Fire Alarm',
    'Accident / Injury',
    'Parking Violation',
    'Vehicle Incident',
    'Access Control Issue',
    'Door / Gate / Lock Issue',
    'Maintenance Issue',
    'Policy / Rule Violation',
    'Guest / Resident Assistance',
    'Visitor / Vendor Issue',
    'Welfare Check',
    'Delivery / Package Issue',
    'Lost & Found',
    'Patrol Observation',
    'Police / Fire / EMS Response',
    'Follow-Up Required',
    'Information Report',
    issueOtherCategory,
  ];

  static const incidentCategories = <String>[
    'Security',
    'Medical',
    'Fire',
    'Theft',
    'Property Damage',
    'Accident',
    'Other',
  ];

  static VisitReportDetails defaultsFor(VisitFlowKind kind) {
    switch (kind) {
      case VisitFlowKind.issueReport:
        return const VisitReportDetails(category: 'Suspicious Activity');
      case VisitFlowKind.incidentReport:
        return VisitReportDetails(
          category: 'Security',
          occurredAt: DateTime.now(),
        );
      case VisitFlowKind.patrol:
      case VisitFlowKind.siteCheck:
        return const VisitReportDetails();
    }
  }

  bool get isOtherCategory {
    final value = category?.trim().toLowerCase();
    return value == 'other';
  }

  /// True when the officer has entered report fields worth keeping as a draft.
  bool get hasUserContent {
    return title.trim().isNotEmpty ||
        details.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        location.trim().isNotEmpty ||
        peopleInvolved.trim().isNotEmpty ||
        categoryOther.trim().isNotEmpty ||
        attentionToPropertyManagement ||
        attentionToNps;
  }

  String get resolvedCategory {
    if (isOtherCategory) {
      return categoryOther.trim();
    }
    return category?.trim() ?? '';
  }

  bool isCompleteFor(VisitFlowKind kind) {
    final hasTitle = title.trim().isNotEmpty;
    switch (kind) {
      case VisitFlowKind.issueReport:
        final hasDetails = details.trim().isNotEmpty;
        final hasCategory = isOtherCategory
            ? categoryOther.trim().isNotEmpty
            : (category?.trim().isNotEmpty ?? false);
        return hasTitle && hasDetails && hasCategory;
      case VisitFlowKind.incidentReport:
        return hasTitle && description.trim().isNotEmpty;
      case VisitFlowKind.patrol:
      case VisitFlowKind.siteCheck:
        return true;
    }
  }

  String? validationMessageFor(VisitFlowKind kind) {
    if (isCompleteFor(kind)) return null;
    switch (kind) {
      case VisitFlowKind.issueReport:
        if (title.trim().isEmpty) return 'Please enter a title for this issue.';
        if (resolvedCategory.isEmpty) {
          return isOtherCategory
              ? 'Please type the issue type for category Other.'
              : 'Please select a category.';
        }
        if (details.trim().isEmpty) {
          return 'Please describe the issue in the details field.';
        }
        return 'Please complete the required issue fields.';
      case VisitFlowKind.incidentReport:
        if (title.trim().isEmpty) {
          return 'Please enter a title for this incident.';
        }
        if (description.trim().isEmpty) {
          return 'Please describe what happened.';
        }
        return 'Please complete the required incident fields.';
      case VisitFlowKind.patrol:
      case VisitFlowKind.siteCheck:
        return null;
    }
  }

  VisitReportDetails copyWith({
    String? title,
    String? category,
    String? categoryOther,
    String? details,
    String? description,
    DateTime? occurredAt,
    String? location,
    String? peopleInvolved,
    bool? attentionToPropertyManagement,
    bool? attentionToNps,
    bool clearCategory = false,
    bool clearOccurredAt = false,
  }) {
    return VisitReportDetails(
      title: title ?? this.title,
      category: clearCategory ? null : (category ?? this.category),
      categoryOther: categoryOther ?? this.categoryOther,
      details: details ?? this.details,
      description: description ?? this.description,
      occurredAt: clearOccurredAt ? null : (occurredAt ?? this.occurredAt),
      location: location ?? this.location,
      peopleInvolved: peopleInvolved ?? this.peopleInvolved,
      attentionToPropertyManagement:
          attentionToPropertyManagement ?? this.attentionToPropertyManagement,
      attentionToNps: attentionToNps ?? this.attentionToNps,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'category': category,
      'categoryOther': categoryOther,
      'details': details,
      'description': description,
      if (occurredAt != null) 'occurredAt': occurredAt!.toIso8601String(),
      'location': location,
      'peopleInvolved': peopleInvolved,
      'attentionToPropertyManagement': attentionToPropertyManagement,
      'attentionToNps': attentionToNps,
    };
  }

  Map<String, dynamic> _attentionUploadFields() {
    return <String, dynamic>{
      'attention_to_property_management': attentionToPropertyManagement
          ? 'yes'
          : 'no',
      'attention_to_nps': attentionToNps ? 'yes' : 'no',
    };
  }

  Map<String, dynamic> toUploadMeta(VisitFlowKind kind) {
    switch (kind) {
      case VisitFlowKind.issueReport:
        return <String, dynamic>{
          'title': title.trim(),
          'category': category?.trim(),
          if (isOtherCategory && categoryOther.trim().isNotEmpty)
            'category_other': categoryOther.trim(),
          'details': details.trim(),
          ..._attentionUploadFields(),
        };
      case VisitFlowKind.incidentReport:
        return <String, dynamic>{
          'title': title.trim(),
          if (category?.trim().isNotEmpty == true) 'category': category!.trim(),
          if (isOtherCategory && categoryOther.trim().isNotEmpty)
            'category_other': categoryOther.trim(),
          if (occurredAt != null)
            'occurred_at': occurredAt!.toUtc().toIso8601String(),
          if (location.trim().isNotEmpty) 'location': location.trim(),
          if (peopleInvolved.trim().isNotEmpty)
            'people_involved': peopleInvolved.trim(),
          'description': description.trim(),
          ..._attentionUploadFields(),
        };
      case VisitFlowKind.patrol:
      case VisitFlowKind.siteCheck:
        return const <String, dynamic>{};
    }
  }

  static VisitReportDetails? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    DateTime? occurredAt;
    final occurredRaw = json['occurredAt'] ?? json['occurred_at'];
    if (occurredRaw is String && occurredRaw.isNotEmpty) {
      occurredAt = DateTime.tryParse(occurredRaw);
    }
    return VisitReportDetails(
      title: (json['title'] as String?)?.toString() ?? '',
      category: _string(json['category']),
      categoryOther:
          (json['categoryOther'] ?? json['category_other'])?.toString() ?? '',
      details: (json['details'] as String?)?.toString() ?? '',
      description: (json['description'] as String?)?.toString() ?? '',
      occurredAt: occurredAt,
      location: (json['location'] as String?)?.toString() ?? '',
      peopleInvolved:
          (json['peopleInvolved'] ?? json['people_involved'])?.toString() ?? '',
      attentionToPropertyManagement: _bool(
        json['attentionToPropertyManagement'] ??
            json['attention_to_property_management'],
      ),
      attentionToNps: _bool(json['attentionToNps'] ?? json['attention_to_nps']),
    );
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }
}
