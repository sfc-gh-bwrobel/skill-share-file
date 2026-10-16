---
name: share-file
description: Share local files with a partner via 7-day presigned Snowflake links, without opening the FILE_UPLOADER Streamlit app. Uploads to @TO_SHARE.PUBLIC.SHARE_FILES, registers the folder in TO_SHARE.APP.FOLDER_METADATA, returns links in chat and creates a Gmail draft. Use when: share a file, upload file for partner, send file to Capgemini/EY/KPMG/Slalom, file share link. Triggers: share file, upload the file for, file for partner, share link, presigned link.
---

# share-file

Replaces the manual flow in the Streamlit app `TO_SHARE.APP.FILE_UPLOADER`.
The existing stream/task (`FILES_STREAM` -> `EXEC_GENERATE_SHARES` -> `GENERATE_SHARES()`) is
unchanged and still sends the "File Share Links" email to Bart about 10 seconds after upload. That is expected.

Connection: `coco_183` (account SFSEEUROPE-EU_DEMO183).

## Inputs

Parse from the request, e.g. "upload ~/Downloads/deck.pdf for Capgemini purpose RfP for BMW, send to klaus.kring@capgemini.com":

- **files** (required): one or more local paths. Expand `~`. Verify each exists (`ls -l`) before uploading.
- **partner** (required): known values in FOLDER_METADATA: Capgemini, EY, KPMG, Slalom. If the partner is not one of these, confirm the spelling with the user.
- **purpose** (required): free text, stored as DESCRIPTION.
- **recipient** (optional): email for the Gmail draft. If missing, ask once. If the user has none, skip the draft and say so.

Ask only for missing required inputs, in a single question.

## Steps

### 1. Folder key

Generate in the app's format `YYMMDD-xxxxx` (5 alphanumeric chars):

```bash
echo "$(date +%y%m%d)-$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 5)"
```

### 2. Upload

Run `snow` **directly in the bash command, once per file**. Do not wrap it in a script: the
harness only injects the Snowflake session token when the command line itself calls `snow`.

```bash
snow stage copy "<local_path>" "@TO_SHARE.PUBLIC.SHARE_FILES/<FOLDER>/" -c coco_183 --overwrite --no-auto-compress
```

Check that the status column says `UPLOADED`. On an error, stop and report it; do not call step 3.

### 3. Register and get links

Use `sql_execute`. Escape single quotes in partner/purpose by doubling them.

```sql
CALL TO_SHARE.APP.REGISTER_SHARE('<FOLDER>', '<partner>', '<purpose>');
```

Returns `FILE_NAME, FILE_URL, EXPIRES_AT` (Europe/Berlin time). If `FILE_NAME = 'ERROR'`, report `FILE_URL` as the error message and stop.
The procedure refreshes the stage directory, inserts the metadata row (idempotent), and creates 7-day presigned URLs.

### 4. Gmail draft

If a recipient is known, call `mcp__gmail-nova__create_draft` with `isHtml: true`:

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
<p>Best regards,<br>Bart</p>
```

Never send the email; only create the draft.

### 5. Output in chat

Short summary:

- Folder: `<FOLDER>`, partner, purpose
- One line per file: `[FILE_NAME](FILE_URL)`
- Expiry date
- Whether the Gmail draft was created (and for whom)

## Re-sharing after expiry

Links expire after 7 days. To get fresh links for an existing folder, skip steps 1-2 and run step 3 with the existing folder key
(find it with `SELECT * FROM TO_SHARE.APP.FOLDER_METADATA WHERE PARTNER_NAME = '<partner>' ORDER BY CREATED_AT DESC`).
The metadata row is not duplicated.
