// Data models for NPS Registration Application
// These models mirror the JavaScript data structure from the HTML app

class UserAccount {
  final String id;
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String phone;
  final String dob;
  final String createdAt;
  ApplicationData application;

  UserAccount({
    required this.id,
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.dob,
    required this.createdAt,
    required this.application,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'password': password,
    'firstName': firstName,
    'lastName': lastName,
    'phone': phone,
    'dob': dob,
    'createdAt': createdAt,
    'application': application.toJson(),
  };

  factory UserAccount.fromJson(Map<String, dynamic> json) => UserAccount(
    id: json['id'] ?? '',
    email: json['email'] ?? '',
    password: json['password'] ?? '',
    firstName: json['firstName'] ?? '',
    lastName: json['lastName'] ?? '',
    phone: json['phone'] ?? '',
    dob: json['dob'] ?? '',
    createdAt: json['createdAt'] ?? '',
    application: ApplicationData.fromJson(json['application'] ?? {}),
  );
}

class ApplicationData {
  String? lastSavedAt;
  int currentPage;
  ProfileData profile;
  AvailabilityData availability;
  Map<String, SignatureData> signatures;
  AgreementsData agreements;
  Map<String, UniformItemData> uniformReceipt;
  ExpectationsData expectations;
  Map<String, dynamic> uploads;
  MetaData meta;

  ApplicationData({
    this.lastSavedAt,
    this.currentPage = 0,
    required this.profile,
    required this.availability,
    required this.signatures,
    required this.agreements,
    required this.uniformReceipt,
    required this.expectations,
    required this.uploads,
    required this.meta,
  });

  Map<String, dynamic> toJson() => {
    'lastSavedAt': lastSavedAt,
    'currentPage': currentPage,
    'profile': profile.toJson(),
    'availability': availability.toJson(),
    'signatures': signatures.map((k, v) => MapEntry(k, v.toJson())),
    'agreements': agreements.toJson(),
    'uniformReceipt': uniformReceipt.map((k, v) => MapEntry(k, v.toJson())),
    'expectations': expectations.toJson(),
    'uploads': uploads,
    'meta': meta.toJson(),
  };

  factory ApplicationData.fromJson(Map<String, dynamic> json) =>
      ApplicationData(
        lastSavedAt: json['lastSavedAt'],
        currentPage: json['currentPage'] ?? 0,
        profile: ProfileData.fromJson(json['profile'] ?? {}),
        availability: AvailabilityData.fromJson(json['availability'] ?? {}),
        signatures:
            (json['signatures'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, SignatureData.fromJson(v)),
            ) ??
            {},
        agreements: AgreementsData.fromJson(json['agreements'] ?? {}),
        uniformReceipt:
            (json['uniformReceipt'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, UniformItemData.fromJson(v)),
            ) ??
            {},
        expectations: ExpectationsData.fromJson(json['expectations'] ?? {}),
        uploads: json['uploads'] ?? {},
        meta: MetaData.fromJson(json['meta'] ?? {}),
      );

  factory ApplicationData.empty({ProfileData? profile}) => ApplicationData(
    currentPage: 0,
    profile: profile ?? ProfileData.empty(),
    availability: AvailabilityData.empty(),
    signatures: {},
    agreements: AgreementsData.empty(),
    uniformReceipt: {},
    expectations: ExpectationsData.empty(),
    uploads: {},
    meta: MetaData(
      registeredAt: DateTime.now().toIso8601String(),
      accountDevice: 'Flutter App',
    ),
  );
}

class ProfileData {
  String firstName;
  String lastName;
  String middleInitial;
  String street;
  String apartment;
  String city;
  String state;
  String zip;
  String phone;
  String email;
  String driversLicense;
  String ssn;
  String dob;
  String hairColor;
  String eyeColor;
  String height;
  String weight;
  String citizen;
  String authorizedToWork;
  String workedBefore;
  String workedBeforeWhen;
  String felony;
  String felonyExplain;
  String otherName;
  String otherNameExplain;
  String recentEmployment;
  String recentCompany;
  String recentPhone;
  String recentAddress;
  String recentJobTitle;
  String emergencyName;
  String emergencyRelationship;
  String emergencyPhone;
  String emergencyAltPhone;
  String guardCard;
  String guardCardExpiry;
  String firearmPermit;
  String firearmPermitExpiry;

  ProfileData({
    this.firstName = '',
    this.lastName = '',
    this.middleInitial = '',
    this.street = '',
    this.apartment = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.phone = '',
    this.email = '',
    this.driversLicense = '',
    this.ssn = '',
    this.dob = '',
    this.hairColor = '',
    this.eyeColor = '',
    this.height = '',
    this.weight = '',
    this.citizen = '',
    this.authorizedToWork = '',
    this.workedBefore = '',
    this.workedBeforeWhen = '',
    this.felony = '',
    this.felonyExplain = '',
    this.otherName = '',
    this.otherNameExplain = '',
    this.recentEmployment = '',
    this.recentCompany = '',
    this.recentPhone = '',
    this.recentAddress = '',
    this.recentJobTitle = '',
    this.emergencyName = '',
    this.emergencyRelationship = '',
    this.emergencyPhone = '',
    this.emergencyAltPhone = '',
    this.guardCard = '',
    this.guardCardExpiry = '',
    this.firearmPermit = '',
    this.firearmPermitExpiry = '',
  });

  factory ProfileData.empty() => ProfileData();

  Map<String, dynamic> toJson() => {
    'firstName': firstName,
    'lastName': lastName,
    'middleInitial': middleInitial,
    'street': street,
    'apartment': apartment,
    'city': city,
    'state': state,
    'zip': zip,
    'phone': phone,
    'email': email,
    'driversLicense': driversLicense,
    'ssn': ssn,
    'dob': dob,
    'hairColor': hairColor,
    'eyeColor': eyeColor,
    'height': height,
    'weight': weight,
    'citizen': citizen,
    'authorizedToWork': authorizedToWork,
    'workedBefore': workedBefore,
    'workedBeforeWhen': workedBeforeWhen,
    'felony': felony,
    'felonyExplain': felonyExplain,
    'otherName': otherName,
    'otherNameExplain': otherNameExplain,
    'recentEmployment': recentEmployment,
    'recentCompany': recentCompany,
    'recentPhone': recentPhone,
    'recentAddress': recentAddress,
    'recentJobTitle': recentJobTitle,
    'emergencyName': emergencyName,
    'emergencyRelationship': emergencyRelationship,
    'emergencyPhone': emergencyPhone,
    'emergencyAltPhone': emergencyAltPhone,
    'guardCard': guardCard,
    'guardCardExpiry': guardCardExpiry,
    'firearmPermit': firearmPermit,
    'firearmPermitExpiry': firearmPermitExpiry,
  };

  factory ProfileData.fromJson(Map<String, dynamic> json) => ProfileData(
    firstName: json['firstName'] ?? '',
    lastName: json['lastName'] ?? '',
    middleInitial: json['middleInitial'] ?? '',
    street: json['street'] ?? '',
    apartment: json['apartment'] ?? '',
    city: json['city'] ?? '',
    state: json['state'] ?? '',
    zip: json['zip'] ?? '',
    phone: json['phone'] ?? '',
    email: json['email'] ?? '',
    driversLicense: json['driversLicense'] ?? '',
    ssn: json['ssn'] ?? '',
    dob: json['dob'] ?? '',
    hairColor: json['hairColor'] ?? '',
    eyeColor: json['eyeColor'] ?? '',
    height: json['height'] ?? '',
    weight: json['weight'] ?? '',
    citizen: json['citizen'] ?? '',
    authorizedToWork: json['authorizedToWork'] ?? '',
    workedBefore: json['workedBefore'] ?? '',
    workedBeforeWhen: json['workedBeforeWhen'] ?? '',
    felony: json['felony'] ?? '',
    felonyExplain: json['felonyExplain'] ?? '',
    otherName: json['otherName'] ?? '',
    otherNameExplain: json['otherNameExplain'] ?? '',
    recentEmployment: json['recentEmployment'] ?? '',
    recentCompany: json['recentCompany'] ?? '',
    recentPhone: json['recentPhone'] ?? '',
    recentAddress: json['recentAddress'] ?? '',
    recentJobTitle: json['recentJobTitle'] ?? '',
    emergencyName: json['emergencyName'] ?? '',
    emergencyRelationship: json['emergencyRelationship'] ?? '',
    emergencyPhone: json['emergencyPhone'] ?? '',
    emergencyAltPhone: json['emergencyAltPhone'] ?? '',
    guardCard: json['guardCard'] ?? '',
    guardCardExpiry: json['guardCardExpiry'] ?? '',
    firearmPermit: json['firearmPermit'] ?? '',
    firearmPermitExpiry: json['firearmPermitExpiry'] ?? '',
  );
}

class AvailabilityData {
  Map<String, bool> fullTime;
  Map<String, bool> partTime;
  Map<String, bool> evening;
  Map<String, bool> night;
  Map<String, bool> onCall;

  AvailabilityData({
    required this.fullTime,
    required this.partTime,
    required this.evening,
    required this.night,
    required this.onCall,
  });

  factory AvailabilityData.empty() => AvailabilityData(
    fullTime: {},
    partTime: {},
    evening: {},
    night: {},
    onCall: {},
  );

  Map<String, dynamic> toJson() => {
    'fullTime': fullTime,
    'partTime': partTime,
    'evening': evening,
    'night': night,
    'onCall': onCall,
  };

  factory AvailabilityData.fromJson(Map<String, dynamic> json) =>
      AvailabilityData(
        fullTime: Map<String, bool>.from(json['fullTime'] ?? {}),
        partTime: Map<String, bool>.from(json['partTime'] ?? {}),
        evening: Map<String, bool>.from(json['evening'] ?? {}),
        night: Map<String, bool>.from(json['night'] ?? {}),
        onCall: Map<String, bool>.from(json['onCall'] ?? {}),
      );
}

class SignatureData {
  String dataUrl;
  String signedAt;
  String device;

  SignatureData({
    required this.dataUrl,
    required this.signedAt,
    required this.device,
  });

  Map<String, dynamic> toJson() => {
    'dataUrl': dataUrl,
    'signedAt': signedAt,
    'device': device,
  };

  factory SignatureData.fromJson(Map<String, dynamic> json) => SignatureData(
    dataUrl: json['dataUrl'] ?? '',
    signedAt: json['signedAt'] ?? '',
    device: json['device'] ?? '',
  );
}

class AgreementsData {
  String baseRate;
  bool driverNotApplicable;
  bool tattooNotApplicable;
  String mealGuideAgree;
  bool finalEmployeeConfirm;

  AgreementsData({
    this.baseRate = '',
    this.driverNotApplicable = false,
    this.tattooNotApplicable = false,
    this.mealGuideAgree = '',
    this.finalEmployeeConfirm = false,
  });

  factory AgreementsData.empty() => AgreementsData();

  Map<String, dynamic> toJson() => {
    'baseRate': baseRate,
    'driverNotApplicable': driverNotApplicable,
    'tattooNotApplicable': tattooNotApplicable,
    'mealGuideAgree': mealGuideAgree,
    'finalEmployeeConfirm': finalEmployeeConfirm,
  };

  factory AgreementsData.fromJson(Map<String, dynamic> json) => AgreementsData(
    baseRate: json['baseRate'] ?? '',
    driverNotApplicable: json['driverNotApplicable'] ?? false,
    tattooNotApplicable: json['tattooNotApplicable'] ?? false,
    mealGuideAgree: json['mealGuideAgree'] ?? '',
    finalEmployeeConfirm: json['finalEmployeeConfirm'] ?? false,
  );
}

class UniformItemData {
  String size;
  String received;
  String returned;

  UniformItemData({this.size = '', this.received = '', this.returned = ''});

  Map<String, dynamic> toJson() => {
    'size': size,
    'received': received,
    'returned': returned,
  };

  factory UniformItemData.fromJson(Map<String, dynamic> json) =>
      UniformItemData(
        size: json['size'] ?? '',
        received: json['received'] ?? '',
        returned: json['returned'] ?? '',
      );
}

class ExpectationsData {
  bool understandsPolicies;
  bool understandsReporting;
  bool understandsAttendance;
  bool understandsProfessionalism;
  bool finalEmployeeConfirm;
  String finalNotes;

  ExpectationsData({
    this.understandsPolicies = false,
    this.understandsReporting = false,
    this.understandsAttendance = false,
    this.understandsProfessionalism = false,
    this.finalEmployeeConfirm = false,
    this.finalNotes = '',
  });

  factory ExpectationsData.empty() => ExpectationsData();

  Map<String, dynamic> toJson() => {
    'understandsPolicies': understandsPolicies,
    'understandsReporting': understandsReporting,
    'understandsAttendance': understandsAttendance,
    'understandsProfessionalism': understandsProfessionalism,
    'finalEmployeeConfirm': finalEmployeeConfirm,
    'finalNotes': finalNotes,
  };

  factory ExpectationsData.fromJson(Map<String, dynamic> json) =>
      ExpectationsData(
        understandsPolicies: json['understandsPolicies'] ?? false,
        understandsReporting: json['understandsReporting'] ?? false,
        understandsAttendance: json['understandsAttendance'] ?? false,
        understandsProfessionalism: json['understandsProfessionalism'] ?? false,
        finalEmployeeConfirm: json['finalEmployeeConfirm'] ?? false,
        finalNotes: json['finalNotes'] ?? '',
      );
}

class MetaData {
  String registeredAt;
  String accountDevice;

  MetaData({required this.registeredAt, required this.accountDevice});

  Map<String, dynamic> toJson() => {
    'registeredAt': registeredAt,
    'accountDevice': accountDevice,
  };

  factory MetaData.fromJson(Map<String, dynamic> json) => MetaData(
    registeredAt: json['registeredAt'] ?? '',
    accountDevice: json['accountDevice'] ?? '',
  );
}

// Step definitions matching the JavaScript steps array
class ApplicationStep {
  final String id;
  final String title;
  final String subtitle;

  const ApplicationStep({
    required this.id,
    required this.title,
    required this.subtitle,
  });
}

const List<ApplicationStep> applicationSteps = [
  ApplicationStep(
    id: 'profile',
    title: 'Employment Application',
    subtitle:
        'Applicant information, availability, emergency contact, permit information',
  ),
  ApplicationStep(
    id: 'terms',
    title: 'Agreement & Terms of Employment',
    subtitle: 'Employment terms and pay rate acknowledgment',
  ),
  ApplicationStep(
    id: 'arbitration',
    title: 'At-Will and Arbitration Agreement',
    subtitle: 'Binding arbitration acknowledgment and signatures',
  ),
  ApplicationStep(
    id: 'eeo',
    title: 'Equal Employment Opportunity',
    subtitle: 'Anti-harassment and non-retaliation acknowledgment',
  ),
  ApplicationStep(
    id: 'noncompete',
    title: 'Non-Competitive and Driver Agreement',
    subtitle: 'Client non-solicitation and company vehicle agreement',
  ),
  ApplicationStep(
    id: 'release',
    title: 'Security Officer Notification & Release',
    subtitle: 'Background report authorization',
  ),
  ApplicationStep(
    id: 'pay',
    title: 'Pay System & Schedule',
    subtitle: 'Weekly payroll policy acknowledgment',
  ),
  ApplicationStep(
    id: 'uniformReceipt',
    title: 'Uniform Issue / Return Receipt',
    subtitle: 'Uniform issue record and return acknowledgment',
  ),
  ApplicationStep(
    id: 'uniformStandards',
    title: 'Uniform Standards',
    subtitle: 'Appearance and uniform standards acknowledgment',
  ),
  ApplicationStep(
    id: 'tattoos',
    title: 'Visible Tattoos',
    subtitle: 'Tattoo coverage acknowledgment when applicable',
  ),
  ApplicationStep(
    id: 'offDuty',
    title: 'Uniform While Off-Duty',
    subtitle: 'Off-duty uniform coverage policy',
  ),
  ApplicationStep(
    id: 'mealGuide',
    title: 'Meal Period Policy & Guide',
    subtitle: 'Meal period guide and agreement choice',
  ),
  ApplicationStep(
    id: 'mealAgreement',
    title: 'On-Duty Meal Period & Rest Break',
    subtitle: 'California on-duty meal agreement and rest break notice',
  ),
  ApplicationStep(
    id: 'expectations',
    title: 'Expectations from Employees',
    subtitle: 'Final employee expectations confirmation and final review',
  ),
  ApplicationStep(
    id: 'w4',
    title: 'W-4 Form (Federal Withholding Form)',
    // subtitle: 'Complete and submit IRS W-4 before or at start of employment',
    subtitle: '',
  ),
  ApplicationStep(
    id: 'review',
    title: 'Review & Finish',
    subtitle: 'Check completion, print, and export application',
  ),
];
