#ifndef __DMON_EXTRA_H__
#define __DMON_EXTRA_H__

//
// Copyright 2021 Sepehr Taghdisian (septag@github). All rights reserved.
// License: https://github.com/septag/dmon#license-bsd-2-clause
//
//  Extra header functionality for dmon.h for the backend based on inotify
//  
//  Add/Remove directory functions:
//  dmon_watch_add: Adds a sub-directory to already valid watch_id. sub-directories are assumed to be relative to watch root_dir
//  dmon_watch_add: Removes a sub-directory from already valid watch_id. sub-directories are assumed to be relative to watch root_dir
//  Reason: The inotify backend does not work well when watching in recursive mode a root directory of a large tree, it may take
//          quite a while until all inotify watches are established, and events will not be received in this time.  Also, since one
//          inotify watch will be established per subdirectory, it is possible that the maximum amount of inotify watches per user
//          will be reached. The default maximum is 8192.
//          When using inotify backend users may turn off the DMON_WATCHFLAGS_RECURSIVE flag and add/remove selectively the
//          sub-directories to be watched based on application-specific logic about which sub-directory actually needs to be watched.
//          The function dmon_watch_add and dmon_watch_rm are used to this purpose.
//

#ifndef __DMON_H__
#error "Include 'dmon.h' before including this file"
#endif

#ifdef __cplusplus
extern "C" {
#endif

DMON_API_DECL bool dmon_watch_add(dmon_watch_id id, const char* subdir);
DMON_API_DECL bool dmon_watch_rm(dmon_watch_id id, const char* watchdir);

#ifdef __cplusplus
}
#endif

#ifdef DMON_IMPL
#if DMON_OS_LINUX
DMON_API_IMPL bool dmon_watch_add(dmon_watch_id id, const char* watchdir)
{
    DMON_ASSERT(id.id > 0 && id.id <= DMON_MAX_WATCHES);

    bool skip_lock = pthread_self() == _dmon.thread_handle;

    if (!skip_lock)
        pthread_mutex_lock(&_dmon.mutex);

    dmon__watch_state* watch = &_dmon.watches[id.id - 1];

    // check if the directory exists
    // if watchdir contains absolute/root-included path, try to strip the rootdir from it
    // else, we assume that watchdir is correct, so save it as it is
    struct stat st;
    dmon__watch_subdir subdir;
    if (stat(watchdir, &st) == 0 && (st.st_mode & S_IFDIR)) {
        dmon__strcpy(subdir.rootdir, sizeof(subdir.rootdir), watchdir);
        if (strstr(subdir.rootdir, watch->rootdir) == subdir.rootdir) {
            dmon__strcpy(subdir.rootdir, sizeof(subdir.rootdir), watchdir + strlen(watch->rootdir));
        }
    } else {
        char fullpath[DMON_MAX_PATH];
        dmon__strcpy(fullpath, sizeof(fullpath), watch->rootdir);
        dmon__strcat(fullpath, sizeof(fullpath), watchdir);
        if (stat(fullpath, &st) != 0 || (st.st_mode & S_IFDIR) == 0) {
            _DMON_LOG_ERRORF("Watch directory '%s' is not valid", watchdir);
            if (!skip_lock)
                pthread_mutex_unlock(&_dmon.mutex);
            return false;
        }
        dmon__strcpy(subdir.rootdir, sizeof(subdir.rootdir), watchdir);
    }

    int dirlen = (int)strlen(subdir.rootdir);
    if (subdir.rootdir[dirlen - 1] != '/') {
        subdir.rootdir[dirlen] = '/';
        subdir.rootdir[dirlen + 1] = '\0';
    }

    // check that the directory is not already added
    for (int i = 0, c = stb_sb_count(watch->subdirs); i < c; i++) {
        if (strcmp(subdir.rootdir, watch->subdirs[i].rootdir) == 0) {
            _DMON_LOG_ERRORF("Error watching directory '%s', because it is already added.", watchdir);
            if (!skip_lock) 
                pthread_mutex_unlock(&_dmon.mutex);
            return false;
        }
    }

    const uint32_t inotify_mask = IN_MOVED_TO | IN_CREATE | IN_MOVED_FROM | IN_DELETE | IN_MODIFY;
    char fullpath[DMON_MAX_PATH];
    dmon__strcpy(fullpath, sizeof(fullpath), watch->rootdir);
    dmon__strcat(fullpath, sizeof(fullpath), subdir.rootdir);
    int wd = inotify_add_watch(watch->fd, fullpath, inotify_mask);
    if (wd == -1) {
        _DMON_LOG_ERRORF("Error watching directory '%s'. (inotify_add_watch:err=%d)", watchdir, errno);
        if (!skip_lock)
            pthread_mutex_unlock(&_dmon.mutex);
        return false;
    }

    stb_sb_push(watch->subdirs, subdir);
    stb_sb_push(watch->wds, wd);

    if (!skip_lock)
        pthread_mutex_unlock(&_dmon.mutex);

    return true;
}

DMON_API_IMPL bool dmon_watch_rm(dmon_watch_id id, const char* watchdir)
{
    DMON_ASSERT(id.id > 0 && id.id <= DMON_MAX_WATCHES);

    bool skip_lock = pthread_self() == _dmon.thread_handle;

    if (!skip_lock)
        pthread_mutex_lock(&_dmon.mutex);

    dmon__watch_state* watch = &_dmon.watches[id.id - 1];

    char subdir[DMON_MAX_PATH];
    dmon__strcpy(subdir, sizeof(subdir), watchdir);
    if (strstr(subdir, watch->rootdir) == subdir) {
        dmon__strcpy(subdir, sizeof(subdir), watchdir + strlen(watch->rootdir));
    }

    int dirlen = (int)strlen(subdir);
    if (subdir[dirlen - 1] != '/') {
        subdir[dirlen] = '/';
        subdir[dirlen + 1] = '\0';
    }

    int i, c = stb_sb_count(watch->subdirs);
    for (i = 0; i < c; i++) {
        if (strcmp(watch->subdirs[i].rootdir, subdir) == 0) {
            break;
        }
    }
    if (i >= c) {
        _DMON_LOG_ERRORF("Watch directory '%s' is not valid", watchdir);
        if (!skip_lock)
            pthread_mutex_unlock(&_dmon.mutex);
        return false;
    }
    inotify_rm_watch(watch->fd, watch->wds[i]);

    /* Remove entry from subdirs and wds by swapping position with the last entry */
    watch->subdirs[i] = stb_sb_last(watch->subdirs);
    stb_sb_pop(watch->subdirs);

    watch->wds[i] = stb_sb_last(watch->wds);
    stb_sb_pop(watch->wds);

    if (!skip_lock)
        pthread_mutex_unlock(&_dmon.mutex);
    return true;
}
#endif  // DMON_OS_LINUX
#endif // DMON_IMPL

#endif // __DMON_EXTRA_H__

