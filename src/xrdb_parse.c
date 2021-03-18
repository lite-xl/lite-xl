#ifdef __unix__

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include "xrdb_parse.h"

extern char **environ;

static int join_path(char buf[], int buf_size, const char *path, const char *name) {
  const char *path_delim = strchr(path, ':');
  if (!path_delim) {
    path_delim = path + strlen(path);
  }
  const int path_len = path_delim - path, name_len = strlen(name);
  if (buf_size < path_len + 1 + name_len + 1) return -1;
  memcpy(buf, path, path_len);
  buf[path_len] = '/';
  memcpy(buf + path_len + 1, name, name_len + 1);
  return 0;
}


static int xrdb_popen (int *pid_ptr) {
  int fd[2];

  if (pipe(fd) != 0) return -1;
  int read_fd = fd[0];
  int write_fd = fd[1];

  int pid = fork();
  if (pid == 0) {
    close(read_fd);
    dup2(write_fd, STDOUT_FILENO);
    close(write_fd);
    char *path = getenv("PATH");
    char xrdb_filename[256];
    while (path) {
      char *xrgb_argv[3] = {"xrdb", "-query", NULL};
      if (join_path(xrdb_filename, 256, path, "xrdb") == 0) {
        execve(xrdb_filename, xrgb_argv, environ);
      }
      path = strchr(path, ':');
      if (path) {
        path++;
      }
    }
  } else {
    *pid_ptr = pid;
    close(write_fd);
    return read_fd;
  }
  return -1;
}


static int xrdb_try_dpi_match(const char *line, int len) {
  if (len >= 8 && strncmp(line, "Xft.dpi:", 8) == 0) {
    for (line += 8; *line && (*line == '\t' || *line == ' '); line++) { }
    int dpi = 0;
    for ( ; *line >= '0' && *line <= '9'; line++) {
      dpi = dpi * 10 + ((int) (*line) - (int) '0');
    }
    return dpi;
  }
  return -1;
}

#define XRDB_READ_BUF_SIZE 256
static void xrdb_complete_reading(int read_fd) {
  char buf[XRDB_READ_BUF_SIZE];
  while (1) {
    int nr = read(read_fd, buf, XRDB_READ_BUF_SIZE);
    if (nr <= 0) return;
  }
}

static int xrdb_parse_for_dpi(int read_fd) {
  char buf[XRDB_READ_BUF_SIZE];
  char buf_remaining = 0;
  while (1) {
    int nr = read(read_fd, buf + buf_remaining, XRDB_READ_BUF_SIZE - buf_remaining);
    if (nr > 0) {
      const char * const buf_limit = buf + nr + buf_remaining;
      char *line_start = buf;
      while (line_start < buf_limit) {
        char *nlptr = line_start;
        while (nlptr < buf_limit && *nlptr != '\n') {
          nlptr++;
        }
        if (nlptr < buf_limit) {
          int dpi_read = xrdb_try_dpi_match(line_start, nlptr - line_start);
          if (dpi_read > 0) {
            xrdb_complete_reading(read_fd);
            return dpi_read;
          }
          /* doesn't match: position after newline to search again */
          line_start = nlptr + 1;
        } else {
          /* No newline found: copy the remaining part at the beginning of buf
             and read again from file descriptor. */
          buf_remaining = buf_limit - line_start;
          if (buf_remaining >= XRDB_READ_BUF_SIZE) {
            /* Line is too long for the buffer: skip. */
            buf_remaining = 0;
          } else {
            memmove(buf, line_start, buf_remaining);
          }
          break;
        }
      }
    } else {
      if (nr == 0 && buf_remaining > 0) {
        int dpi_read = xrdb_try_dpi_match(buf, buf_remaining);
        if (dpi_read > 0) {
          return dpi_read;
        }
      }
      break;
    }
  }
  return -1;
}

int xrdb_find_dpi() {
  int xrdb_pid;
  int read_fd = xrdb_popen(&xrdb_pid);
  if (read_fd >= 0) {
    int dpi_read = xrdb_parse_for_dpi(read_fd);
    int child_status;
    waitpid(xrdb_pid, &child_status, 0);
    close(read_fd);
    return dpi_read;
  }
  return -1;
}

#endif
