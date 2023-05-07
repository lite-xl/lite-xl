/*
 * Crossplatform implementation of shared memory objects.
 *
 * References:
 *
 * POSIX Naming conventions:
 *   1. man shm_open
 *   2. man 7 sem_overview
 *
 * Windows Naming conventions:
 *   1. https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createfilemappinga
 */

#include "api.h"
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#ifdef _WIN32
  #include <windows.h>

  typedef HANDLE shmem_handle;
  typedef HANDLE shmem_mutex_handle;
#else
  #include <unistd.h>
  #include <sys/mman.h>
  #include <sys/stat.h>
  #include <fcntl.h>
  #include <semaphore.h>

  typedef int shmem_handle;
  typedef sem_t* shmem_mutex_handle;
#endif

#define SHMEM_NAME_LEN 124
#define SHMEM_NS_LEN 251

typedef struct {
  shmem_handle handle;
  char name[SHMEM_NS_LEN];
  size_t size;
  void* map;
} shmem_object;

typedef struct {
  shmem_mutex_handle handle;
  char name[SHMEM_NS_LEN];
} shmem_mutex;

typedef struct {
  char name[SHMEM_NAME_LEN];
  size_t size;
} shmem_entry;

typedef struct {
  int refcount;
  size_t size;
  size_t capacity;
  shmem_entry entries[];
} shmem_namespace;

typedef struct {
  shmem_object* handle;
  shmem_mutex* mutex;
  shmem_namespace* namespace;
  size_t entry_handles_loaded;
  shmem_object* entry_handles[];
} shmem_container;

static inline void shmem_ns_name(
  char* ns_name, const char* name
) {
  if (name[0] != '/')
    sprintf(ns_name, "/%s", name);
  else
    sprintf(ns_name, "%s", name);
}

static inline void shmem_ns_entry_name(
  char* ns_name, shmem_container* container, const char* entry_name
) {
  sprintf(ns_name, "%s.%s", container->handle->name, entry_name);
}

static inline bool shmem_name_valid(const char* name) {
  if (
    strlen(name) > SHMEM_NAME_LEN
    ||
    strstr(name, "/") != NULL
    ||
    strstr(name, "\\") != NULL
  )
    return false;

  return true;
}

shmem_object* shmem_open(const char* name, size_t size) {
  shmem_object* object = malloc(sizeof(shmem_object));
  strcpy(object->name, name);
  object->size = size;

#ifdef _WIN32
  object->handle = CreateFileMappingA(
    INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0, size, name
  );

  if (object->handle == NULL) goto shmem_open_error;

  object->map = MapViewOfFile(
    object->handle, FILE_MAP_ALL_ACCESS, 0, 0, size
  );

  if (object->map == NULL) {
    CloseHandle(object->handle);
    goto shmem_open_error;
  }
#else
  object->handle = shm_open(name, O_CREAT | O_RDWR, 0666);

  if (object->handle == -1) goto shmem_open_error;

  if (ftruncate(object->handle, size) == -1) {
    close(object->handle);
    goto shmem_open_error;
  }

  object->map = mmap(
    NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, object->handle, 0
  );

  if (object->map == MAP_FAILED) {
    close(object->handle);
    goto shmem_open_error;
  }
#endif

  return object;

shmem_open_error:
  free(object);
  return NULL;
}

void shmem_close(shmem_object* object, bool unregister) {
#ifdef _WIN32
  UnmapViewOfFile(object->map);
  CloseHandle(object->handle);
#else
  munmap(object->map, sizeof(object->size));
  close(object->handle);

  if (unregister)
    shm_unlink(object->name);
#endif

  free(object);
}

shmem_object* shmem_resize(shmem_object** object, size_t new_size) {
  char name[SHMEM_NS_LEN];
  strcpy(name, (*object)->name);

  shmem_close((*object), false);

  *object = shmem_open(name, new_size);

  return *object;
}

shmem_mutex* shmem_mutex_open(const char* name) {
  shmem_mutex* mutex = malloc(sizeof(shmem_mutex));

#ifdef _WIN32
  mutex->handle = CreateMutexA(NULL, FALSE, name);
  if (mutex->handle == NULL) goto shmem_mutex_open_error;
#else
  mutex->handle = sem_open(name, O_CREAT, 0666, 1);
  if (mutex->handle == SEM_FAILED) goto shmem_mutex_open_error;
#endif

  strcpy(mutex->name, name);

  return mutex;

shmem_mutex_open_error:
  free(mutex);
  return NULL;
}

void shmem_mutex_lock(shmem_mutex* mutex) {
#ifdef _WIN32
  WaitForSingleObject(mutex->handle, INFINITE);
#else
  sem_wait(mutex->handle);
#endif
}

void shmem_mutex_unlock(shmem_mutex* mutex) {
#ifdef _WIN32
  ReleaseMutex(mutex->handle);
#else
  sem_post(mutex->handle);
#endif
}

void shmem_mutex_close(shmem_mutex* mutex, bool unregister) {
#ifdef _WIN32
  CloseHandle(mutex->handle);
#else
  sem_close(mutex->handle);
  if (unregister) sem_unlink(mutex->name);
#endif
  free(mutex);
}

void shmem_container_entry_clear(shmem_container* container, bool unregister) {
  for (size_t i=0; i < container->entry_handles_loaded; i++) {
    if (container->entry_handles[i] != NULL) {
      shmem_close(container->entry_handles[i], unregister);
      container->entry_handles[i] = NULL;
    }
  }
  container->entry_handles_loaded = 0;
}

void shmem_container_entry_remove(
  shmem_container* container, const char* name, bool unregister
)
{
  if (container->entry_handles_loaded > 0) {
    for (size_t pos=0; pos < container->entry_handles_loaded; pos++) {
      if (strcmp(container->entry_handles[pos]->name, name) == 0) {
        shmem_close(container->entry_handles[pos], unregister);
        container->entry_handles[pos] = NULL;

        if ((pos + 1) != container->entry_handles_loaded) {
          memmove(
            container->entry_handles+pos,
            container->entry_handles+pos+1,
            sizeof(shmem_object*) * (container->entry_handles_loaded - (pos+1))
          );
        }

        container->entry_handles_loaded--;
        break;
      }
    }
  }
}

shmem_object* shmem_container_entry_get(
  shmem_container* container, size_t position, const char* name, size_t size
)
{
  shmem_object* object = NULL;
  size_t assigned_position = position;

  if (container->entry_handles_loaded > 0) {
    if (
      container->entry_handles[position]
      &&
      strcmp(container->entry_handles[position]->name, name) == 0
    ) {
      object = container->entry_handles[position];
    } else {
      for (size_t i=0; i<container->entry_handles_loaded; i++) {
        if (strcmp(container->entry_handles[i]->name, name) == 0) {
          object = container->entry_handles[i];
          assigned_position = i;
          break;
        }
      }
    }
  }

  if (!object) {
    assigned_position = container->entry_handles_loaded;
    object = shmem_open(name, size);
    container->entry_handles[assigned_position] = object;
    container->entry_handles_loaded++;
  }

  if (object->size != size)
    container->entry_handles[assigned_position] = shmem_resize(&object, size);

  return object;
}

void shmem_container_entry_gc(
  shmem_container* container
)
{
  shmem_mutex_lock(container->mutex);

  if (container->entry_handles_loaded > container->namespace->size) {
    if (container->namespace->size <= 0) {
      shmem_container_entry_clear(container, true);
    } else {
      char ns_name[SHMEM_NS_LEN];

      for (size_t i=0; i < container->entry_handles_loaded; i++) {
        if (container->entry_handles[i] == NULL)
          continue;

        bool found = false;

        for (size_t y=0; y < container->namespace->size; y++) {
          shmem_ns_entry_name(
            ns_name, container, container->namespace->entries[y].name
          );

          if (strcmp(ns_name, container->entry_handles[i]->name) == 0) {
            found = true;
            break;
          }
        }

        if (!found) {
          shmem_close(container->entry_handles[i], true);
          container->entry_handles[i] = NULL;

          if ((i + 1) != container->entry_handles_loaded) {
            memmove(
              container->entry_handles+i,
              container->entry_handles+i+1,
              sizeof(shmem_object*) * (container->entry_handles_loaded - (i+1))
            );
          }

          container->entry_handles_loaded--;

          if (container->entry_handles_loaded == 0)
            break;
        }
      }
    }
  }

  shmem_mutex_unlock(container->mutex);
}

long int shmem_container_ns_entries_find(
  shmem_container* container,
  const char* name
) {
  long int position = -1;

  shmem_mutex_lock(container->mutex);
  for (size_t i=0; i<container->namespace->size; i++) {
    if (strcmp(container->namespace->entries[i].name, name) == 0) {
      position = i;
      break;
    }
  }
  shmem_mutex_unlock(container->mutex);

  return position;
}

bool shmem_container_ns_entries_set(
  shmem_container* container,
  const char* name,
  const char* value,
  size_t value_size
) {
  bool updated = false;
  shmem_object* object = NULL;
  long int pos = shmem_container_ns_entries_find(container, name);

  shmem_container_entry_gc(container);

  shmem_mutex_lock(container->mutex);

  char ns_name[SHMEM_NS_LEN];
  shmem_ns_entry_name(ns_name, container, name);

  bool found = false;
  if (pos == -1) {
    pos = container->namespace->size;

    if (pos < container->namespace->capacity) {
      object = shmem_container_entry_get(
        container, pos, ns_name, value_size
      );
    }
  } else {
    object = shmem_container_entry_get(
      container, pos, ns_name, value_size
    );
    found = true;
  }

  if (object) {
    strcpy(container->namespace->entries[pos].name, name);
    container->namespace->entries[pos].size = value_size;
    memcpy(object->map, value, value_size);
    updated = true;

    if (!found)
      container->namespace->size++;
  }

  shmem_mutex_unlock(container->mutex);

  return updated;
}

char* shmem_container_ns_entries_get(
  shmem_container* container,
  const char* name,
  size_t* data_len
) {
  char* data = NULL;
  *data_len = 0;

  char ns_name[SHMEM_NS_LEN];
  shmem_ns_entry_name(ns_name, container, name);

  shmem_mutex_lock(container->mutex);
  for (size_t i=0; i<container->namespace->size; i++) {
    if (strcmp(container->namespace->entries[i].name, name) == 0) {
      shmem_object* object = shmem_container_entry_get(
        container, i, ns_name, container->namespace->entries[i].size
      );

      if (object && container->namespace->entries[i].size > 0) {
        data = malloc(container->namespace->entries[i].size);
        memcpy(data, object->map, container->namespace->entries[i].size);
        *data_len = container->namespace->entries[i].size;
      }

      break;
    }
  }
  shmem_mutex_unlock(container->mutex);

  return data;
}

char* shmem_container_ns_entries_get_by_position(
  shmem_container* container,
  size_t position,
  char* name,
  size_t* data_len
) {
  char* data = NULL;
  *data_len = 0;

  shmem_mutex_lock(container->mutex);
  strcpy(name, container->namespace->entries[position].name);
  size_t name_len = strlen(name);
  size_t size = container->namespace->entries[position].size;

  if (name_len <= 0 || size <= 0 || position >= container->namespace->size)
    goto shmem_container_ns_size_end;

  char ns_name[SHMEM_NS_LEN];
  shmem_ns_entry_name(ns_name, container, name);

  shmem_object* object = shmem_container_entry_get(
    container, position, ns_name, size
  );

  if (object) {
    data = malloc(size);
    memcpy(data, object->map, size);
    *data_len = size;
  }

shmem_container_ns_size_end:
  shmem_mutex_unlock(container->mutex);
  return data;
}

void shmem_container_ns_entries_remove(
  shmem_container* container,
  const char* name
) {
  long int pos = shmem_container_ns_entries_find(container, name);

  if (pos != -1) {
    shmem_mutex_lock(container->mutex);

    if ((pos + 1) != container->namespace->size) {
      memmove(
        container->namespace->entries+pos,
        container->namespace->entries+pos+1,
        sizeof(shmem_entry) * (container->namespace->size - (pos+1))
      );
    }

    container->namespace->size--;

    shmem_mutex_unlock(container->mutex);
  }

  char ns_name[SHMEM_NS_LEN];
  shmem_ns_entry_name(ns_name, container, name);

  shmem_container_entry_remove(container, ns_name, true);
}

void shmem_container_ns_entries_clear(shmem_container* container, bool unregister) {
  shmem_mutex_lock(container->mutex);
  if (unregister && container->namespace->size > 0) {
    for (size_t i=0; i<container->namespace->size; i++) {
      char ns_name[SHMEM_NS_LEN];
      shmem_ns_entry_name(ns_name, container, container->namespace->entries[i].name);

      strcpy(container->namespace->entries[i].name, "");
      container->namespace->entries[i].size = 0;
    }
    container->namespace->size = 0;
  }
  shmem_container_entry_clear(container, unregister);
  shmem_mutex_unlock(container->mutex);
}

size_t shmem_container_ns_get_size(shmem_container* container) {
  shmem_mutex_lock(container->mutex);
  size_t size = container->namespace->size;
  shmem_mutex_unlock(container->mutex);
  return size;
}

size_t shmem_container_ns_get_capacity(shmem_container* container) {
  shmem_mutex_lock(container->mutex);
  size_t capacity = container->namespace->capacity;
  shmem_mutex_unlock(container->mutex);
  return capacity;
}

shmem_container* shmem_container_open(const char* namespace, size_t capacity) {
  shmem_container* container = malloc(
    sizeof(shmem_container)
    +
    (capacity * sizeof(shmem_object*))
  );

  size_t ns_size = sizeof(shmem_namespace) + (capacity * sizeof(shmem_entry));

  char ns_name[SHMEM_NAME_LEN];
  shmem_ns_name(ns_name, namespace);

  shmem_object* object = shmem_open(ns_name, ns_size);

  if (!object)
    goto shmem_container_open_error;

  char mutex_name[SHMEM_NS_LEN];
  sprintf(mutex_name, "%s_%s", ns_name, "mutex");

  shmem_mutex* mutex = shmem_mutex_open(mutex_name);

  if (!mutex) {
    shmem_close(object, true);
    goto shmem_container_open_error;
  }

  container->handle = object;
  container->namespace = object->map;
  container->mutex = mutex;
  container->entry_handles_loaded = 0;
  memset(container->entry_handles, 0, capacity * sizeof(shmem_object*));

  shmem_namespace* ns = container->namespace;

  shmem_mutex_lock(container->mutex);
  if (!ns->refcount) {
    ns->size = 0;
    ns->capacity = capacity;
    ns->refcount = 1;
  } else {
    ns->refcount++;
  }
  shmem_mutex_unlock(container->mutex);

  return container;

shmem_container_open_error:
  free(container);
  return NULL;
}

void shmem_container_close(shmem_container* container) {
  shmem_mutex_lock(container->mutex);
  int refcount = container->namespace->refcount--;
  shmem_mutex_unlock(container->mutex);

  bool unregister = refcount <= 0;

  shmem_container_ns_entries_clear(container, unregister);
  shmem_mutex_close(container->mutex, unregister);

  shmem_close(container->handle, unregister);

  free(container);
}


typedef struct {
  shmem_container* container;
} l_shmem_container;

#define L_SHMEM_SELF(L, idx) ( \
  (l_shmem_container*) luaL_checkudata(L, idx, API_TYPE_SHARED_MEMORY) \
)->container

typedef struct {
  shmem_container* container;
  size_t position;
} l_shmem_state;


static int l_shmem_pairs_iterator(lua_State *L) {
  l_shmem_state *state = (l_shmem_state*)lua_touserdata(L, lua_upvalueindex(2));

  if (state->position < shmem_container_ns_get_size(state->container)) {
    for (
      size_t i=state->position;
      i < shmem_container_ns_get_size(state->container);
      i++
    ) {
      state->position++;

      char name[SHMEM_NAME_LEN];
      size_t data_len;
      char* data = shmem_container_ns_entries_get_by_position(
        state->container, i,
        name, &data_len
      );

      if (data) {
        lua_pushstring(L, name);
        lua_pushlstring(L, data, data_len);

        free(data);

        return 2;
      }
    }
  }

  return 0;
}


static int f_shmem_open(lua_State* L) {
  const char* namespace = luaL_checkstring(L, 1);
  size_t capacity = luaL_checkinteger(L, 2);

  if (!shmem_name_valid(namespace))
    return luaL_error(
      L,
      "namespace can not be longer than %d characters or contain any '/' or '\\'",
      SHMEM_NAME_LEN
    );

  shmem_container* container = shmem_container_open(namespace, capacity);
  if (!container) {
    lua_pushnil(L);
    lua_pushstring(L, "error initializing the shared memory container");
    return 2;
  }

  l_shmem_container* self = lua_newuserdata(L, sizeof(l_shmem_container));
  self->container = container;
  luaL_setmetatable(L, API_TYPE_SHARED_MEMORY);

  return 1;
}


static int m_shmem_set(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  const char* name = luaL_checkstring(L, 2);
  size_t value_len;
  const char* value = luaL_checklstring(L, 3, &value_len);

  if (!shmem_name_valid(name))
    return luaL_error(
      L,
      "name can not be longer than %d characters or contain any '/' or '\\'",
      SHMEM_NAME_LEN
    );

  lua_pushboolean(
    L,
    shmem_container_ns_entries_set(self, name, value, value_len)
  );

  return 1;
}


static int m_shmem_get(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);

  char* data = NULL;
  size_t data_len;

  if (lua_type(L, 2) == LUA_TSTRING) {
    const char* name = luaL_checkstring(L, 2);
    data = shmem_container_ns_entries_get(self, name, &data_len);
  } else if (lua_type(L, 2) == LUA_TNUMBER) {
    char name[SHMEM_NAME_LEN];
    size_t position = luaL_checkinteger(L, 2);
    position = position - 1 < 0 ? 0 : position - 1;
    data = shmem_container_ns_entries_get_by_position(self, position, name, &data_len);
  } else {
    return luaL_typeerror(L, 2, "string or integer");
  }

  if (data) {
    lua_pushlstring(L, data, data_len);
    free(data);
  }
  else
    lua_pushnil(L);

  return 1;
}


static int m_shmem_remove(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  const char* name = luaL_checkstring(L, 2);
  shmem_container_ns_entries_remove(self, name);
  return 0;
}


static int m_shmem_clear(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  shmem_container_ns_entries_clear(self, true);
  return 0;
}


static int m_shmem_size(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  lua_pushinteger(L, shmem_container_ns_get_size(self));
  return 1;
}


static int m_shmem_capacity(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  lua_pushinteger(L, shmem_container_ns_get_capacity(self));
  return 1;
}


static int mm_shmem_pairs(lua_State *L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);

  l_shmem_state *state;
  state = (l_shmem_state*)lua_newuserdata(L, sizeof(l_shmem_state));

  state->position = 0;
  state->container = self;

  lua_pushcclosure(L, l_shmem_pairs_iterator, 2);
  return 1;
}


static int mm_shmem_gc(lua_State* L) {
  shmem_container* self = L_SHMEM_SELF(L, 1);
  shmem_container_close(self);
  return 0;
}


static const luaL_Reg shmem_lib[] = {
  { "open",     f_shmem_open     },
  {NULL, NULL}
};

static const luaL_Reg shmem_class[] = {
  { "set",      m_shmem_set      },
  { "get",      m_shmem_get      },
  { "remove",   m_shmem_remove   },
  { "clear",    m_shmem_clear    },
  { "size",     m_shmem_size     },
  { "capacity", m_shmem_capacity },
  { "__pairs",  mm_shmem_pairs   },
  { "__gc",     mm_shmem_gc      },
  {NULL, NULL}
};


int luaopen_shmem(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_SHARED_MEMORY);
  luaL_setfuncs(L, shmem_class, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newlib(L, shmem_lib);
  return 1;
}
