-- Kamailio PostgreSQL Database Schema
-- Version table (Kamailio tüm tablolar için versiyon kontrolü yapar)

CREATE TABLE version (
    table_name VARCHAR(32) NOT NULL,
    table_version INTEGER DEFAULT 0 NOT NULL,
    CONSTRAINT version_t_name_idx PRIMARY KEY (table_name)
);

-- Subscriber table (Kullanıcı kimlik bilgileri)
CREATE TABLE subscriber (
    id SERIAL PRIMARY KEY,
    username VARCHAR(64) NOT NULL DEFAULT '',
    domain VARCHAR(64) NOT NULL DEFAULT '',
    password VARCHAR(64) NOT NULL DEFAULT '',
    email_address VARCHAR(64) NOT NULL DEFAULT '',
    ha1 VARCHAR(64) NOT NULL DEFAULT '',
    ha1b VARCHAR(64) NOT NULL DEFAULT '',
    rpid VARCHAR(64) DEFAULT NULL
);

CREATE INDEX subscriber_account_idx ON subscriber (username, domain);
CREATE UNIQUE INDEX subscriber_username_idx ON subscriber (username, domain);

INSERT INTO version (table_name, table_version) VALUES ('subscriber', 7);

-- Location table (Kullanıcı kayıt bilgileri - REGISTER)
CREATE TABLE location (
    id SERIAL PRIMARY KEY,
    ruid VARCHAR(64) NOT NULL DEFAULT '',
    username VARCHAR(64) NOT NULL DEFAULT '',
    domain VARCHAR(64) DEFAULT NULL,
    contact VARCHAR(512) NOT NULL DEFAULT '',
    received VARCHAR(128) DEFAULT NULL,
    path VARCHAR(512) DEFAULT NULL,
    expires TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT '2030-05-28 21:32:15',
    q REAL NOT NULL DEFAULT 1.0,
    callid VARCHAR(255) NOT NULL DEFAULT 'Default-Call-ID',
    cseq INTEGER NOT NULL DEFAULT 1,
    last_modified TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT '2000-01-01 00:00:01',
    flags INTEGER NOT NULL DEFAULT 0,
    cflags INTEGER NOT NULL DEFAULT 0,
    user_agent VARCHAR(255) NOT NULL DEFAULT '',
    socket VARCHAR(64) DEFAULT NULL,
    methods INTEGER DEFAULT NULL,
    instance VARCHAR(255) DEFAULT NULL,
    reg_id INTEGER NOT NULL DEFAULT 0,
    server_id INTEGER NOT NULL DEFAULT 0,
    connection_id INTEGER NOT NULL DEFAULT 0,
    keepalive INTEGER NOT NULL DEFAULT 0,
    partition INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX location_account_contact_idx ON location (username, domain, contact);
CREATE INDEX location_expires_idx ON location (expires);
CREATE INDEX location_connection_idx ON location (server_id, connection_id);

INSERT INTO version (table_name, table_version) VALUES ('location', 9);

-- Dispatcher table (FreeSWITCH gibi backend sunucular için)
CREATE TABLE dispatcher (
    id SERIAL PRIMARY KEY,
    setid INTEGER NOT NULL DEFAULT 0,
    destination VARCHAR(192) NOT NULL DEFAULT '',
    flags INTEGER NOT NULL DEFAULT 0,
    priority INTEGER NOT NULL DEFAULT 0,
    attrs VARCHAR(128) NOT NULL DEFAULT '',
    description VARCHAR(64) NOT NULL DEFAULT ''
);

CREATE INDEX dispatcher_setid_idx ON dispatcher (setid);

INSERT INTO version (table_name, table_version) VALUES ('dispatcher', 4);

-- Test kullanıcısı ekleyelim (şifre: test123)
-- ha1 = MD5(username:realm:password) = MD5(test:kamailio:test123)
INSERT INTO subscriber (username, domain, password, ha1, ha1b) 
VALUES (
    'test',
    'kamailio',
    'test123',
    MD5('test:kamailio:test123'),
    MD5('test@kamailio:kamailio:test123')
);

-- FreeSWITCH dispatcher kaydı
INSERT INTO dispatcher (setid, destination, flags, priority, attrs, description)
VALUES (1, 'sip:172.26.26.224:5060', 0, 0, '', 'FreeSWITCH Backend');

-- Veritabanı hazır mesajı
DO $$
BEGIN
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Kamailio database schema created successfully!';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Test user created:';
    RAISE NOTICE '  Username: test';
    RAISE NOTICE '  Domain: kamailio';
    RAISE NOTICE '  Password: test123';
    RAISE NOTICE '==============================================';
END $$;
