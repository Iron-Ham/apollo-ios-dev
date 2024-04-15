import Foundation
#if !COCOAPODS
import ApolloAPI
#endif

/// A `GraphQLQueryWatcher` is responsible for watching the store, and calling the result handler with a new result whenever any of the data the previous result depends on changes.
///
/// NOTE: The store retains the watcher while subscribed. You must call `cancel()` on your query watcher when you no longer need results. Failure to call `cancel()` before releasing your reference to the returned watcher will result in a memory leak.
public final class GraphQLQueryWatcher<Query: GraphQLQuery>: Cancellable, ApolloStoreSubscriber {
  weak var client: ApolloClientProtocol?
  public let query: Query
  let resultHandler: GraphQLResultHandler<Query.Data>

  private let callbackQueue: DispatchQueue

  private let contextIdentifier = UUID()
  private let context: RequestContext?
  private let debouncer: Debounce?

  private class WeakFetchTaskContainer {
    weak var cancellable: Cancellable?
    var cachePolicy: CachePolicy?

    fileprivate init(_ cancellable: Cancellable?, _ cachePolicy: CachePolicy?) {
      self.cancellable = cancellable
      self.cachePolicy = cachePolicy
    }
  }

  @Atomic private var fetching: WeakFetchTaskContainer = .init(nil, nil)

  @Atomic private var dependentKeys: Set<CacheKey>? = nil

  /// Designated initializer
  ///
  /// - Parameters:
  ///   - client: The client protocol to pass in.
  ///   - query: The query to watch.
  ///   - context: [optional] A context that is being passed through the request chain. Defaults to `nil`.
  ///   - callbackQueue: The queue for the result handler. Defaults to the main queue.
  ///   - resultHandler: The result handler to call with changes.
  public init(
    client: ApolloClientProtocol,
    query: Query,
    context: RequestContext? = nil,
    callbackQueue: DispatchQueue = .main,
    debounceTimeInterval: TimeInterval = 0.5,
    resultHandler: @escaping GraphQLResultHandler<Query.Data>
  ) {
    self.client = client
    self.query = query
    self.resultHandler = resultHandler
    self.callbackQueue = callbackQueue
    self.context = context
    if debounceTimeInterval > .zero {

    }

    self.debouncer = debounceTimeInterval > .zero
      ? Debounce(timeInterval: debounceTimeInterval)
      : nil

    client.store.subscribe(self)
  }

  /// Refetch a query from the server.
  public func refetch(cachePolicy: CachePolicy = .fetchIgnoringCacheData) {
    fetch(cachePolicy: cachePolicy)
  }

  func fetch(cachePolicy: CachePolicy) {
    $fetching.mutate {
      // Cancel anything already in flight before starting a new fetch
      $0.cancellable?.cancel()
      $0.cachePolicy = cachePolicy
      $0.cancellable = client?.fetch(query: query, cachePolicy: cachePolicy, contextIdentifier: self.contextIdentifier, context: self.context, queue: callbackQueue) { [weak self] result in
        guard let self = self else { return }

        switch result {
        case .success(let graphQLResult):
          self.$dependentKeys.mutate {
            $0 = graphQLResult.dependentKeys
          }
        case .failure:
          break
        }

        self.debounce(result: result)
      }
    }
  }

  func debounce(result: Result<GraphQLResult<Query.Data>, Error>) {
    if let debouncer {
      debouncer.queue { [weak self] in
        self?.resultHandler(result)
      }
    } else {
      resultHandler(result)
    }
  }

  /// Cancel any in progress fetching operations and unsubscribe from the store.
  public func cancel() {
    fetching.cancellable?.cancel()
    client?.store.unsubscribe(self)
  }

  public func store(_ store: ApolloStore,
                    didChangeKeys changedKeys: Set<CacheKey>,
                    contextIdentifier: UUID?) {
    if
      let incomingIdentifier = contextIdentifier,
      incomingIdentifier == self.contextIdentifier {
      // This is from changes to the keys made from the `fetch` method above,
      // changes will be returned through that and do not need to be returned
      // here as well.
      return
    }

    guard let dependentKeys = self.dependentKeys else {
      // This query has nil dependent keys, so nothing that changed will affect it.
      return
    }

    if !dependentKeys.isDisjoint(with: changedKeys) {
      // First, attempt to reload the query from the cache directly, in order not to interrupt any in-flight server-side fetch.
      store.load(self.query) { [weak self] result in
        guard let self = self else { return }

        switch result {
        case .success(let graphQLResult):
          self.callbackQueue.async { [weak self] in
            guard let self = self else {
              return
            }

            self.$dependentKeys.mutate {
              $0 = graphQLResult.dependentKeys
            }
            self.debounce(result: result)
          }
        case .failure:
          if self.fetching.cachePolicy != .returnCacheDataDontFetch {
            // If the cache fetch is not successful, for instance if the data is missing, refresh from the server.
            self.fetch(cachePolicy: .fetchIgnoringCacheData)
          }
        }
      }
    }
  }
}

private final class Debounce {
  let timeInterval: TimeInterval

  // using a timer avoids runloop execution on UITrackingRunLoopMode
  // which will prevent UI updates during interaction
  var timer: Timer?
  var block: (() -> Void)?

  init(timeInterval: TimeInterval) {
    self.timeInterval = timeInterval
  }

  func cancel() {
    timer?.invalidate()
    block = nil
  }

  func queue(block: @escaping () -> Void) {
    self.block = block
    self.timer?.invalidate()
    let timer = Timer(timeInterval: timeInterval, repeats: false, block: { [weak self] _ in
      self?.block?()
      self?.block = nil
    })
    self.timer = timer
    RunLoop.current.add(timer, forMode: .default)
  }
}
