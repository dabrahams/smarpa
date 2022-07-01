# Notes

Terminology:

**sorted array mapping**
: A sorted array mapping is an array of integer pairs (*s*, *d*), sorted by
  increasing *s*. The *i*th element (*sᵢ*, *dᵢ*) = is interpreted as mapping every
  *x* s.t. *sᵢ* ≤ *x* < *sᵢ₊₁* to *dᵢ* + (*x* - *sᵢ*).

**prediction item**
: An Earley item with its dot preceding its first RHS symbol.

## Grammar Representation

Rule Storage:
- Rules stored end-to-end in a `ruleStore` array.
- Storage format: RHS symbols, a sentinel symbol, then LHS symbol.
- **A position in a grammar** is defined to be a position in this array.
- The size of this array is the size of the grammar (per accepted definition of
  that term) plus the number of rules.
  
- All nullable symbols are eliminated in preprocessing.

- A *sorted array mapping* relates positions in the preprocessed grammar to positions in the
  un-preprocessed grammar.

## Chart Representation

The chart is composed of two arrays:
- an **item array** of Earley items, stored in earleme order
- an **earleme array** of earleme start positions in the first array.

## Earley Item Representation

- Only 3 fields are needed
  - start position in input
  - dot position in the grammar
  - derivations

The parsing process is simpler to talk about if we don't distinguish scans
(recognized terminals) from completions (recognized nonterminals).  Instead we
have (notional) **terminal items** representing scans as completions of a vacuous
rule.

## Chart lookups

There are two situations where we want to quickly search an Earley set:

1. To find items with a given postdot symbol, when that symbol has been
   recognized starting in the set's earleme.
2. To quickly determine whether a given item is already stored in the set, so
   that it isn't added twice.  This capability is only needed for the current
   earleme.  For this purpose, we can keep a set of the current earleme's items
   (sans derivations) and clear that set when a new earleme is started.
   


## Derivation links

The parse can be thought of as a search through the space of parses for those
that matches the grammar to the input, with each earley item representing a
state in that search space.  When the parse is unambiguous, the states form a
binary tree (not a parse tree) with each state being either a leaf, or derived
directly from two other states in one step. In general, though, there may be an
arbitrary number of state pairs that can be combined to reach a given state, and
a given state can participate in multiple pairings.

Let's call these pairs **derivations**.  A derivation of an item X consists of two parts:
- **predot:** refers to a completed item in the same earleme as X describing the
  parse(s) of X's predot symbol.
- **prefix:** refers to an incomplete item in an earlier earleme describing the
  parses of the RHS symbols *before* X's predot symbol.
  
The leaves in this graph are *prediction items* and *terminal items*.  In fact,
though, no *prefix* link to a *prediction item* is needed, because it can always
be fully reconstructed from the item it derives: it is known to be the derived
item's start earleme with the dot at the beginning of the item's rule's RHS.
This fact makes it practical to think about representing *prediction items*
differently from the others.

Since completed items are never awaiting a symbol to advance, they don't need to
be quickly findable.


- Each time a node is reached, it is reached by combining two other nodes.
  - an item from the current earleme
- Every item is reached by the combination of 
- Any other Earley item can have an arbitrary number of predecessors from
  which it was reached in a single completion or scan step.
- When the item represents an unambiguous partial parse, it is guaranteed to
  have only one predecessor.
- Additional predecessors for a given item may be discovered as the item's
  Earleme is being built.

- We can optimize for unambiguous parses by storing predecessors as a number:
  - If positive, it is the index of the predecessor item in the *item array*.
  - Otherwise, it identifies a collection of predecessor items stored elsewhere.


---------------

Example grammar:

```bnf
A -> B C
B -> D
D -> E
C -> F
F -> G H
```

Input: E G H
      0 1 2 3
        
- Earleme 0:
  - 0: •B  C <- A  (initial)
  - 0: •D <- B     (predicted from above)
  - 0: •E <- D     (predicted from above)
  
- Earleme 1:
  - 0: E • <- [D]  (scan)
  - 0: D • <- [B]  (completion of D above)
  - 0: B •C <- A   (completion of B above)
  - 1:   •F <- C   (predicted from above)
  - 1:   •G H <- F (predicted from above)
  
- Earleme 2:
  - 1: G •H -> F   (scan - H is a terminal so no predictions)
  
- Earleme 3:
  - 1: G  H • <- [F] (scan)
  - 1:    F • <- [C] (completion of F above)
  - 0:  B C • <- [A] (completion of C above)
  
<!-- Local Variables: -->
<!-- fill-column: 80 -->
<!-- End: -->
