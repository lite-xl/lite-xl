#ifndef STATE_H
#define STATE_H

typedef struct app_state
{
  lua_State *L;
  int has_restarted;
  int argc;
  char **argv;
} app_state;

#endif