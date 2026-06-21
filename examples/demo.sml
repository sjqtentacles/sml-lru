(* sml-lru demo: shows LRU eviction, LFU eviction, and TTL expiry, threading
   the immutable cache through each step and printing the result. Keys are
   strings; values are ints. *)

val intEq : string * string -> bool = (op =)

fun showOpt NONE = "miss"
  | showOpt (SOME v) = "hit " ^ Int.toString v

fun showCache c =
  "{" ^ String.concatWith ", "
          (List.map (fn (k, v) => k ^ "=" ^ Int.toString v) (Lru.toList c)) ^ "}"

fun line s = print (s ^ "\n")

(* ---- LRU: least-recently-used is evicted first ---- *)
val () = line "== LRU (capacity 2) =="
val c = Lru.make {capacity = 2, policy = Lru.LRU, eq = intEq}
val c = Lru.put c "a" 1
val c = Lru.put c "b" 2
val () = line ("put a, put b              -> " ^ showCache c)
val (_, c) = Lru.get c "a"
val () = line ("get a (a now most-recent) -> " ^ showCache c)
val c = Lru.put c "c" 3
val () = line ("put c (evicts b)          -> " ^ showCache c)
val (b, _) = Lru.get c "b"
val () = line ("lookup b                  -> " ^ showOpt b)

(* ---- LFU: least-frequently-used is evicted first ---- *)
val () = line "\n== LFU (capacity 2) =="
val c = Lru.make {capacity = 2, policy = Lru.LFU, eq = intEq}
val c = Lru.put c "a" 1
val c = Lru.put c "b" 2
val (_, c) = Lru.get c "a"
val (_, c) = Lru.get c "a"
val (_, c) = Lru.get c "b"
val () = line ("put a,b; get a x2, get b  -> " ^ showCache c)
val c = Lru.put c "c" 3
val () = line ("put c (evicts b, low freq)-> " ^ showCache c)
val (b, _) = Lru.get c "b"
val () = line ("lookup b                  -> " ^ showOpt b)

(* ---- TTL: entries expire ttl ticks after their last write ---- *)
val () = line "\n== TTL (ttl 10, logical ticks) =="
val c = Lru.makeTtl {capacity = 4, policy = Lru.LRU, ttl = 10, eq = intEq}
val c = Lru.putAt c 0 "x" 42
val () = line "putAt tick 0: x=42"
val (v5, c) = Lru.getAt c 5 "x"
val () = line ("getAt tick 5              -> " ^ showOpt v5)
val (v20, c) = Lru.getAt c 20 "x"
val () = line ("getAt tick 20 (expired)   -> " ^ showOpt v20)
val () = line ("size after expiry         -> " ^ Int.toString (Lru.size c))
