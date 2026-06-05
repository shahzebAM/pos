-- COMPLETE RESET FOR A NEW BUILD
-- WARNING: This permanently deletes every table, function, trigger, policy, view,
-- enum/type, and all data in the public schema.
--
-- It does NOT delete Supabase Auth users because those live in auth.users.
-- If you also want Auth users removed, delete them from Supabase Dashboard:
-- Authentication > Users.
--
-- Run this first in Supabase SQL Editor before installing the new module-by-module schema.

drop schema if exists public cascade;

create schema public;

grant usage on schema public to postgres;
grant usage on schema public to anon;
grant usage on schema public to authenticated;
grant usage on schema public to service_role;

grant all on schema public to postgres;
grant all on schema public to service_role;

alter default privileges in schema public
  grant all on tables to postgres, service_role;

alter default privileges in schema public
  grant all on functions to postgres, service_role;

alter default privileges in schema public
  grant all on sequences to postgres, service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to authenticated;

alter default privileges in schema public
  grant usage, select on sequences to authenticated;

alter default privileges in schema public
  grant execute on functions to authenticated;

alter default privileges in schema public
  grant select on tables to anon;

notify pgrst, 'reload schema';
