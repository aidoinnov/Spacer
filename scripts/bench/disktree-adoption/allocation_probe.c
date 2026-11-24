// Counts selected libc allocator entry points in owned unsigned benchmark CLIs.
// Requested bytes are cumulative calls, NOT live bytes or all zone allocations.
#include <stdlib.h>
#include <stdint.h>
#include <stdatomic.h>
static _Atomic uint64_t counters[4];
uint64_t sniffer_allocation_counter(uint32_t index) {
    return index < 4 ? atomic_load_explicit(&counters[index], memory_order_relaxed) : 0;
}
static void charge(uint32_t index, size_t size) {
    atomic_fetch_add_explicit(&counters[index], 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&counters[3], (uint64_t)size, memory_order_relaxed);
}
static void *probe_malloc(size_t size) { charge(0, size); return malloc(size); }
static void *probe_calloc(size_t n, size_t size) {
    charge(1, size && n > SIZE_MAX / size ? SIZE_MAX : n * size);
    return calloc(n, size);
}
static void *probe_realloc(void *ptr, size_t size) { charge(2, size); return realloc(ptr, size); }
#define INTERPOSE(replacement, original) \
    __attribute__((used, section("__DATA,__interpose"))) \
    static const struct { const void *replacement; const void *original; } interpose_##original = \
    { (const void *)&replacement, (const void *)&original };
INTERPOSE(probe_malloc, malloc)
INTERPOSE(probe_calloc, calloc)
INTERPOSE(probe_realloc, realloc)
