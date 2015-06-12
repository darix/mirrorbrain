
-- 
-- MirrorBrain Database scheme for PostgreSQL
-- 

-- before PL/pgSQL functions can be used, the languages needs to be "installed"
-- in the database. This is done with:
-- 
-- createlang plpgsql <dbname>

-- --------------------------------------------------------
BEGIN;
-- --------------------------------------------------------


CREATE TABLE "version" (
        "id" serial NOT NULL PRIMARY KEY,
        "component" text NOT NULL,
        "major" INTEGER NOT NULL,
        "minor" INTEGER NOT NULL,
        "patchlevel" INTEGER NOT NULL
);

-- --------------------------------------------------------


CREATE TABLE "file" (
        "id" serial NOT NULL PRIMARY KEY,
        "path" varchar(512) UNIQUE NOT NULL
);


CREATE TABLE mirror (fileid INTEGER NOT NULL REFERENCES file(id),
                     mirrorid INTEGER NOT NULL REFERENCES server(id),
                     PRIMARY KEY (fileid, mirrorid));

-- --------------------------------------------------------


CREATE TABLE "hash" (
        "file_id" INTEGER REFERENCES file(id) PRIMARY KEY,
        "mtime" INTEGER NOT NULL,
        "size" BIGINT NOT NULL,
        "md5"    BYTEA NOT NULL,
        "sha1"   BYTEA NOT NULL,
        "sha256" BYTEA NOT NULL,
        "sha1piecesize" INTEGER NOT NULL,
        "sha1pieces" BYTEA NOT NULL,
        "btih"   BYTEA NOT NULL,
        "pgp" TEXT NOT NULL,
        "zblocksize" SMALLINT NOT NULL,
        "zhashlens" VARCHAR(8),
        "zsums" BYTEA NOT NULL
);

-- For conveniency, this view provides the binary columns from the "hash" table
-- also encoded in hex
--
-- Note on binary data (bytea) column.
-- PostgreSQL escapes binary (bytea) data on output. But hex encoding is more
-- efficient (it results in shorter strings, and thus less data to transfer
-- over the wire, and it's also faster). The escape format doesn't make sense
-- for a new application (which we are).
-- On the other hand, storage in bytea is as compact as it can be, which is good.
-- The hex encoding function in PostgreSQL seems to be fast.
CREATE VIEW hexhash AS 
  SELECT file_id, mtime, size, 
         md5,
         encode(md5, 'hex') AS md5hex, 
         sha1,
         encode(sha1, 'hex') AS sha1hex, 
         sha256,
         encode(sha256, 'hex') AS sha256hex, 
         sha1piecesize, 
         sha1pieces,
         encode(sha1pieces, 'hex') AS sha1pieceshex,
         btih,
         encode(btih, 'hex') AS btihhex, 
         pgp,
         zblocksize,
         zhashlens,
         zsums,
         encode(zsums, 'hex') AS zsumshex
  FROM hash;

-- --------------------------------------------------------


CREATE TABLE "server" (
        "id" serial NOT NULL PRIMARY KEY,
        "identifier" varchar(64) NOT NULL UNIQUE,
        "baseurl"       varchar(128) NOT NULL,
        "baseurl_ftp"   varchar(128) NOT NULL,
        "baseurl_rsync" varchar(128) NOT NULL,
        "enabled"        boolean NOT NULL,
        "status_baseurl" boolean NOT NULL,
        "region"  varchar(2) NOT NULL,
        "country" varchar(2) NOT NULL,
        "asn" integer NOT NULL,
        "prefix" varchar(18) NOT NULL,
        "ipv6_only" boolean NOT NULL default 'f',
        "score" smallint NOT NULL,
        "scan_fpm" integer NOT NULL,
        "last_scan" timestamp with time zone NULL,
        "comment" text NOT NULL,
        "operator_name" varchar(128) NOT NULL,
        "operator_url" varchar(128) NOT NULL,
        "public_notes" varchar(512) NOT NULL,
        "admin"       varchar(128) NOT NULL,
        "admin_email" varchar(128) NOT NULL,
        "lat" numeric(6, 3) NULL,
        "lng" numeric(6, 3) NULL,
        "country_only" boolean NOT NULL,
        "region_only" boolean NOT NULL,
        "as_only" boolean NOT NULL,
        "prefix_only" boolean NOT NULL,
        "other_countries" varchar(512) NOT NULL,
        "file_maxsize" integer NOT NULL default 0
);

CREATE INDEX "server_enabled_status_baseurl_score_key" ON "server" (
        "enabled", "status_baseurl", "score"
);

-- --------------------------------------------------------


CREATE TABLE "marker" (
        "id" serial NOT NULL PRIMARY KEY,
        "subtree_name" varchar(128) NOT NULL,
        "markers" varchar(512) NOT NULL
);

-- --------------------------------------------------------

CREATE TABLE "country" (
        "id" serial NOT NULL PRIMARY KEY,
        "code" varchar(2) NOT NULL,
        "name" varchar(64) NOT NULL
);

CREATE TABLE "region" (
        "id" serial NOT NULL PRIMARY KEY,
        "code" varchar(2) NOT NULL,
        "name" varchar(64) NOT NULL
);




-- add a mirror to the list of mirrors where a file was seen
CREATE OR REPLACE FUNCTION mirr_add_byid(arg_serverid integer, arg_fileid integer) RETURNS integer AS $$
BEGIN
        INSERT INTO mirror (mirrorid, fileid) VALUES (arg_serverid, arg_fileid);
        RETURN 1;
EXCEPTION
        WHEN unique_violation THEN
                RAISE DEBUG 'already there -- nothing to do';
                RETURN 0;
END;
$$ LANGUAGE plpgsql;


-- remove a mirror from the list of mirrors where a file was seen
CREATE OR REPLACE FUNCTION mirr_del_byid(arg_serverid integer, arg_fileid integer) RETURNS integer AS $$
BEGIN
        DELETE FROM mirror WHERE fileid = arg_fileid AND mirrorid = arg_serverid;
        IF FOUND THEN
                RETURN 1;
        END IF;

        RETURN 0;
END;
$$ LANGUAGE plpgsql;


-- check whether a given mirror is known to have a file (id)
CREATE OR REPLACE FUNCTION mirr_hasfile_byid(arg_serverid integer, arg_fileid integer) RETURNS boolean AS $$
BEGIN
        PERFORM * FROM mirror WHERE mirrorid = arg_serverid AND fileid = arg_fileid;
        RETURN FOUND;
END;
$$ LANGUAGE plpgsql;


-- check whether a given mirror is known to have a file (name)
CREATE OR REPLACE FUNCTION mirr_hasfile_byname(arg_serverid integer, arg_path text) RETURNS boolean AS $$
BEGIN
    PERFORM fileid FROM file INNER JOIN mirror ON (file.id = mirror.fileid) 
            WHERE path = arg_path AND mirrorid = arg_serverid;
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION mirr_add_bypath(arg_serverid integer, arg_path text) RETURNS integer AS $$
DECLARE
    _fileid integer;
BEGIN
    SELECT INTO _fieldid FROM file INNER JOIN mirror ON (file.id = mirror.fileid)
        WHERE path = arg_path AND mirrorid = arg_serverid;
    IF FOUND THEN
        RAISE DEBUG 'nothing to do';
        RETURN _fieldid;
    END IF;

    SELECT INTO _fileid FROM file WHERE path = arg_path;
    IF NOT FOUND THEN
        -- new file case?
        RAISE DEBUG 'creating entry for new file.';
        INSERT INTO file (path) VALUES (arg_path) RETURNING id INTO _fileid;
    ELSE
        RAISE DEBUG 'update existing file entry (id: %)', _fileid;
    END IF;

    INSERT INTO mirror (fileid, mirrorid) VALUES (_fileid, arg_serverid);
    RETURN _fileid;

EXCEPTION
    WHEN unique_violation THEN
        RAISE NOTICE 'file % was just inserted by somebody else', arg_path;
        -- just update it by calling ourselves again
        SELECT into _fileid mirr_add_bypath(arg_serverid, arg_path);
        RETURN _fileid;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE FUNCTION mirr_get_name(integer) RETURNS text AS '
    SELECT identifier FROM server WHERE id=$1
' LANGUAGE SQL;


CREATE OR REPLACE FUNCTION mirr_get_name(ids smallint[]) RETURNS text[] AS $$
DECLARE
    names text[];
    -- i integer;
BEGIN
    names := ARRAY(
                  select mirr_get_name(cast(ids[i] AS integer)) from generate_series(array_lower(ids, 1), array_upper(ids, 1)) as i
                  );
    RETURN names;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION mirr_get_nfiles(integer) RETURNS bigint AS '
    SELECT count(file.id)
        FROM file
        INNER JOIN mirror ON (file.id = mirror.fileid)
    WHERE mirrorid = $1
' LANGUAGE SQL;


CREATE OR REPLACE FUNCTION mirr_get_nfiles(text) RETURNS bigint AS '
    SELECT count(file.id)
        FROM file
        INNER JOIN mirror ON (file.id = mirror.fileid)
        INNER JOIN server ON (mirror.mirrorid = server.id)
        WHERE identifier = $1
' LANGUAGE SQL;


-- --------------------------------------------------------
COMMIT;
-- --------------------------------------------------------

-- vim: ft=sql ai ts=4 sw=4 smarttab expandtab
