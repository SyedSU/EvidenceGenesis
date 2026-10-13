/* First-party file persistence; no network, subprocesses or model input. */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "save_platform.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

/* Paths come from Godot globalize_path. Moves must stay in one directory:
 * no cross-volume copy fallback, and only one directory needs syncing. */
static const char *last_separator(const char *path) {
    const char *last = strrchr(path, '/');
#ifdef _WIN32
    const char *back = strrchr(path, '\\');
    if (back && (!last || back > last)) last = back;
#endif
    return last;
}
static int same_parent(const char *a, const char *b) {
    if (!a || !b || !a[0] || !b[0] || !strcmp(a,b)) return 0;
    const char *x=last_separator(a), *y=last_separator(b);
    return x && y && x[1] && y[1] && x-a==y-b && !memcmp(a,b,(size_t)(x-a));
}

#ifdef _WIN32
static wchar_t *wide_path(const char *path) {
    if (!path || !path[0]) return NULL;
    int count=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,NULL,0);
    if (!count) return NULL;
    wchar_t *wide=calloc((size_t)count,sizeof(wchar_t));
    if (wide && !MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,path,-1,wide,count)) {free(wide);return NULL;}
    return wide;
}
static int regular_path(const wchar_t *path, int allow_missing) {
    DWORD flags=GetFileAttributesW(path);
    if (flags==INVALID_FILE_ATTRIBUTES) return allow_missing && GetLastError()==ERROR_FILE_NOT_FOUND;
    return !(flags & (FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));
}
int genesis_sync_file(const char *path) {
    wchar_t *wide=wide_path(path);
    if (!wide) return 1;
    if (!regular_path(wide,0)) {free(wide);return 1;}
    HANDLE file=CreateFileW(wide,GENERIC_WRITE,FILE_SHARE_READ,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,NULL);
    free(wide);
    if (file==INVALID_HANDLE_VALUE) return 1;
    int ok=FlushFileBuffers(file)!=0;
    if (!CloseHandle(file)) ok=0;
    return ok?0:1;
}
int genesis_replace_file(const char *source, const char *destination) {
    if (!same_parent(source,destination) || genesis_sync_file(source)) return 1;
    wchar_t *src=wide_path(source), *dst=wide_path(destination);
    if (!src || !dst) {free(src);free(dst);return 1;}
    int result=1;
    if (regular_path(src,0) && regular_path(dst,1)) {
        /* Same-directory rename/replace. Never delete destination first, and
         * never request COPY_ALLOWED. WRITE_THROUGH requests completed move. */
        if (MoveFileExW(src,dst,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))
            result=genesis_sync_file(destination)?2:0;
    }
    free(src);free(dst);return result;
}
#else
static int sync_descriptor(int fd) {
    int result;
    do {result=fsync(fd);} while (result<0 && errno==EINTR);
    return result;
}
int genesis_sync_file(const char *path) {
    if (!path || path[0]!='/') return 1;
    int fd=open(path,O_WRONLY|O_CLOEXEC|O_NOFOLLOW|O_NONBLOCK);
    if (fd<0) return 1;
    struct stat status;
    int ok=fstat(fd,&status)==0 && S_ISREG(status.st_mode) && sync_descriptor(fd)==0;
    if (close(fd)<0) ok=0;
    return ok?0:1;
}
int genesis_replace_file(const char *source, const char *destination) {
    if (!same_parent(source,destination) || genesis_sync_file(source)) return 1;
    struct stat target;
    if (lstat(destination,&target)==0) {
        if (!S_ISREG(target.st_mode)) return 1;
    } else if (errno!=ENOENT) return 1;
    const char *separator=last_separator(source);
    size_t size=(size_t)(separator-source);
    char *parent=malloc(size+2);
    if (!parent) return 1;
    memcpy(parent,source,size);parent[size]=0;
    if (!size) {parent[0]='/';parent[1]=0;}
    int directory=open(parent,O_RDONLY|O_DIRECTORY|O_CLOEXEC);
    free(parent);
    if (directory<0) return 1;
    int result=1;
    if (rename(source,destination)==0) result=sync_descriptor(directory)==0?0:2;
    if (close(directory)<0 && result==0) result=2;
    return result;
}
#endif
