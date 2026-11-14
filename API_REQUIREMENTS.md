# NPS Schedules 360 - REST API Requirements
## Overview
 
### 1. Authentication Operations

---

#### Operation: Login (Email & Password)

**Type:** PROPOSED ENDPOINT 

**Proposed Endpoint:** `POST /api/auth/login`  
**HTTP Method:** POST
 
**Purpose:**  
Authenticate user using email/ID and password. Return authentication token(s) and basic user profile for dashboard display.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `email` | string | YES | Valid email format (shown as "Enter your ID" in UI) |
| `password` | string | YES | Min 1 char (no visible min length in login, but signup suggests min 8) |

**Example Request:**
```json
{
  "email": "officer@example.com",
  "password": "password123",
}
```

**Expected Response (inferred):**
```json
{
  "token": "string (JWT or session token)",
  "refreshToken": "string (optional)",
  "user": {
    "id": "string (uid)",
    "email": "string",
    "fullName": "string",
    "role": "string (e.g., 'user', 'officer')"
  },
  "lastLoginAt": "ISO8601 timestamp"
}

**Auth / Permissions:**
- No auth required to call this endpoint.
- Public endpoint for password recovery.
```
 

#### Operation: User Registration (Multi-Step)

#### Step Validation API Requirements

The frontend validates form fields progressively across steps. To support real-time validation, the backend should provide step-specific validation endpoints that check for conflicts (e.g., email/username already exists) and field correctness.

##### Step 1 - Validate Personal Information

**Proposed Endpoint:** `POST /api/auth/register/validate-step-1`  
**HTTP Method:** POST

**Used On Screen(s):** PersonalInfoStep

**Purpose:**  
Validate Step 1 personal information fields (email, phone) against backend rules. Check if email is already registered and validate field formats.

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `email` | string | YES | Email to validate for uniqueness and format |
| `phone` | string | YES | Phone number to validate |
| `fullName` | string | YES | Full name for format validation |
| `dateOfBirth` | string (YYYY-MM-DD) | YES | Date of birth to validate |

**Example Request:**
```json
{
  "fullName": "John Officer",
  "dateOfBirth": "1990-01-15",
  "phone": "+1 555 123 4567",
  "email": "john.officer@example.com"
}
```

**Expected Response (Success):**
```json
{
  "success": true,
  "message": "Step 1 validation passed",
  "fields": {
    "email": { "valid": true },
    "phone": { "valid": true },
    "fullName": { "valid": true },
    "dateOfBirth": { "valid": true }
  }
}
```

**Expected Response (Email Already Exists):**
```json
{
  "success": false,
  "message": "Email already registered",
  "fields": {
    "email": { "valid": false, "error": "This email is already in use" }
  }
}
```

**Auth / Permissions:**
- No auth required.
- Public endpoint for registration validation.

---

##### Step 2 - Validate Account Information

**Proposed Endpoint:** `POST /api/auth/register/validate-step-2`  
**HTTP Method:** POST

**Used On Screen(s):** AccountInfoStep

**Purpose:**  
Validate Step 2 account information fields (username, password). Check if username is available and validate password complexity.

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `username` | string | YES | Username to validate for uniqueness and format |
| `password` | string | YES | Password to validate for complexity/length |

**Example Request:**
```json
{
  "username": "johnofficer",
  "password": "SecurePass123!"
}
```

**Expected Response (Success):**
```json
{
  "success": true,
  "message": "Step 2 validation passed",
  "fields": {
    "username": { "valid": true },
    "password": { "valid": true }
  }
}
```

**Expected Response (Username Already Exists):**
```json
{
  "success": false,
  "message": "Username already taken",
  "fields": {
    "username": { "valid": false, "error": "This username is already taken" }
  }
}
```

**Auth / Permissions:**
- No auth required.
- Public endpoint for registration validation.

---


**Type:** PROPOSED ENDPOINT 

**Proposed Endpoint:** `POST /api/auth/register`  
**HTTP Method:** POST

**Used On Screen(s):**

- **Step 1:** PersonalInfoStep
- **Step 2:** AccountInfoStep
- **Step 3:** ContactInfoStep

**Request Data:**


**Step 1 - Personal Information:**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `fullName` | string | YES | Full legal name |
| `dateOfBirth` | date | YES | Format: MM/dd/yyyy (from date picker) |
| `phone` | string | YES | Phone number (no strict format visible in UI) |
| `email` | string | YES | Valid email format |
| `selfiePhoto` | file/base64 | YES | Self-portrait image, jpg/png, max 75% quality |
| `idPhoto` | file/base64 | YES | ID/government photo, jpg/png, max 75% quality |

**Step 2 - Account Information:**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `username` | string | YES | Unique username for login |
| `password` | string | YES | Min 8 characters (inferred from typical password rules) |
| `confirmPassword` | string | YES | Must match password (validated on frontend) |

**Step 3 - Contact Information:**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `address` | string | YES | Residential address |
| `city` | string | YES | City name |
| `state` | string | YES | State/Province |
| `zipCode` | string | YES | ZIP/Postal code |
| `emergencyContactName` | string | YES | Full name of emergency contact |
| `emergencyContactRelationship` | string | YES | Relationship to officer (e.g., "Brother") |
| `emergencyContactPhone` | string | YES | Phone number of emergency contact |
| `agreedToTerms` | boolean | YES | "I certify the information provided is true and complete" |

**Example Request:**
```json
{
  "fullName": "John Officer",
  "dateOfBirth": "1990-01-15",
  "phone": "+1 555 123 4567",
  "email": "john.officer@example.com",
  "selfiePhoto": "base64_encoded_image_data_or_file_reference",
  "idPhoto": "base64_encoded_image_data_or_file_reference",
  "username": "johnofficer",
  "password": "SecurePass123!",
  "address": "123 Main Street",
  "city": "New York",
  "state": "NY",
  "zipCode": "10001",
  "emergencyContactName": "Jane Officer",
  "emergencyContactRelationship": "Sister",
  "emergencyContactPhone": "+1 555 987 6543",
  "agreedToTerms": true
}
```

**Expected Response (inferred):**
```json
{
  "success": true,
  "message": "Application submitted successfully! Pending admin approval.",
  "userId": "string (temporary ID)",
  "status": "pending_approval",
  "email": "john.officer@example.com"
}
```


 
**Auth / Permissions:**
- No auth required to call this endpoint.
- Public endpoint for password recovery.

---

#### Operation: Password Reset Request

**Proposed Endpoint:** `POST /api/auth/forgot-password`  
**HTTP Method:** POST



**Purpose:**  
Send password reset email to user's registered email address. Backend verifies email exists before sending reset link.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `email` | string | YES | Must be valid email and must exist in system |

**Example Request:**
```json
{
  "email": "officer@example.com"
}
```

**Expected Response (inferred):**
```json
{
  "success": true,
  "message": "Password reset email sent. Check your inbox.",
  "email": "officer@example.com"
}
```

**Auth / Permissions:**
- No auth required to call this endpoint.
- Public endpoint for password recovery.

**Notes / Business Rules:**
- Frontend checks if email is empty before sending: `"Please enter your email address"`
- Backend must verify email exists in database before sending reset email.
- If email not found, return: `"No account found with this email address"`
- Email should contain:
  - Reset link (with token)
  - Token expiration time (suggested: 24 hours)
  - Instructions to reset password
- Frontend shows: `"Please check your email for reset instructions"`

---

#### Operation: Logout / Sign Out

**Proposed Endpoint:** `POST /api/auth/logout`  
**HTTP Method:** POST

**Purpose:**  
Invalidate session/token and clear user authentication on server side.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| (body may be empty) | — | — | Token passed in Authorization header |

**Example Request:**
```json
{}
```

**Expected Response (inferred):**
```json
{
  "success": true,
  "message": "Logged out successfully"
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- Only authenticated users can call this endpoint.

---


### 2. User Profile Operations

---

#### Operation: Get User Profile


**Proposed Endpoint:** `GET /api/users/profile`  
**HTTP Method:** GET

**Purpose:**  
Retrieve authenticated user's full profile including personal, account, and contact information.

**Example Request:**
```
GET /api/users/profile
Authorization: Bearer {token}
```

**Expected Response (inferred from UI display):**
```json
{
  "id": "string (uid)",
  "fullName": "string",
  "email": "string",
  "phone": "string",
  "dateOfBirth": "YYYY-MM-DD",
  "username": "string",
  "role": "string",
  "address": "string",
  "city": "string",
  "state": "string",
  "zipCode": "string",
  "emergencyContactName": "string",
  "emergencyContactRelationship": "string",
  "emergencyContactPhone": "string",
  "employeeId": "string (if applicable)",
  "photoURL": "string (optional)",
  "createdAt": "ISO8601 timestamp",
  "lastLoginAt": "ISO8601 timestamp"
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- User can only retrieve their own profile.

---

#### Operation: Update User Profile

**Proposed Endpoint:** `PUT /api/users/profile`  
**HTTP Method:** PUT

**Purpose:**  
Update user's profile information. Supports partial updates (only changed fields).

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `fullName` | string | NO | Full name |
| `phone` | string | NO | Phone number |
| `dateOfBirth` | date | NO | Format: YYYY-MM-DD |
| `address` | string | NO | Residential address |
| `city` | string | NO | City name |
| `state` | string | NO | State/Province |
| `zipCode` | string | NO | ZIP/Postal code |
| `emergencyContactName` | string | NO | Emergency contact name |
| `emergencyContactRelationship` | string | NO | Relationship |
| `emergencyContactPhone` | string | NO | Emergency contact phone |

**Example Request:**
```json
{
  "fullName": "Test Officer Updated",
  "phone": "+1 987 654 3210",
  "address": "456 Secure Ave",
  "city": "Los Angeles",
  "state": "CA",
  "zipCode": "90001",
  "emergencyContactName": "Jane Officer",
  "emergencyContactPhone": "+1 555 987 6543"
}
```

**Expected Response (inferred):**
```json
{
  "success": true,
  "message": "Profile updated successfully",
  "user": {
    "id": "string",
    "fullName": "Test Officer Updated",
    "email": "test@example.com",
    "phone": "+1 987 654 3210",
    "updatedAt": "ISO8601 timestamp"
  }
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)

---

### 3. Dashboard / Assignments Operations

---

### Operation: Get Monthly Schedule Calendar

**Endpoint:** `GET /api/schedules/monthly`
**HTTP Method:** `GET`

**Purpose:**
Return all scheduled shifts for the selected month so the calendar can:


---

### Request Data

| Field   | Type   | Required | Validation / Notes                                                                 |
| ------- | ------ | -------- | ---------------------------------------------------------------------------------- |
| `month` | string | NO       | Target month in `YYYY-MM` (e.g., `2025-12`). Defaults to current month if omitted. |

---

### Example Request

```http
GET /api/schedules/monthly?month=2025-12
Authorization: Bearer {token}
```

---

### Expected Response

```json
{
  "month": "December 2025",
  "year": 2025,
  "data": [
    {
      "date": "2025-12-07",
      "status": "Permanent Shift",
      "title": "Morning Shift",
      "timeRange": "8:00 AM – 8:00 PM",
      "note": "30m unpaid",
      "startDateTime": "2025-12-07T08:00:00Z",
      "endDateTime": "2025-12-07T20:00:00Z",
      "unpaidBreakMinutes": 30
    },
    {
      "date": "2025-12-26",
      "status": "Permanent Shift",
      "title": "Morning Shift",
      "timeRange": "8:00 AM – 8:00 PM",
      "note": "30m unpaid",
      "startDateTime": "2025-12-26T08:00:00Z",
      "endDateTime": "2025-12-26T20:00:00Z",
      "unpaidBreakMinutes": 30
    }
  ]
}
```

---

### Auth / Permissions

* **Requires authentication token** (Bearer token in `Authorization` header).
* Officer should only receive **their own** scheduled shifts.

#### Operation: Get User Assignments

**Proposed Endpoint:** `GET /api/assignments`  
**HTTP Method:** GET

**Purpose:**  
Retrieve list of security patrol assignments/schedules for the authenticated officer. Shows sites, round types, completion status.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `page` | number | NO | Page number (0-indexed or 1-indexed, TBD) |
| `pageSize` | number | NO | Records per page (default: suggested 20-50) |
| `status` | string | NO | Filter by status: 'Completed', 'Pending' |
| `sortBy` | string | NO | Sort field: 'site', 'date', 'status' |

**Example Request:**
```
GET /api/assignments?page=0&pageSize=20&status=Pending
Authorization: Bearer {token}
```

**Expected Response (inferred from UI):**
```json
{
  "data": [
    {
      "id": "string (assignment ID)",
      "index": "number (display order)",
      "site": "string (site name/address)",
      "roundType": "string (e.g., 'Patrol')",
      "frequency": "string (e.g., 'Daily', 'Weekly')",
      "completed": "number (rounds completed)",
      "total": "number (total rounds required)",
      "status": "string ('Completed' or 'Pending')",
      "startTime": "ISO8601 timestamp (if applicable)",
      "endTime": "ISO8601 timestamp (if applicable)"
    }
  ],
  "pagination": {
    "page": "number",
    "pageSize": "number",
    "totalRecords": "number",
    "totalPages": "number"
  }
}
```

**Example Assignments from Frontend:**
```json
{
  "data": [
    {
      "id": "assign_1",
      "index": 1,
      "site": "742 Grayson Street",
      "roundType": "Patrol",
      "frequency": "Daily",
      "completed": 1,
      "total": 1,
      "status": "Completed"
    },
    {
      "id": "assign_4",
      "index": 4,
      "site": "1380 N California Blvd",
      "roundType": "Patrol",
      "frequency": "Daily",
      "completed": 0,
      "total": 1,
      "status": "Pending"
    }
  ],
  "pagination": {
    "page": 0,
    "pageSize": 20,
    "totalRecords": 9,
    "totalPages": 1
  }
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- User retrieves only their own assignments.

---

### Dashboard / Time Tracker (Region/Shift selection & Dialer)

#### Operation: Get Available Regions

**Proposed Endpoint:** `GET /api/locations/regions`  
**HTTP Method:** GET


**Purpose:**
Return the list of available regions the officer can select as their scope.


**Expected Response:**
```json
{
  "data": [
   "East Bay Patrol" ,
     "East Bay Stationed Sites" ,
      "Los Angeles" 
  ]
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
 
#### Operation: Get Available Shifts

**Proposed Endpoint:** `GET /api/shifts`  
**HTTP Method:** GET
 

**Purpose:**
Return a list of shift options (labels and time ranges) relevant to the officer or selected region.
 
**Example Request:**
```
GET /api/shifts?regionId=region_eb_patrol
Authorization: Bearer {token}
```

**Expected Response:**
```json
{
  "data": [
    {  "label": "EB Morning / Stagger Patrol (08:00 AM - 06:00 PM)", "start": "08:00", "end": "18:00" },
    {  "label": "EB Swing / Graveyard Patrol (06:00 PM - 08:00 AM)", "start": "18:00", "end": "08:00" }
  ]
}
```

**Auth / Permissions:**
- **Requires authentication token**
 

#### Operation: Clock In (start shift session)

**Proposed Endpoint:** `POST /api/time-tracker/clock-in`  
**HTTP Method:** POST
 
**Purpose:**
Begin an on-duty session for the officer. The frontend will prompt for Region & Shift if not already selected; the chosen scope should be sent with the clock-in request so the server can persist the active session.

**Request Body:**

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `regionId` | string | YES | Selected region id (from `/api/locations/regions`) |
| `shiftId` | string | YES | Selected shift id (from `/api/shifts`) | 
| `clockInAt` | string (ISO8601) | NO | Optional client timestamp; server will record authoritative timestamp if omitted |
| `latitude` | number | NO | Optional GPS coordinate |
| `longitude` | number | NO | Optional GPS coordinate |

**Example Request:**
```json
{
  "regionId": "region_eb_patrol",
  "shiftId": "shift_eb_morning", 
  "latitude": 37.902,
  "longitude": -122.056
}
```

**Expected Response:**
```json
{
  "sessionId": "string",
  "userId": "string",
  "regionId": "region_eb_patrol",
  "shiftId": "shift_eb_morning",
  "clockInAt": "2025-12-07T08:00:12Z",
  "status": "on_duty"
}
```

**Auth / Permissions:**
- **Requires authentication token**

**Notes / Business Rules:** 
- If the officer is already on an active session, the endpoint should return `409 Conflict` with the active `sessionId`.

#### Operation: Start Break

**Proposed Endpoint:** `POST /api/time-tracker/{sessionId}/break-start`  
**HTTP Method:** POST
 
**Purpose:**
Record the start of a break for the given shift session.

**Request Body / Path Params:**
- `sessionId` (path) — required
- `breakStartAt` (ISO8601) — optional client timestamp

**Example Request:**
```
POST /api/time-tracker/session_123/break-start
Authorization: Bearer {token}

Body: { "breakStartAt": "2025-12-07T12:15:00Z" }
```

**Expected Response:**
```json
{
  "sessionId": "session_123",
  "breakStartAt": "2025-12-07T12:15:00Z",
  "status": "on_break"
}
```

**Auth / Permissions:**
- **Requires authentication token**

**Notes:**
- Frontend checks `breakAllowed` before enabling Start Break; backend should enforce policy (e.g., shift rules, required minimum work before break).

#### Operation: End Break

**Proposed Endpoint:** `POST /api/time-tracker/{sessionId}/break-end`  
**HTTP Method:** POST
 
**Purpose:**
Record break end and accumulate break duration into the active session.

**Request Body / Path Params:**
- `sessionId` (path) — required
- `breakEndAt` (ISO8601) — optional client timestamp

**Expected Response:**
```json
{
  "sessionId": "session_123",
  "breakStartAt": "2025-12-07T12:15:00Z",
  "breakEndAt": "2025-12-07T12:30:00Z",
  "breakDurationSeconds": 900,
  "status": "on_duty"
}
```

**Auth / Permissions:**
- **Requires authentication token**

**Notes:**
- Backend should calculate break duration server-side and validate that a break was previously started.

#### Operation: Clock Out (end shift session)

**Proposed Endpoint:** `POST /api/time-tracker/{sessionId}/clock-out`  
**HTTP Method:** POST
 
**Purpose:**
Terminate the active shift session and return summary totals (work before break, break, work after break, total worked seconds).

**Request Body / Path Params:**
- `sessionId` (path) — required
|- `clockOutAt` (ISO8601) — optional client timestamp

**Expected Response:**
```json
{
  "sessionId": "session_123",
  "clockInAt": "2025-12-07T08:00:12Z",
  "clockOutAt": "2025-12-07T16:05:23Z",
  "workBeforeBreakSeconds": 14400,
  "breakSeconds": 1800,
  "workAfterBreakSeconds": 15071,
  "totalWorkedSeconds": 31271,
  "status": "off_duty"
}
```

**Auth / Permissions:**
- **Requires authentication token**
 
#### Operation: Get Current Session Status

**Proposed Endpoint:** `GET /api/time-tracker/session/current`  
**HTTP Method:** GET
 
 

**Expected Response:**
```json
{
  "sessionId": "session_123",
  "onDuty": true,
  "breakActive": false,
  "clockInAt": "2025-12-07T08:00:12Z",
  "breakStartAt": null,
  "breakEndAt": null,
  "workBeforeBreakSeconds": 14400,
  "breakSeconds": 0,
  "workAfterBreakSeconds": 0
}
```

**Auth / Permissions:**
- **Requires authentication token**
 


**Notes / Business Rules:**
- Frontend displays assignments as cards with:
  - Site name, round type, frequency
  - Progress bar: "completed / total" rounds
  - Status badge: "Completed" (green) or "Pending" (orange)
- Example sites in code: "742 Grayson Street", "Edson House Apartments", "1380 N California Blvd", etc.
- Frequency values: "Daily", "Weekly"
- No filtering UI visible in current code, but backend should support these filters.
- Pagination not visible in current UI

---

### 4. Daily Activity Report (DAR) Operations

---
#### Operation: Get Activity Types (Dropdown)

**Endpoint:** `GET /api/create-dar/activity-types`
**HTTP Method:** GET

**Purpose:**
Fetch the list of allowed activity types to populate the “Select activity type…” dropdown in the DAR form.

**Request Parameters (from frontend):**
*None* (only auth header required)

**Headers:**

* `Authorization: Bearer {token}`

**Example Request:**

```http
GET /api/activity-types
Authorization: Bearer {token}
```

**Example Response:**

```json
{
  "success": true,
  "data": [
     "hourly update",
    "patrol update" ,
      "visitor log" ,
      "deliveries log" ,
     "vendor's log" ,
      "other" 
  ]
}
```

**Auth / Permissions:**

* Requires valid **Bearer token**.

#### Operation: Create DAR


**Proposed Endpoint:** `POST /api/create-dar`  
**HTTP Method:** POST


**Purpose:**  
Create a new Daily Activity Report with location, site details, activity type, seriousness level, description, and multiple photos.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `site` | string | YES | Site name / location |
| `dateTime` | datetime | YES | Date and time of activity (from date+time pickers) |
| `activityType` | string | YES | Type of activity (e.g., 'Patrol', 'Incident', etc.) |
| `seriousness` | string | YES | Severity level (options: dropdown, e.g., 'Low', 'Moderate', 'High') |
| `reportDetails` | string | YES | Detailed description of activity |
| `photos` | array of files/base64 | YES | Multiple images (at least 1 required) |
| `gpsLocation` | object | NO | GPS coordinates: `{latitude, longitude}` |

**Example Request (multipart/form-data recommended):**
```
POST /api/dars
Authorization: Bearer {token}
Content-Type: multipart/form-data

{
  "site": "101 Pringle Ave, Walnut Creek",
  "dateTime": "2025-12-04T14:30:00Z",
  "activityType": "Patrol",
  "seriousness": "Moderate",
  "reportDetails": "Routine patrol completed. No incidents observed.",
  "scheduleNumber": "#30",
  "gpsLocation": {
    "latitude": 31.4160423,
    "longitude": 74.28704
  },
  "photos": [file1, file2, ...]
}
```

**Expected Response (inferred):**
```json
{
  "success": true,
  "message": "DAR created successfully",
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)

**Notes / Business Rules:**
- **File handling:** Frontend uses `ImagePicker` to collect photos from camera or gallery.
  - Multiple images can be added.
  - Images compressed to 75% quality.
  - Recommend **multipart/form-data** encoding.
- **Date/Time picker:** Used to select date and time of activity (not current time).
- **Activity Type:** Currently shows dropdown in UI; backend should define allowed values.
- **Seriousness levels:** UI shows options (inferred from frontend filters):
  - "Any Level", "Low", "Moderate", "High" (or similar)
- **GPS coordinates:** UI includes "Open in Maps" feature; backend should store coordinates.
- **Photos:** Displayed in gallery grid; backend should store as URLs or generate URLs after upload.
- Frontend shows location as: "31.4160423, 74.28704"
- After submission: App navigates away and refreshes DAR list.

---

---

### **API – Get Activity Types Dropdown**

```http
GET /api/activity-types
Authorization: Bearer {token}
```

**Response:**

```json
{
  "success": true,
  "data": [
    "hourly update",
    "patrol update",
    "visitor log",
    "deliveries log",
    "vendor's log",
    "other"
  ]
}
```

---

### **API – Get All Shifts Dropdown**

```http
GET /api/shifts
Authorization: Bearer {token}
```

**Response:**

```json
{
  "success": true,
  "data": [
    "Morning (06:00–14:00)",
    "Evening (14:00–22:00)",
    "Night (22:00–06:00)"
  ]
}
```

---

### **API – Get All Sites Dropdown**

```http
GET /api/sites
Authorization: Bearer {token}
```

**Response:**

```json
{
  "success": true,
  "data": [
    "101 Pringle Ave, Walnut Creek",
    "200 Market Street, San Francisco",
    "Mountain View HQ - Gate 3",
    "Fremont Industrial Yard"
  ]
}
```

#### Operation: Get DAR List (with Filtering)


**Proposed Endpoint:** `GET /api/dars`  
**HTTP Method:** GET

**Used On Screen(s):**
- Displays list of DARs with search and filter options

**Purpose:**  
Retrieve list of DARs for the authenticated officer with optional filtering by site, shift, seriousness, and schedule.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `page` | number | NO | Page number (default: 0) |
| `pageSize` | number | NO | Records per page (default: 20-50) |
| `search` | string | NO | Search term (filters site name, schedule, etc.) |
| `site` | string | NO | Filter by site name (exact or partial match) |
| `shift` | string | NO | Filter by shift type (e.g., "EB Morning", "EB Swing") |
| `seriousness` | string | NO | Filter by seriousness level (e.g., "Moderate", "All Good") |
| `schedule` | string | NO | Filter by schedule number (e.g., "#30") |
| `sortBy` | string | NO | Sort field: 'date' (default), 'site', 'status' |
| `sortOrder` | string | NO | 'asc' or 'desc' (default: 'desc' for date) |

**Example Request:**
```
GET /api/dars?page=0&pageSize=20&site=Walnut%20Creek&seriousness=Moderate&sortBy=date&sortOrder=desc
Authorization: Bearer {token}
```

**Expected Response (inferred from UI):**
```json
{
  "data": [
    {
      "id": "string (DAR ID)",
      "dateTime": "ISO8601 timestamp",
      "siteName": "string",
      "shiftType": "string (e.g., 'EB Swing / Graveyard Patrol')",
      "schedule": "string (e.g., '#30')",
      "status": "string ('All Good', 'Moderate', etc.)",
      "photoCount": "number",
      "photos": ["url1", "url2", ...],
      "description": "string (truncated for list)"
    }
  ],
  "pagination": {
    "page": "number",
    "pageSize": "number",
    "totalRecords": "number",
    "totalPages": "number"
  }
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- Officer retrieves only their own DARs.

---


### **Operation: Search DARs**

**Endpoint:** `GET /api/dars/search`
**Method:** `GET`

**Used in screen:**
*Daily Activity Report → Search Bar*

**Purpose:**
Allows officers to search their DAR history using free-text input.
Search matches fields like *site*, *schedule number*, *status*, and *shift*, similar to what the UI shows.

---

### **Request Query Parameters**

| Field             | Type   | Required | Description                                       |
| ----------------- | ------ | -------- | ------------------------------------------------- |
| `q` (or `search`) | string | NO       | Search term (site, schedule, status, shift, etc.) |
| `page`            | number | NO       | Default: `0`                                      |
| `pageSize`        | number | NO       | Default: `20`                                     |
| `sortBy`          | string | NO       | `date` (default), `site`, `status`                |
| `sortOrder`       | string | NO       | `asc` / `desc` (default: desc)                    |

---



```http
GET /api/dars/search?q=Schedule%2031&page=1&pageSize=10&sortBy=date&sortOrder=desc
Authorization: Bearer {token}
```

---

```json
{
  "success": true,
  "data": [
    {
      "dateTime": "2025-12-07T20:16:00Z",
      "siteName": "101 Pringle Ave, Walnut Creek",
      "shift": "EB Swing / Graveyard Patrol",
      "schedule": "#30",
      "status": "All Good",
      "photos": ["url1", "url2"],
      "photoCount": 3
    },
    {
      "dateTime": "2025-12-07T17:16:00Z",
      "siteName": "1 Bluxome Street",
      "shift": "EB Morning / Stagger Patrol",
      "schedule": "#31",
      "status": "Moderate",
      "photos": ["url1", "url2"],
      "photoCount": 2
    }
  ],
  "pagination": {
    "page": 0,
    "pageSize": 20,
    "totalRecords": 112,
    "totalPages": 6
  }
}
```

---

### Notes / Search Behavior

* Search triggers when user types in search bar.
* Search should match text in fields like:

  * Site Name (`101 Pringle Ave`)
* Recommended: **server-side filtering for performance.**

---




#### Operation: Get DAR Detail


**Proposed Endpoint:** `GET /api/dars/{darId}`  
**HTTP Method:** GET


**Purpose:**  
Retrieve full details of a specific DAR including description, GPS location, all photos, and metadata.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `darId` | string | YES (in URL path) | DAR unique identifier |

**Example Request:**
```
GET /api/dars/dar_12345
Authorization: Bearer {token}
```

**Expected Response (inferred from UI):**
```json
{
  "id": "string (DAR ID)",
  "dateTime": "ISO8601 timestamp",
  "siteName": "string",
  "shiftType": "string",
  "schedule": "string",
  "status": "string",
  "activityType": "string",
  "seriousness": "string",
  "description": "string (full text)",
  "gpsLocation": {
    "latitude": "number",
    "longitude": "number"
  },
  "photos": [
    "string (URL)",
    "string (URL)"
  ],
  "guardGroup": "string (optional)",
  "unitNumber": "string (optional)",
  "createdAt": "ISO8601 timestamp",
  "createdBy": "string (officer name)"
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- Officer can only view their own DARs (or assigned supervisor/admin can view).

---

### 5. Timesheet Operations

---

#### Operation: Get Monthly Timesheet

**Proposed Endpoint:** `GET /api/timesheets/monthly`  
**HTTP Method:** GET


**Purpose:**  
Retrieve monthly timesheet data showing daily work hours for the authenticated officer.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `month` | string | NO | Month to retrieve (format: YYYY-MM, default: current month) |
| `year` | number | NO | Year (if separate from month parameter) |

**Example Request:**
```
GET /api/timesheets/monthly?month=2025-12
Authorization: Bearer {token}
```

**Expected Response (inferred from UI):**
```json
{
  "month": "string (e.g., 'December 2025')",
  "year": "number (2025)",
  "totalHours": "number (total hours worked in month)",
  "data": [
    {
      "date": "YYYY-MM-DD",
      "day": "string (e.g., 'Monday')",
      "worked": "string (time in HH:MM format, e.g., '08:45')",
    }
  ]
}
```

**Example Response (from mock data):**
```json
{
  "month": "December 2025",
  "year": 2025,
  "totalHours": 172.5,
  "data": [
    {
      "date": "2025-12-01",
      "day": "Monday",
      "worked": "08:00",
      "status": "worked"
    },
    {
      "date": "2025-12-06",
      "day": "Saturday",
      "worked": "00:45",
      "status": "worked"
    },
    {
      "date": "2025-12-07",
      "day": "Sunday",
      "worked": "00:29",
      "status": "worked"
    },
    {
      "date": "2025-12-10",
      "day": "Wednesday",
      "worked": "01:15",
      "status": "worked"
    }
  ]
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- Officer retrieves only their own timesheet.


---

### 6. Settings & Preferences Operations

---

#### Operation: Get User Settings

**Proposed Endpoint:** `GET /api/settings`  
**HTTP Method:** GET


**Purpose:**  
Retrieve user's app settings and preferences (dark mode, notifications, etc.).

**Request Data (from frontend):**
| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| (none) | — | — | Query string parameters (optional) |

**Example Request:**
```
GET /api/settings
Authorization: Bearer {token}
```

**Expected Response (inferred):**
```json
{
  "isDarkMode": "boolean",
  "notificationsEnabled": "boolean",
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- User retrieves only their own settings.
---

#### Operation: Update User Settings

**Type:** PROPOSED ENDPOINT (inferred from `settingscontroller.dart`)

**Proposed Endpoint:** `PUT /api/settings`  
**HTTP Method:** PUT


**Purpose:**  
Update user's app settings and preferences.

**Request Data (from frontend):**

| Field | Type | Required | Validation / Notes |
|-------|------|----------|-------------------|
| `isDarkMode` | boolean | NO | Dark mode toggle |
| `notificationsEnabled` | boolean | NO | Notifications preference |

**Example Request:**
```json
{
  "isDarkMode": true
}
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Settings updated successfully",
  "settings": {
    "isDarkMode": true
  }
}
```

**Auth / Permissions:**
- **Requires authentication token** (Bearer token in Authorization header)
- User can only update their own settings.

Here’s your updated doc with the **new endpoints added in the right sections**.

```md
---

---

## Field Reference by Screen

### LoginScreen
- **Email field:** "Enter your ID" (email/username)
- **Password field:** Plain password input
- **API called:** POST /api/auth/login

### SignUpScreen (Multi-Step)
**Step 1 - Personal Info:**
- Full Name, DOB, Phone, Email, Selfie photo, ID photo
- API called: POST /api/auth/register (all data submitted together)

**Step 2 - Account Info:**
- Username, Password, Confirm Password
- (Form validation continues)

**Step 3 - Contact Info:**
- Address, City, State, ZIP
- Emergency contact name, relationship, phone
- Terms agreement checkbox
- **Submit:** POST /api/auth/register

### DashboardScreen
- Displays list of assignments  
- Monthly schedule calendar (Your Monthly Calendar)
- APIs called:
  - GET /api/assignments
  - GET /api/schedules/monthly
  - Time-Tracker APIs:
    - GET /api/locations/regions
    - GET /api/shifts
    - POST /api/time-tracker/clock-in
    - POST /api/time-tracker/{sessionId}/break-start
    - POST /api/time-tracker/{sessionId}/break-end
    - POST /api/time-tracker/{sessionId}/clock-out
    - GET /api/time-tracker/session/current

### DARScreen
- List of DARs with search/filter
- Search bar to search DARs
- FAB "Add DAR" button
- APIs called:
  - GET /api/dars (with optional filters: site, shift, seriousness, schedule, etc.)
  - GET /api/dars/search (server-side search by text)
  - GET /api/sites (sites dropdown for filters)
  - GET /api/shifts (shifts dropdown for filters)
- FAB redirects to: CreatDARScreen

### CreatDARScreen
- Site, DateTime, Activity Type, Seriousness, Report Details
- Photo upload (multiple)
- Dropdowns:
  - Site list
  - Activity type list
  - Shift list (if needed)
- APIs called:
  - GET /api/sites
  - GET /api/activity-types
  - GET /api/shifts
  - POST /api/create-dar (or POST /api/dars as final create endpoint)

### DARDetailScreen
- Full DAR details (read-only view)
- Photo gallery
- "Open in Maps" button
- API called: GET /api/dars/{darId}

### TimesheetScreen
- Monthly view with daily hours
- Month selector (Prev / Next month reloads same endpoint with different `month`)
- API called: GET /api/timesheets/monthly

### ProfileScreen
- Display user info (name, email, phone, username, role, etc.)
- "Edit" button redirects to EditProfileScreen
- Settings icon (bottom right)
- API called: GET /api/users/profile

### EditProfileScreen
- Editable form with editable profile fields
- Save button
- API called: PUT /api/users/profile

### SettingsBottomSheet
- Dark Mode toggle
- Log Out button
- APIs called:
  - PUT /api/settings (for dark mode)
  - POST /api/auth/logout

---

## Summary

| **Feature** | **Endpoint** | **Method** | **Auth Required** | **Status** |
|--|--|--|--|--|
| Login | `POST /api/auth/login` | POST | No | ✅ Proposed |
| Register (Final Submit) | `POST /api/auth/register` | POST | No | ✅ Proposed |
| Register - Step 1 Validation | `POST /api/auth/register/validate-step-1` | POST | No | ✅ Proposed |
| Register - Step 2 Validation | `POST /api/auth/register/validate-step-2` | POST | No | ✅ Proposed |
| Forgot Password | `POST /api/auth/forgot-password` | POST | No | ✅ Proposed |
| Logout | `POST /api/auth/logout` | POST | Yes | ✅ Proposed |
| Delete Account | `DELETE /api/auth/account` | DELETE | Yes | ✅ Proposed |
| Get Profile | `GET /api/users/profile` | GET | Yes | ✅ Proposed |
| Update Profile | `PUT /api/users/profile` | PUT | Yes | ✅ Proposed |
| Get Assignments | `GET /api/assignments` | GET | Yes | ✅ Proposed |
| Get Regions | `GET /api/locations/regions` | GET | Yes | ✅ Proposed |
| Get Shifts | `GET /api/shifts` | GET | Yes | ✅ Proposed |
| Clock In (Time Tracker) | `POST /api/time-tracker/clock-in` | POST | Yes | ✅ Proposed |
| Break Start | `POST /api/time-tracker/{sessionId}/break-start` | POST | Yes | ✅ Proposed |
| Break End | `POST /api/time-tracker/{sessionId}/break-end` | POST | Yes | ✅ Proposed |
| Clock Out | `POST /api/time-tracker/{sessionId}/clock-out` | POST | Yes | ✅ Proposed |
| Get Current Session | `GET /api/time-tracker/session/current` | GET | Yes | ✅ Proposed |
| Create DAR | `POST /api/dars` or `POST /api/create-dar` | POST | Yes | ✅ Proposed |
| Get DAR List | `GET /api/dars` | GET | Yes | ✅ Proposed |
| Search DARs | `GET /api/dars/search` | GET | Yes | ✅ Proposed |
| Get DAR Detail | `GET /api/dars/{darId}` | GET | Yes | ✅ Proposed |
| Update DAR | `PUT /api/dars/{darId}` | PUT | Yes | 🔄 Inferred (optional) |
| Delete DAR | `DELETE /api/dars/{darId}` | DELETE | Yes | 🔄 Inferred (optional) |
| Get Activity Types (DAR dropdown) | `GET /api/activity-types` | GET | Yes | ✅ Proposed |
| Get Shifts (dropdown / filters) | `GET /api/shifts` | GET | Yes | ✅ Proposed |
| Get Sites (dropdown / filters) | `GET /api/sites` | GET | Yes | ✅ Proposed |
| Get Timesheet | `GET /api/timesheets/monthly` | GET | Yes | ✅ Proposed |
| Get Daily Timesheet | `GET /api/timesheets/{date}` | GET | Yes | 🔄 Inferred (optional) |
| Get Monthly Schedule (Dashboard calendar) | `GET /api/schedules/monthly` | GET | Yes | ✅ Proposed |
| Get Settings | `GET /api/settings` | GET | Yes | 🔄 Inferred |
| Update Settings | `PUT /api/settings` | PUT | Yes | ✅ Proposed |

---
```
