#include <windows.h>
#include <ras.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>


enum { CMD_quit, CMD_dialup, CMD_hangup, CMD_status, CMD_nmb };
char cmd_chars[CMD_nmb];
typedef int (*command) (void *arg);
command cmd_hooks[CMD_nmb];

enum { STATE_online, STATE_dialing, STATE_offline, STATE_startup, STATE_nmb};
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


/* =========================================== */
int cmd_ignore (void *p);
int cmd_dialup (void *p);
int cmd_hangup (void *p);
int cmd_quit (void *p);
int cmd_status (void *p);
void hangup (void);
VOID WINAPI rd_callback(UINT unMsg, RASCONNSTATE rasconnstate, DWORD dwError);


int
parse_data_file (const char *file)
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

void
set_state (int state)
{
#define set_state(state_) ((prev_state=curr_state), (curr_state=(state_)))
  if (state != curr_state)
    set_state (state);
#undef set_state
}

static void
update_state_by_rc_state ()
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

void
rd_callback(UINT unMsg, RASCONNSTATE rasconnstate, DWORD dwError)
{
  if (unMsg != WM_RASDIALEVENT)
    return;
  if (rc_state != rasconnstate) {
    rc_state = rasconnstate;
    update_state_by_rc_state ();
  }
}

struct peer *
get_peer (const char *name)
{
  int i;
  for (i=0; i < peer_cnt; ++i)
    if (strcmp (peers[i].name, name) == 0)
      return &peers[i];

  return 0; /* peer not exist */
}

void
dispatch ()
{
  int c, i;
  while ((c = getchar ()) != EOF) {

    switch (c) {
    case 'C':
      if ((c = getchar ()) != EOF) {
	for (i=0; i < CMD_nmb; ++i) {
	  if (cmd_chars[i] == c && cmd_hooks[i]) {
	    char buf[80];
	    if (fgets(buf, sizeof buf, stdin))
	      buf[strlen(buf)-1]= '\0';
	    (cmd_hooks[i]) (buf); }}}
      break;
    case 'D':
      fprintf (stderr, "debug prev_state: %d curr_state: %d rc_state: %d\n",
	      prev_state, curr_state, rc_state);
      break;
    }
  }
}

int
cmd_ignore (void *p)
{
  fprintf (stderr, "cmd_ignore(%s)\n", (const char *)p);
  return 0;
}

int
cmd_dialup (void *p)
{
  DWORD error;
  char buf[512];
  char *error_string="no error";
  const struct peer *peer;

  hangup();

  fprintf (stderr, "cmd_dialup(%s)\n", (const char *)p);
  //  set_state (STATE_dialing); // XXX
  if (!(peer = get_peer (p))) {
    //    set_state (STATE_offline); // XXX
  } else {
    dial_params.dwSize = 1052;  /* XXX-bw/8-Sep-00 stupid Windows95 */
    lstrcpy (dial_params.szEntryName, peer->dun_name);
    lstrcpy (dial_params.szUserName, peer->login);
    lstrcpy (dial_params.szPassword, peer->passwd);
    lstrcpy (dial_params.szPhoneNumber, peer->phone_number);
    dial_params.szCallbackNumber[0] = '*';
    dial_params.szDomain[0] = '*';
    if ((error = RasDial (0, 0, &dial_params, 0, rd_callback, &ras_conn))) {
      char buf[256];
      RasGetErrorStringA(error, buf, sizeof buf);
      fprintf (stderr, "Error %d: %s\n", error, &buf);
    }
    if (!ras_conn)
      set_state (STATE_offline);
  }
  return 0;

}

int
cmd_hangup (void *p)
{
  fprintf (stderr, "cmd_hangup(%s)\n", (const char *)p);
  hangup();
  return 0;
}

int
cmd_quit (void *p)
{
  fprintf (stderr, "cmd_quit(%s)\n", (const char *)p);
  hangup(); /* already in atexit() */
  exit (0);
  /* NOTREACHED */
  return 0;
}

FILE *state_files[STATE_nmb];
char *state_file_names[STATE_nmb];

FILE *file_state_dialing, *file_state_offline, *file_state_lock1, *lock2;
int reported_curr_state = STATE_startup;
int reported_prev_state = STATE_startup;

void
set_file_state (int state)
{
  if (!state_files[state] && state_file_names[state])
    {
      state_files[state] = fopen (state_file_names[state], "w");
    }
}

void
clear_file_state (int state)
{
  if (state_files[state])
    {
      fclose (state_files[state]);
      state_files[state] = 0;
      remove (state_file_names[state]);
    }
}

void
update_state ()
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

int
cmd_status (void *p)
{
  //  fprintf (stderr, "cmd_status(%s)\n", (const char *)p);
  update_state ();
#if 0
  fprintf (stderr, "debug prev_state: %d curr_state: %d rc_state: %d\n",
	  prev_state, curr_state, rc_state);
#endif
  if (reported_curr_state == curr_state &&
      reported_prev_state == prev_state)
    return 0;


 
  if (reported_prev_state != prev_state)
    clear_file_state (reported_prev_state);
  if (reported_curr_state != curr_state)
    clear_file_state (reported_curr_state);

  set_file_state (curr_state);
  
  reported_curr_state = curr_state;
  reported_prev_state = prev_state;
  

  return 0;
}

void
hangup ()
{
  fprintf (stderr, "hangup() 0x%p\n", ras_conn);
  if (ras_conn) {
    RasHangUp (ras_conn);
    ras_conn=0;
    set_state (STATE_offline);
  }
}

void
init ()
{
  int i;
  state_file_names[STATE_dialing] = "C:/WINDOWS/TEMP/tkdialup_dialing";
  state_file_names[STATE_online] = "C:/WINDOWS/TEMP/tkdialup_online";
  state_file_names[STATE_offline] = "C:/WINDOWS/TEMP/tkdialup_offline";
  for (i=0; i < STATE_nmb; ++i)
    if (state_file_names[i])
      remove (state_file_names[i]);
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

void
cleanup ()
{
  int i;
  hangup();
  for (i=0; i < STATE_nmb; ++i)
    clear_file_state (i);

  sleep (3000); /* safe hangup */
}


int
main (int ac, char **av)
{
  init ();
  atexit(cleanup);
  dispatch();
  exit (0);
  /* NOTREACHED */
  return 0;
}
