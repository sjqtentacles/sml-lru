(* lru.sig

   Bounded caches with a pluggable eviction policy (LRU or LFU) and an
   optional time-to-live. Everything is pure: a cache is an immutable value,
   and the mutating operations (put, get, and their *At variants) return a new
   cache. `get` updates recency/frequency bookkeeping, so it too returns a new
   cache alongside the looked-up value.

   There is no wall clock. Time is a logical "tick" supplied by the caller via
   the *At operations; a TTL cache expires an entry once `now - lastWrite`
   exceeds its ttl. The plain put/get operations behave as a cache with no
   expiry. *)

signature LRU =
sig
  (* Eviction policy:
       LRU - evict the least-recently-used entry
       LFU - evict the least-frequently-used entry (ties broken least-recently
             used). *)
  datatype policy = LRU | LFU

  type ('k, 'v) cache

  (* A cache holding at most `capacity` entries, using `policy` for eviction
     and `eq` to compare keys. No TTL: entries never expire. *)
  val make : {capacity : int, policy : policy, eq : 'k * 'k -> bool}
             -> ('k, 'v) cache

  (* Like `make`, but entries expire `ttl` ticks after their last write. *)
  val makeTtl : {capacity : int, policy : policy, ttl : int,
                 eq : 'k * 'k -> bool}
                -> ('k, 'v) cache

  (* Insert or overwrite key->value, returning the updated cache. If the cache
     is at capacity and the key is new, one existing entry is evicted first
     (per the policy). A write counts as an access for LFU and refreshes the
     TTL window. *)
  val put : ('k, 'v) cache -> 'k -> 'v -> ('k, 'v) cache

  (* Look up a key. Returns the value (if present and not expired) together
     with a new cache reflecting the access (updated recency/frequency, and
     any TTL-expired entries purged). *)
  val get : ('k, 'v) cache -> 'k -> 'v option * ('k, 'v) cache

  (* TTL-aware variants. `now` is the current logical tick. `putAt` stamps the
     entry's last-write time as `now`; `getAt` first drops every entry whose
     age (`now - lastWrite`) exceeds the cache's ttl, then performs the lookup.
     For a cache built with `make` (no ttl), these behave exactly like put/get
     and `now` only orders nothing it is simply ignored for expiry. *)
  val putAt : ('k, 'v) cache -> int -> 'k -> 'v -> ('k, 'v) cache
  val getAt : ('k, 'v) cache -> int -> 'k -> 'v option * ('k, 'v) cache

  (* Number of entries currently stored. *)
  val size : ('k, 'v) cache -> int

  (* Entries in eviction order, most-evictable first: for LRU that is
     least-recently-used first; for LFU it is lowest-frequency first, ties
     broken least-recently-used. TTL is not consulted here (no `now` is
     supplied), so entries are listed as currently stored. *)
  val toList : ('k, 'v) cache -> ('k * 'v) list
end
