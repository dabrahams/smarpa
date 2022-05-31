enum AllSomeNone { case all, some, none }

extension Collection {
  /// Returns an indication of whether all, some, or no elements satisfy `predicate`.
  func satisfaction(_ predicate: (Element)->Bool) -> AllSomeNone {
    guard let i = firstIndex(where: predicate) else { return .none }
    if i == startIndex && dropFirst().allSatisfy(predicate) { return .all }
    return .some
  }

  func nth(_ n: Int) -> Element { dropFirst(n).first! }
}

extension Array {
  mutating func amortizedLinearReserveCapacity(_ minimumCapacity: Int) {
    let n = capacity > minimumCapacity ? capacity : Swift.max(2 * capacity, minimumCapacity)
    reserveCapacity(n) // Note: must reserve unconditionally to ensure uniqueness
  }
}

public struct Grammar<RawSymbol: Hashable> {

  /// Symbols for the nihilist normal form (NNF) of the raw grammar, per Aycock and Horspool
  enum Symbol: Hashable {
    /// The plain raw symbol
    case some(RawSymbol)
    
    /// The nulling version of the symbol.
    case null(RawSymbol)
  }
  
  /// A type that stores all rules packed end-to-end, with the LHS symbol following the RHS symbols.
  ///
  /// For example A -> B C is stored as the subsequence [B, C, A].
  typealias RuleStore = [Symbol]
  
  /// Storage for all the rules.
  private var ruleStore: [Symbol] = []


  struct Rule: Hashable {
    struct ID: Hashable { var lhsIndex: RuleStore.Index }
    var rhsIndices: Range<RuleStore.Index>
  }

  /// The right-hand side alternatives for each nonterminal symbol.
  private var rulesByLHS = MultiMap<Symbol, Rule>()

  /// The lhsIndex of all right-recursive rules.
  private var rightRecursive: Set<Rule.ID> = []
}

extension Grammar {
  typealias SymbolString = LazyMapSequence<Range<RuleStore.Index>, Symbol>

  /// A suffix of a grammar rule's RHS, from which the rule's LHS symbol can also be identified.
  struct DottedRule: Hashable {
    var postdotIndices: Range<RuleStore.Index>
  }
}

extension Grammar.DottedRule {
  var lhsIndex: Grammar.RuleStore.Index { postdotIndices.upperBound }
  var postdotIndex: Grammar.RuleStore.Index? { postdotIndices.first }
  var postdotCount: Int { postdotIndices.count }
  var advanced: Self {
    Self(postdotIndices: postdotIndices.dropFirst())
  }
  var ruleID: Grammar.Rule.ID { .init(lhsIndex: lhsIndex) }
  var isComplete: Bool { postdotIndices.isEmpty }
}

extension Grammar.Rule {
  var lhsIndex: Grammar.RuleStore.Index { rhsIndices.upperBound }
  var id: ID { .init(lhsIndex: lhsIndex) }
  var dotted: Grammar.DottedRule { .init(postdotIndices: rhsIndices) }
  var rhsCount: Int { rhsIndices.count }
}

extension Grammar.Symbol {
  /// `true` iff this symbol derives 𝝐 and only 𝝐
  var isNulling: Bool {
    if case .null = self { return true } else { return false }
  }

  var raw: RawSymbol {
    switch self { case let .some(r), let .null(r): return r }
  }

  mutating func makeNull() {
    self = .null(raw)
  }
}

extension Grammar.Symbol: CustomStringConvertible {
  var description: String {
    switch self {
    case let .some(r): return "\(r)"
    case let .null(r): return "\(r)𝜀"
    }
  }
}

extension Grammar {
  /// The rules for a given LHS symbol.
  typealias Alternatives = [Rule]

  /// Returns the right-hand side alternatives for lhs, or an empty collection if lhs is a terminal.
  func alternatives(_ lhs: Symbol) -> Alternatives { rulesByLHS[lhs] }

  /// Returns the LHS symbol for the rule corresponding to `t`.
  func lhs(_ t: DottedRule) -> Symbol { ruleStore[t.lhsIndex] }

  /// Returns the LHS symbol for the rule corresponding to `t`.
  func lhs(_ t: Rule) -> Symbol { ruleStore[t.lhsIndex] }

  /// Returns the next expected symbol of `t`, .
  func postdot(_ t: DottedRule) -> Symbol? { ruleStore[t.postdotIndices].first }

  init<RawRules: Collection, RHS: Collection>(_ rawRules: RawRules)
    where RawRules.Element == (lhs: RawSymbol, rhs: RHS), RHS.Element == RawSymbol
  {
    for (s, rhs) in rawRules {
      let start = ruleStore.count
      ruleStore.append(contentsOf: rhs.lazy.map { s in .some(s) } )
      let r = Rule(rhsIndices: start..<ruleStore.endIndex)
      ruleStore.append(.some(s))
      rulesByLHS[.some(s)].append(r)
    }

    // Put the grammar in nihilist normal form (NNF), per Aycock and Horspool
    enterNihilistNormalForm()
    findRightRecursions()
  }

  mutating func enterNihilistNormalForm() {
    var rulesByRHS = MultiMap<Symbol, Rule>()
    for rules in rulesByLHS.values {
      for r in rules {
        for s in rhs(r) { rulesByRHS[s].append(r) }
      }
    }

    let (nullable, nulling) = discoverNulls(rulesByRHS: rulesByRHS)
    
    // First the nulling symbols
    for s in nulling {
      let firstRule = rulesByLHS[s].first!
      rulesByLHS.removeKey(s)
      // Change the LHS symbol
      let nullS = Symbol.null(s.raw)
      ruleStore[firstRule.lhsIndex] = nullS
      // Register it in the new place
      rulesByLHS[nullS].append(firstRule)
    }

    // Then the rules with nullable symbols on the RHS
    let rulesToClone
      = Set(nullable.lazy.map { s in rulesByRHS[s] }.joined())

    for r in rulesToClone {
      clone(r, forNullablesStartingAt: 0)
    }

    func clone(_ r: Rule, forNullablesStartingAt n: Int) {
      // TODO: consider eliminating recursion
      for i in n..<r.rhsCount where nullable.contains(rhs(r).nth(i)) {
        // Reserve storage so we can safely insert from a pointer into self.
        ruleStore.amortizedLinearReserveCapacity(ruleStore.count + r.rhsCount + 1)

        // Grab the buffer pointer.
        let src = ruleStore.withUnsafeBufferPointer { b in b }

        // Copy the symbols, remembering where they went.
        let cloneStart = ruleStore.count
        ruleStore.append(contentsOf: src[r.rhsIndices.lowerBound...r.rhsIndices.upperBound])

        // Replace the ith one with its nulling version.
        ruleStore[cloneStart + i] = .null(rhs(r).nth(i).raw)

        // Register the new rule.
        let r1 = Rule(rhsIndices: cloneStart..<(ruleStore.count - 1))
        rulesByLHS[lhs(r1)].append(r1)

        // Be sure to clone again for any remaining nulling symbols in the clone.
        clone(r1, forNullablesStartingAt: i + 1)
      }
    }
  }

  func discoverNulls(rulesByRHS: MultiMap<Symbol, Rule>)
    -> (nullable: Set<Symbol>, nulling: Set<Symbol>)
  {
    var nullable = Set<Symbol>()
    var nulling = Set<Symbol>()
    for (s, alternatives) in rulesByLHS.storage {
      let x = alternatives.satisfaction { r in r.rhsCount == 0 }
      if x == .all { discoverNulling(s) }
      else if x != .none { discoverNullable(s) }
    }

    func discoverNulling(_ s: Symbol) {
      if !nullable.contains(s) { discoverNullable(s) }
      nulling.insert(s)
      for r in rulesByRHS[s] {
        let s0 = self.lhs(r)
        if nulling.contains(s0) { continue }
        if rulesByLHS[s0]
             .allSatisfy({ r in rhs(r).allSatisfy(nulling.contains) })
        {
          discoverNulling(s0)
        }
      }
    }

    func discoverNullable(_ s: Symbol) {
      nullable.insert(s)
      for r in rulesByRHS[s] {
        let s0 = lhs(r)
        if !nullable.contains(s0) && rhs(r).allSatisfy(nullable.contains) {
          discoverNullable(s0)
        }
      }
    }
    return (nullable, nulling)
  }

  mutating func findRightRecursions() {
    for rules in rulesByLHS.values {
      for r in rules {
        if computeIsRightRecursive(r) { rightRecursive.insert(r.id) }
      }
    }
  }
}

/// Leo support
extension Grammar {
  // Note: UNUSED
  /// Returns `true` iff `s` is a terminal symbol.
  func isTerminal(_ s: Symbol) -> Bool { return alternatives(s).isEmpty }

  /// Returns the RHS symbols of `x` that have yet to be recognized.
  func postdotRHS(_ x: DottedRule) -> SymbolString {
    x.postdotIndices.lazy.map { i in ruleStore[i] }
  }

  /// Returns the RHS symbols of `x`.
  func rhs(_ x: Rule) -> SymbolString { postdotRHS(x.dotted) }

  func rightmostNonNullingSymbol(_ r: Rule) -> Symbol? {
    rhs(r).last { s in !s.isNulling }
  }

  func computeIsRightRecursive(_ x: Rule) -> Bool {
    guard let rnn = rightmostNonNullingSymbol(x) else {
      return false
    }
    if lhs(x) == rnn { return true }
    var visited: Set<Symbol> = []
    var q: Set<Symbol> = [rnn]

    while let s = q.popFirst() {
      visited.insert(s)
      for r in alternatives(s) {
        guard let rnn = rightmostNonNullingSymbol(r) else { continue }
        if rnn == lhs(x) { return true }
        if !visited.contains(rnn) { q.insert(rnn) }
      }
    }
    return false
  }

  func penult(_ x: DottedRule) -> Symbol? {
    guard let next = postdot(x) else { return nil }
    return !next.isNulling && postdotRHS(x.advanced).allSatisfy { s in s.isNulling }
      ? next : nil
  }

  func isRightRecursive(_ x: DottedRule) -> Bool {
    rightRecursive.contains(x.ruleID)
  }
}

extension Grammar {
  func description(_ x: DottedRule) -> String {
    var r = "\(lhs(x)) ->\t"
    let fullRule = alternatives(lhs(x)).first { $0.id == x.ruleID }!
    var toPrint = fullRule.rhsIndices
    if toPrint.isEmpty { r += "•" }
    while let i = toPrint.popFirst() {
      r += "\(ruleStore[i]) "
      if toPrint.count == x.postdotCount { r += "• " }
    }
    return r
  }
}
// typealias SourcePosition = Int
