enum VisitFlowKind {
  patrol,
  siteCheck,
  issueReport,
  incidentReport;

  static const issueReportVisitType = 'issue_report';
  static const incidentReportVisitType = 'incident_report';
  static const siteCheckVisitType = 'site_check';

  bool get isStructuredReport =>
      this == VisitFlowKind.issueReport || this == VisitFlowKind.incidentReport;

  String? get draftFolderSuffix {
    switch (this) {
      case VisitFlowKind.issueReport:
        return 'issue';
      case VisitFlowKind.incidentReport:
        return 'incident';
      case VisitFlowKind.patrol:
      case VisitFlowKind.siteCheck:
        return null;
    }
  }

  String get visitTypeValue {
    switch (this) {
      case VisitFlowKind.issueReport:
        return issueReportVisitType;
      case VisitFlowKind.incidentReport:
        return incidentReportVisitType;
      case VisitFlowKind.siteCheck:
        return siteCheckVisitType;
      case VisitFlowKind.patrol:
        return 'patrol';
    }
  }

  static VisitFlowKind fromVisitType(String? visitType) {
    final value = visitType?.trim().toLowerCase();
    if (value == null || value.isEmpty) return VisitFlowKind.patrol;
    switch (value) {
      case siteCheckVisitType:
        return VisitFlowKind.siteCheck;
      case issueReportVisitType:
      case 'issue':
      case 'report_issue':
      case 'report-an-issue':
        return VisitFlowKind.issueReport;
      case incidentReportVisitType:
      case 'incident':
        return VisitFlowKind.incidentReport;
      default:
        return VisitFlowKind.patrol;
    }
  }

  static VisitFlowKind? tryParseDraftSuffix(String? suffix) {
    switch (suffix?.trim().toLowerCase()) {
      case 'issue':
        return VisitFlowKind.issueReport;
      case 'incident':
        return VisitFlowKind.incidentReport;
      default:
        return null;
    }
  }
}
