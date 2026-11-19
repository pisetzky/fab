// Small lock-free helpers shared between the UI thread and the real-time audio thread.
// Plain C so they can use C11 atomics (Swift cannot express these safely before iOS 18).

#ifndef CPLockFree_h
#define CPLockFree_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Single-producer / single-consumer ring of packed 32-bit messages (status | data1<<8 | data2<<16).
typedef struct CPRing CPRing;

CPRing * _Nonnull cp_ring_create(uint32_t capacityPowerOfTwo);
void cp_ring_destroy(CPRing * _Nonnull ring);
bool cp_ring_push(CPRing * _Nonnull ring, uint32_t message);
bool cp_ring_pop(CPRing * _Nonnull ring, uint32_t * _Nonnull message);

/// Atomic 32-bit integer.
typedef struct CPAtomicInt CPAtomicInt;

CPAtomicInt * _Nonnull cp_atomic_create(int32_t initial);
void cp_atomic_destroy(CPAtomicInt * _Nonnull a);
int32_t cp_atomic_load(CPAtomicInt * _Nonnull a);
void cp_atomic_store(CPAtomicInt * _Nonnull a, int32_t value);
int32_t cp_atomic_exchange(CPAtomicInt * _Nonnull a, int32_t value);

#ifdef __cplusplus
}
#endif

#endif /* CPLockFree_h */
