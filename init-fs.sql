-- Create database if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'freeswitch') THEN
        EXECUTE 'CREATE DATABASE freeswitch';
    END IF;
END
$$;

-- Create role if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'freeswitch') THEN
        EXECUTE 'CREATE ROLE freeswitch WITH PASSWORD ''freeswitch@vishalk17'' LOGIN SUPERUSER CREATEDB';
    END IF;
END
$$;

-- Grant privileges (this is idempotent)
GRANT ALL PRIVILEGES ON DATABASE freeswitch TO freeswitch;