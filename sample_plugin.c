
typedef struct lua_State lua_State;
#define SYMBOL(NAME, RTYPE, ...) RTYPE (*lua_##NAME)(lua_State*, __VA_ARGS__) = (RTYPE (*)(lua_State*, __VA_ARGS__))symbol("lua_" #NAME);

int lua_open_sample(lua_State* L, void* (*symbol(const char*))) {
  SYMBOL(createtable, void, int, int);
  SYMBOL(setfield, void, int, const char*);
  SYMBOL(pushstring, const char*, const char*);
  
  lua_createtable(L, 0, 0);
  lua_pushstring(L, "value");
  lua_setfield(L, -2, "example");
  return 1;
}
