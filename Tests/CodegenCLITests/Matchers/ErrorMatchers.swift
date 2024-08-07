import Foundation
import Nimble
@testable import ArgumentParser

public func throwUserValidationError(
  _ expectedError: ValidationError
) -> Nimble.Matcher<any ParsableCommand> {
  return Matcher { actualExpression in
    var actualError: (any Error)?
    do {
      _ = try actualExpression.evaluate()
    } catch {
      actualError = error
    }

    guard let actualError = actualError else {
      return MatcherResult(
        status: .fail,
        message: .fail("No error was thrown!")
      )
    }

    guard
      let commandError = actualError as? CommandError,
      case let ParserError.userValidationError(parserError) = commandError.parserError,
      let validationError = parserError as? ValidationError,
      validationError.message == expectedError.message
    else {
      return MatcherResult(
        status: .fail,
        message: .expectedTo(
          "equal ValidationError(\"\(expectedError.self)\"), got \(actualError)"
        )
      )
    }

    return MatcherResult(
      status: .matches,
      message: .expectedTo("be equal")
    )
  }
}

public func throwUnknownOptionError() -> Nimble.Matcher<any ParsableCommand> {
  return Matcher { actualExpression in
    var actualError: (any Error)?
    do {
      _ = try actualExpression.evaluate()
    } catch {
      actualError = error
    }

    guard let actualError = actualError else {
      return MatcherResult(
        status: .fail,
        message: .fail("No error was thrown!")
      )
    }

    guard
      let commandError = actualError as? CommandError,
      case ParserError.unknownOption = commandError.parserError
    else {
      return MatcherResult(
        status: .fail,
        message: .expectedTo("equal UnknownOption(), got \(actualError)")
      )
    }

    return MatcherResult(
      status: .matches,
      message: .expectedTo("be equal")
    )
  }
}

public func throwError(
  localizedDescription: String,
  ignoringExtraCharacters: Bool = false
) -> Nimble.Matcher<Any> {
  return Matcher { actualExpression in
    var actualError: (any Error)?
    do {
      _ = try actualExpression.evaluate()
    } catch {
      actualError = error
    }

    guard let actualError = actualError else {
      return MatcherResult(
        status: .fail,
        message: .fail("No error was thrown!")
      )
    }

    if ignoringExtraCharacters {
      if !actualError.localizedDescription.starts(with: localizedDescription) {
        return MatcherResult(
          status: .doesNotMatch,
          message: .expectedTo(
            "start with \"\(localizedDescription)\", got \"\(actualError.localizedDescription)\""
          )
        )
      }
    } else {
      if !(actualError.localizedDescription == localizedDescription) {
        return MatcherResult(
          status: .doesNotMatch,
          message: .expectedTo(
            "equal \"\(localizedDescription)\", got \"\(actualError.localizedDescription)\""
          )
        )
      }
    }

    return MatcherResult(
      status: .matches,
      message: .expectedTo("be equal")
    )
  }
}
