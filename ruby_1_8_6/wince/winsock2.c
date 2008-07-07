/***************************************************************
  winsock2.c
***************************************************************/

//#define _WINSOCK2_C_DEBUG_MAIN_

#include <windows.h>
#include "wince.h"
#ifdef _WINSOCK2_C_DEBUG_MAIN_
  #include <winsock.h>
#endif

#ifndef _WINSOCK2_C_DEBUG_MAIN_
struct  servent{
	char*  s_name;     /* official service name */
	char** s_aliases;  /* alias list */
	short  s_port;     /* port # */
	char*  s_proto;    /* protocol to use */
};
struct  protoent{
	char*  p_name;     /* official protocol name */
	char** p_aliases;  /* alias list */
	short  p_proto;    /* protocol # */
};
#endif

struct sproto{
	short num;
	char name[10];
};
struct sserv{
	short num;
	char protoname[10];
	char servname[20];
};

static struct sproto _proto_table[11]={
	0,  "ip",
	1,  "icmp",
	3,  "ggp",
	6,  "tcp",
	8,  "egp",
	12, "pup",
	17, "udp",
	20, "hmp",
	22, "xns-idp",
	27, "rdp",
	66, "rvd",
};

static struct sserv _serv_table[142]={
	7, "tcp", "echo",
	7, "udp", "echo",
	9, "tcp", "discard",
	9, "udp", "discard",
	11, "tcp", "systat",
	11, "udp", "systat",
	13, "tcp", "daytime",
	13, "udp", "daytime",
	15, "tcp", "netstat",
	17, "tcp", "qotd",
	17, "udp", "qotd",
	19, "tcp", "chargen",
	19, "udp", "chargen",
	20, "tcp", "ftp-data",
	21, "tcp", "ftp",
	23, "tcp", "telnet",
	25, "tcp", "smtp",
	37, "tcp", "time",
	37, "udp", "time",
	39, "udp", "rlp",
	42, "tcp", "name",
	42, "udp", "name",
	43, "tcp", "whois",
	53, "tcp", "domain",
	53, "udp", "domain",
	53, "tcp", "nameserver",
	53, "udp", "nameserver",
	57, "tcp", "mtp",
	67, "udp", "bootp",
	69, "udp", "tftp",
	77, "tcp", "rje",
	79, "tcp", "finger",
	87, "tcp", "link",
	95, "tcp", "supdup",
	101, "tcp", "hostnames",
	102, "tcp", "iso-tsap",
	103, "tcp", "dictionary",
	103, "tcp", "x400",
	104, "tcp", "x400-snd",
	105, "tcp", "csnet-ns",
	109, "tcp", "pop",
	109, "tcp", "pop2",
	110, "tcp", "pop3",
	111, "tcp", "portmap",
	111, "udp", "portmap",
	111, "tcp", "sunrpc",
	111, "udp", "sunrpc",
	113, "tcp", "auth",
	115, "tcp", "sftp",
	117, "tcp", "path",
	117, "tcp", "uucp-path",
	119, "tcp", "nntp",
	123, "udp", "ntp",
	137, "udp", "nbname",
	138, "udp", "nbdatagram",
	139, "tcp", "nbsession",
	144, "tcp", "NeWS",
	153, "tcp", "sgmp",
	158, "tcp", "tcprepo",
	161, "tcp", "snmp",
	162, "tcp", "snmp-trap",
	170, "tcp", "print-srv",
	175, "tcp", "vmnet",
	315, "udp", "load",
	400, "tcp", "vmnet0",
	500, "udp", "sytek",
	512, "udp", "biff",
	512, "tcp", "exec",
	513, "tcp", "login",
	513, "udp", "who",
	514, "tcp", "shell",
	514, "udp", "syslog",
	515, "tcp", "printer",
	517, "udp", "talk",
	518, "udp", "ntalk",
	520, "tcp", "efs",
	520, "udp", "route",
	525, "udp", "timed",
	526, "tcp", "tempo",
	530, "tcp", "courier",
	531, "tcp", "conference",
	531, "udp", "rvd-control",
	532, "tcp", "netnews",
	533, "udp", "netwall",
	540, "tcp", "uucp",
	543, "tcp", "klogin",
	544, "tcp", "kshell",
	550, "udp", "new-rwho",
	556, "tcp", "remotefs",
	560, "udp", "rmonitor",
	561, "udp", "monitor",
	600, "tcp", "garcon",
	601, "tcp", "maitrd",
	602, "tcp", "busboy",
	700, "udp", "acctmaster",
	701, "udp", "acctslave",
	702, "udp", "acct",
	703, "udp", "acctlogin",
	704, "udp", "acctprinter",
	704, "udp", "elcsd",
	705, "udp", "acctinfo",
	706, "udp", "acctslave2",
	707, "udp", "acctdisk",
	750, "tcp", "kerberos",
	750, "udp", "kerberos",
	751, "tcp", "kerberos_master",
	751, "udp", "kerberos_master",
	752, "udp", "passwd_server",
	753, "udp", "userreg_server",
	754, "tcp", "krb_prop",
	888, "tcp", "erlogin",
	1109, "tcp", "kpop",
	1167, "udp", "phone",
	1524, "tcp", "ingreslock",
	1666, "udp", "maze",
	2049, "udp", "nfs",
	2053, "tcp", "knetd",
	2105, "tcp", "eklogin",
	5555, "tcp", "rmt",
	5556, "tcp", "mtb",
	9535, "tcp", "man",
	9536, "tcp", "w",
	9537, "tcp", "mantst",
	10000, "tcp", "bnews",
	10000, "udp", "rscs0",
	10001, "tcp", "queue",
	10001, "udp", "rscs1",
	10002, "tcp", "poker",
	10002, "udp", "rscs2",
	10003, "tcp", "gateway",
	10003, "udp", "rscs3",
	10004, "tcp", "remp",
	10004, "udp", "rscs4",
	10005, "udp", "rscs5",
	10006, "udp", "rscs6",
	10007, "udp", "rscs7",
	10008, "udp", "rscs8",
	10009, "udp", "rscs9",
	10010, "udp", "rscsa",
	10011, "udp", "rscsb",
	10012, "tcp", "qmaster",
	10012, "udp", "qmaster",
};

/* WinCE doesn't have /etc/protocols. */
struct protoent* getprotobyname(const char* name)
{
	static struct protoent pe;
	int i;
	int len = strlen(name);

	memset( &pe, 0, sizeof(struct protoent) );

	for(i=0; i<9; i++)
	{
		if( 0==strnicmp(_proto_table[i].name, name, len) )
		{
			pe.p_name = _proto_table[i].name;
			pe.p_proto= _proto_table[i].num;
			break;
		}
	}

	return &pe;
}

struct protoent* getprotobynumber(int proto)
{
	static struct protoent pe={0};
	int i;

	memset( &pe, 0, sizeof(struct protoent) );

	for(i=0; i<9; i++)
	{
		if( proto == _proto_table[i].num )
		{
			pe.p_name = _proto_table[i].name;
			pe.p_proto= _proto_table[i].num;
			break;
		}
	}

	return &pe;
}

/* WinCE doesn't have /etc/services. */
struct servent* getservbyname(const char* name,
                              const char* proto)
{
	static struct servent se;
	int i;
	int slen = strlen(name), plen = strlen(proto);

	memset( &se, 0, sizeof(struct servent) );

	if( proto==NULL ) return NULL;
	if( 0!=strnicmp( proto, "tcp", 3 ) &&
		0!=strnicmp( proto, "udp", 3 ) )
		return NULL;

	for( i=0; i<142; i++ )
	{
		if( 0==strnicmp( name, _serv_table[i].servname, slen ) &&
			0==strnicmp( proto, _serv_table[i].protoname, plen ) )
		{
			char hc, lc;
			se.s_name = _serv_table[i].servname;
			se.s_proto= _serv_table[i].protoname;
			hc = (_serv_table[i].num&0xFF00)>>8;
			lc = _serv_table[i].num&0xFF;
			se.s_port = (lc<<8) + hc;
			break;
		}
	}

	return &se;
}

struct servent* getservbyport(int port, const char* proto)
{
	static struct servent se;
	int i;
	int plen = strlen(proto);
	short sport;
	char  lc, hc;

	hc = (port&0xFF00)>>8;
	lc = port&0xFF;

	sport = (lc<<8) + hc;

	memset( &se, 0, sizeof(struct servent) );

	if( proto==NULL ) return NULL;
	if( 0!=strnicmp( proto, "tcp", 3 ) &&
		0!=strnicmp( proto, "udp", 3 ) )
		return NULL;

	for( i=0; i<142; i++ )
	{
		if( sport == _serv_table[i].num &&
			0==strnicmp( proto, _serv_table[i].protoname, plen ) )
		{
			se.s_name = _serv_table[i].servname;
			se.s_proto= _serv_table[i].protoname;
			se.s_port = port;
			break;
		}
	}

	return &se;
}


#ifdef _WINSOCK2_C_DEBUG_MAIN_

int main()
{
	WORD wVersionRequested = MAKEWORD(1,1);
	WSADATA wsaData;
	int nErrorStatus;
	struct protoent pe1, pe2;
	struct servent se1, se2;

	nErrorStatus = WSAStartup(wVersionRequested, &wsaData);
	if(nErrorStatus != 0)
		return -1;

	pe1 = *getprotobyname("UDP");
	pe2 = *_getprotobyname("UDP");

//	pe1 = *getprotobynumber(17);
//	pe2 = *_getprotobynumber(17);

//	se1 = *getservbyname("gateway", "tcp");
//	se2 = *_getservbyname("gateway", "tcp");

	se1 = *getservbyport(0x1327, "tcp");
	se2 = *_getservbyport(0x1327, "tcp");

	WSACleanup();

	return 0;
}

#endif
