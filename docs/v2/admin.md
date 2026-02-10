# Admin UI for Organization and User Management

## Overview

Build a localhost admin interface to manage Fomomon organizations, users, and sites. The system will provide bidirectional org creation/editing, user management via Cognito, and sites.json editing capabilities.

**Default Port**: `8090`  
**Access URL**: `http://localhost:8090`

## Architecture

```
admin/
├── backend/
│   ├── main.py              # FastAPI server
│   ├── cognito_service.py   # Cognito user management (reuse add_users.py logic)
│   ├── s3_service.py         # S3 operations (sites.json, bucket structure)
│   ├── iam_service.py       # IAM role policy management
│   └── requirements.txt     # Python dependencies
├── frontend/
│   ├── index.html           # Main dashboard
│   ├── org.html             # Org detail/edit page
│   ├── styles.css           # Styling
│   └── app.js               # Frontend logic
└── README.md                # Setup instructions
```

## Backend Implementation (FastAPI)

### Core Services

**`cognito_service.py`**: Reuse logic from `hack/cognito/add_users.py`
- `get_or_create_user_pool(app_name)` - Get/create user pool
- `get_or_create_user_pool_client(pool_id, client_name)` - Get/create client
- `get_or_create_identity_pool(name, user_pool_id, client_id, region)` - Get/create identity pool
- `get_or_create_role(role_name, bucket_name, write_access, identity_pool_id)` - **Modified**: Always grant bucket-wide access (`fomomon/*`) instead of org-specific
- `add_user_to_pool(pool_id, user_data)` - Add single user
- `remove_user_from_pool(pool_id, username)` - Remove user
- `list_users_in_pool(pool_id)` - List all users in pool
- `update_user_password(pool_id, username, password)` - Update password

**`s3_service.py`**: S3 operations
- `list_orgs(bucket_name)` - Scan S3 bucket for org prefixes (folders)
- `get_sites_json(bucket_name, org)` - Download `sites.json` from `s3://bucket/org/sites.json`
- `put_sites_json(bucket_name, org, sites_data)` - Upload `sites.json`
- `create_org_prefix(bucket_name, org)` - Create org folder in S3
- `upload_ghost_image(bucket_name, org, site_id, image_file, orientation)` - Upload reference images
- `list_org_files(bucket_name, org)` - List files in org prefix

**`iam_service.py`**: IAM and bucket permissions
- `update_role_policy(role_name, bucket_name, write_access)` - Update IAM role to grant bucket-wide access (`fomomon/*`)
- `get_bucket_public_read_status(bucket_name)` - Check if bucket has public read
- `set_bucket_public_read(bucket_name, enabled)` - Toggle bucket ACL/policy for public read
- Uses bucket policy (like `hack/s3/create_bucket.sh`) to enable/disable public read

### API Endpoints

**`main.py`** - FastAPI routes:

```
GET  /api/orgs                    # List all orgs (scan S3)
GET  /api/orgs/{org}               # Get org details (users, sites.json, bucket structure)
POST /api/orgs                    # Create new org
PUT  /api/orgs/{org}               # Update org (sites.json, users)
DELETE /api/orgs/{org}/users/{username}  # Remove user from org

GET  /api/orgs/{org}/sites         # Get sites.json
PUT  /api/orgs/{org}/sites         # Update sites.json
POST /api/orgs/{org}/sites         # Create sites.json (if missing)

POST /api/orgs/{org}/users        # Add user to org
PUT  /api/orgs/{org}/users/{username}  # Update user password

GET  /api/bucket/public-read       # Check public read status
PUT  /api/bucket/public-read       # Toggle public read
```

### Configuration

- Default bucket: `fomomon` (configurable via env var `FOMOMON_BUCKET`)
- Default region: `ap-south-1` (configurable via env var `AWS_REGION`)
- App name: `fomomon` (configurable via env var `APP_NAME`)
- App type: `phone` (hardcoded, matches existing setup)
- Default port: `8090` (configurable via env var `PORT`)

## Frontend Implementation (HTML/CSS/JS)

### Pages

**`index.html`** - Dashboard
- List all orgs (from `/api/orgs`)
- "Create New Org" button
- For each org: name, user count, sites count, last modified
- Click org → navigate to `org.html?org={org_name}`

**`org.html`** - Org Management
- **Users Section**:
  - List users (email, name, user_id)
  - "Add User" form (email, name, user_id, password)
  - Delete user button
  - Update password button
- **Sites Section**:
  - Display sites.json in editable JSON editor (or form-based)
  - "Add Site" form (id, lat, lng, reference images, survey questions)
  - Edit/delete existing sites
  - "Upload sites.json" button (for bulk upload)
  - "Download sites.json" button
- **Permissions Section**:
  - Toggle for "Public Read" (entire bucket)
  - Display current IAM role policy status

### UI Features

- Simple, clean design
- JSON editor for sites.json (use `<textarea>` with JSON formatting or simple JSON editor library)
- File upload for ghost images (portrait/landscape)
- Form validation
- Error handling and success messages

## Key Implementation Details

### IAM Role Policy (Bucket-Wide Access)

Modify `get_or_create_role()` in `cognito_service.py` to always grant access to entire bucket:
```python
s3_resources = [
    f"arn:aws:s3:::{bucket_name}/*",
    f"arn:aws:s3:::{bucket_name}",
    f"arn:aws:s3:::{bucket_name}/"
]
```
This fixes the limitation where adding a new org overwrote previous org access.

### Public Read Toggle

Use S3 bucket policy (similar to `hack/s3/create_bucket.sh`):
- **Enable**: Add policy allowing `s3:GetObject` for `Principal: "*"`
- **Disable**: Remove the policy statement
- Also manage Public Access Block settings if needed

### Sites.json Schema

Follow existing schema from `examples/sites.json`:
- `bucket_root`: `https://fomomon.s3.amazonaws.com/{org}/`
- `sites[]`: Array of site objects with id, location, creation_timestamp, reference_portrait, reference_landscape, survey[]

### User Management

- All users go into single Cognito User Pool: `fomomon-user-pool`
- Users identified by `user_id` (lowercased) or `email` (lowercased)
- Password stored in Cognito (not in JSON files)
- When creating org, users are added to the shared pool
- IAM role grants bucket-wide access to all authenticated users

### Org Creation Flow

1. User enters org name (e.g., "t4gc")
2. System creates S3 prefix: `s3://fomomon/t4gc/`
3. Creates empty `sites.json` with `bucket_root` and empty `sites[]`
4. User can add sites and users via UI
5. Users are added to Cognito pool
6. IAM role policy updated (if needed) to ensure bucket-wide access

### Incomplete Org Handling

- If org exists in S3 but lacks `sites.json`, show "Create sites.json" option
- Allow uploading existing `sites.json` file
- Validate JSON schema before saving

## Testing

### Testing Approach

The admin UI can be tested interactively through a web browser:

1. **Start the server**: Run `uvicorn backend.main:app --reload --port 8090`
2. **Open browser**: Navigate to `http://localhost:8090`
3. **Test org creation**: Create a new org (e.g., "testorg")
4. **Test user addition**: Add users using data from `examples/users.json`
5. **Test sites.json**: Upload or create sites.json using `examples/sites.json` as reference
6. **Verify in S3**: Use AWS CLI commands to verify changes
7. **Cleanup**: Delete test org/users via UI or CLI

### Test Data

Use the example files in `examples/` directory:
- `examples/users.json` - Sample user data for testing
- `examples/sites.json` - Sample sites.json for testing

### Verification Commands

After each major operation, verify using AWS CLI:

#### Stage 1: After Creating Org
```bash
# List all orgs (prefixes) in bucket
aws s3 ls s3://fomomon/ --recursive | grep -E "^PRE|sites.json"

# Check if org prefix exists
aws s3 ls s3://fomomon/testorg/
```

#### Stage 2: After Adding Users
```bash
# List users in Cognito pool (requires pool ID)
aws cognito-idp list-users --user-pool-id <POOL_ID>

# Get pool ID first
python hack/cognito/get_app_info.py --app-name fomomon --app-type phone
```

#### Stage 3: After Creating/Uploading sites.json
```bash
# Download and verify sites.json
aws s3 cp s3://fomomon/testorg/sites.json - | jq .

# List all files in org
aws s3 ls s3://fomomon/testorg/ --recursive
```

#### Stage 4: After Toggling Public Read
```bash
# Check bucket policy
aws s3api get-bucket-policy --bucket fomomon

# Check public access block settings
aws s3api get-public-access-block --bucket fomomon
```

#### Stage 5: After Deleting Org/Users (Cleanup)
```bash
# Verify org deleted
aws s3 ls s3://fomomon/ | grep testorg

# Verify users removed (if applicable)
aws cognito-idp list-users --user-pool-id <POOL_ID>
```

### Testing Workflow

1. **Create Test Org**:
   - Navigate to `http://localhost:8090`
   - Click "Create New Org"
   - Enter org name: `testorg`
   - Verify: `aws s3 ls s3://fomomon/testorg/`

2. **Add Test Users**:
   - Open org detail page
   - Add users from `examples/users.json`:
     - user_id: `prashanthb`, email: `prashanth@tech4goodcommunity.com`, password: `testpass123`
     - user_id: `lakshmi_n`, email: `lakshmi@ngo.org`, password: `testpass123`
   - Verify: `aws cognito-idp list-users --user-pool-id <POOL_ID>`

3. **Create/Upload sites.json**:
   - Use `examples/sites.json` as template
   - Update `bucket_root` to `https://fomomon.s3.amazonaws.com/testorg/`
   - Upload via UI or create through form
   - Verify: `aws s3 cp s3://fomomon/testorg/sites.json - | jq .`

4. **Test Public Read Toggle**:
   - Toggle public read on/off
   - Verify: `aws s3api get-bucket-policy --bucket fomomon`

5. **Cleanup**:
   - Delete test users via UI
   - Delete test org (or manually: `aws s3 rm s3://fomomon/testorg/ --recursive`)
   - Verify cleanup: `aws s3 ls s3://fomomon/ | grep testorg`

## Dependencies

**Backend**:
- `fastapi`
- `uvicorn[standard]`
- `boto3`
- `python-multipart` (for file uploads)

**Frontend**:
- Vanilla JavaScript (or minimal library like Alpine.js if needed)
- No build step required

## Future Enhancements (Not in Scope)

- Ghost image upload UI (can be added later)
- Site deletion from S3 (currently only sites.json editing)
- User password reset flow
- Bulk user import from CSV/JSON

