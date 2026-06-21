(* lru.sml

   A purely functional bounded cache. Entries are kept in a plain list; each
   carries:
     - seq:   a monotonically increasing logical sequence number, bumped on
              every operation and re-stamped whenever the entry is written or
              read. Recency order is therefore total and deterministic.
     - freq:  number of accesses (writes and reads), used by the LFU policy.
     - stamp: the `now` tick of the entry's last write, used for TTL expiry.

   Because every operation assigns a fresh `seq` (drawn from the cache's
   internal tick counter, which only ever increases), no two live entries ever
   share a `seq`; we use that to identify an entry for removal. The internal
   tick is independent of the caller-supplied `now`, so recency ordering stays
   well-defined even when many operations share a single logical time. *)

structure Lru :> LRU =
struct
  datatype policy = LRU | LFU

  type ('k, 'v) entry =
    {key : 'k, value : 'v, seq : int, freq : int, stamp : int}

  type ('k, 'v) cache =
    {capacity : int,
     policy   : policy,
     eq       : 'k * 'k -> bool,
     ttl      : int option,
     tick     : int,
     entries  : ('k, 'v) entry list}

  fun mk (capacity, policy, eq, ttl, tick, entries) : ('k, 'v) cache =
    {capacity = capacity, policy = policy, eq = eq,
     ttl = ttl, tick = tick, entries = entries}

  fun make {capacity, policy, eq} =
    mk (capacity, policy, eq, NONE, 0, [])

  fun makeTtl {capacity, policy, ttl, eq} =
    mk (capacity, policy, eq, SOME ttl, 0, [])

  fun size (c : ('k, 'v) cache) = List.length (#entries c)

  (* An entry is alive at `now` when its age does not exceed the ttl. With no
     ttl every entry is alive. *)
  fun alive ttl now ({stamp, ...} : ('k, 'v) entry) =
    case ttl of
        NONE => true
      | SOME t => now - stamp <= t

  fun purge ttl now entries = List.filter (alive ttl now) entries

  (* Is `a` more evictable than `b` under the given policy?  More evictable
     entries sort earlier in `toList` and are removed first. *)
  fun moreEvictable policy (a : ('k, 'v) entry, b : ('k, 'v) entry) =
    case policy of
        LRU => #seq a < #seq b
      | LFU => if #freq a <> #freq b then #freq a < #freq b
               else #seq a < #seq b

  (* The single most-evictable entry, or NONE for an empty list. *)
  fun victim policy entries =
    case entries of
        [] => NONE
      | e :: es =>
          SOME (List.foldl
                  (fn (x, best) => if moreEvictable policy (x, best) then x else best)
                  e es)

  (* Drop the most-evictable entries until at most `capacity` remain. *)
  fun trimTo (capacity, policy) entries =
    if List.length entries <= capacity then entries
    else
      case victim policy entries of
          NONE => entries
        | SOME v =>
            trimTo (capacity, policy)
              (List.filter (fn e => #seq e <> #seq v) entries)

  fun partitionKey eq k entries =
    List.partition (fn e => eq (#key e, k)) entries

  fun putAt (c : ('k, 'v) cache) now k v =
    let
      val {capacity, policy, eq, ttl, tick, entries} = c
      val tick' = tick + 1
      val live = purge ttl now entries
      val (matches, rest) = partitionKey eq k live
      val freq' =
        case matches of
            existing :: _ => #freq existing + 1
          | [] => 1
      (* For a brand-new key at capacity, make room among existing entries
         first; an overwrite keeps the count unchanged. *)
      val rest' =
        case matches of
            _ :: _ => rest
          | [] => trimTo (capacity - 1, policy) rest
      val entry = {key = k, value = v, seq = tick', freq = freq', stamp = now}
    in
      mk (capacity, policy, eq, ttl, tick', entry :: rest')
    end

  fun getAt (c : ('k, 'v) cache) now k =
    let
      val {capacity, policy, eq, ttl, tick, entries} = c
      val tick' = tick + 1
      val live = purge ttl now entries
      val (matches, rest) = partitionKey eq k live
    in
      case matches of
          existing :: _ =>
            let
              val touched =
                {key = #key existing, value = #value existing,
                 seq = tick', freq = #freq existing + 1, stamp = #stamp existing}
            in
              (SOME (#value existing),
               mk (capacity, policy, eq, ttl, tick', touched :: rest))
            end
        | [] =>
            (NONE, mk (capacity, policy, eq, ttl, tick', live))
    end

  (* Plain put/get: no expiry, so the `now` passed through is irrelevant. *)
  fun put c k v = putAt c 0 k v
  fun get c k = getAt c 0 k

  fun toList (c : ('k, 'v) cache) =
    let
      val {policy, entries, ...} = c
      (* insertion sort by evictability: most-evictable first *)
      fun insert (x, []) = [x]
        | insert (x, y :: ys) =
            if moreEvictable policy (x, y) then x :: y :: ys
            else y :: insert (x, ys)
      val sorted = List.foldr insert [] entries
    in
      List.map (fn e => (#key e, #value e)) sorted
    end
end
