# sml-lru

[![CI](https://github.com/sjqtentacles/sml-lru/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-lru/actions/workflows/ci.yml)

Bounded caches for Standard ML with pluggable eviction policies (**LRU** and
**LFU**) and an optional **time-to-live**.

`sml-lru` is pure and functional: a cache is an immutable value, and every
operation returns a new cache. There is no wall clock — time is a logical
*tick* supplied by the caller, so behaviour is fully deterministic and
reproducible. No FFI, no threads, no mutation. Just the Basis library.

Verified to produce byte-for-byte identical output on **MLton** and
**Poly/ML**.

## At a glance

```sml
val c = Lru.make {capacity = 2, policy = Lru.LRU, eq = (op =)}
val c = Lru.put c "a" 1
val c = Lru.put c "b" 2
val (v, c) = Lru.get c "a"     (* SOME 1; "a" is now most-recently-used *)
val c = Lru.put c "c" 3        (* over capacity -> evicts "b" (LRU) *)
val keys = List.map #1 (Lru.toList c)   (* ["a", "c"] in eviction order *)
```

## API

```sml
structure Lru : sig
  datatype policy = LRU | LFU

  type ('k, 'v) cache

  val make    : {capacity : int, policy : policy, eq : 'k * 'k -> bool}
                -> ('k, 'v) cache
  val makeTtl : {capacity : int, policy : policy, ttl : int,
                 eq : 'k * 'k -> bool}
                -> ('k, 'v) cache

  val put : ('k, 'v) cache -> 'k -> 'v -> ('k, 'v) cache
  val get : ('k, 'v) cache -> 'k -> 'v option * ('k, 'v) cache

  val putAt : ('k, 'v) cache -> int -> 'k -> 'v -> ('k, 'v) cache
  val getAt : ('k, 'v) cache -> int -> 'k -> 'v option * ('k, 'v) cache

  val size   : ('k, 'v) cache -> int
  val toList : ('k, 'v) cache -> ('k * 'v) list   (* most-evictable first *)
end
```

### Semantics

- **`get` returns a new cache.** A lookup updates recency (for LRU) and
  frequency (for LFU), so it threads an updated cache back to the caller
  alongside the `'v option` result.
- **Eviction happens on insert.** When `put` adds a *new* key to a full cache,
  one existing entry is evicted first, chosen by the policy:
  - `LRU` evicts the least-recently-used entry.
  - `LFU` evicts the least-frequently-used entry, breaking ties by least
    recently used.
  Overwriting an existing key never evicts.
- **`toList` is in eviction order, most-evictable first** — least-recently-used
  first for LRU, lowest-frequency first (ties least-recently-used) for LFU.
- **TTL is logical.** `putAt c now k v` stamps the entry's last-write time as
  `now`. `getAt c now k` drops every entry whose age (`now - lastWrite`)
  exceeds the cache's `ttl` before looking up, so an expired entry reads as a
  miss and is purged. Reads do not extend the window; a fresh write resets it.
  `put`/`get` are simply the no-TTL case (the tick is ignored for expiry).

### TTL example

```sml
val c = Lru.makeTtl {capacity = 4, policy = Lru.LRU, ttl = 10, eq = (op =)}
val c = Lru.putAt c 0 "x" 42
val (a, c) = Lru.getAt c 5  "x"   (* SOME 42 — age 5 <= 10 *)
val (b, c) = Lru.getAt c 20 "x"   (* NONE    — age 20 > 10, expired + purged *)
```

## Build & test

Requires [MLton](http://mlton.org/) and/or [Poly/ML](https://polyml.org/).

```sh
make test        # build + run the suite under MLton
make test-poly   # run the suite under Poly/ML
make all-tests   # both
make example     # build + run the LRU/LFU/TTL demo
make clean
```

## Installing with smlpkg

```sh
smlpkg add github.com/sjqtentacles/sml-lru
smlpkg sync
```

Reference `lib/github.com/sjqtentacles/sml-lru/lru.mlb` from your own `.mlb`
(MLton / MLKit), or feed `sources.mlb` to `tools/polybuild` (Poly/ML).

## Layout

```
sml.pkg                                       smlpkg manifest
Makefile                                      MLton + Poly/ML targets
.github/workflows/ci.yml                      CI: MLton + Poly/ML
lib/github.com/sjqtentacles/sml-lru/
  lru.sig/.sml   bounded LRU/LFU cache (+ TTL)
  sources.mlb    ordered source list
  lru.mlb        public basis
examples/
  demo.sml       LRU + LFU + TTL eviction demo
  sources.mlb
test/
  harness.sml    shared assertion harness
  test.sml       eviction + TTL suite (17 checks)
  entry.sml / main.sml
tools/polybuild  Poly/ML build wrapper
```

## Tests

17 deterministic checks covering LRU eviction order, LFU eviction by
frequency, the capacity invariant across a sequence of operations, `toList`
ordering, and TTL expiry. Run `make all-tests` to verify identical output
under both compilers.

## License

MIT. See [LICENSE](LICENSE).
