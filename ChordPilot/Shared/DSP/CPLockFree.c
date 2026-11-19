#include "CPLockFree.h"
#include <stdatomic.h>
#include <stdlib.h>

struct CPRing {
    _Atomic uint32_t head;   // written by producer
    _Atomic uint32_t tail;   // written by consumer
    uint32_t mask;
    uint32_t *buffer;
};

CPRing *cp_ring_create(uint32_t capacity) {
    uint32_t cap = 2;
    while (cap < capacity) cap <<= 1;
    CPRing *r = (CPRing *)calloc(1, sizeof(CPRing));
    r->buffer = (uint32_t *)calloc(cap, sizeof(uint32_t));
    r->mask = cap - 1;
    atomic_init(&r->head, 0);
    atomic_init(&r->tail, 0);
    return r;
}

void cp_ring_destroy(CPRing *r) {
    free(r->buffer);
    free(r);
}

bool cp_ring_push(CPRing *r, uint32_t message) {
    uint32_t head = atomic_load_explicit(&r->head, memory_order_relaxed);
    uint32_t tail = atomic_load_explicit(&r->tail, memory_order_acquire);
    if (head - tail > r->mask) return false; // full
    r->buffer[head & r->mask] = message;
    atomic_store_explicit(&r->head, head + 1, memory_order_release);
    return true;
}

bool cp_ring_pop(CPRing *r, uint32_t *message) {
    uint32_t tail = atomic_load_explicit(&r->tail, memory_order_relaxed);
    uint32_t head = atomic_load_explicit(&r->head, memory_order_acquire);
    if (tail == head) return false; // empty
    *message = r->buffer[tail & r->mask];
    atomic_store_explicit(&r->tail, tail + 1, memory_order_release);
    return true;
}

struct CPAtomicInt { _Atomic int32_t value; };

CPAtomicInt *cp_atomic_create(int32_t initial) {
    CPAtomicInt *a = (CPAtomicInt *)calloc(1, sizeof(CPAtomicInt));
    atomic_init(&a->value, initial);
    return a;
}
void cp_atomic_destroy(CPAtomicInt *a) { free(a); }
int32_t cp_atomic_load(CPAtomicInt *a) { return atomic_load_explicit(&a->value, memory_order_acquire); }
void cp_atomic_store(CPAtomicInt *a, int32_t v) { atomic_store_explicit(&a->value, v, memory_order_release); }
int32_t cp_atomic_exchange(CPAtomicInt *a, int32_t v) { return atomic_exchange_explicit(&a->value, v, memory_order_acq_rel); }
