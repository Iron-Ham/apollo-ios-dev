// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "StarWarsAPI",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_14),
    .tvOS(.v12),
    .watchOS(.v5),
  ],
  products: [
    .library(name: "StarWarsAPI", targets: ["StarWarsAPI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apollographql/apollo-ios", exact: "1.16.1"),
  ],
  targets: [
    .target(
      name: "StarWarsAPI",
      dependencies: [
        .product(name: "ApolloAPI", package: "apollo-ios"),
      ],
      path: "./Sources"
    ),
  ]
)
