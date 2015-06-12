ALTER TABLE filearr RENAME TO file;
ALTER SEQUENCE filearr_id_seq RENAME TO file_id_seq;
CREATE TABLE mirror (fileid INTEGER NOT NULL REFERENCES file(id), 
                     mirrorid INTEGER NOT NULL REFERENCES server(id),
                     PRIMARY KEY (fileid, mirrorid));


INSERT INTO mirror (fileid, mirrorid) SELECT id, unnest(mirrors) FROM file;
ALTER TABLE file DROP COLUMN mirrors;



-- add a mirror to the list of mirrors where a file was seen
CREATE OR REPLACE FUNCTION mirr_add_byid(arg_serverid integer, arg_fileid integer) RETURNS integer AS $$
BEGIN
        INSERT INTO mirror (mirrorid, fileid) VALUES (arg_serverid, arg_fileid);
        RETURN 1;
EXCEPTION 
        WHEN unique_violation THEN
                -- RAISE DEBUG 'already there -- nothing to do';
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
    SELECT id INTO _fileid FROM file WHERE path = arg_path;
    IF NOT FOUND THEN
        -- new file case?
        -- RAISE DEBUG 'creating entry for new file.';
        INSERT INTO file (path) VALUES (arg_path) RETURNING id INTO _fileid;
    ELSE
        PERFORM fileid FROM mirror WHERE fileid = _fileid AND mirrorid = arg_serverid;
        IF FOUND THEN
            -- RAISE DEBUG 'nothing to do';
            RETURN _fileid;
        END IF;
    END IF;

    -- RAISE DEBUG 'update existing file entry (id: %)', _fileid;
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
