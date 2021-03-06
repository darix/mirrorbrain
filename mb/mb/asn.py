
def iplookup(conn, s):

    from mb.util import IpAddress
    import mb.mberr


    if s[0].isdigit():
        a = IpAddress()
        if ':' in s:
            a.ip6 = s
        else:
            a.ip = s

    else:
        import sys, socket
        ips = []
        ip6s = []
        try:
            for res in socket.getaddrinfo(s, None):
                af, socktype, proto, canonname, sa = res
                if ':' in sa[0]:
                    if sa[0] not in ip6s:
                        ip6s.append(sa[0])
                else:
                    if sa[0] not in ips:
                        ips.append(sa[0])
        except socket.error, e:
            if e[0] == socket.EAI_NONAME:
                raise mb.mberr.NameOrServiceNotKnown(s)
            else:
                print 'socket error msg:', str(e)
                return None


        #print ips
        #print ip6s
        if len(ips) > 1 or len(ip6s) > 1:
            print >>sys.stderr, '>>> warning: %r resolves to multiple IP addresses: ' % s,
            if len(ips) > 1:
                print >>sys.stderr, ', '.join(ips),
            if len(ip6s) > 1:
                print >>sys.stderr, ', '.join(ip6s),
            print >>sys.stderr, '\n>>> see http://mirrorbrain.org/archive/mirrorbrain/0042.html why this could\n' \
                                '>>> could be a problem, and what to do about it. But note that this is not\n' \
                                '>>> necessarily a problem and could actually be intended depending on the\n' \
                                '>>> mirror\'s configuration (see http://mirrorbrain.org/issues/issue152).\n' \
                                '>>> It\'s best to talk to the mirror\'s admins.\n'
        a = IpAddress()
        if ips: a.ip = ips[0]
        if ip6s: a.ip6 = ip6s[0]
        

    if not a.ip:
        return a
    query = """SELECT pfx, asn \
                   FROM pfx2asn \
                   WHERE pfx >>= ipaddress('%s') \
                   ORDER BY @ pfx \
                   LIMIT 1""" % a.ip

    try:
        res = conn.Pfx2asn._connection.queryAll(query)
    except AttributeError:
        # we get this error if mod_asn isn't installed as well
        return a

    if len(res) != 1:
        return a
    (a.prefix, a.asn) = res[0]
    return a

def asn_prefixes(conn, asn):

    query = """SELECT pfx \
                   FROM pfx2asn \
                   WHERE asn='%s'""" % asn

    res = conn.Pfx2asn._connection.queryAll(query)
    l = [ i[0] for i in res ]
    return l
