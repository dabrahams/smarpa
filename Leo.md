# Notation

- Let G = (V, Σ, P, S) denote an arbitrary context-free grammar, where 
  - V is the vocabulary
  - Σ the set of terminal symbols
  - P a finite set of productions, and
  - S the start symbol

  - V-Σ is the set of non-terminal symbols,denotedby N

- Let w = a₁,...an, with aᵢ 𝟄 Σ (1≤i≤n) denote the input string to be parsed or
  recognized.
  - The substring aᵢ₊₁ ... aⱼ is denoted as wᵢⱼ.
  - Instead of w₀ⱼ we also write wⱼ.

- A recognizer is a procedure to decide for every w in Σ* whether or not w 𝟄 L(G).

- A parser is a recognizer which yields for every w 𝟄 L(G) the derivation(s) of
  w in one form or another.

# Earley

- no grammar transformations are required. 

- Where no lookahead is used:
  - it successively builds lists I₀,...,In, containing items of the form
    [A→𝜶.𝜷,i] (where A→𝜶𝜷 is a production and . is a symbol not in V).
    
  - When list Iⱼ is completed, it contains item [A→𝜶.𝜷,i] iff S⟹⃰wᵢA𝜸 for some 𝜸
    𝟄 V* and 𝜶⟹⃰wᵢⱼ.

# Improving on Earley

- space complexity of Earley’s algorithm could be improved in some cases by
  removing all complete items in Iⱼ after this list has been built, but in
  general this would make parsing harder.

- Some of the complete items contributing to a parse 
  - can easily be reconstructed afterwards in a deterministic way.
  - need not be generated at all while building the lists I₀,..., In. 

- For certain right recursive grammars this will speed up the recognition time
  by a factor n.

## Initialization

Let I₀ be the set of all items of the form [A→𝜶.𝜷,0] (where A→𝜶𝜷 is a production
in P, s.t. S⟹⃰A𝜼 for some 𝜼 𝟄 V*), and 𝜶⟹⃰𝝀.

Comment
: Appears to be the same as Earley initialization

[Now assume that the sets I₀,...,Iⱼ₋₁ have already been constructed, and set Iⱼ
is still empty.]

## Scanner

for each item [A→𝜶.aᵢ𝜹𝜸,i] 𝟄 Iⱼ₋₁, such that 𝜹⟹⃰𝝀, 
- add [A→𝜶aᵢ𝜹.𝜸,i] to Iⱼ.

Comment
: Scanning advances past all combinations of nullable symbols.

## Completer

for each complete item of the form [A→𝜸.,i] in or newly added to Iⱼ

- if ∃x s.t. x is the topmost complete item on the deterministic reduction path
  (DRP) above [A→𝜸.,i]
  - add x to Iⱼ.
  
- otherwise, 
  - for each item [B→𝜶.A𝜹𝜼,k] 𝟄 Iᵢ s.t. 𝜹⟹⃰𝝀
    - add [B→𝜶A𝜹.𝜼,k] to Iⱼ
      
Comment
: It appears that the point here is to skip generating intermediate items on the
  DRP.

## Predictor

For each [A→𝜶.B𝜷,i] 𝟄 Iⱼ,
- Add to Iⱼ all items [C→𝜸.𝝃,j] s.t. C→𝜸𝝃 𝟄 P, 𝜸⟹⃰𝝀, B⟹⃰C𝜼 for some 𝜼 𝟄 V*,

# Deterministic Reduction Path (DRP)

An item x is said to be on the deterministic reduction path above [A→𝜸.,i] if
- x is [B→𝜶A.,k] s.t. [B→𝜶.A,k] is the only item in Iᵢ with the dot preceding A,
- or, x is on the DRP above [B→𝜶A.,k]

An item on such a path is called the topmost one if there is no item on the
deterministic reduction path above it.

Comment
: The DRP is the chain of unique completions triggered by a completion. The
  chain stops anywhere a given completion triggers more than one completion.
  “Above” refers to height in the parse tree, where the root is at the top.

To be continued.

<!-- Local Variables: -->
<!-- fill-column: 80 -->
<!-- End: -->
