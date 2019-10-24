//
//  CwlSerializingContext.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 19/1/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose with or without
//  fee is hereby granted, provided that the above copyright notice and this permission notice
//  appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS
//  SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
//  AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
//  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
//  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
//  OF THIS SOFTWARE.
//

import Foundation

/// An `ExecutionContext` wraps a mutex around calls invoked by an underlying execution context. The effect is to serialize concurrent contexts (immediate or concurrent).
public struct SerializingContext: CustomExecutionContext {
	public let underlying: Exec
	public let mutex = PThreadMutex(type: .recursive)
	
	public init(concurrentContext: Exec) {
		underlying = concurrentContext
	}
	
	public var type: ExecutionType {
		switch underlying.type {
		case .immediate: return .mutex
		case .concurrentAsync: return .serialAsync
		case .mutex, .recursiveMutex, .thread, .threadAsync, .serialAsync: return underlying.type
		}
	}
	
	public func invoke(_ execute: @escaping () -> Void) {
		if case .direct = underlying {
			mutex.sync(execute: execute)
		} else {
			underlying.invoke { [mutex] in mutex.sync(execute: execute) }
		}
	}
	
	public func invokeAsync(_ execute: @escaping () -> Void) {
		underlying.invokeAsync { [mutex] in mutex.sync(execute: execute) }
	}
	
	@available(*, deprecated, message: "Use invokeSync instead")
	public func invokeAndWait(_ execute: @escaping () -> Void) {
		invokeSync(execute)
	}
	
	public func invokeSync<Return>(_ execute: () throws -> Return) rethrows -> Return {
		if case .direct = underlying {
			return try mutex.sync(execute: execute)
		} else {
			return try underlying.invokeSync { [mutex] () throws -> Return in try mutex.sync(execute: execute) }
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return mutex.sync { () -> Lifetime in
			let wrapper = MutexWrappedLifetime(mutex: mutex)
			let lifetime = underlying.singleTimer(interval: interval, leeway: leeway) { [weak wrapper] in
				if let w = wrapper {
					w.mutex.sync {
						// Need to perform this double check since the timer may have been cancelled/changed before we managed to enter the mutex
						if w.lifetime != nil {
							handler()
						}
					}
				}
			}
			wrapper.lifetime = lifetime
			return wrapper
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return mutex.sync { () -> Lifetime in
			let wrapper = MutexWrappedLifetime(mutex: mutex)
			let lifetime = underlying.singleTimer(parameter: parameter, interval: interval, leeway: leeway) { [weak wrapper] p in
				if let w = wrapper {
					w.mutex.sync {
						// Need to perform this double check since the timer may have been cancelled/changed before we managed to enter the mutex
						if w.lifetime != nil {
							handler(p)
						}
					}
				}
			}
			wrapper.lifetime = lifetime
			return wrapper
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		return mutex.sync { () -> Lifetime in
			let wrapper = MutexWrappedLifetime(mutex: mutex)
			let lifetime = underlying.periodicTimer(interval: interval, leeway: leeway) { [weak wrapper] in
				if let w = wrapper {
					w.mutex.sync {
						// Need to perform this double check since the timer may have been cancelled/changed before we managed to enter the mutex
						if w.lifetime != nil {
							handler()
						}
					}
				}
			}
			wrapper.lifetime = lifetime
			return wrapper
		}
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		return mutex.sync { () -> Lifetime in
			let wrapper = MutexWrappedLifetime(mutex: mutex)
			let lifetime = underlying.periodicTimer(parameter: parameter, interval: interval, leeway: leeway) { [weak wrapper] p in
				if let w = wrapper {
					w.mutex.sync {
						if w.lifetime != nil {
							handler(p)
						}
					}
				}
			}
			wrapper.lifetime = lifetime
			return wrapper
		}
	}
	
	/// Gets a timestamp representing the host uptime the in the current context
	public func timestamp() -> DispatchTime {
		return underlying.timestamp()
	}
}

/// A wrapper around Lifetime that applies a mutex on the cancel operation.
/// This is a class so that `SerializingContext` can pass it weakly to the timer closure, avoiding having the timer keep itself alive.
private class MutexWrappedLifetime: Lifetime {
	var lifetime: Lifetime? = nil
	let mutex: PThreadMutex
	
	init(mutex: PThreadMutex) {
		self.mutex = mutex
	}
	
	func cancel() {
		mutex.sync {
			lifetime?.cancel()
			lifetime = nil
		}
	}
	
	deinit {
		cancel()
	}
}
