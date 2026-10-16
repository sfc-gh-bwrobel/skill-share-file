---
name: share-file
description: Share local files with a partner via 7-day presigned Snowflake links, without opening the FILE_UPLOADER Streamlit app. Uploads to @<database>.PUBLIC.SHARE_FILES, registers the folder in <database>.APP.FOLDER_METADATA, returns links in chat and optionally creates a Gmail draft. Use when: share a file, upload file for partner, send file to Capgemini/EY/KPMG/Slalom, file share link. Triggers: share file, upload the file for, file for partner, share link, presigned link.
---

# share-file

Uploads files to a Snowflake stage and returns 7-day presigned links. Requires the objects from `sql/setup.sql`
(see README.md). After each upload, the stage stream/task also emails the links to the configured NOTIFY_EMAIL
about 10 seconds later. That is expected.

## 0. Config

Read `config.json` in this skill's base directory:

- `connection`: Snowflake connection name, passed as `connection` to every `sql_execute` call.
- `database`: database created by `sql/setup.sql` (written as `<DB>` below).
- `sender_name`: signature for the Gmail draft.

If `config.json` is missing, copy `config.example.json` to `config.json`, ask the user for the three values, and save them.

## Inputs

Parse from the request, e.g. "upload ~/Downloads/deck.pdf for Capgemini purpose RfP for BMW, send to klaus.kring@capgemini.com":

- **files** (required): one or more local paths. Expand `~` to an absolute path. Verify each exists (`ls -l`) before uploading.
- **partner** (required): check `SELECT DISTINCT PARTNER_NAME FROM <DB>.APP.FOLDER_METADATA`. If the partner is new or spelled differently, confirm with the user.
- **purpose** (required): free text, stored as DESCRIPTION.
- **recipient** (optional): email for the Gmail draft. If missing, ask once. If the user has none, skip the draft.

Ask only for missing inputs, in a single question.

## Steps

### 1. Folder key

Format `YYMMDD-xxxxx` (5 alphanumeric chars):

```bash
echo "$(date +%y%m%d)-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5)"
```

### 2. Upload

One `sql_execute` call per file (absolute path, no `~`). Quote paths containing spaces exactly as shown:

```sql
PUT 'file://<absolute_path>' '@<DB>.PUBLIC.SHARE_FILES/<FOLDER>' AUTO_COMPRESS = FALSE OVERWRITE = TRUE;
```

Check that the status is `UPLOADED`. On an error, stop and report it; do not continue to step 3.

### 3. Register and get links

Escape single quotes in partner/purpose by doubling them.

```sql
CALL <DB>.APP.REGISTER_SHARE('<FOLDER>', '<partner>', '<purpose>');
```

Returns `FILE_NAME, FILE_URL, EXPIRES_AT` (Europe/Berlin time). If `FILE_NAME = 'ERROR'`, report `FILE_URL` as the error message and stop.

### 4. Gmail draft (optional)

Only if a recipient is known and `mcp__gmail-nova__create_draft` is available; otherwise skip and say so.
Call it with `isHtml: true`:

- **to**: recipient
- **subject**: `<purpose> - files from Snowflake`
- **body**:

```html
<p>Hi,</p>
<p>Please find the files for <b><purpose></b> below:</p>
<ul>
  <li><a href="<FILE_URL>"><FILE_NAME></a></li>
</ul>
<p>The links expire on <EXPIRES_AT> (CET). Please download the files before that date.</p>
<p>Best regards,<br><sender_name></p>
```

Never send the email; only create the draft.

### 5. Output in chat

- Folder: `<FOLDER>`, partner, purpose
- One line per file: `[FILE_NAME](FILE_URL)`
- Expiry date
- Whether the Gmail draft was created (and for whom)

## Re-sharing after expiry

To get fresh links for an existing folder, skip steps 1-2 and run step 3 with the existing folder key
(find it with `SELECT * FROM <DB>.APP.FOLDER_METADATA WHERE PARTNER_NAME = '<partner>' ORDER BY CREATED_AT DESC`).
No new email is sent and the metadata row is not duplicated.
