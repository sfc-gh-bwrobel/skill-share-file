---
name: share-file
description: Share local files with a partner via 7-day presigned Snowflake links, without opening the FILE_UPLOADER Streamlit app. Runs scripts/share_file.sh, which uploads to @<database>.PUBLIC.SHARE_FILES and registers the folder in <database>.APP.FOLDER_METADATA; returns links in chat. Also renews expired links and lists shares. Use when: share a file, upload file for partner, send file to Capgemini/EY/KPMG/Slalom, file share link, renew share links, list my shares. Triggers: share file, upload the file for, file for partner, share link, presigned link, renew links, show my shares.
---

# share-file

All Snowflake work is done by `scripts/share_file.sh` (in this skill's base directory) through the `snow` CLI,
using the connection from `config.json`. Do **not** use `sql_execute` for this skill: the Cortex Code
active connection may point to a different account.

Because the skill never uses `sql_execute` or the Cortex Code session connection, it is safe to run from any
workspace or session, including the default one, whatever connection is active there (e.g. Snowhouse).
It does not run queries in, or change anything on, the active connection's account.

After each upload, the stage stream/task also emails the links to the configured NOTIFY_EMAIL about 10 seconds later.
That is expected.

## 0. Config

Read `config.json` in this skill's base directory:

- `connection`: snow connection name, passed as `-c` (script default: `coco_183`).
- `database`: database created by `sql/setup.sql`, passed as `-d` (script default: `TO_SHARE`).

If `config.json` is missing, copy `config.example.json` to `config.json`, ask the user for the two values, and save them.

Always run the script with `bash` (it may not be executable):

```bash
bash "<base_dir>/scripts/share_file.sh" -c "<connection>" -d "<database>" ...
```

If the connection's login has expired, the script opens a browser for login; tell the user to complete it.

## Share files

### Inputs

Parse from the request, e.g. "upload ~/Downloads/deck.pdf for Capgemini purpose RfP for BMW":

- **files** (required): one or more local paths. Expand `~` to absolute paths.
- **partner** (required). Run the list command below to see existing partner names; if the partner is new or spelled differently, confirm with the user.
- **purpose** (required): free text.

Ask only for missing inputs, in a single question.

### Run

Quote every argument:

```bash
bash "<base_dir>/scripts/share_file.sh" -c "<connection>" -d "<database>" -p "<partner>" -m "<purpose>" "<file1>" ["<file2>" ...]
```

Output: a line `FOLDER=<key>`, then a JSON array of `{FILE_NAME, FILE_URL, EXPIRES_AT}` (Europe/Berlin time).
On a non-zero exit, show the error output and stop. If `FILE_NAME` is `ERROR`, report `FILE_URL` as the error.

### Output in chat

- Folder: `<FOLDER>`, partner, purpose
- One line per file: `[FILE_NAME](FILE_URL)`
- Expiry date

Do not create Gmail drafts or emails, and do not ask about recipients.

## Renew links after expiry

Find the folder key with the list command, then:

```bash
bash "<base_dir>/scripts/share_file.sh" -c "<connection>" -d "<database>" -r "<folder>"
```

Same JSON output as an upload. No email is sent and the metadata row is not duplicated.

## List shares

For "show my shares (for <partner>)":

```bash
bash "<base_dir>/scripts/share_file.sh" -c "<connection>" -d "<database>" -l [-p "<partner>"]
```

Returns JSON with `FOLDER_NAME, PARTNER_NAME, DESCRIPTION, CREATED_AT`; present it as a table.
