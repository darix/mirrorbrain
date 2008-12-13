from sqlobject.sqlbuilder import AND

def has_file(conn, path, mirror_id):
    """check if file 'path' exists on mirror 'mirror_id'
    by looking at the database.
    
    path can contain wildcards, which will result in a LIKE match.
    """
    if path.find('*') > 0 or path.find('%') > 0:
        pattern = True
        oprtr = 'like'
        path = path.replace('*', '%')
    else:
        pattern = False
        oprtr = '='

    query = 'SELECT path \
                FROM file \
                LEFT JOIN file_server \
                ON file.id = file_server.fileid \
                WHERE file_server.serverid = %s \
                 AND  file.path %s \'%s\' \
                ORDER BY file.path' \
                  % (mirror_id, oprtr, path)


    rows = conn.FileServer._connection.queryAll(query)

    return len(rows) > 0


def check_for_marker_files(conn, markers, mirror_id):
    """
    Check if all files in the markers list are present on a mirror,
    according to the database. 

    Markers actually a list of marker files.

    If a filename is prefixed with !, it negates the match, thus it can be used
    to check for non-existance.
    """
    found_all = True
    for m in markers.split():
        found_this = has_file(conn, m.lstrip('!'), mirror_id)
        if m.startswith('!'):
            found_this = not found_this
        found_all = found_all and found_this
    return found_all


def ls(conn, path, mirror = None):
    if path.find('*') > 0 or path.find('%') > 0:
        pattern = True
        oprtr = 'like'
        path = path.replace('*', '%')
    else:
        pattern = False
        oprtr = '='

    if mirror:
        query = 'SELECT server.identifier, server.country, server.region, \
                           server.score, server.baseurl, server.enabled, \
                           server.status_baseurl, file.path \
                    FROM file \
                    LEFT JOIN file_server \
                    ON file.id = file_server.fileid \
                    LEFT JOIN server \
                    ON file_server.serverid = server.id \
                    WHERE file.path %s \'%s\' \
                    AND file_server.serverid = %s \
                    ORDER BY server.region, server.country, server.score DESC' \
                      % (oprtr, path, mirror.id)
    else:
        query = 'SELECT server.identifier, server.country, server.region, \
                           server.score, server.baseurl, server.enabled, \
                           server.status_baseurl, file.path \
                    FROM file \
                    LEFT JOIN file_server \
                    ON file.id = file_server.fileid \
                    LEFT JOIN server \
                    ON file_server.serverid = server.id \
                    WHERE file.path %s \'%s\' \
                    ORDER BY server.region, server.country, server.score DESC' \
                      % (oprtr, path)

    rows = conn.FileServer._connection.queryAll(query)

    files = []
    # ugly. Really need to let an ORM do this.
    for i in rows:
        d = { 'identifier':     i[0],
              'country':        i[1] or '',
              'region':         i[2] or '',
              'score':          i[3] or 0,
              'baseurl':        i[4] or '<base url n/a>',
              'enabled':        i[5],
              'status_baseurl': i[6], }
        if pattern:
            d['path'] = i[7]
        else:
            d['path'] = path

        files.append(d)

    return files


def add(conn, path, mirror):

    files = conn.File.select(conn.File.q.path==path)
    if files.count() == 0:
        f = conn.File(path = path)
        fileid = f.id
    else:
        fileid = list(files)[0].id

    relations = conn.FileServer.select(AND(conn.FileServer.q.fileid == fileid,
                                           conn.FileServer.q.serverid == mirror.id))
    if relations.count() == 0:

        # this doesn't work because the table doesn't have a primary key 'id'...
        # (our primary Key consists only of a number of columns)
        #import datetime
        #fs = conn.FileServer(fileid = f.id,
        #                     serverid = mirror.id,
        #                     pathMd5 = b64_md5(path),
        #                     timestampScanner = datetime.datetime.now())
        #print fs

        query = """INSERT INTO file_server SET fileid=%d, serverid=%d""" \
                   % (fileid, mirror.id)
        conn.FileServer._connection.queryAll(query)
    else:
        print 'already exists'


def rm(conn, path, mirror):
    fileobj = conn.File.select(conn.File.q.path==path)
    fileid = list(fileobj)[0].id
    print fileid
    query = """DELETE FROM file_server WHERE serverid=%s AND fileid=%s""" \
                 % (mirror.id, fileid)
    print query
    print conn.FileServer._connection.queryAll(query)
