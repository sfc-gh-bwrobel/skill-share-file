-- Change who receives the "File Share Links" email. Run as ACCOUNTADMIN:
--   snow sql -c <connection> -f sql/set_notify_email.sql -D database=TO_SHARE -D notify_email=someone@snowflake.com
-- The address must be the verified email of a user in this account.

UPDATE <% database %>.APP.SETTINGS SET VALUE = '<% notify_email %>' WHERE KEY = 'NOTIFY_EMAIL';
ALTER NOTIFICATION INTEGRATION <% database %>_EMAIL_INT SET ALLOWED_RECIPIENTS = ('<% notify_email %>');
