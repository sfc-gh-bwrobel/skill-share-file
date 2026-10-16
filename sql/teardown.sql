-- Removes everything created by setup.sql, including all uploaded files. Run as ACCOUNTADMIN:
--   snow sql -c <connection> -f sql/teardown.sql -D database=TO_SHARE

ALTER TASK IF EXISTS <% database %>.PUBLIC.EXEC_GENERATE_SHARES SUSPEND;
DROP DATABASE IF EXISTS <% database %>;
DROP INTEGRATION IF EXISTS <% database %>_EMAIL_INT;
