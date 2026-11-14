class UserModel {
  final int? id;
  final String employeeNo;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final String? approvedAt;
  final int? teamId;
  final String dob;
  final String address;
  final String city;
  final String state;
  final String zip;
  final String phone;
  final String username;
  final String emergencyName;
  final String emergencyPhone;
  final String emergencyRelationship;
  final String photoPath;

  const UserModel({
    this.id,
    this.employeeNo = '',
    this.fullName = '',
    this.email = '',
    this.role = '',
    this.status = '',
    this.approvedAt,
    this.teamId,
    this.dob = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.zip = '',
    this.phone = '',
    this.username = '',
    this.emergencyName = '',
    this.emergencyPhone = '',
    this.emergencyRelationship = '',
    this.photoPath = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: _toInt(json['id']),
      employeeNo: _toStr(json['employee_no'] ?? json['employeeId']),
      fullName: _toStr(json['fullName']),
      email: _toStr(json['email']),
      role: _toStr(json['role']),
      status: _toStr(json['status']),
      approvedAt: json['approvedAt']?.toString(),
      teamId: _toInt(json['team_id'] ?? json['teamId']),
      dob: _toStr(json['dob'] ?? json['dateOfBirth']),
      address: _toStr(json['address']),
      city: _toStr(json['city']),
      state: _toStr(json['state']),
      zip: _toStr(json['zip'] ?? json['zipCode']),
      phone: _toStr(json['phone']),
      username: _toStr(
        json['username'] ?? json['employee_no'] ?? json['employeeId'],
      ),
      emergencyName: _toStr(
        json['emergency_name'] ?? json['emergencyContactName'],
      ),
      emergencyPhone: _toStr(
        json['emergency_phone'] ?? json['emergencyContactPhone'],
      ),
      emergencyRelationship: _toStr(
        json['emergency_relationship'] ?? json['emergencyContactRelationship'],
      ),
      photoPath: _toStr(json['photo_path'] ?? json['photoURL']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'employee_no': employeeNo,
      'fullName': fullName,
      'email': email,
      'role': role,
      'status': status,
      'approvedAt': approvedAt,
      'team_id': teamId,
      'dob': dob,
      'address': address,
      'city': city,
      'state': state,
      'zip': zip,
      'phone': phone,
      'username': username,
      'emergency_name': emergencyName,
      'emergency_phone': emergencyPhone,
      'emergency_relationship': emergencyRelationship,
      'photo_path': photoPath,
    };
  }

  Map<String, dynamic> toProfileMap() {
    return {
      ...toJson(),
      'employeeId': employeeNo,
      'dateOfBirth': dob,
      'zipCode': zip,
      'emergencyContactName': emergencyName,
      'emergencyContactPhone': emergencyPhone,
      'emergencyContactRelationship': emergencyRelationship,
      'photoURL': photoPath,
    };
  }

  static String _toStr(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}
