import Apollo
import ApolloAPI
import Combine

public protocol PagerType {
  associatedtype InitialQuery: GraphQLQuery
  associatedtype PaginatedQuery: GraphQLQuery

  var canLoadNext: Bool { get }
  var canLoadPrevious: Bool { get }
  func cancel()
  func loadPrevious(
    cachePolicy: CachePolicy,
    completion: ((Error?) -> Void)?
  )
  func loadNext(
    cachePolicy: CachePolicy,
    completion: ((Error?) -> Void)?
  )
  func loadAll(
    fetchFromInitialPage: Bool,
    completion: ((Error?) -> Void)?
  )
  func refetch(cachePolicy: CachePolicy)
  func fetch()
}

/// Handles pagination in the queue by managing multiple query watchers.
public class GraphQLQueryPager<InitialQuery: GraphQLQuery, PaginatedQuery: GraphQLQuery>: PagerType {

  private actor Subscriptions {
    var subscriptions: Set<AnyCancellable> = []

    func store(subscription: AnyCancellable) {
      subscriptions.insert(subscription)
    }
  }

  private class Completion {
    var completion: ((Error?) -> Void)?

    init(completion: ((Error?) -> Void)?) {
      self.completion = completion
    }

    func execute(error: Error?) async {
      await MainActor.run { [weak self] in
        self?.completion?(error)
        self?.completion = nil
      }
    }
  }

  private actor CompletionManager {
    var completions: [Completion] = []

    func append(completion: Completion) {
      completions.append(completion)
    }

    func reset() {
      completions.removeAll()
    }

    func execute(completion: Completion, with error: Error?) async {
      await completion.execute(error: error)
    }

    deinit {
      completions.forEach { $0.completion?(PaginationError.cancellation) }
    }
  }

  private let pager: Actor
  private var subscriptions = Subscriptions()
  private var completions = CompletionManager()

  public init<P: PaginationInfo>(
    client: ApolloClientProtocol,
    initialQuery: InitialQuery,
    extractPageInfo: @escaping (PageExtractionData) -> P,
    pageResolver: ((P, PaginationDirection) -> PaginatedQuery?)?
  ) {
    pager = .init(
      client: client,
      initialQuery: initialQuery,
      extractPageInfo: extractPageInfo,
      pageResolver: pageResolver
    )
    Task { [weak self] in
      guard let self else { return }
      let (previousPageVarMapPublisher, initialPublisher, nextPageVarMapPublisher) = await pager.publishers
      let publishSubscriber = previousPageVarMapPublisher.combineLatest(
        initialPublisher,
        nextPageVarMapPublisher
      ).sink { [weak self] _ in
        guard !Task.isCancelled else { return }
        Task { [weak self] in
          guard let self else { return }
          let (canLoadNext, canLoadPrevious) = await self.pager.canLoadPages
          self.canLoadNext = canLoadNext
          self.canLoadPrevious = canLoadPrevious
        }
      }
      await subscriptions.store(subscription: publishSubscriber)
    }
  }

  /// Convenience initializer, internal only.
  /// - Parameter pager: An `Actor`.
  init(pager: Actor) {
    self.pager = pager
  }

  /// Allows the caller to subscribe to new pagination results.
  /// - Parameter onUpdate: A closure which provides the most recent pagination result. This closure is guaruanteed to be dispatched to the `MainActor`
  public func subscribe(onUpdate: @MainActor @escaping (Result<Output, Error>) -> Void) {
    Task { [weak self] in
      guard let self else { return }
      let subscription = await self.pager.subscribe(onUpdate: onUpdate)
      await subscriptions.store(subscription: subscription)
    }
  }

  /// Whether or not we can load the next page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadNext: Bool = false
  /// Whether or not we can load the previous page. Initializes with a `false` value that is updated after the initial fetch.
  public var canLoadPrevious: Bool = false

  /// Reset all pagination state and cancel all in-flight requests.
  public func cancel() {
    Task { [weak self] in
      guard let self else { return }
      for completion in await self.completions.completions {
        await completion.execute(error: PaginationError.cancellation)
      }
      await self.completions.reset()
      await self.pager.cancel()
    }
  }

  /// Loads the previous page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadPrevious(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: ((Error?) -> Void)? = nil
  ) {
    execute(completion: completion) { [weak self] in
      try await self?.pager.loadPrevious(cachePolicy: cachePolicy)
    }
  }

  /// Loads the next page, if we can.
  /// - Parameters:
  ///   - cachePolicy: The Apollo `CachePolicy` to use. Defaults to `fetchIgnoringCacheData`.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadNext(
    cachePolicy: CachePolicy = .fetchIgnoringCacheData,
    completion: ((Error?) -> Void)? = nil
  ) {
    execute(completion: completion) { [weak self] in
      try await self?.pager.loadNext(cachePolicy: cachePolicy)
    }
  }

  /// Loads all pages.
  /// - Parameters:
  ///   - fetchFromInitialPage: Pass true to begin loading from the initial page; otherwise pass false.  Defaults to `true`.  **NOTE**: Loading all pages with this value set to `false` requires that the initial page has already been loaded previously.
  ///   - completion: An optional error closure that triggers in the event of an error. Defaults to `nil`.
  public func loadAll(fetchFromInitialPage: Bool = true, completion: ((Error?) -> Void)? = nil) {
    execute(completion: completion) { [weak self] in
      try await self?.pager.loadAll(fetchFromInitialPage: fetchFromInitialPage)
    }
  }

  /// Discards pagination state and fetches the first page from scratch.
  /// - Parameter cachePolicy: The apollo cache policy to trigger the first fetch with. Defaults to `fetchIgnoringCacheData`.
  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
    Task {
      for completion in await self.completions.completions {
        await completion.execute(error: PaginationError.cancellation)
      }
      await pager.refetch(cachePolicy: cachePolicy)
    }
  }

  /// Fetches the first page.
  public func fetch() {
    Task {
      await pager.fetch()
    }
  }

  private func execute(completion: ((Error?) -> Void)?, operation: @escaping () async throws -> Void) {
    Task<_, Never> { [weak self] in
      let completionHandler = Completion(completion: completion)
      await self?.completions.append(completion: completionHandler)
      do {
        try await operation()
        await self?.completions.execute(completion: completionHandler, with: nil)
      } catch {
        await self?.completions.execute(completion: completionHandler, with: error)
      }
    }
  }
}
