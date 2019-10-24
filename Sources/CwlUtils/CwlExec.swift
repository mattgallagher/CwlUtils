//
//  CwlExec.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2015/02/03.
//  Copyright © 2015 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any
//  purpose with or without fee is hereby granted, provided that the above
//  copyright notice and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
//  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
//  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
//  SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
//  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
//  IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

import Foundation

/// `Exec` is a representation of an arbitrary execution context and offers the ability to interrogate properties of the execution context or to invoke blocks within the context in a number of different ways. The base enum implements the three most common types of execution context in Swift. Switching over these pre-defined cases enables the caller to perform appropriate optimizations (e.g. avoiding calling `invoke` on Exec.direct).
///
/// - direct: the context will directly call any supplied block with no other action taken
/// - main: the context will invoke on the main thread, preferring synchronous invocation where possible.
/// - queue: the context will invoke on a DispatchQueue with details descrbied in the `ExecutionType`
/// - custom: a `CustomExecutionContext` handles all interrogation and invoking
public enum Exec {
	/// Invoked directly from the caller's context
	case direct
	
	/// Invoked on the main thread, directly if the current thread is the main thread, otherwise asynchronously (unless invokeSync is used)
	case main
	
	/// Invoked using a Dispatch Queue
	case queue(DispatchQueue, ExecutionType)
	
	/// Invoked using the wrapped existential.
	case custom(CustomExecutionContext)
}

public extension Exec {
	/// If this context is concurrent, returns a serialization around this context, otherwise returns this context.
	func serialized() -> Exec {
		return self.type.isConcurrent ? Exec.custom(SerializingContext(concurrentContext: self)) : self
	}
	
	/// Invoked on the main thread, always asynchronously (unless invokeSync is used)
	static var mainAsync: Exec {
		return .queue(.main, .threadAsync { Thread.isMainThread })
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_DEFAULT priority
	static var global: Exec {
		return .queue(.global(), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_DEFAULT priority
	static func global(qos: DispatchQoS.QoSClass) -> Exec {
		return .queue(.global(qos: qos), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_USER_INTERACTIVE priority
	static var interactive: Exec {
		return .queue(.global(qos: .userInteractive), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_USER_INITIATED priority
	static var user: Exec {
		return .queue(.global(qos: .userInitiated), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_UTILITY priority
	static var utility: Exec {
		return .queue(.global(qos: .utility), .concurrentAsync)
	}
	
	/// Invoked asynchronously in the global queue with QOS_CLASS_BACKGROUND priority
	static var background: Exec {
		return .queue(.global(qos: .background), .concurrentAsync)
	}
	
	/// Constructs an Exec.queue configured as an ExecutionType.recursiveMutex
	static func syncQueue(qos: DispatchQoS.QoSClass = .default) -> Exec {
		return Exec.queue(DispatchQueue(label: ""), ExecutionType.mutex)
	}
	
	/// Constructs an Exec.queue configured as an ExecutionType.recursiveAsync
	static func asyncQueue(qos: DispatchQoS.QoSClass = .default) -> Exec {
		return Exec.queue(DispatchQueue(label: ""), ExecutionType.serialAsync)
	}
}

extension Exec: CustomExecutionContext {
	/// A description about how functions will be invoked on an execution context.
	public var type: ExecutionType {
		switch self {
		case .direct: return .immediate
		case .main: return .thread { Thread.isMainThread }
		case .custom(let c): return c.type
		case .queue(_, let t): return t
		}
	}
	
	/// Run `execute` normally on the execution context
	public func invoke(_ execute: @escaping () -> Void) {
		switch self {
		case .direct: execute()
		case .main where Thread.isMainThread: execute()
		case .main: DispatchQueue.main.async(execute: execute)
		case .queue(_, .thread(let test)) where test(): execute()
		case .queue(_, .recursiveMutex(let test)) where test(): execute()
		case .queue(let q, let t) where t.isImmediateInCurrentContext: q.sync(execute: execute)
		case .queue(let q, _): q.async(execute: execute)
		case .custom(let c): c.invoke(execute)
		}
	}
	
	/// Run `execute` asynchronously on the execution context
	public func invokeAsync(_ execute: @escaping () -> Void) {
		switch self {
		case .direct: DispatchQueue.global().async(execute: execute)
		case .custom(let c): c.invokeAsync(execute)
		case .main: DispatchQueue.main.async(execute: execute)
		case .queue(let q, _): q.async(execute: execute)
		}
	}
	
	/// Run `execute` on the execution context but don't return from this function until the provided function is complete.
	public func invokeSync<Result>(_ execute: () throws -> Result) rethrows -> Result {
		switch self {
		case .direct: return try execute()
		case .main where Thread.isMainThread: return try execute()
		case .main: return try DispatchQueue.main.sync(execute: execute)
		case .queue(_, .thread(let test)) where test(): return try execute()
		case .queue(_, .threadAsync(let test)) where test(): return try execute()
		case .queue(_, .recursiveMutex(let test)) where test(): return try execute()
		case .queue(let q, _): return try withoutActuallyEscaping(execute) { e in try q.sync(execute: e) }
		case .custom(let c): return try c.invokeSync(execute)
		}
	}
	
	/// Invokes in a global concurrent context. This context can be used to safely "escape" self.
	///
	/// - Parameter qos: the QoSClass for the new async context. If `nil`, the QoSClass will be derived from the properties of `self`
	/// - Returns: a context that is asynchronous and can be used to escape self
	public func relativeAsync(qos: DispatchQoS.QoSClass? = nil) -> Exec {
		switch self {
		case .custom(let c): return c.relativeAsync(qos: qos)
		case .main: return Exec.global(qos: .userInteractive)
		case .queue(let q, _): return Exec.global(qos: q.qos.qosClass)
		case .direct: return Exec.global
		}
	}
	
	private var timerQueue: DispatchQueue {
		switch self {
		case .direct: return DispatchQueue.global()
		case .main: return DispatchQueue.main
		case .queue(let q, _): return q
		case .custom: fatalError()
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping () -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.singleTimer(interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.singleTimer(interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.singleTimer(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.singleTimer(parameter: parameter, interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping () -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.periodicTimer(interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.repeatingTimer(interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval = .nanoseconds(0), handler: @escaping (T) -> Void) -> Lifetime {
		if case .custom(let c) = self {
			return c.periodicTimer(parameter: parameter, interval: interval, leeway: leeway, handler: handler)
		}
		return DispatchSource.repeatingTimer(parameter: parameter, interval: interval, leeway: leeway, queue: timerQueue, handler: handler) as! DispatchSource
	}
	
	/// Gets a timestamp representing the host uptime the in the current context
	public func timestamp() -> DispatchTime {
		if case .custom(let c) = self {
			return c.timestamp()
		}
		return DispatchTime.now()
	}
}

public extension Exec {
	@available(*, deprecated, message: "Use invokeSync instead")
	func invokeAndWait(_ execute: @escaping () -> Void) {
        invokeSync(execute)
	}
	
	@available(*, deprecated, message:"Values returned from this may be misleading. Perform your own switch to precisely get the information you need.")
	var dispatchQueue: DispatchQueue {
		switch self {
		case .direct, .custom: return DispatchQueue.global()
		case .main: return DispatchQueue.main
		case .queue(let q, _): return q
		}
	}
}
