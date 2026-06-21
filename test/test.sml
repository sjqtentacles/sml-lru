(* Tests for sml-lru: bounded LRU/LFU caches with optional TTL.

   The cache is a pure, functional value: put/get return a new cache (get
   updates recency/frequency, hence threads a new cache through). Time is a
   logical tick supplied by the caller; there is no wall clock. *)

structure LruTests =
struct
  open Harness

  val intEq : int * int -> bool = (op =)

  fun keys c = List.map #1 (Lru.toList c)

  fun run () =
    let
      (* --- LRU eviction order ---
         capacity 2, put a,b, get a, put c  =>  b evicted (a,c remain). *)
      val () = section "LRU eviction"
      val c = Lru.make {capacity = 2, policy = Lru.LRU, eq = intEq}
      val c = Lru.put c 1 100
      val c = Lru.put c 2 200
      val (va, c) = Lru.get c 1
      val () = checkBool "get a hits" (true, va = SOME 100)
      val c = Lru.put c 3 300
      val () = checkInt "size stays at capacity" (2, Lru.size c)
      val (vb, c) = Lru.get c 2
      val () = checkBool "b was evicted" (true, vb = NONE)
      val (va2, c) = Lru.get c 1
      val () = checkBool "a survived" (true, va2 = SOME 100)
      val (vc, c) = Lru.get c 3
      val () = checkBool "c present" (true, vc = SOME 300)

      (* --- LFU eviction ---
         capacity 2, put a,b, get a twice, get b once, put c => b evicted
         (b has lower frequency than a among the existing entries). *)
      val () = section "LFU eviction"
      val c = Lru.make {capacity = 2, policy = Lru.LFU, eq = intEq}
      val c = Lru.put c 1 100
      val c = Lru.put c 2 200
      val (_, c) = Lru.get c 1
      val (_, c) = Lru.get c 1
      val (_, c) = Lru.get c 2
      val c = Lru.put c 3 300
      val () = checkInt "size stays at capacity" (2, Lru.size c)
      val (vb, c) = Lru.get c 2
      val () = checkBool "b (lower freq) evicted" (true, vb = NONE)
      val (va, c) = Lru.get c 1
      val () = checkBool "a (higher freq) survived" (true, va = SOME 100)
      val (vc, c) = Lru.get c 3
      val () = checkBool "c present" (true, vc = SOME 300)

      (* --- toList order: most-evictable first --- *)
      val () = section "toList ordering"
      val c = Lru.make {capacity = 3, policy = Lru.LRU, eq = intEq}
      val c = Lru.put c 1 10
      val c = Lru.put c 2 20
      val c = Lru.put c 3 30
      val (_, c) = Lru.get c 1   (* 1 becomes most-recently-used *)
      val () = checkIntList "LRU: least-recently-used first" ([2, 3, 1], keys c)

      val c = Lru.make {capacity = 3, policy = Lru.LFU, eq = intEq}
      val c = Lru.put c 1 10
      val c = Lru.put c 2 20
      val c = Lru.put c 3 30
      val (_, c) = Lru.get c 3   (* 3 -> freq 2 *)
      val (_, c) = Lru.get c 3   (* 3 -> freq 3 *)
      val (_, c) = Lru.get c 2   (* 2 -> freq 2 *)
      (* freqs: 1=1, 2=2, 3=3; most-evictable (lowest freq) first *)
      val () = checkIntList "LFU: lowest frequency first" ([1, 2, 3], keys c)

      (* --- capacity invariant across a sequence --- *)
      val () = section "capacity invariant"
      val cap = 3
      val c0 = Lru.make {capacity = cap, policy = Lru.LRU, eq = intEq}
      val ops = [1, 2, 3, 4, 2, 5, 6, 3, 7, 1, 8, 2, 9]
      val (final, ok) =
        List.foldl
          (fn (k, (c, allok)) =>
             let val c = Lru.put c k (k * 10)
             in (c, allok andalso Lru.size c <= cap) end)
          (c0, true) ops
      val () = checkBool "size never exceeds capacity" (true, ok)
      val () = checkInt "ends full" (cap, Lru.size final)

      (* --- TTL expiry ---
         put at tick 0 with ttl 10; getAt tick 5 hits, getAt tick 20 misses. *)
      val () = section "TTL expiry"
      val c = Lru.makeTtl {capacity = 4, policy = Lru.LRU, ttl = 10, eq = intEq}
      val c = Lru.putAt c 0 1 100
      val (h5, c) = Lru.getAt c 5 1
      val () = checkBool "alive within ttl (tick 5)" (true, h5 = SOME 100)
      val (h20, c) = Lru.getAt c 20 1
      val () = checkBool "expired past ttl (tick 20)" (true, h20 = NONE)
      val () = checkInt "expired entry purged" (0, Lru.size c)

      (* a fresh write refreshes the TTL window *)
      val c = Lru.makeTtl {capacity = 4, policy = Lru.LRU, ttl = 10, eq = intEq}
      val c = Lru.putAt c 0 1 100
      val c = Lru.putAt c 8 1 111   (* rewrite at 8 resets the clock *)
      val (h15, c) = Lru.getAt c 15 1
      val () = checkBool "rewrite extends ttl" (true, h15 = SOME 111)
    in
      ()
    end
end
