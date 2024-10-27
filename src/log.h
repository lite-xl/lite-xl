#ifndef LOG_H
#define LOG_H

void lxl_log_init();

// call lua_setwarnf with this function and the lua_State as userdata
void lxl_log_setwarnf(void *ud, const char *msg, int tocont);

void lxl_log_verbose(const char *fmt, ...);
void lxl_log_info(const char *fmt, ...);
void lxl_log_warn(const char *fmt, ...);
void lxl_log_error(const char *fmt, ...);
void lxl_log_critical(const char *fmt, ...);

#endif