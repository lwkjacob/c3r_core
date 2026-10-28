-- Database schema. Tables are created on start, so there is no SQL file to import.
-- Needs MariaDB 10.2+ or MySQL 8 (window functions).

DB = {}

local TABLES = {
    -- One row per phone. On unique-phone servers `owner` is whoever first set the phone up.
    [[CREATE TABLE IF NOT EXISTS lwk_phone_phones (
        number VARCHAR(16) NOT NULL PRIMARY KEY,
        owner VARCHAR(80) NOT NULL,
        name VARCHAR(64) DEFAULT NULL,
        created TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        KEY owner (owner)
    )]],
    -- The phone each character used last (employee lists, offline lookups).
    [[CREATE TABLE IF NOT EXISTS lwk_phone_last (
        owner VARCHAR(80) NOT NULL PRIMARY KEY,
        number VARCHAR(16) NOT NULL
    )]],
    -- Private per-phone data as JSON: contacts, notes, settings, photos...
    [[CREATE TABLE IF NOT EXISTS lwk_phone_data (
        phone VARCHAR(16) NOT NULL,
        k VARCHAR(24) NOT NULL,
        v LONGTEXT NOT NULL,
        PRIMARY KEY (phone, k)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_calls (
        id INT AUTO_INCREMENT PRIMARY KEY,
        caller VARCHAR(16) NOT NULL,
        callee VARCHAR(16) NOT NULL,
        video TINYINT NOT NULL DEFAULT 0,
        hidden TINYINT NOT NULL DEFAULT 0,
        answered TINYINT NOT NULL DEFAULT 0,
        duration INT NOT NULL DEFAULT 0,
        created BIGINT NOT NULL,
        KEY caller (caller), KEY callee (callee)
    )]],
    -- Conversations of every kind: texts, group texts, social DMs, anonymous channels, match chats.
    [[CREATE TABLE IF NOT EXISTS lwk_phone_channels (
        id INT AUTO_INCREMENT PRIMARY KEY,
        kind VARCHAR(16) NOT NULL,
        name VARCHAR(64) DEFAULT NULL,
        size INT NOT NULL DEFAULT 2,
        updated BIGINT NOT NULL,
        KEY kind_name (kind, name)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_members (
        channel INT NOT NULL,
        member VARCHAR(64) NOT NULL,
        unread INT NOT NULL DEFAULT 0,
        cleared INT NOT NULL DEFAULT 0,   -- id of the last message this member deleted; older ones are not shown to them
        PRIMARY KEY (channel, member),
        KEY member (member)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_msgs (
        id INT AUTO_INCREMENT PRIMARY KEY,
        channel INT NOT NULL,
        sender VARCHAR(64) NOT NULL,
        body TEXT NOT NULL,
        created BIGINT NOT NULL,
        KEY channel (channel, id)
    )]],
    -- Social app accounts. `username` is a phone number for apps without logins.
    [[CREATE TABLE IF NOT EXISTS lwk_phone_accounts (
        app VARCHAR(16) NOT NULL,
        username VARCHAR(32) NOT NULL,
        password VARCHAR(100) DEFAULT NULL,
        profile TEXT DEFAULT NULL,
        created BIGINT NOT NULL,
        PRIMARY KEY (app, username)
    )]],
    -- Which account each phone is signed in to.
    [[CREATE TABLE IF NOT EXISTS lwk_phone_sessions (
        phone VARCHAR(16) NOT NULL,
        app VARCHAR(16) NOT NULL,
        username VARCHAR(32) NOT NULL,
        PRIMARY KEY (phone, app)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_posts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        app VARCHAR(16) NOT NULL,
        kind VARCHAR(8) NOT NULL DEFAULT 'post',
        username VARCHAR(32) NOT NULL,
        body TEXT NOT NULL,
        parent INT DEFAULT NULL,
        created BIGINT NOT NULL,
        KEY feed (app, kind, parent, id),
        KEY author (app, username)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_reactions (
        post INT NOT NULL,
        username VARCHAR(32) NOT NULL,
        kind VARCHAR(8) NOT NULL,
        PRIMARY KEY (post, username, kind)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_follows (
        app VARCHAR(16) NOT NULL,
        follower VARCHAR(32) NOT NULL,
        followee VARCHAR(32) NOT NULL,
        PRIMARY KEY (app, follower, followee),
        KEY followee (app, followee)
    )]],
    [[CREATE TABLE IF NOT EXISTS lwk_phone_mail (
        id INT AUTO_INCREMENT PRIMARY KEY,
        sender VARCHAR(64) NOT NULL,
        recipient VARCHAR(64) NOT NULL,
        subject VARCHAR(120) NOT NULL,
        body TEXT NOT NULL,
        seen TINYINT NOT NULL DEFAULT 0,
        created BIGINT NOT NULL,
        KEY recipient (recipient), KEY sender (sender)
    )]],
}

-- Columns added since the first release: { table, column, definition }. CREATE TABLE IF NOT EXISTS
-- leaves a table that is already there as it is, so they are added to it here.
local COLUMNS = {
    { 'lwk_phone_members', 'cleared', 'INT NOT NULL DEFAULT 0' },
}

-- What has been brought over from another phone already (server/transfer.lua).
TABLES[#TABLES + 1] = [[CREATE TABLE IF NOT EXISTS lwk_phone_imported (
    source VARCHAR(24) NOT NULL,
    ref VARCHAR(120) NOT NULL,
    PRIMARY KEY (source, ref)
)]]

local ready = false

MySQL.ready(function()
    for _, sql in ipairs(TABLES) do MySQL.query.await(sql) end
    for _, c in ipairs(COLUMNS) do
        if #MySQL.query.await(("SHOW COLUMNS FROM %s LIKE '%s'"):format(c[1], c[2])) == 0 then
            MySQL.query.await(('ALTER TABLE %s ADD COLUMN %s %s'):format(c[1], c[2], c[3]))
        end
    end
    ready = true
end)

--- Blocks until the tables exist. Call from any thread that may run during startup.
function DB.wait()
    while not ready do Wait(50) end
end
