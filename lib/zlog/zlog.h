/*
 * Zlog utility
 * By: Eric Ma https://www.ericzma.com
 * Released under Unlicense
 */

#ifndef ZLOG_H_
# define ZLOG_H_

#include<stdio.h>

#define ZLOG_LOC __FILE__, __LINE__

#define ZLOG_DEBUG_LOG_MSG 1
#define ZLOG_INFO_LOG_MSG 0

#ifdef DEBUG
    #define ZLOG_LOG_LEVEL 1
#else
    #define ZLOG_LOG_LEVEL 0
#endif

extern FILE* zlog_fout;
extern const char* zlog_file_log_name;

// Start API

// initialize zlog: flush to a log file
void zlog_init(char const* log_file);
// initialize zlog: flush to a STDOUT
void zlog_init_stdout(void);
// initialize zlog: flush to a STDERR
void zlog_init_stderr(void);
// creating a flushing thread
void zlog_init_flush_thread(void);
// finish using the zlog; clean up
void zlog_finish(void);
// Explicitly flush the buffer in memory
void zlog_flush_buffer(void);

// log an entry; using the printf format
void zlogf(int msg_level, char const * fmt, ...);

// log an entry with a timestamp
void zlogf_time(int msg_level, char const * fmt, ...);

// log an entry with the filename and location;
//   the first 2 arguments can be replaced by ZLOG_LOC which 
//   will be filled by the compiler
void zlog(int msg_level, char* filename, int line, char const * fmt, ...);

// log an entry with the filename and location with a timestamp
void zlog_time(int msg_level, char* filename, int line, char const * fmt, ...);

// return where logs are being written (file absolute path)
const char* zlog_get_log_file_name(void);

// End API

#endif
