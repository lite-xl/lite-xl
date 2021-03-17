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

  pipe(fd);
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
  if (len >= 8 && strncmp(line, "Xft.dpi:", 8) == 0 && len - 8 + 1 <= 64) {
    char buf[64];
    memcpy(buf, line + 8, len - 8);
    buf[len - 8] = 0;
    return strtol(buf, NULL, 10);
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
  char read_buf_offset = 0;
  while (1) {
    int nr = read(read_fd, buf + read_buf_offset, XRDB_READ_BUF_SIZE - read_buf_offset);
    if (nr > 0) {
      const char * const buf_limit = buf + nr + read_buf_offset;
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
          const int rem = nr + read_buf_offset - (line_start - buf);
          if (rem >= XRDB_READ_BUF_SIZE) {
            /* Line is too long for the buffer: skip. */
            read_buf_offset = 0;
          } else {
            int c = 0;
            while (c < rem) {
              buf[c] = line_start[c];
              c++;
            }
            read_buf_offset = rem;
          }
          break;
        }
      }
    } else {
      if (nr == 0 && read_buf_offset > 0) {
        int dpi_read = xrdb_try_dpi_match(buf, read_buf_offset);
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
