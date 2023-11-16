import IR
import GraphQLCompiler

public struct OperationDescriptor: Sendable {
  public enum OperationType: String, Hashable {
    case query
    case mutation
    case subscription
  }

  public enum SourceFormat {
    /// The source text for the operation formatted exactly as it will be sent via network
    /// transport when executed by an `ApolloClient`. This value should be used to calculate
    /// the operation identifier for a persisted queries manifest.
    ///
    /// This format includes:
    /// - The operation's source, minimized to a single line
    /// - The source of each fragment referenced by the operation, each minimized to a
    ///   single line. There will be a `\n` character between the operation and each
    ///   fragment.
    case rawSource

    /// The source text formatted for inclusion as the "body" field in a JSON object
    /// written into a `OperationManifestTemplate`. It provides the
    /// exact data that will be sent by the Apollo network transport when the
    /// operation is executed in a format that can be written to a file.
    ///
    /// This escapes the newline characters between fragments.
    case manifestJSONBody
  }

  let underlyingDefinition: CompilationResult.OperationDefinition

  public var name: String { underlyingDefinition.name }

  public var filePath: String { underlyingDefinition.filePath }

  public var type: OperationType {
    guard let type = OperationType(rawValue: underlyingDefinition.operationType.rawValue) else {
      preconditionFailure("Unknown GraphQL operation type: \(underlyingDefinition.operationType.rawValue)")
    }
    return type
  }

  /// The source text for the operation formatted exactly as it will be sent via network
  /// transport when executed by an `ApolloClient`. This value should be used to calculate
  /// the operation identifier for a persisted queries manifest.
  ///
  /// This format includes:
  /// - The operation's source, minimized to a single line
  /// - The source of each fragment referenced by the operation, each minimized to a
  ///   single line. There will be a `\n` character between the operation and each
  ///   fragment.
  public var rawSourceText: String {
    sourceText(withFormat: .rawSource)
  }

  // MARK: - Internal

  init(_ operation: CompilationResult.OperationDefinition) {
    self.underlyingDefinition = operation
  }

  func sourceText(withFormat format: SourceFormat) -> String {
    format.formatted(self)
  }

  fileprivate var allReferencedFragments: [CompilationResult.FragmentDefinition] {
    func insertAllFragments(
      from fragment: CompilationResult.FragmentDefinition,
      into set: inout Set<CompilationResult.FragmentDefinition>
    ) {
      set.insert(fragment)
      for referencedFragment in fragment.referencedFragments {
        insertAllFragments(from: referencedFragment, into: &set)
      }
    }

    var fragmentSet = Set<CompilationResult.FragmentDefinition>()
    for fragment in underlyingDefinition.referencedFragments {
      insertAllFragments(from: fragment, into: &fragmentSet)
    }
    return fragmentSet.sorted { $0.name < $1.name }
  }

}

// MARK: - Formatting

fileprivate extension OperationDescriptor.SourceFormat {
  func formatted(_ operation: OperationDescriptor) -> String {
    var source = operation.underlyingDefinition.source.convertedToSingleLine()
    for fragment in operation.allReferencedFragments {
      source += formatted(fragment)
    }

    switch self {
    case .rawSource:
      return source
    case .manifestJSONBody:
      return source.replacingOccurrences(of: #"""#, with: #"\""#)
    }
  }

  private func formatted(_ fragment: CompilationResult.FragmentDefinition) -> String {
    switch self {
    case .rawSource:
      return "\n\(fragment.source.convertedToSingleLine())"

    case .manifestJSONBody:
      return #"\n\#(fragment.source.convertedToSingleLine())"#
    }
  }
}
