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

      (* ----------------------------------------------------------------- *)
      val () = section "properties (sml-check, seed 0wx1)"
      val seed : Check.seed = 0wx1
      val genKey = Check.choose (0, 4)
      val genVal = Check.choose (0, 999)
      val genCap = Check.choose (1, 5)
      val genBase = Check.choose (0, 1000)
      fun showIntList xs = "[" ^ String.concatWith "," (List.map Int.toString xs) ^ "]"

      (* size never exceeds capacity over a random put sequence. *)
      val () =
        Harness.check "prop: size never exceeds capacity"
          (case Check.quickCheck
                  (Check.forAll
                     (Check.bind genCap (fn cap =>
                        Check.map (fn kvs => (cap, kvs))
                          (Check.listOf (Check.tuple2 (genKey, genVal)))))
                     (fn (cap, kvs) =>
                        "cap=" ^ Int.toString cap ^ " kvs="
                        ^ showIntList (List.map #1 kvs))
                     (fn (cap, kvs) =>
                        let
                          val c0 = Lru.make {capacity = cap, policy = Lru.LRU, eq = intEq}
                          fun step ((k, v), (c, ok)) =
                              let val c' = Lru.put c k v
                              in (c', ok andalso Lru.size c' <= cap) end
                          val (_, ok) = List.foldl step (c0, true) kvs
                        in ok end)) of
               Check.Passed _ => true
             | Check.Failed _ => false)

      (* put then get on the same key always hits with the written value. *)
      val () =
        Harness.check "prop: put k v; get k = SOME v"
          (case Check.quickCheck
                  (Check.forAll (Check.tuple2 (genKey, genVal))
                     (fn (k, v) => "k=" ^ Int.toString k ^ " v=" ^ Int.toString v)
                     (fn (k, v) =>
                        let
                          val c = Lru.make {capacity = 3, policy = Lru.LRU, eq = intEq}
                          val c1 = Lru.put c k v
                          val (r, _) = Lru.get c1 k
                        in r = SOME v end)) of
               Check.Passed _ => true
             | Check.Failed _ => false)

      (* Filling a cache with capacity+1 distinct keys, back-to-back with no
         intervening gets, evicts exactly the first-inserted (least-recently-
         used) key and keeps every other one. *)
      val () =
        Harness.check "prop: capacity+1 distinct puts evict the first key"
          (case Check.quickCheck
                  (Check.forAll
                     (Check.bind genCap (fn cap => Check.map (fn base => (cap, base)) genBase))
                     (fn (cap, base) => "cap=" ^ Int.toString cap ^ " base=" ^ Int.toString base)
                     (fn (cap, base) =>
                        let
                          val keys = List.tabulate (cap + 1, fn i => base + i)
                          val c0 = Lru.make {capacity = cap, policy = Lru.LRU, eq = intEq}
                          val c = List.foldl (fn (k, c) => Lru.put c k k) c0 keys
                          val firstEvicted = #1 (Lru.get c (List.hd keys)) = NONE
                          val restPresent =
                              List.all (fn k => #1 (Lru.get c k) = SOME k) (List.drop (keys, 1))
                        in firstEvicted andalso restPresent end)) of
               Check.Passed _ => true
             | Check.Failed _ => false)

      (* get on a key refreshes its recency, protecting it from the next
         eviction that would otherwise have targeted the true LRU key. *)
      val () =
        Harness.check "prop: get refreshes recency"
          (case Check.quickCheck
                  (Check.forAll genBase (fn base => "base=" ^ Int.toString base)
                     (fn base =>
                        let
                          val k0 = base and k1 = base + 1 and k2 = base + 2 and k3 = base + 3
                          val c0 = Lru.make {capacity = 3, policy = Lru.LRU, eq = intEq}
                          val c = Lru.put c0 k0 0
                          val c = Lru.put c k1 1
                          val c = Lru.put c k2 2
                          val (_, c) = Lru.get c k0   (* k0 becomes most-recently-used *)
                          val c = Lru.put c k3 3      (* evicts the true LRU, k1 *)
                        in
                          #1 (Lru.get c k0) = SOME 0
                          andalso #1 (Lru.get c k1) = NONE
                        end)) of
               Check.Passed _ => true
             | Check.Failed _ => false)

      (* A naive list-based reference model (append-to-tail on put/hit,
         evict-from-head when over capacity) agrees with the cache's key
         order and every get's result over a random put/get sequence. *)
      val () =
        Harness.check "prop: matches naive recency-list reference model"
          (case Check.quickCheck
                  (Check.forAll
                     (Check.listOf (Check.tuple3 (Check.choose (0, 1), genKey, genVal)))
                     (fn ops => Int.toString (List.length ops) ^ " ops")
                     (fn ops =>
                        let
                          val cap = 3
                          fun modelRemove (model, k) =
                              List.filter (fn (k', _) => k' <> k) model
                          fun modelPut (model, k, v) =
                              let val model1 = modelRemove (model, k) @ [(k, v)]
                              in if List.length model1 > cap
                                 then (case model1 of _ :: rest => rest | [] => [])
                                 else model1
                              end
                          fun modelGet (model, k) =
                              case List.find (fn (k', _) => k' = k) model of
                                  NONE => (NONE, model)
                                | SOME (_, v) => (SOME v, modelRemove (model, k) @ [(k, v)])
                          val c0 = Lru.make {capacity = cap, policy = Lru.LRU, eq = intEq}
                          fun step ((tag, k, v), (c, model, ok)) =
                              if tag = 0
                              then (Lru.put c k v, modelPut (model, k, v), ok)
                              else
                                let
                                  val (r, c') = Lru.get c k
                                  val (mr, model') = modelGet (model, k)
                                in (c', model', ok andalso r = mr) end
                          val (cFinal, modelFinal, ok) = List.foldl step (c0, [], true) ops
                        in
                          ok andalso List.map #1 (Lru.toList cFinal) = List.map #1 modelFinal
                        end)) of
               Check.Passed _ => true
             | Check.Failed _ => false)
    in
      ()
    end
end
