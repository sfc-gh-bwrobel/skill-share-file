# share-file

A Cortex Code skill that shares local files with partners through 7-day presigned links from a Snowflake stage.
No Snowsight login and no app: ask Cortex Code to "upload ~/Downloads/deck.pdf for Capgemini purpose RfP for BMW"
and get the links in chat, plus an optional Gmail draft. A copy of the links is also emailed to a configurable address.

## How it works

1. The skill uploads the file to `@<DB>.PUBLIC.SHARE_FILES/<YYMMDD-xxxxx>/` with `PUT`.
2. `<DB>.APP.REGISTER_SHARE` records the partner and purpose in `<DB>.APP.FOLDER_METADATA` and returns 7-day presigned links.
3. The stream `FILES_STREAM` triggers the task `EXEC_GENERATE_SHARES`, which emails the links to `NOTIFY_EMAIL`.

Anyone with a link can download the file until it expires. Links cannot last longer than 7 days.

## Prerequisites

- A Snowflake account where you can use ACCOUNTADMIN (setup creates a notification integration).
- Your email verified in your Snowflake user profile (required by `SYSTEM$SEND_EMAIL`).
- Cortex Code with a connection to that account.
- Optional: the `gmail-nova` MCP server for Gmail drafts.

## Setup

1. Clone the repo and create the Snowflake objects:

   ```bash
   snow sql -c <connection> -f sql/setup.sql -D database=TO_SHARE -D notify_email=you@snowflake.com
   ```

   Pick any database name; it must not clash with an existing one. You can also ask Cortex Code to run `sql/setup.sql` with these values.

2. Configure the skill:

   ```bash
   cp .cortex/skills/share-file/config.example.json .cortex/skills/share-file/config.json
   ```

   Set `connection`, `database` (same as above) and `sender_name`. `config.json` is git-ignored.

3. Start `cortex` in the repo folder. The skill is discovered from `.cortex/skills/`.
   To use it from any folder, copy `.cortex/skills/share-file` to `~/.snowflake/cortex/skills/`.

4. Test: "share /tmp/test.txt for TEST purpose setup test". Check the link in chat and the email in your inbox.

## Change the email recipient

```bash
snow sql -c <connection> -f sql/set_notify_email.sql -D database=TO_SHARE -D notify_email=someone@snowflake.com
```

The address must be the verified email of a user in the account.

## Remove everything

Deletes the database (including all uploaded files) and the email integration:

```bash
snow sql -c <connection> -f sql/teardown.sql -D database=TO_SHARE
```

## Objects created

| Object | Purpose |
|---|---|
| `<DB>.PUBLIC.SHARE_FILES` | Stage with server-side encryption and auto-refreshing directory |
| `<DB>.APP.FOLDER_METADATA` | Folder, partner, purpose, created by/at |
| `<DB>.APP.SETTINGS` | `NOTIFY_EMAIL` |
| `<DB>.PUBLIC.FILES_STREAM` | Stream on the stage directory |
| `<DB>.PUBLIC.GENERATE_SHARES()` | Emails links for new files |
| `<DB>.PUBLIC.EXEC_GENERATE_SHARES` | Serverless task, runs when the stream has data |
| `<DB>.APP.REGISTER_SHARE()` | Called by the skill |
| `<DB>_EMAIL_INT` | Email notification integration |
