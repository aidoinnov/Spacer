#ifndef WINDOWS_DIRECTORY_IO_H
#define WINDOWS_DIRECTORY_IO_H
#include <stdint.h>
typedef struct sniffer_directory sniffer_directory;
typedef struct {
    const uint16_t *name;
    uint32_t name_units, attributes, reparse_tag;
    uint64_t logical_bytes, allocated_bytes, volume, id_low, id_high;
    uint64_t created_ticks, accessed_ticks, modified_ticks;
} sniffer_entry;
sniffer_directory *sniffer_open(const uint16_t *path, uint32_t *error);
/* 1 entry, 0 terminal EOF, -1 failure. Name storage valid until next call. */
int sniffer_next(sniffer_directory *directory, sniffer_entry *entry, uint32_t *error);
typedef struct {
    uint64_t total_bytes, free_bytes, created_ticks, accessed_ticks, modified_ticks;
    uint32_t attributes, is_volume_root;
} sniffer_root_metadata;
/* One root query per scan; no per-entry metadata calls on the bulk path. */
/* exact_mount rejects junctions/symlinks; returns a canonical volume GUID. */
int sniffer_volume_identity(const uint16_t *path, int exact_mount, uint16_t *out, uint32_t count);
int sniffer_query_root(const uint16_t *path, sniffer_root_metadata *out);
void sniffer_close(sniffer_directory *directory);
#endif
