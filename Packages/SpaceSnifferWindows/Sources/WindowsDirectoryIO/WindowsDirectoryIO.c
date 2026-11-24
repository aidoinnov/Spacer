#define _WIN32_WINNT 0x0602
#include "WindowsDirectoryIO.h"
#include <windows.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <wchar.h>
struct sniffer_directory {
    HANDLE handle, find;
    wchar_t *path;
    uint64_t volume;
    unsigned char *buffer;
    size_t offset;
    int refill, started, fallback;
    WIN32_FIND_DATAW data;
};
static int dot(const wchar_t *s, size_t n) { return n==1&&s[0]==L'.' || n==2&&s[0]==L'.'&&s[1]==L'.'; }
sniffer_directory *sniffer_open(const uint16_t *path, uint32_t *error) {
    *error=0;
    HANDLE h=CreateFileW((const wchar_t*)path,FILE_LIST_DIRECTORY|FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS,NULL);
    if(h==INVALID_HANDLE_VALUE){*error=GetLastError();return NULL;}
    sniffer_directory *d=calloc(1,sizeof(*d));
    if(!d){CloseHandle(h);*error=ERROR_NOT_ENOUGH_MEMORY;return NULL;}
    d->handle=h;d->find=INVALID_HANDLE_VALUE;d->refill=1;
    d->path=_wcsdup((const wchar_t*)path);d->buffer=malloc(65536);
    if(!d->path||!d->buffer){*error=ERROR_NOT_ENOUGH_MEMORY;sniffer_close(d);return NULL;}
    FILE_ID_INFO id;
    if(GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id)))d->volume=id.VolumeSerialNumber;
    return d;
}
static wchar_t *child(sniffer_directory *d,const wchar_t *name){
    size_t a=wcslen(d->path),b=wcslen(name);wchar_t *p=malloc((a+b+2)*sizeof(wchar_t));
    if(!p)return NULL;
    memcpy(p,d->path,a*sizeof(wchar_t));
    if(a&&p[a-1]!=L'\\'&&p[a-1]!=L'/')p[a++]=L'\\';
    memcpy(p+a,name,(b+1)*sizeof(wchar_t));return p;
}
static int fallback_next(sniffer_directory *d,sniffer_entry *out,uint32_t *error){
    for(;;){
        if(d->find==INVALID_HANDLE_VALUE){
            wchar_t *glob=child(d,L"*");if(!glob){*error=ERROR_NOT_ENOUGH_MEMORY;return -1;}
            d->find=FindFirstFileExW(glob,FindExInfoBasic,&d->data,FindExSearchNameMatch,NULL,FIND_FIRST_EX_LARGE_FETCH);free(glob);
            if(d->find==INVALID_HANDLE_VALUE){*error=GetLastError();if(*error==ERROR_FILE_NOT_FOUND||*error==ERROR_NO_MORE_FILES){*error=0;return 0;}return -1;}
        }else if(!FindNextFileW(d->find,&d->data)){*error=GetLastError();if(*error==ERROR_NO_MORE_FILES){*error=0;return 0;}return -1;}
        size_t n=wcslen(d->data.cFileName);if(dot(d->data.cFileName,n))continue;
        memset(out,0,sizeof(*out));out->name=(const uint16_t*)d->data.cFileName;out->name_units=(uint32_t)n;
        out->created_ticks=((uint64_t)d->data.ftCreationTime.dwHighDateTime<<32)|d->data.ftCreationTime.dwLowDateTime;
        out->accessed_ticks=((uint64_t)d->data.ftLastAccessTime.dwHighDateTime<<32)|d->data.ftLastAccessTime.dwLowDateTime;
        out->modified_ticks=((uint64_t)d->data.ftLastWriteTime.dwHighDateTime<<32)|d->data.ftLastWriteTime.dwLowDateTime;
        out->attributes=d->data.dwFileAttributes;out->reparse_tag=d->data.dwReserved0;out->volume=d->volume;
        if(!(out->attributes&FILE_ATTRIBUTE_DIRECTORY)){
            out->logical_bytes=((uint64_t)d->data.nFileSizeHigh<<32)|d->data.nFileSizeLow;
            wchar_t *p=child(d,d->data.cFileName);if(!p){*error=ERROR_NOT_ENOUGH_MEMORY;return -1;}
            HANDLE h=CreateFileW(p,FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,NULL,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,NULL);
            if(h==INVALID_HANDLE_VALUE){*error=GetLastError();free(p);return -1;}
            FILE_STANDARD_INFO st;FILE_ID_INFO id;
            if(!GetFileInformationByHandleEx(h,FileStandardInfo,&st,sizeof(st))){*error=GetLastError();CloseHandle(h);free(p);return -1;}
            out->allocated_bytes=(uint64_t)st.AllocationSize.QuadPart;
            if(GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id))){out->volume=id.VolumeSerialNumber;memcpy(&out->id_low,id.FileId.Identifier,8);memcpy(&out->id_high,id.FileId.Identifier+8,8);}
            CloseHandle(h);free(p);
        }
        return 1;
    }
}
int sniffer_next(sniffer_directory *d,sniffer_entry *out,uint32_t *error){
    *error=0;
    if(d->fallback)return fallback_next(d,out,error);
    for(;;){
        if(d->refill){
            if(!GetFileInformationByHandleEx(d->handle,FileIdExtdDirectoryInfo,d->buffer,65536)){
                DWORD e=GetLastError();if(e==ERROR_NO_MORE_FILES)return 0;
                if(!d->started&&(e==ERROR_INVALID_PARAMETER||e==ERROR_NOT_SUPPORTED||e==ERROR_INVALID_FUNCTION)){
                    d->fallback=1;return fallback_next(d,out,error);
                }
                *error=e;return -1;
            }
            d->started=1;d->offset=0;d->refill=0;
        }
        size_t header=offsetof(FILE_ID_EXTD_DIR_INFO,FileName);
        if(d->offset>65536-header){*error=ERROR_INVALID_DATA;return -1;}
        FILE_ID_EXTD_DIR_INFO *r=(FILE_ID_EXTD_DIR_INFO*)(d->buffer+d->offset);
        if(r->FileNameLength%2||r->FileNameLength>65536-d->offset-header){*error=ERROR_INVALID_DATA;return -1;}
        if(r->NextEntryOffset){if(r->NextEntryOffset<header+r->FileNameLength||r->NextEntryOffset>65536-d->offset){*error=ERROR_INVALID_DATA;return -1;}d->offset+=r->NextEntryOffset;}
        else d->refill=1;
        size_t n=r->FileNameLength/2;if(dot(r->FileName,n))continue;
        memset(out,0,sizeof(*out));out->name=(const uint16_t*)r->FileName;out->name_units=(uint32_t)n;
        out->created_ticks=(uint64_t)r->CreationTime.QuadPart;
        out->accessed_ticks=(uint64_t)r->LastAccessTime.QuadPart;
        out->modified_ticks=(uint64_t)r->LastWriteTime.QuadPart;
        out->attributes=r->FileAttributes;out->reparse_tag=r->ReparsePointTag;out->volume=d->volume;
        if(!(r->FileAttributes&FILE_ATTRIBUTE_DIRECTORY)){out->logical_bytes=(uint64_t)r->EndOfFile.QuadPart;out->allocated_bytes=(uint64_t)r->AllocationSize.QuadPart;}
        memcpy(&out->id_low,r->FileId.Identifier,8);memcpy(&out->id_high,r->FileId.Identifier+8,8);
        return 1;
    }
}
void sniffer_close(sniffer_directory *d){if(!d)return;if(d->handle!=INVALID_HANDLE_VALUE)CloseHandle(d->handle);if(d->find!=INVALID_HANDLE_VALUE)FindClose(d->find);free(d->path);free(d->buffer);free(d);}

static uint64_t file_ticks(FILETIME t) { return ((uint64_t)t.dwHighDateTime<<32)|t.dwLowDateTime; }
static int same_root(const wchar_t *a,const wchar_t *b) {
    if(wcsncmp(a,L"\\\\?\\",4)==0)a+=4;
    if(wcsncmp(b,L"\\\\?\\",4)==0)b+=4;
    size_t na=wcslen(a),nb=wcslen(b);
    while(na&&a[na-1]==L'\\')--na;
    while(nb&&b[nb-1]==L'\\')--nb;
    return na==nb&&_wcsnicmp(a,b,na)==0;
}
int sniffer_query_root(const uint16_t *path,sniffer_root_metadata *out) {
    memset(out,0,sizeof(*out));
    const wchar_t *p=(const wchar_t*)path;
    WIN32_FILE_ATTRIBUTE_DATA data;
    if(GetFileAttributesExW(p,GetFileExInfoStandard,&data)) {
        out->created_ticks=file_ticks(data.ftCreationTime);out->accessed_ticks=file_ticks(data.ftLastAccessTime);
        out->modified_ticks=file_ticks(data.ftLastWriteTime);out->attributes=data.dwFileAttributes;
    }
    wchar_t *volume=calloc(32768,sizeof(wchar_t));
    if(!volume)return 0;
    int result=0;
    if(GetVolumePathNameW(p,volume,32768)) {
        ULARGE_INTEGER total,free_bytes;
        if(GetDiskFreeSpaceExW(volume,NULL,&total,&free_bytes)) {
            out->total_bytes=total.QuadPart;out->free_bytes=free_bytes.QuadPart;result=1;
        }
        out->is_volume_root=same_root(p,volume);
    }
    free(volume);return result;
}

int sniffer_volume_identity(const uint16_t *path,int exact_mount,uint16_t *out,uint32_t count) {
    if(!path||!out||count<50)return 0;
    const wchar_t *p=(const wchar_t*)path;
    wchar_t *mount=calloc(32768,sizeof(wchar_t));if(!mount)return 0;
    if(exact_mount) {
        size_t n=wcslen(p);if(n>32765){free(mount);return 0;}
        memcpy(mount,p,(n+1)*sizeof(wchar_t));if(n&&mount[n-1]!=L'\\'){mount[n++]=L'\\';mount[n]=0;}
    } else if(!GetVolumePathNameW(p,mount,32768)){free(mount);return 0;}
    int result=GetVolumeNameForVolumeMountPointW(mount,(wchar_t*)out,count)!=0;
    free(mount);return result;
}
