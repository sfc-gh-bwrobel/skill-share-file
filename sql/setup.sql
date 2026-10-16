-- share-file: one-time setup in your own Snowflake account.
-- Run as ACCOUNTADMIN (creates a notification integration):
--   snow sql -c <connection> -f sql/setup.sql -D database=TO_SHARE -D notify_email=you@snowflake.com
-- notify_email: a single address; must be the verified email of a user in this account.
-- Re-running is safe; it replaces procedures and the task but keeps files and metadata.

CREATE DATABASE IF NOT EXISTS <% database %>;
CREATE SCHEMA IF NOT EXISTS <% database %>.APP;
CREATE SCHEMA IF NOT EXISTS <% database %>.PUBLIC;

-- Server-side encryption is required: presigned links on client-side encrypted stages return unreadable files.
CREATE STAGE IF NOT EXISTS <% database %>.PUBLIC.SHARE_FILES
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
  DIRECTORY = (ENABLE = TRUE AUTO_REFRESH = TRUE);

CREATE TABLE IF NOT EXISTS <% database %>.APP.FOLDER_METADATA (
  FOLDER_NAME VARCHAR NOT NULL,
  DESCRIPTION VARCHAR,
  CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  CREATED_BY VARCHAR DEFAULT CURRENT_USER(),
  PARTNER_NAME VARCHAR
);

-- Who gets the "File Share Links" email. Change later with sql/set_notify_email.sql.
CREATE TABLE IF NOT EXISTS <% database %>.APP.SETTINGS (KEY VARCHAR NOT NULL, VALUE VARCHAR);
MERGE INTO <% database %>.APP.SETTINGS t
USING (SELECT 'NOTIFY_EMAIL' AS KEY, '<% notify_email %>' AS VALUE) s ON t.KEY = s.KEY
WHEN MATCHED THEN UPDATE SET VALUE = s.VALUE
WHEN NOT MATCHED THEN INSERT (KEY, VALUE) VALUES (s.KEY, s.VALUE);

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS <% database %>_EMAIL_INT
  TYPE = EMAIL
  ENABLED = TRUE
  ALLOWED_RECIPIENTS = ('<% notify_email %>');
ALTER NOTIFICATION INTEGRATION <% database %>_EMAIL_INT SET ALLOWED_RECIPIENTS = ('<% notify_email %>');

CREATE STREAM IF NOT EXISTS <% database %>.PUBLIC.FILES_STREAM ON DIRECTORY(@<% database %>.PUBLIC.SHARE_FILES);

-- Emails presigned links for newly uploaded files to NOTIFY_EMAIL.
CREATE OR REPLACE PROCEDURE <% database %>.PUBLIC.GENERATE_SHARES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  html VARCHAR;
  c INTEGER DEFAULT 0;
  expiry_ts VARCHAR;
  recipients VARCHAR;
  file_list CURSOR FOR SELECT
                         RELATIVE_PATH,
                         GET_PRESIGNED_URL(@<% database %>.PUBLIC.SHARE_FILES, RELATIVE_PATH, 604800) AS FILE_URL
                       FROM <% database %>.PUBLIC.FILES_STREAM
                       WHERE METADATA$ACTION = 'INSERT';
BEGIN
  SELECT MAX(VALUE) INTO :recipients FROM <% database %>.APP.SETTINGS WHERE KEY = 'NOTIFY_EMAIL';
  IF (COALESCE(TRIM(recipients), '') = '') THEN
    RETURN 'NOTIFY_EMAIL not set, no email sent';
  END IF;

  expiry_ts := TO_CHAR(CONVERT_TIMEZONE('Europe/Berlin', DATEADD(second, 604800, CURRENT_TIMESTAMP()))::TIMESTAMP_NTZ, 'YYYY-MM-DD HH24:MI');
  html := '<p>The links expire on ' || expiry_ts || ', make sure to download them before that date.</p><ul>';

  FOR file_item IN file_list DO
    html := html || '<li><a href="' || file_item.FILE_URL || '">' || REGEXP_SUBSTR(file_item.RELATIVE_PATH, '[^/]+$') || '</a></li>';
    c := c + 1;
  END FOR;

  html := html || '</ul>';

  IF (c > 0) THEN
    CALL SYSTEM$SEND_EMAIL('<% database %>_EMAIL_INT', :recipients, 'File Share Links', :html, 'text/html');
  END IF;

  RETURN :c || ' links emailed';
END;
$$;

-- Serverless task: runs when new files land, then consumes the stream.
CREATE OR REPLACE TASK <% database %>.PUBLIC.EXEC_GENERATE_SHARES
  TARGET_COMPLETION_INTERVAL = '10 SECONDS'
  WHEN SYSTEM$STREAM_HAS_DATA('<% database %>.PUBLIC.FILES_STREAM')
AS
BEGIN
  CALL <% database %>.PUBLIC.GENERATE_SHARES();
  CREATE OR REPLACE TEMP TABLE consume_stream AS SELECT * FROM <% database %>.PUBLIC.FILES_STREAM;
END;
ALTER TASK <% database %>.PUBLIC.EXEC_GENERATE_SHARES RESUME;

-- Called by the share-file skill: registers a folder and returns 7-day presigned links.
CREATE OR REPLACE PROCEDURE <% database %>.APP.REGISTER_SHARE(FOLDER VARCHAR, PARTNER VARCHAR, DESCRIPTION VARCHAR)
RETURNS TABLE (FILE_NAME VARCHAR, FILE_URL VARCHAR, EXPIRES_AT VARCHAR)
LANGUAGE SQL
COMMENT = 'Registers an uploaded share folder in FOLDER_METADATA and returns 7-day presigned links. Used by the share-file skill.'
EXECUTE AS OWNER
AS
$$
DECLARE
  n INTEGER;
  res RESULTSET;
BEGIN
  IF (NOT REGEXP_LIKE(:FOLDER, '^[0-9]{6}-[A-Za-z0-9]{5}$')) THEN
    res := (SELECT 'ERROR' AS FILE_NAME, 'Invalid folder key: ' || :FOLDER AS FILE_URL, NULL::VARCHAR AS EXPIRES_AT);
    RETURN TABLE(res);
  END IF;

  ALTER STAGE <% database %>.PUBLIC.SHARE_FILES REFRESH;

  SELECT COUNT(*) INTO :n FROM DIRECTORY(@<% database %>.PUBLIC.SHARE_FILES)
  WHERE STARTSWITH(RELATIVE_PATH, :FOLDER || '/');
  IF (n = 0) THEN
    res := (SELECT 'ERROR' AS FILE_NAME, 'No files found in folder ' || :FOLDER AS FILE_URL, NULL::VARCHAR AS EXPIRES_AT);
    RETURN TABLE(res);
  END IF;

  MERGE INTO <% database %>.APP.FOLDER_METADATA t
  USING (SELECT :FOLDER AS F) s ON t.FOLDER_NAME = s.F
  WHEN NOT MATCHED THEN INSERT (FOLDER_NAME, PARTNER_NAME, DESCRIPTION) VALUES (:FOLDER, :PARTNER, :DESCRIPTION);

  res := (
    SELECT REGEXP_SUBSTR(RELATIVE_PATH, '[^/]+$') AS FILE_NAME,
           GET_PRESIGNED_URL(@<% database %>.PUBLIC.SHARE_FILES, RELATIVE_PATH, 604800) AS FILE_URL,
           TO_CHAR(CONVERT_TIMEZONE('Europe/Berlin', DATEADD(second, 604800, CURRENT_TIMESTAMP()))::TIMESTAMP_NTZ, 'YYYY-MM-DD HH24:MI') AS EXPIRES_AT
    FROM DIRECTORY(@<% database %>.PUBLIC.SHARE_FILES)
    WHERE STARTSWITH(RELATIVE_PATH, :FOLDER || '/')
    ORDER BY 1
  );
  RETURN TABLE(res);
END;
$$;
