#include <windows.h>
#include <ras.h>
#include <winsock.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>


#if 0
#define db_trace puts
#define db_tracef(x) printf x
#else
#define db_trace(x)
#define db_tracef(x)
#endif

#define USE_SOCKETS
#define MULTIUSER

enum { CMD_quit, CMD_dialup, CMD_hangup, CMD_status, CMD_nmb };
char cmd_chars[CMD_nmb];
typedef int (*command) (void *arg);
command cmd_hooks[CMD_nmb];

enum { STATE_startup, STATE_offline, STATE_dialing, STATE_online, STATE_nmb};
int curr_state, prev_state;
RASCONNSTATE rc_state;
RASCONNSTATUS rc_status;

#define default_data_file "./w32phonebook.txt"
#define site_data_file "./w32phonebook-site.txt"
#define home_data_file "/.tkd-w32phonebook.txt"
#define PEER_max 100
struct peer {
  char name[40], dun_name[40], login[40], passwd[40], phone_number[40];
} peers[PEER_max];
int peer_cnt;


RASDIALPARAMS dial_params;
HRASCONN ras_conn;

int reported_curr_state = STATE_startup;
int reported_prev_state = STATE_startup;


struct options {
  char *addr;
  unsigned long port;
#define OPT_addr 1
#define OPT_port 2
  long mask;
} opts;

SOCKET sock;
fd_set sock_readfds, sock_writefds, sock_exceptfds;
enum {POLL_block, POLL_wait, POLL_nonblock};

struct sockaddr_in *login_sn;


#define MTYPE_invalid 0
#define MTYPE_test 1
#define MTYPE_dm 2
#define MTYPE_nmb 3

struct msg {
  unsigned short type, size;
};
struct test_msg {
  struct msg h;
  char txt[80];
};

struct dm_msg {
  struct msg h;
  unsigned long sender_addr;
  unsigned short sender_port;
  unsigned short id;
  char txt[80];
#define dm_msg__hsize(mp) (ntohs((mp)->h.size))
#define dm_msg__htype(mp) (ntohs((mp)->h.type))
#define dm_msg__hsender_addr(mp) (ntohl((mp)->sender_addr))
#define dm_msg__hsender_port(mp) (ntohs((mp)->sender_port))
#define dm_msg__nsize(mp) (0+((mp)->h.size))
#define dm_msg__ntype(mp) (0+((mp)->h.type))
#define dm_msg__nsender_addr(mp) (0+((mp)->sender_addr))
#define dm_msg__nsender_port(mp) (0+((mp)->sender_port))
#define dm_msg__init(mp)  (((mp)->h.size = htons(sizeof (struct dm_msg))),\
			   ((mp)->h.type = MTYPE_dm))
};

struct dm_msg msg_template;


/* =========================================== */
int parse_data_file (const char *file);
void set_state (int state);
static void update_state_by_rc_state ();
void rd_callback(UINT unMsg, RASCONNSTATE rasconnstate, DWORD dwError);
struct peer *get_peer (const char *name);
int make_recv_socket (struct sockaddr_in *sn);
int init_sockets ();
int recv_msg (struct msg *msg);
int recv_dm_msg (struct dm_msg *msg);
int poll_socket (int poll_type);
int reply_dm_msg (struct dm_msg *msg);
int handle_login (struct dm_msg *msg);
void tick_state ();
void tick ();
void dispatch ();
void Usage(char *programName);
int HandleOptions(int argc,char *argv[]);
int cmd_ignore (void *p);
int cmd_dialup (void *p);
int cmd_hangup (void *p);
int cmd_quit (void *p);
void update_state ();
int cmd_status (void *p);
void hangup ();
void init ();
void cleanup ();
int main (int ac, char **av);

int parse_data_file (const char *file)
{
  FILE *in;
  if ((in = fopen (file, "r"))) {
    int rc;
    while (peer_cnt < PEER_max &&
	   (rc= fscanf (in, "%39s %39s %39s %39s %39s\n",
			peers[peer_cnt].name,
			peers[peer_cnt].dun_name,
			peers[peer_cnt].login,
			peers[peer_cnt].passwd,
			peers[peer_cnt].phone_number)) != EOF) {

      if (strcmp (peers[peer_cnt].login, ".") == 0) peers[peer_cnt].login[0] = '\0';
      if (strcmp (peers[peer_cnt].passwd, ".") == 0) peers[peer_cnt].passwd[0] = '\0';
      if (strcmp (peers[peer_cnt].phone_number, ".") == 0) peers[peer_cnt].phone_number[0] = '\0';
      
      if (rc >= 2) /* we must have at least .name and .dun_name */
	++peer_cnt;
    }
    fclose (in);
    return 0;
  }
  return -1;
}

void set_state (int state)
{
#define set_state(state_) ((prev_state=curr_state), (curr_state=(state_)))
  if (state != curr_state)
    set_state (state);
#undef set_state
}

static void update_state_by_rc_state ()
{
  puts ("trace update_state_by_rc_state ()");
  switch (rc_state) {
  case RASCS_ConnectDevice:
    set_state (STATE_dialing);
    break;
  case RASCS_Connected:
    set_state (STATE_online);
    break;
  case RASCS_Disconnected:
    set_state (STATE_offline);
    hangup ();
    break;
  }
}

void rd_callback(UINT unMsg, RASCONNSTATE rasconnstate, DWORD dwError)
{
  if (unMsg != WM_RASDIALEVENT)
    return;
  if (rc_state != rasconnstate) {
    rc_state = rasconnstate;
    update_state_by_rc_state ();
  }
}

struct peer *get_peer (const char *name)
{
  int i;
  for (i=0; i < peer_cnt; ++i)
    if (strcmp (peers[i].name, name) == 0)
      return &peers[i];

  return 0; /* peer not exist */
}


/*** Sockets ***/
int make_recv_socket (struct sockaddr_in *sn)
{
  if ((sock = socket (sn->sin_family, SOCK_DGRAM, 0)) == INVALID_SOCKET)
    return -1;
  return bind (sock, sn, sizeof *sn);
}



int init_sockets ()
{
  WORD wVersionRequested;
  WSADATA wsaData;
  int err;

  wVersionRequested = MAKEWORD( 1, 1 );

  if ((err = WSAStartup (wVersionRequested, &wsaData))) {
    /* Tell the user that we couldn't find a usable */
    /* WinSock DLL.                                  */
    return err;
  }

  return 0;
}

/*** Messages ***/
int recv_msg (struct msg *msg)
{
  unsigned short old_size = msg->size;

  int err = recv (sock, (char *) msg, ntohs (msg->size), 0);
  if (err != SOCKET_ERROR)
    if (old_size != msg->size)
      msg->type = htons (MTYPE_invalid);

  return err;
}

int recv_dm_msg (struct dm_msg *msg)
{
  unsigned short old_size = msg->h.size;
  struct sockaddr_in sn;
  int sn_size = sizeof sn;

  int err = recvfrom (sock, (char *) msg, ntohs (msg->h.size), 0, (void *)&sn, &sn_size);
  if (err != SOCKET_ERROR) {
    if (old_size != msg->h.size)
      msg->h.type = htons (MTYPE_invalid);
    /* Don't allow wrong (!?) sender_addr/sender_port fields in msg */
    if (sn.sin_addr.s_addr != msg->sender_addr)
      msg->h.type = htons (MTYPE_invalid);
    if (sn.sin_port != msg->sender_port)
      msg->h.type = htons (MTYPE_invalid);
  }


  return err;
}

int poll_socket (int poll_type)
{
  struct timeval tv, *tvp=&tv;
  int sock_nfds;
  if (poll_type == POLL_wait) {
    tv.tv_sec = 0;
    tv.tv_usec = 250000;
  } else if (poll_type == POLL_nonblock) {
    tv.tv_sec = 0;
    tv.tv_usec = 0;
  } else /* if (poll_type == POLL_block) */ {
    tvp=0;
  }

  FD_ZERO (&sock_readfds);
  FD_ZERO (&sock_writefds);
  FD_ZERO (&sock_exceptfds);
  FD_SET (sock, &sock_readfds);
  sock_nfds = sock;

  return select (sock_nfds, &sock_readfds, &sock_writefds, &sock_exceptfds, tvp);
  /* Note: According to w32SDK-help we could just pass NULL for each
     fd-set on w32 systems -bw */
}

int send_msg_to (struct msg *msg, struct sockaddr_in *sn) {
  return sendto (sock,
		 (char *) msg, ntohs(msg->size),
		 0, sn, sizeof *sn);
}

int send_dm_string (const char *s, struct sockaddr_in *sn) {
  int err;
  struct dm_msg msg = msg_template;
  strncpy (msg.txt, s, (sizeof msg.txt) - 1);
  db_tracef(("trace send_dm_string: %s addr: 0x%p port: %u\n", s,
	 dm_msg__hsender_addr(&msg),
	 (unsigned)dm_msg__hsender_port(&msg)));
  if ((err = send_msg_to (&msg.h, sn)) == SOCKET_ERROR)
    printf ("error in send_dm_string: %d\n", WSAGetLastError());
  return err;
}

/* Return dm_msg MSG to sender. */
/* The original msg->sender_addr|port are kept. */
int reply_dm_msg (struct dm_msg *msg)
{
  struct sockaddr_in sn;
  sn.sin_family = PF_INET;
  sn.sin_port = dm_msg__nsender_port (msg);
  sn.sin_addr.s_addr = dm_msg__nsender_addr (msg);

  return send_msg_to (&msg->h, &sn);
}

/* If MSG is a 'L' try to perform login/logout.  Otherwise, test if
   MSG sender is allowed to send restricted commands which require a
   succesful login.  Returns 0 for succes. */
int handle_login (struct dm_msg *msg)
{
  static struct sockaddr_in sn = { PF_INET, };

  if (msg->txt[0] == 'L') {
    switch (msg->txt[1]) {
    case 'i':
      if (!sn.sin_addr.s_addr && !sn.sin_port) {
	sn.sin_port = dm_msg__nsender_port (msg);
	sn.sin_addr.s_addr = dm_msg__nsender_addr (msg);
	login_sn = &sn;
	return 0;
      }
      break;
    case 'o':
      if (sn.sin_port == dm_msg__nsender_port (msg) &&
	  sn.sin_addr.s_addr == dm_msg__nsender_addr (msg)) {
	sn.sin_addr.s_addr = 0;
	sn.sin_port = 0;
	login_sn = 0;
	return 0;
      }
      break;
    default:
      return -1;
    }
  } else {
    if (sn.sin_port == dm_msg__nsender_port (msg) &&
	sn.sin_addr.s_addr == dm_msg__nsender_addr (msg))
      return 0;
  }
  return -1;
}

void tick_state ()
{
  char *s=0;

  update_state ();
  if (reported_curr_state != curr_state) {
    if (prev_state <= STATE_offline) {
      if (curr_state == STATE_dialing)
	s="Sd";
    } else if (prev_state == STATE_dialing) {
      if (curr_state == STATE_online) {
	s="Sc";
      } else if (curr_state == STATE_offline) {
	s="Sf";
      }
    } else if (prev_state == STATE_online) {
      s="Sx";
    }

    if (s && login_sn)
      send_dm_string (s, login_sn);

    reported_curr_state = curr_state;
    reported_prev_state = prev_state;
  }
}

/* tick - propagate timer ticks */
/* tick() is called for each timout and for each arrieved message.  If
 SLOW is set, this tick() was called from a timer but. */
void tick (int slow)
{
  db_trace("tick()");
  if (slow) {
    tick_state();
  }
}

/*** Mesage Processing ***/
void dispatch ()
{
  int c, i, err;
  struct sockaddr_in sock_name;
  sock_name.sin_family = PF_INET;
  sock_name.sin_port = (opts.mask & OPT_port) ? htons (opts.port) : htons (8888);
  sock_name.sin_addr.s_addr = ((opts.mask & OPT_addr) ?  inet_addr(opts.addr)
			       : INADDR_ANY);

  if ((err=init_sockets ()))
    {
      printf ("error in init-socket: %d\n", WSAGetLastError());
      return;
    } else if ((err=make_recv_socket (&sock_name))) {
      printf ("cannot bind socket: %d\n", WSAGetLastError());
      return;
    } else {
      int msg_pending=0; /* FIXME */
      struct dm_msg msg;
      
      dm_msg__init (&msg);

      /* init our template for creating sending messages */
      dm_msg__init (&msg_template);
      /* Note: I assume 4 byte addresses in next line.  This works for IPv4 addresses */
      memcpy (&msg_template.sender_addr, gethostbyname ("localhost")->h_addr_list[0], 4);
      msg_template.sender_port = sock_name.sin_port;
      
      /* event loop */
      for (;;) {
	int ps_res;
	int poll_type 
	  = ((msg_pending) ? POLL_nonblock
	     : ((curr_state > STATE_offline) ? POLL_wait : POLL_block));
	
	if ((ps_res = poll_socket (poll_type))== SOCKET_ERROR) {
	  puts("Socket Error");
	  /* TODO */ break; /* ???-bw/17-Sep-00 */

	} else {
	  tick(!msg_pending);

	  msg_pending = 0; /* reset */

	  /* Receive and process all pending messages */
	  if (ps_res > 0 && FD_ISSET (sock, &sock_readfds)) {
	    int err;
	    msg_pending = 1;

	    err = recv_msg (&msg.h);

	    db_tracef(("trace recv_dm_msg: %s addr: 0x%p port: %u\n", msg.txt,
		   dm_msg__hsender_addr(&msg),
		   (unsigned)dm_msg__hsender_port(&msg)));

	    db_trace("got message");
	    if (err == SOCKET_ERROR) {
	      printf ("Last Error: %d\n", WSAGetLastError());
	      break; // XXX
	    }
	    else if (dm_msg__htype (&msg) != MTYPE_dm)
	      {
		printf("wrong type of message <%d>\n", msg.h.type);
		continue; // XXX
	      }

	    switch (msg.txt[0]) {
	    case 'C': /* command */
	      if (!handle_login (&msg) && (c = msg.txt[1])) {
		for (i=0; i < CMD_nmb; ++i) {
		  if (cmd_chars[i] == c && cmd_hooks[i]) {
		    (cmd_hooks[i]) (&msg.txt[2]);
		    msg.txt[0]='R'; msg.txt[0]='o';
		    reply_dm_msg (&msg);
		    break;
		  }
		}
	      } else {
		msg.txt[0]='R'; msg.txt[0]='e';
		reply_dm_msg (&msg);
	      }
	      break;
	    case 'D': /* debug */
	      fprintf (stderr, "debug prev_state: %d curr_state: %d rc_state: %d\n",
		       prev_state, curr_state, rc_state);
	      break;
	    case 'L':  /* login, logout */
	      if (handle_login (&msg)) {
		msg.txt[0]='R'; msg.txt[0]='e';
		reply_dm_msg (&msg);
	      } else {
		msg.txt[0]='R'; msg.txt[0]='o';
		reply_dm_msg (&msg);
	      }
	      break;
	    }
	  }
	}
      }
    }
}

void Usage(char *programName)
{
  char buf[300];
  sprintf(buf, "echo %s usage: [-p <IP-Port-Number>] [ -a <IP-Address-Mask> ] \n"
	  ,programName);
  system (buf);
}	

/* returns the index of the first argument that is not an option; i.e.
   does not start with a dash or a slash
*/
int HandleOptions(int argc,char *argv[])
{
  int i,firstnonoption=0;

  for (i=1; i< argc;i++) {
    if (argv[i][0] == '/' || argv[i][0] == '-') {
      switch (argv[i][1]) {
				/* An argument -? means help is requested */
      case '?':
      case 'h':
	Usage(argv[0]);
	exit(0);
	break;
       case 'H':
	if (!stricmp(argv[i]+1,"help")) {
	  Usage(argv[0]);
	  break;
	}
	/* If the option -h means anything else
	 * in your application add code here 
	 * Note: this falls through to the default
	 * to print an "unknow option" message
	 */
				/* add your option switches here */
      case 'a':
	if (argv[i+1]) {
	  opts.addr = argv[++i];
	  opts.mask |= OPT_addr;
	} else {
	  Usage(argv[0]);
	  exit (EXIT_FAILURE);
	}
	break;
      case 'p':
	if (argv[i+1]) {
	  opts.port = atol (argv[++i]);
	  opts.mask |= OPT_port;
	} else {
	  Usage(argv[0]);
	  exit (EXIT_FAILURE);
	}
	break;
      default:
	fprintf(stderr,"unknown option %s\n",argv[i]);
	break;
      }
    }
    else {
      firstnonoption = i;
      break;
    }
  }
  return firstnonoption;
}



/*** Commands ***/
int cmd_ignore (void *p)
{
  db_tracef (("cmd_ignore(%s)\n", (const char *)p));
  return 0;
}

int cmd_dialup (void *p)
{
  DWORD error;
  char buf[512];
  char *error_string="no error";
  const struct peer *peer;
#ifdef MULTIUSER /* a hangup() should only done if the connection is
                    owned by the same user -bw/14-Sep-00 */
  hangup();
#else
  if (curr_state != STATE_offline ||
      curr_state != STATE_startup) /* we could leave such checks to windows */
    return;
#endif
  db_tracef (("cmd_dialup(%s)\n", (const char *)p));
  //  set_state (STATE_dialing); // XXX
  if (!(peer = get_peer (p))) {
    fprintf(stderr, "unknown peer <%s>\n", (const char *)p);
    //    set_state (STATE_offline); // XXX
  } else {
    dial_params.dwSize = 1052;  /* XXX-bw/8-Sep-00 stupid Windows95 */
    lstrcpy (dial_params.szEntryName, peer->dun_name);
    lstrcpy (dial_params.szUserName, peer->login);
    lstrcpy (dial_params.szPassword, peer->passwd);
    lstrcpy (dial_params.szPhoneNumber, peer->phone_number);
    dial_params.szCallbackNumber[0] = '*';
    dial_params.szDomain[0] = '*';
    set_state (STATE_dialing); tick_state();
    if ((error = RasDial (0, 0, &dial_params, 0, rd_callback, &ras_conn))) {
      char buf[256];
      RasGetErrorStringA(error, buf, sizeof buf);
      fprintf (stderr, "Error %d: %s\n", error, &buf);
    }
    if (!ras_conn)
      {
	set_state (STATE_offline); tick_state ();
      }
  }
  return 0;

}

int cmd_hangup (void *p)
{
  db_tracef (("cmd_hangup(%s)\n", (const char *)p));
  hangup();
  return 0;
}

int cmd_quit (void *p)
{
  fprintf (stderr, "cmd_quit(%s)\n", (const char *)p);
  hangup(); /* already in atexit() */
  exit (0);
  /* NOTREACHED */
  return 0;
}

void update_state ()
{
  int error;
  if (ras_conn && curr_state == STATE_online)
    if (!(error=RasGetConnectStatus (ras_conn, &rc_status))) {
      if (rc_state != rc_status.rasconnstate) {
	rc_state=rc_status.rasconnstate;
	update_state_by_rc_state ();
      }
    } else if (error == ERROR_INVALID_HANDLE) {
      rc_state=RASCS_Disconnected; /* XXX */
      update_state_by_rc_state ();
    } else {
      char buf[256];
      RasGetErrorStringA(error, buf, sizeof buf);
      fprintf (stderr, "Error %d: %s\n", error, &buf);
    }
}

int cmd_status (void *p)
{
  //  fprintf (stderr, "cmd_status(%s)\n", (const char *)p);
  tick_state();
  return 0;
}

void hangup ()
{
  db_tracef(("hangup() 0x%p\n", ras_conn));
  if (ras_conn) {
    RasHangUp (ras_conn);
    ras_conn=0;
    set_state (STATE_offline); tick_state ();
  }
}

void init ()
{
  int i;
  rc_status.dwSize = 160; /* XXX-bw/10-Sep-00 stupid Windows95 */

  cmd_hooks[CMD_quit] = cmd_quit;
  cmd_hooks[CMD_dialup] = cmd_dialup;
  cmd_hooks[CMD_hangup] = cmd_hangup;
  cmd_hooks[CMD_status] = cmd_status;
  cmd_chars[CMD_quit] = 'q';
  cmd_chars[CMD_dialup] = 'd';
  cmd_chars[CMD_hangup] = 'h';
  cmd_chars[CMD_status] = 's';
  prev_state = curr_state = STATE_startup;


#ifdef home_data_file
  {
    const char *home=getenv("HOME");
    char *buf;
    if (home &&
	(buf = malloc (strlen (home) + strlen (home_data_file) + 1))) {
      strcpy (buf, home);
      strcat (buf, home_data_file);
      parse_data_file (buf);
      free (buf);
    }
  }
#endif
#ifdef site_data_file	
  parse_data_file (default_data_file);
#endif
#ifdef default_data_file	
  parse_data_file (default_data_file);
#endif
}

void cleanup ()
{
  int i;
  hangup();
  sleep (3000); /* safe hangup */
}


int main (int ac, char **av)
{
  HandleOptions (ac, av);
  init ();
  atexit(cleanup);
  dispatch();
  exit (0);
  /* NOTREACHED */
  return 0;
}
