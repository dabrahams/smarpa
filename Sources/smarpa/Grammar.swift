enum AllSomeNone { case all, some, none }

extension Collection {
  /// Returns an indication of whether all, some, or no elements satisfy `predicate`.
  func whichSatisfy(_ predicate: (Element)->Bool) -> AllSomeNone {
    guard let i = firstIndex(where: predicate) else { return .none }
    if i == startIndex && dropFirst().allSatisfy(predicate) { return .all }
    return .some
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
  private let ruleStore: [Symbol]

  /// A suffix of a grammar rule's RHS, from which the rule's LHS symbol can also be identified.
  typealias PartialRule = Range<RuleStore.Index>

  /// The right-hand side alternatives for each nonterminal symbol.
  private let rulesByLHS: MultiMap<Symbol, PartialRule>
}

extension Grammar.Symbol {
  /// `true` iff this symbol derives 𝝐 and only 𝝐
  var isNull: Bool {
    if case .null = self { return true } else { return false }
  }

  var raw: RawSymbol {
    switch self { case let .some(r), let .null(r): return r }
  }

  /// Returns the other version of `self`.
  var togglingNull: Self {
    switch self {
    case let .some(r): return .null(r)
    case let .null(r): return .some(r)
    }
  }
}

extension Grammar {
  /// The rules for a given LHS symbol.
  typealias Alternatives = [PartialRule]

  /// Returns the right-hand side alternatives for lhs, or an empty collection if lhs is a terminal.
  func alternatives(_ lhs: Symbol) -> Alternatives { rulesByLHS[lhs] }

  /// Returns `true` iff `rhs` is empty.
  func isComplete(_ rhs: PartialRule) -> Bool { rhs.isEmpty }

  /// Returns the LHS symbol for the rule corresponding to `t`.
  func lhs(_ t: PartialRule) -> Symbol { ruleStore[t.upperBound] }

  /// Returns the next expected symbol of `t`, .
  func postdot(_ t: PartialRule) -> Symbol? { ruleStore[t].first }

  init<RawRules: Collection, RHS: Collection>(_ rawRules: RawRules)
    where RawRules.Element == (lhs: RawSymbol, rhs: RHS), RHS.Element == RawSymbol
  {
    var rulesByLHS = MultiMap<Symbol, PartialRule>()
    var rulesByRHS = MultiMap<Symbol, PartialRule>()

    var ruleStore: [Symbol] = []
    for (lhs, rhs) in rawRules {
      let start = ruleStore.count
      ruleStore.append(contentsOf: rhs.lazy.map { s in .some(s) } )
      let r = start..<ruleStore.endIndex
      ruleStore.append(.some(lhs))

      rulesByLHS[.some(lhs)].append(r)
      for s in rhs { rulesByRHS[.some(s)].append(r) }
    }
    self.ruleStore = ruleStore

    var nullable = Set<Symbol>()
    var nulling = Set<Symbol>()
    for (lhs, alternatives) in rulesByLHS.storage {
      let x = alternatives.whichSatisfy { $0.isEmpty }
      if x == .all { discoverNulling(lhs) }
      else if x != .none { discoverNullable(lhs) }
    }

    func discoverNulling(_ s: Symbol) {
      discoverNullable(s)
      nulling.insert(s)
      for r in rulesByRHS[s] {
        let lhs = ruleStore[r.upperBound]
        if nulling.contains(lhs) { continue }
        if rulesByLHS[lhs]
             .allSatisfy({ r in ruleStore[r].allSatisfy(nulling.contains) })
        {
          discoverNulling(lhs)
        }
      }
    }
    
    func discoverNullable(_ s: Symbol) {
      nullable.insert(s)
      for r in rulesByRHS[s] {
        let lhs = ruleStore[r.upperBound]
        if !nullable.contains(lhs) && ruleStore[r].allSatisfy(nullable.contains) {
          discoverNullable(lhs)
        }
      }
    }

    // Put the grammar in nihilist normal form (NNF), per Aycock and Horspool
    
    // First the nulling symbols
    for s in nulling {
      let firstRule = rulesByLHS[s].first!
      rulesByLHS.removeKey(s)
      // Change the LHS symbol
      let nullS = Symbol.null(s.raw)
      ruleStore[firstRule.upperBound] = nullS
      // Register it in the new place
      rulesByLHS[nullS].append(firstRule)
    }

    // Then the rules with nullable symbols on the RHS
    let rulesToClone
      = Set(nullable.lazy.map { s in rulesByRHS[s] }.joined())

    for r in rulesToClone {
      clone(r, forNullablesStartingAt: r.startIndex)
    }
    
    func clone(_ r: PartialRule, forNullablesStartingAt i_: PartialRule.Index) {
      var i = i_
      while let j = r[i...].first(where: { j in nullable.contains(ruleStore[j]) }) {
        let tmp = ruleStore[r][..<j] + ruleStore[r][j+1...r.upperBound]
        let r1Start = ruleStore.count
        ruleStore.append(contentsOf: tmp)
        let r1 = r1Start..<ruleStore.count - 1
        rulesByLHS[ruleStore.last!].append(r1)
        clone(r1, forNullablesStartingAt: j - r.lowerBound)
        i = j + 1
      }
    }
    
    self.rulesByLHS = rulesByLHS
  }
}

extension Grammar {
  /// Returns `true` iff `s` is a terminal symbol.
  func isTerminal(_ s: Symbol) -> Bool { return alternatives(s).isEmpty }
  
  func postdotRHS(_ x: PartialRule) -> LazyMapSequence<PartialRule, Symbol> {
    x.lazy.map { s in ruleStore[s] }
  }

  var allRules: FlattenSequence<Dictionary<Symbol, [PartialRule]>.Values> {
    rulesByLHS.values.joined()
  }
}

// typealias SourcePosition = Int

typealias Grammar_<RawSymbol: Hashable> = Grammar<RawSymbol: Hashable>

/// A parse rule being matched.
struct Parser<RawSymbol>: CustomStringConvertible {
  typealias Grammar = Grammar_<RawSymbol>
  
  struct PartialParse: Hashable {
    /// The positions in ruleStore of yet-to-be recognized RHS symbols.
    var rule: Grammar.PartialRule

    /// The position in the token stream where the partially-parsed input begins.
    let start: SourcePosition

    init(expecting expected: Grammar.PartialRule, at start: SourcePosition) {
      self.rule = expected
      self.start = start
    }

    /// Returns `self`, having advanced the forward by one position.
    func advanced() -> Self { Self(expecting: rule.dropFirst(), at: start) }
  }

  /// Creates an instance for the given grammar.
  init(_ g: Grammar) {

  /// The grammar
  var g: Grammar { get }

  /// All the partial parses, grouped by earleme.
  var partials: [PartialParse] { get set }

  /// The position in `partials` where each earleme begins.
  var earlemeStart: [Array<PartialParse>.Index] { get set }

  mutating func reduce(_ p: PartialParse)
  mutating func inferenceHook(_ p: PartialParse)
}

public extension AnyEarleyParser {
  func postdot(_ p: PartialParse) -> Grammar.Symbol? { g.postdot(p.rule) }
  func lhs(_ p: PartialParse) -> Grammar.Symbol { g.lhs(p.rule) }
  func inferenceHook(_ p: PartialParse) {  }
}

public struct EarleyParser<Grammar: AnyEarleyGrammar>: AnyEarleyParser {
  /// Creates an instance for the given grammar.
  public init(_ g: Grammar) { self.g = g }

  /// A position in the input.
  public typealias SourcePosition = Int

  /// All the partial parses, grouped by earleme.
  public var partials: [PartialParse] = []

  /// The position in `partials` where each earleme begins.
  public var earlemeStart: [Array<PartialParse>.Index] = []

  /// The grammar
  public var g: Grammar
}

/// Initialization and algorithm.
extension AnyEarleyParser {
  /// Adds `p` to the latest earleme if it is not already there.
  mutating func insert(_ p: PartialParse) {
    if !partials[earlemeStart.last!...].contains(p) { partials.append(p) }
  }

  /// Recognizes the sequence of symbols in `source` as a parse of `start`.
  public mutating func recognize<Source: Collection>(_ source: Source, as start: Grammar.Symbol)
    where Source.Element == Grammar.Symbol
  {
    let n = source.count
    partials.removeAll(keepingCapacity: true)
    earlemeStart.removeAll(keepingCapacity: true)
    earlemeStart.reserveCapacity(n + 1)
    earlemeStart.append(0)

    for r in g.alternatives(start) {
      partials.append(PartialParse(expecting: r, at: 0))
    }

    // Recognize each token over its range in the source.
    var tokens = source.makeIterator()

    var i = 0 // The current earleme
    while i != earlemeStart.count {
      var j = earlemeStart[i] // The partial parse within the current earleme

      // predictions and completions
      while j < partials.count {
        let p = partials[j]
        if let s = postdot(p) { // predict
          for rhs in g.alternatives(s) {
            insert(PartialParse(expecting: rhs, at: i))
            if g.isNullable(s) { insert(p.advanced()) }
          }
        }
        else {
          reduce(p)
        }
        inferenceHook(p)
        j += 1
      }

      // scans
      if let t = tokens.next() {
        for j in partials[earlemeStart[i]...].indices {
          let p = partials[j]
          if postdot(p) == t {
            if earlemeStart.count == i + 1 { earlemeStart.append(partials.count) }
            insert(p.advanced())
          }
        }
      }
      i += 1
    }
  }

  public mutating func reduce(_ p: PartialParse) { earleyReduce(p) }

  mutating func earleyReduce(_ p: PartialParse) {
    var k = earlemeStart[p.start]
    // TODO: if we can prove the insert is a no-op when p.start == i, we
    // can simplify the loop.
    while k < (p.start == earlemeStart.count - 1 ? partials.count: earlemeStart[p.start + 1]) {
      let q = partials[k]
      if postdot(q) == lhs(p) { insert(q.advanced()) }
      k += 1
    }
  }
}

extension AnyEarleyParser {
  public var description: String {
    var lines: [String] = []
    var i = -1
    for j in partials.indices {
      if earlemeStart.count > i + 1 && j == earlemeStart[i + 1] {
        i += 1
        lines.append("\n=== \(i) ===")
      }
      lines.append(ruleString(partials[j]))
    }
    return lines.joined(separator: "\n")
  }

  func ruleString(_ p: PartialParse) -> String {
    var r = "\(lhs(p)) ->\t"
    var all = g.alternatives(lhs(p)).first { $0.endIndex == p.rule.endIndex }!
    while !g.isComplete(all) {
      if all.count == p.rule.count { r += "• " }
      r += "\(g.postdot(all)!) "
      _ = all.popFirst()
    }
    if p.rule.isEmpty { r += "•" }
    r += "\t(\(p.start))"
    return r
  }
}
*/