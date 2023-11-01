extension CursorBasedPagination {
  public struct BidirectionalPagination: PaginationInfo, Hashable {
    public let hasNext: Bool
    public let endCursor: String?
    public let hasPrevious: Bool
    public let startCursor: String?

    public var canLoadMore: Bool { hasNext }
    public var canLoadPrevious: Bool { hasPrevious }

    public init(
      hasNext: Bool,
      endCursor: String?,
      hasPrevious: Bool,
      startCursor: String?
    ) {
      self.hasNext = hasNext
      self.endCursor = endCursor
      self.hasPrevious = hasPrevious
      self.startCursor = startCursor
    }
  }
}
