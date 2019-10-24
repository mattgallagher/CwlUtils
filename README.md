# CwlUtils

A collection of utilities written as part of articles on [Cocoa with Love](https://www.cocoawithlove.com)

## Included functionality

The following features are included in the library.

* [CwlStackFrame.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlStackFrame.swift) from [Better stack traces in Swift](https://cocoawithlove.com/blog/2016/02/28/stack-traces-in-swift.html)
* [CwlSysctl.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlSysctl.swift) from [Gathering system information in Swift with sysctl](https://www.cocoawithlove.com/blog/2016/03/08/swift-wrapper-for-sysctl.html)
* [CwlUnanticipatedError.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlUnanticipatedError.swift) from [Presenting unanticipated errors to users](https://www.cocoawithlove.com/blog/2016/04/14/error-recovery-attempter.html)
* [CwlScalarScanner.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlScalarScanner.swift) from [Swift name demangling: C++ vs Swift for parsing](https://www.cocoawithlove.com/blog/2016/05/01/swift-name-demangling.html)
* [CwlRandom.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlRandom.swift) from [Random number generators in Swift](https://www.cocoawithlove.com/blog/2016/05/19/random-numbers.html)
* [CwlMutex.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlMutex.swift) from [Mutexes and closure capture in Swift](https://www.cocoawithlove.com/blog/2016/06/02/threads-and-mutexes.html)
* [CwlDispatch.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDispatch.swift) from [Design patterns for safe timer usage](https://www.cocoawithlove.com/blog/2016/07/30/timer-problems.html)
* [CwlResult.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlResult.swift) from [Values and errors, part 1: 'Result' in Swift](https://www.cocoawithlove.com/blog/2016/08/21/result-types-part-one.html)
* [CwlDeque.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDeque.swift) from [Optimizing a copy-on-write double-ended queue in Swift](https://www.cocoawithlove.com/blog/2016/09/22/deque.html)
* [CwlExec.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlExec.swift) from [Specifying function execution contexts](https://www.cocoawithlove.com/blog/specifying-execution-contexts.html)
* [CwlDebugContext.swift](https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlDebugContext.swift) from [Testing actions over time](https://www.cocoawithlove.com/blog/testing-actions-over-time.html)

## Adding to your project

The CwlUtils library requires the [Swift Package Manager](#swift-package-manager). Minimum requirements are iOS 8 or macOS 10.10 and Swift 5.0.

Add the following to the `dependencies` array in your "Package.swift" file:

	.package(url: "https://github.com/mattgallagher/CwlUtils.git", from: Version(3, 0, 0)),

> NOTE: even though this git repository includes its dependencies in the Dependencies folder, building via the Swift Package manager fetches and builds these dependencies independently.

## CocoaPods and Carthage

Up to version 2.2.1, this library supported CocoaPods and Carthage. If you wish to use these package managers, you can check out the [CwlUtils 2.2.1 tag](https://github.com/mattgallagher/CwlUtils/releases/tag/2.2.1)
