# Redesign Notes

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
- Possible storage formats: 
  - 1: RHS symbols, then LHS symbol, with a bit used to mark the LHS symbol.
    The size of the array is is the size of the grammar (per accepted definition
    of that term).
  - 2: RHS symbols, a sentinel symbol, then LHS symbol.  The size of the array
    is the size of the grammar plus the number of rules.
- **A position in a grammar** is defined to be a position in this array.
  
- All nullable symbols are eliminated in preprocessing.

- A *sorted array mapping* relates positions in the preprocessed grammar to
  corresponding positions in the un-preprocessed grammar.  That's enough
  information to present a client with information in terms of the original
  grammar.

## Chart Representation

The chart is composed of two arrays:
- an **item array** of Earley items, stored in earleme order
- an **earleme array** of earleme start positions in the first array.

## Earley Item Representation

- Only 3 fields are needed
  - start earleme
  - dot position in the grammar
  - derivation set

The parsing process is simpler to talk about if we don't distinguish scans
(recognized terminals) from completions (recognized nonterminals).  Instead we
have (notional) **terminal items** representing scans as completions of a vacuous
rule.

## Chart lookups

There are two situations during recognition where we want to quickly search an
Earley set:

- **Lookup 1:** find items with a given postdot symbol in a completed Earley
  set, when that symbol has been recognized starting in the set's earleme. If we
  sort each earley set by postdot symbol when it is completed, *lookup 1* can
  be a binary search.
  
- **Lookup 2:** to quickly determine whether a given item is already stored in
  the current Earley set, so that it isn't added twice.
   
Since completed items will never be found by *lookup 1*, they don't need to be
quickly found once their earleme is complete.  This also suggests they could be
stored separately. For this purpose, we can keep a set of the current earleme's
items (sans derivations) and clear that set when a new earleme is started.

## Derivation links

Recognition can be thought of as a search through the space of partial matches of
the grammar to the input, looking for complete matches. Each earley item
represents a state in that search space.  When the parse is unambiguous, the
states form a binary tree (not a parse tree) with each state being either a
leaf, or reached directly from a pair of other states in one search step. In
general, though, there may be an arbitrary number of state pairs that can be
combined to reach a given state. Regardless of ambiguity, a given state can
participate in multiple pairings.

Let's call these pairs **derivations**.  A derivation of an item X has two parts:
- **predot item:** a completed item in the same earleme as X describing the
  parse(s) of X's predot symbol.
- **prefix item:** an incomplete item in an earlier earleme describing the
  parses of the RHS symbols *before* X's predot symbol. The postdot symbol of
  any prefix item of X is always X's predot symbol.

The leaves in this graph are *prediction items* and *terminal items*.  In fact,
though, no *prefix* link to a *prediction item* is needed, because it can always
be fully reconstructed from the item it derives: it is known to be the derived
item's start earleme with the dot at the beginning of the item's rule's RHS.

The sorting of Earley sets upon completion poses no problem for *prefix* links,
as a prefix item always appears in an an already-sorted prior earleme with a
stable position in the item array: we can simply store that position as a prefix
link.  The *predot* link is a different matter; it refers to an item in a
not-yet-sorted Earley set, so needs to survive sorting.  But since completed
items don't need to be sorted, we can refer to them by the order of their
discovery in the Earley set.  We can half-stable partition them to the beginning
of the set in the item array before sorting, and then they can be found by
offset from the beginning of the set.

We can optimize for unambiguous parses by using one bit of an Earley item's
storage to indicate whether its *derivations* field stores a single derivation
internally, or identifies a sequence of derivations in a derivations table.

## Representing Predictions

Many *prediction items* may be generated that never lead anywhere, especially at
the beginning of a parse.  The fact that derivation links to these items never
need to be represented makes it practical to think about storing prediction
items differently from the others.

We can:
- Store each Earley set's predictions as a bitset of rule ordinals.
- Precompute the bitset of rules predicted by each symbol in the grammar
- Union the sets associated with all postdot symbols to get the prediction set.
- For every symbol s, precompute the bitset of initiating rules whose RHS starts
  with s
- When a symbol is s recognized we can intersect its bitset of initiating rules
  with the prediction set to get the rules that will advance.

## Dealing with Leo items

The DRP eliminated by Leo's optimization is always a chain of predot items.

### Storage and lookup

WRITEME

### Linking

WRITEME

### Reconstruction of missing items.

Leo optimizes away intermediate items on the DRP of right-recursive rules.  If
possible, I'd like to avoid creating storage for these items.

## Chart Pruning

What MARPA calls a Bocage is essentially a copy of the recognition chart, but
omitting all items that never participate in a complete parse.  I'm not sure
that's a win for unambiguous/low-ambiguity grammars, so I'd like to at least
have the option to do evaluation directly on the complete chart.

---------------

Example grammar:

```bnf
A -> B C
B -> D
D -> E
C -> F
F -> G H
```

```
Input: E G H
      0 1 2 3
```

| Item array index | Earleme 0     | Earleme 1        | Earleme 2    | Earleme 3     | derivations     | predictor |
|------------------|---------------|------------------|--------------|---------------|-----------------|-----------|
| 0                | A -> •B  C    |                  |              |               |                 | *none*    |
| 1                | B -> •D       |                  |              |               |                 | 0         |
| 2                | D -> •E       |                  |              |               |                 | 1         |
| 3                | <............ | [D] -> E •       |              |               | (2, *scan*)     |           |
| 4                | <............ | [B] -> D •       |              |               | (1, **3**)      |           |
| 5                | <............ | A   -> B •C      |              |               | (0, **4**)      |           |
| 6                |               | C   ->   •F      |              |               |                 | 5         |
| 7                |               | F   ->   •G H    |              |               |                 | 6         |
| 8                |               | <............... | F -> G •H    |               | (7, *scan*)     |           |
| 9                |               | <............... | ............ | [F] -> G  H • | (**8**, *scan*) |           |
| 10               |               | <............... | ............ | [C] ->    F • | (6, **9**)      |           |
| 11               | <............ | ................ | ............ | [A] -> B  C • | (**5**, **10**) |           |






**Notes**
- Dotted arrows show the start earlemes of each earley item. 
- A [bracketed] LHS indicates a completion
- Only **bold** info in derivations column needs to be stored.

<!-- Local Variables: -->
<!-- fill-column: 80 -->
<!-- End: -->
