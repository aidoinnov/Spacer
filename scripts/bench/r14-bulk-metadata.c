/* Research-only flat-directory prototype. Not linked into the app. */
#include <sys/attr.h>
#include <sys/stat.h>
#include <sys/vnode.h>
#include <sys/resource.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>

typedef struct {
    char *name;
    uint32_t type, device, permissions, flags;
    uint64_t inode;
    int64_t logical, allocated;
    struct timespec created, modified, accessed;
} Row;
typedef struct {
    Row *rows; size_t count, capacity;
    uint64_t readdir_calls, lstat_calls, bulk_calls, missing_fields, boundary_fallbacks, entry_errors;
} Result;
static const uint32_t common_required = ATTR_CMN_NAME | ATTR_CMN_DEVID | ATTR_CMN_OBJTYPE |
    ATTR_CMN_CRTIME | ATTR_CMN_MODTIME | ATTR_CMN_ACCTIME | ATTR_CMN_ACCESSMASK | ATTR_CMN_FLAGS | ATTR_CMN_FILEID;
static const uint32_t file_required = ATTR_FILE_ALLOCSIZE | ATTR_FILE_DATALENGTH;
static void fail(const char *message) { perror(message); exit(2); }
static void append(Result *result, Row row) {
    if (result->count == result->capacity) {
        result->capacity = result->capacity ? result->capacity * 2 : 128;
        result->rows = realloc(result->rows, result->capacity * sizeof(Row));
        if (!result->rows) fail("realloc");
    }
    result->rows[result->count++] = row;
}
static void release(Result *result) {
    for (size_t i=0;i<result->count;i++) free(result->rows[i].name);
    free(result->rows); memset(result,0,sizeof(*result));
}
static uint32_t kind(mode_t mode) {
    switch(mode & S_IFMT) { case S_IFREG: return VREG; case S_IFDIR: return VDIR; case S_IFLNK: return VLNK; case S_IFIFO: return VFIFO; case S_IFSOCK: return VSOCK; default:return VNON; }
}
static Row stat_row(int fd, const char *name, Result *counters) {
    struct stat st; counters->lstat_calls++;
    if (fstatat(fd,name,&st,AT_SYMLINK_NOFOLLOW) != 0) fail("fstatat");
    Row row={0}; row.name=strdup(name); row.type=kind(st.st_mode); row.device=st.st_dev; row.inode=st.st_ino;
    row.permissions=st.st_mode & 07777; row.flags=st.st_flags;
    row.created=st.st_birthtimespec; row.modified=st.st_mtimespec; row.accessed=st.st_atimespec;
    if(row.type==VREG) { row.logical=st.st_size; row.allocated=(int64_t)st.st_blocks*512; }
    return row;
}
static int compare_name(const void *a,const void *b) { return strcmp(((const Row*)a)->name,((const Row*)b)->name); }
static Result baseline(const char *path) {
    Result result={0}; DIR *directory=opendir(path); if(!directory) fail("opendir");
    struct dirent *entry;
    while(result.readdir_calls++, (entry=readdir(directory))) {
        if(strcmp(entry->d_name,".")==0 || strcmp(entry->d_name,"..")==0)continue;
        append(&result,stat_row(dirfd(directory),entry->d_name,&result));
    }
    closedir(directory); qsort(result.rows,result.count,sizeof(Row),compare_name); return result;
}
static void take(const char **cursor,const char *end,void *value,size_t size) {
    if((size_t)(end-*cursor)<size) { fprintf(stderr,"truncated bulk record\n"); exit(2); }
    memcpy(value,*cursor,size); *cursor+=size;
}
static Result bulk(const char *path) {
    Result result={0}; int fd=open(path,O_RDONLY|O_DIRECTORY); if(fd<0)fail("open");
    struct attrlist list={0}; list.bitmapcount=ATTR_BIT_MAP_COUNT;
    list.commonattr=ATTR_CMN_RETURNED_ATTRS|ATTR_CMN_ERROR|common_required;
    list.dirattr=ATTR_DIR_MOUNTSTATUS; list.fileattr=file_required;
    char *buffer=malloc(64*1024); if(!buffer)fail("malloc");
    for(;;) {
        result.bulk_calls++; int count=getattrlistbulk(fd,&list,buffer,64*1024,FSOPT_PACK_INVAL_ATTRS);
        if(count<0)fail("getattrlistbulk"); if(count==0)break;
        const char *entry=buffer;
        for(int n=0;n<count;n++) {
            const char *p=entry;uint32_t length,error=0,mount=0;attribute_set_t returned;attrreference_t ref;
            take(&p,buffer+64*1024,&length,sizeof(length)); const char *end=entry+length;
            if(length<4 || end>buffer+64*1024) {fprintf(stderr,"invalid bulk length\n");exit(2);}
            take(&p,end,&returned,sizeof(returned));take(&p,end,&error,sizeof(error));
            const char *name_field=p;take(&p,end,&ref,sizeof(ref));
            const char *name=name_field+ref.attr_dataoffset;
            if(ref.attr_length<1 || name<entry || name+ref.attr_length>end || name[ref.attr_length-1]!=0) {fprintf(stderr,"invalid bulk name\n");exit(2);}
            Row row={0};row.name=strdup(name);
            take(&p,end,&row.device,sizeof(row.device));take(&p,end,&row.type,sizeof(row.type));
            take(&p,end,&row.created,sizeof(row.created));take(&p,end,&row.modified,sizeof(row.modified));take(&p,end,&row.accessed,sizeof(row.accessed));
            take(&p,end,&row.permissions,sizeof(row.permissions));row.permissions &= 07777;
            take(&p,end,&row.flags,sizeof(row.flags));take(&p,end,&row.inode,sizeof(row.inode));
            // Object-specific groups are selected by OBJTYPE; PACK_INVAL_ATTRS
            // does not make a file's buffer contain the directory group.
            if(row.type==VDIR)take(&p,end,&mount,sizeof(mount));
            if(row.type==VREG) {take(&p,end,&row.allocated,sizeof(row.allocated));take(&p,end,&row.logical,sizeof(row.logical));}
            int missing=(returned.commonattr&common_required)!=common_required ||
                (row.type==VREG && (returned.fileattr&file_required)!=file_required) ||
                (row.type==VDIR && !(returned.dirattr&ATTR_DIR_MOUNTSTATUS));
            int boundary=(row.type==VDIR && (mount & DIR_MNTSTATUS_MNTPOINT)) || (row.flags & SF_FIRMLINK);
            if(missing || boundary || error) {
                result.missing_fields+=missing;result.boundary_fallbacks+=!!boundary;result.entry_errors+=!!error;
                free(row.name);row=stat_row(fd,name,&result);
            }
            append(&result,row);entry=end;
        }
    }
    free(buffer);close(fd);qsort(result.rows,result.count,sizeof(Row),compare_name);return result;
}
static uint64_t mix(uint64_t hash,const void *data,size_t count) {
    const unsigned char *bytes=data;for(size_t i=0;i<count;i++)hash=(hash^bytes[i])*1099511628211ULL;return hash;
}
static uint64_t checksum(Result *r) {
    uint64_t h=1469598103934665603ULL;
    for(size_t i=0;i<r->count;i++) {
        Row *v=&r->rows[i];h=mix(h,v->name,strlen(v->name));
        h=mix(h,&v->type,sizeof(v->type));h=mix(h,&v->device,sizeof(v->device));h=mix(h,&v->permissions,sizeof(v->permissions));h=mix(h,&v->flags,sizeof(v->flags));
        h=mix(h,&v->inode,sizeof(v->inode));h=mix(h,&v->logical,sizeof(v->logical));h=mix(h,&v->allocated,sizeof(v->allocated));
        h=mix(h,&v->created,sizeof(v->created));h=mix(h,&v->modified,sizeof(v->modified));h=mix(h,&v->accessed,sizeof(v->accessed));
    }return h;
}
static double seconds(void) {struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);return now.tv_sec+now.tv_nsec/1e9;}
int main(int argc,char **argv) {
    if(argc<3) {fprintf(stderr,"usage: r14-bulk-metadata baseline|bulk|check path [iterations]\n");return 2;}
    if(!strcmp(argv[1],"check")) {
        Result a=baseline(argv[2]),b=bulk(argv[2]);size_t differences=0;
        if(a.count!=b.count)differences++;
        for(size_t i=0;i<a.count && i<b.count;i++) {
            Row *x=&a.rows[i],*y=&b.rows[i];
            if(strcmp(x->name,y->name)||x->type!=y->type||x->device!=y->device||x->permissions!=y->permissions||x->flags!=y->flags||x->inode!=y->inode||x->logical!=y->logical||x->allocated!=y->allocated||memcmp(&x->created,&y->created,sizeof(x->created))||memcmp(&x->modified,&y->modified,sizeof(x->modified))||memcmp(&x->accessed,&y->accessed,sizeof(x->accessed))) {
                if(differences<16)fprintf(stderr,"metadata mismatch %s/%s type%u/%u dev%u/%u ino%llu/%llu size%lld/%lld alloc%lld/%lld mode%u/%u flags%u/%u\n",x->name,y->name,x->type,y->type,x->device,y->device,(unsigned long long)x->inode,(unsigned long long)y->inode,(long long)x->logical,(long long)y->logical,(long long)x->allocated,(long long)y->allocated,x->permissions,y->permissions,x->flags,y->flags);differences++;
            }
        }
        printf("{\"mode\":\"check\",\"entries\":%zu,\"differences\":%zu,\"baseline_checksum\":\"%llu\",\"bulk_checksum\":\"%llu\",\"bulk_calls\":%llu,\"fallback_lstat\":%llu,\"missing_fields\":%llu,\"boundary_fallbacks\":%llu,\"entry_errors\":%llu}\n",a.count,differences,(unsigned long long)checksum(&a),(unsigned long long)checksum(&b),(unsigned long long)b.bulk_calls,(unsigned long long)b.lstat_calls,(unsigned long long)b.missing_fields,(unsigned long long)b.boundary_fallbacks,(unsigned long long)b.entry_errors);
        release(&a);release(&b);return differences?1:0;
    }
    int iterations=argc>3?atoi(argv[3]):20;double start=seconds();uint64_t h=0;size_t entries=0;uint64_t calls=0,stats=0,missing=0,boundary=0;
    for(int i=0;i<iterations;i++) {
        Result r=!strcmp(argv[1],"bulk")?bulk(argv[2]):baseline(argv[2]);h^=checksum(&r)+(uint64_t)i;entries=r.count;calls+=!strcmp(argv[1],"bulk")?r.bulk_calls:r.readdir_calls;stats+=r.lstat_calls;missing+=r.missing_fields;boundary+=r.boundary_fallbacks;release(&r);
    }
    double elapsed=seconds()-start;struct rusage usage;getrusage(RUSAGE_SELF,&usage);
    printf("{\"mode\":\"%s\",\"iterations\":%d,\"entries\":%zu,\"seconds\":%.9f,\"checksum\":\"%llu\",\"enumeration_api_calls\":%llu,\"stat_api_calls\":%llu,\"missing_fields\":%llu,\"boundary_fallbacks\":%llu,\"max_rss_bytes\":%ld}\n",argv[1],iterations,entries,elapsed,(unsigned long long)h,(unsigned long long)calls,(unsigned long long)stats,(unsigned long long)missing,(unsigned long long)boundary,usage.ru_maxrss);
    return 0;
}
