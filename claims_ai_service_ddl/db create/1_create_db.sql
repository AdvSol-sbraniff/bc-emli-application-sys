-- this script is run by superuser
-- roles (login users)
-- the db is owned by the owner in postgres. in prod it will already exist for me.
-- in that case, only the creation of the invoice_app userid should occur.
-- a schema is a folder
-- all ddl is run by the db owner userid and there is no such thing as a schema owner userid

CREATE ROLE invoice_owner LOGIN PASSWORD 'owner_pw';
CREATE ROLE invoice_app   LOGIN PASSWORD 'app_pw';

-- database
CREATE DATABASE invoice_dev OWNER invoice_owner;

