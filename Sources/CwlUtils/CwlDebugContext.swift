//
//  CwlDebugContext.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 2016/05/15.
//  Copyright © 2016 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
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

/// A set of identifiers for the different queues in the DebugContextCoordinator
///
/// - unspecified: used when a initial DebugContextThread is not specified on startup (not used otherwise)
/// - main: used by `main` and `mainAsync` contexts
/// - `global`: used for a concurrent queues and for timers on direct
/// - custom: any custom queue
public enum DebugContextThread: Hashable {
	case unspecified
	case main
	case global
	case custom(String)
	
	/// Convenience test to determine if an `Exec` instance wraps a `DebugContext` identifying `self` as its `thread`.
	public func matches(_ exec: Exec) -> Bool {
		if case .custom(let debugContext as DebugContext) = exec, debugContext.thread == self {
			return true
		} else {
			return false
		}
	}
}

/// Basic equality tests for `DebugContextThread`
///
/// - Parameters:
///   - left: a `DebugContextThread`
///   - right: another `DebugContextThread`
/// - Returns: true if they are equal value
public func ==(left: DebugContextThread, right: DebugContextThread) -> Bool {
	switch (left, right) {
	case (.custom(let l), .custom(let r)) where l == r: return true
	case (.unspecified, .unspecified): return true
	case (.main, .main): return true
	case (.global, .global): return true
	default: return false
	}
}

/// Simulates running a series of blocks across threads over time by instead queuing the blocks and running them serially in time priority order, incrementing the `currentTime` to reflect the time priority of the last run block.
/// The result is a deterministic simulation of time scheduled blocks, which is otherwise subject to thread scheduling non-determinism.
public class DebugContextCoordinator {
	// We use DispatchTime for time calculations but time 0 is treated as a special value ("now") so we start at time = 1, internally, and subtract 1 when returning through the public `currentTime` accessor.
	var internalTime: UInt64 = 1
	var queues: Dictionary<DebugContextThread, DebugContextQueue> = [:]
	var stopRequested: Bool = false
	
	/// Returns the current simulated time in nanoseconds
	public var currentTime: UInt64 { return internalTime - 1 }
	
	/// Returns the last runs simulated thread
	fileprivate (set) public var currentThread: DebugContextThread
	
	/// Constructs an empty instance
	public init() {
		currentThread = .unspecified
	}
	
	/// Constructs an empty instance
	public init(initialThread: DebugContextThread) {
		self.currentThread = initialThread
	}
	
	/// Implementation mimicking Exec.direct but returning an Exec.custom(DebugContext)
	public var direct: Exec {
		return .custom(DebugContext(type: .immediate, thread: .global, coordinator: self))
	}
	
	/// Implementation mimicking Exec.main but returning an Exec.custom(DebugContext)
	public var main: Exec {
		return .custom(DebugContext(type: .thread { [weak self] in self?.currentThread == .main }, thread: .main, coordinator: self))
	}
	
	/// Implementation mimicking Exec.mainAsync but returning an Exec.custom(DebugContext)
	public var mainAsync: Exec {
		return .custom(DebugContext(type: .threadAsync { [weak self] in self?.currentThread == .main }, thread: .main, coordinator: self))
	}
	
	/// Implementation mimicking Exec.default but returning an Exec.custom(DebugContext)
	public var global: Exec {
		return .custom(DebugContext(type: .concurrentAsync, thread: .global, coordinator: self))
	}
	
	/// Implementation mimicking Exec.syncQueue but returning an Exec.custom(DebugContext)
	public func syncQueue() -> Exec {
		let uuidString = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String? ?? ""
		return .custom(DebugContext(type: .mutex, thread: .custom(uuidString), coordinator: self))
	}
	
	/// Implementation mimicking Exec.asyncQueue but returning an Exec.custom(DebugContext)
	public func asyncQueue() -> Exec {
		let uuidString = CFUUIDCreateString(nil, CFUUIDCreate(nil)) as String? ?? ""
		return .custom(DebugContext(type: .serialAsync, thread: .custom(uuidString), coordinator: self))
	}
	
	/// Performs all scheduled actions in a serial loop.
	///
	/// - parameter stoppingAfter: If nil, loop will continue until `stop` invoked or until no actions remain. If non-nil, loop will abort after an action matching Lifetime is completed.
	public func runScheduledTasks(stoppingAfter: (AnyObject & Lifetime)? = nil) {
		stopRequested = false
		currentThread = .unspecified
		while !stopRequested, let nextTimer = runNextTask() {
			if stoppingAfter != nil, stoppingAfter === nextTimer {
				break
			}
		}
		if stopRequested {
			// Since releasing `queues` will likely cause the release of closures and items held by the queue, which might lead to nested calls to remove items from `queues` violating ownership rules...
			// We copy queues to a non-shared stack location, clear `queues` and *then* release the contents.
			withExtendedLifetime(queues) { queues = [:] }
		}
	}
	
	/// Performs all scheduled actions in a serial loop.
	///
	/// - parameter stoppingAfter: If nil, loop will continue until `stop` invoked or until no actions remain. If non-nil, loop will abort after an action matching Lifetime is completed.
	public func runScheduledTasks(untilTime: UInt64) {
		stopRequested = false
		currentThread = .unspecified
		while !stopRequested, let (threadIndex, time) = nextTask(), time <= untilTime {
			_ = runTask(threadIndex: threadIndex, time: time)
		}
		if stopRequested {
			// Since releasing `queues` will likely cause the release of closures and items held by the queue, which might lead to nested calls to remove items from `queues` violating ownership rules...
			// We copy queues to a non-shared stack location, clear `queues` and *then* release the contents.
			withExtendedLifetime(queues) { queues = [:] }
		}
	}
	
	/// Causes `runScheduledTasks` to exit as soon as possible, if it is running.
	public func stop() {
		stopRequested = true
	}
	
	/// Discards all scheduled actions and resets time to 1. Useful if the `DebugContextCoordinator` is to be reused.
	public func reset() {
		internalTime = 1
		
		// Since releasing `queues` will likely cause the release of closures and items held by the queue, which might lead to nested calls to remove items from `queues` violating ownership rules...
		// We copy queues to a non-shared stack location, clear `queues` and *then* release the contents.
		withExtendedLifetime(queues) { queues = [:] }
	}
	
	func getOrCreateQueue(forName: DebugContextThread) -> DebugContextQueue {
		if let t = queues[forName] {
			return t
		}
		let t = DebugContextQueue()
		
		// Since releasing `queues` will likely cause the release of closures and items held by the queue, which might lead to nested calls to remove items from `queues` violating ownership rules...
		// We copy queues to a non-shared stack location, clear `queues` and *then* release the contents.
		withExtendedLifetime(queues[forName]) { queues[forName] = t }
		
		return t
	}
	
	// Fundamental method for scheduling a block on the coordinator for later invocation.
	func schedule(block: @escaping () -> Void, thread: DebugContextThread, timeInterval interval: Int64, repeats: Bool) -> DebugContextTimer {
		let i = interval > 0 ? UInt64(interval) : 0 as UInt64
		let debugContextTimer = DebugContextTimer(thread: thread, rescheduleInterval: repeats ? i : nil, coordinator: self)
		getOrCreateQueue(forName: thread).schedule(pending: PendingBlock(time: internalTime + i, timer: debugContextTimer, block: block))
		return debugContextTimer
	}
	
	// Remove a block from the scheduler
	func cancelTimer(_ toCancel: DebugContextTimer) {
		if let t = queues[toCancel.thread]  {
			t.cancelTimer(toCancel)
		}
	}
	
	func nextTask() -> (DebugContextThread, UInt64)? {
		var lowestTime = UInt64.max
		var selectedIndex = DebugContextThread.unspecified
		
		// We want a deterministic ordering, so we'll iterate over the queues by key sorted by hashValue
		for index in queues.keys.sorted(by: { (left, right) -> Bool in left.hashValue < right.hashValue }) {
			if let t = queues[index], t.nextTime < lowestTime {
				selectedIndex = index
				lowestTime = t.nextTime
			}
		}
		if lowestTime == UInt64.max {
			return nil
		}
		
		return (selectedIndex, lowestTime)
	}
	
	func runTask(threadIndex: DebugContextThread, time: UInt64) -> DebugContextTimer? {
		(currentThread, internalTime) = (threadIndex, time)
		return queues[threadIndex]?.popAndInvokeNext()
	}
	
	// Run the next event. If nil is returned, no further events remain. If
	func runNextTask() -> DebugContextTimer? {
		if let (threadIndex, time) = nextTask() {
			return runTask(threadIndex: threadIndex, time: time)
		}
		return nil
	}
}

// This structure is used to represent scheduled actions in the DebugContextCoordinator.
struct PendingBlock {
	let time: UInt64
	weak var timer: DebugContextTimer?
	let block: () -> Void
	
	init(time: UInt64, timer: DebugContextTimer?, block: @escaping () -> Void) {
		self.time = time
		self.timer = timer
		self.block = block
	}
	
	var nextInterval: PendingBlock? {
		if let t = timer, let i = t.rescheduleInterval, t.coordinator != nil {
			return PendingBlock(time: time + i, timer: t, block: block)
		}
		return nil
	}
}

// A `DebugContextQueue` is just an array of `PendingBlock`, sorted by scheduled time. It represents the blocks queued for execution on a thread in the `DebugContextCoordinator`.
class DebugContextQueue {
	var pendingBlocks: Array<PendingBlock> = []
	
	init() {
	}
	
	// Insert a block in scheduled order
	func schedule(pending: PendingBlock) {
		var insertionIndex = 0
		while pendingBlocks.count > insertionIndex && pendingBlocks[insertionIndex].time <= pending.time {
			insertionIndex += 1
		}
		
		pendingBlocks.insert(pending, at: insertionIndex)
	}
	
	// Remove a block
	func cancelTimer(_ toCancel: DebugContextTimer) {
		if let index = pendingBlocks.firstIndex(where: { tuple -> Bool in tuple.timer === toCancel }) {
			pendingBlocks.remove(at: index)
		}
	}
	
	// Return the earliest scheduled time in the queue
	var nextTime: UInt64 {
		return pendingBlocks.first?.time ?? UInt64.max
	}
	
	// Runs the next block in the queue
	func popAndInvokeNext() -> DebugContextTimer? {
		if let next = pendingBlocks.first {
			pendingBlocks.remove(at: 0)
			next.block()
			if let nextInterval = next.nextInterval {
				schedule(pending: nextInterval)
			}
			
			// We ran a block, don't return nil (next.timer may return nil if it has self-cancelled)
			return next.timer ?? DebugContextTimer()
		}
		
		return nil
	}
}

/// An implementation of `ExecutionContext` that schedules its non-immediate actions on a `DebugContextCoordinator`. This type is constructed using the `Exec` mimicking properties and functions on `DebugContextCoordinator`.
public struct DebugContext: CustomExecutionContext {
	public let type: ExecutionType
	public let thread: DebugContextThread
	weak var coordinator: DebugContextCoordinator?
	
	init(type: ExecutionType, thread: DebugContextThread, coordinator: DebugContextCoordinator) {
		self.type = type
		self.thread = thread
		self.coordinator = coordinator
	}
	
	/// Run `execute` normally on the execution context
	public func invoke(_ execute: @escaping () -> Void) {
		guard let c = coordinator else { return }
		if type.isImmediateInCurrentContext {
			let previousThread = c.currentThread
			if !type.isConcurrent {
				c.currentThread = thread
			}
			execute()
			if !type.isConcurrent {
				c.currentThread = previousThread
			}
		} else {
			invokeAsync(execute)
		}
	}
	
	/// Run `execute` asynchronously on the execution context
	public func invokeAsync(_ execute: @escaping () -> Void) {
		_ = coordinator?.schedule(block: execute, thread: thread, timeInterval: 1, repeats: false)
	}
	
	@available(*, deprecated, message: "Use invokeSync instead")
	public func invokeAndWait(_ execute: @escaping () -> Void) {
        invokeSync(execute)
	}
	
	/// Run `execute` on the execution context but don't return from this function until the provided function is complete.
	///
	/// If the debug coordinator is nil or has completed before this block is run, the block will be directly invoked instead of running in the debug context.
	/// In general this shouldn't matter since the debug context is generally just a synchronous invocation.
	///
	/// - Parameter execute: the block to run
	/// - Returns: the return value from running the block
	public func invokeSync<Return>(_ execute: () throws -> Return) rethrows -> Return {
		guard let c = coordinator else {
			return try execute()
		}
		if type.isImmediateInCurrentContext {
			let previousThread = c.currentThread
			if !type.isConcurrent {
				c.currentThread = thread
			}
			let r = try execute()
			if !type.isConcurrent {
				c.currentThread = previousThread
			}
			return r
		} else {
			let result = try withoutActuallyEscaping(execute) { ex throws -> Return? in
				var rr: Result<Return, Error>? = nil
				c.runScheduledTasks(stoppingAfter: c.schedule(block: {
					rr = Result { try ex() }
				}, thread: thread, timeInterval: 1, repeats: false))
				return try rr?.get()
			}
			guard let r = result else { return try execute() }
			return r
		}
	}
	
	public func relativeAsync(qos: DispatchQoS.QoSClass?) -> Exec {
		guard let c = coordinator else {
			return Exec.direct
		}
		return c.global
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		guard let c = coordinator else { return DebugContextTimer() }
		return c.schedule(block: handler, thread: thread, timeInterval: interval.nanoseconds, repeats: false)
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, unless the returned `Lifetime` is cancelled or released before running occurs.
	public func singleTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		guard let c = coordinator else { return DebugContextTimer() }
		return c.schedule(block: { handler(parameter) }, thread: thread, timeInterval: interval.nanoseconds, repeats: false)
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer(interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping () -> Void) -> Lifetime {
		guard let c = coordinator else { return DebugContextTimer() }
		return c.schedule(block: handler, thread: thread, timeInterval: interval.nanoseconds, repeats: true)
	}
	
	/// Run `execute` on the execution context after `interval` (plus `leeway`), passing the `parameter` value as an argument, and again every `interval` (within a `leeway` margin of error) unless the returned `Lifetime` is cancelled or released before running occurs.
	public func periodicTimer<T>(parameter: T, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, handler: @escaping (T) -> Void) -> Lifetime {
		guard let c = coordinator else { return DebugContextTimer() }
		return c.schedule(block: { handler(parameter) }, thread: thread, timeInterval: interval.nanoseconds, repeats: true)
	}
	
	/// Gets a timestamp representing the host uptime the in the current context
	public func timestamp() -> DispatchTime {
		guard let c = coordinator else { return DispatchTime.now() }
		return DispatchTime(uptimeNanoseconds: c.currentTime)
	}
}

// All actions scheduled with a `DebugContextCoordinator` are referenced by a DebugContextTimer (even those actions that are simply asynchronous invocations without a delay).
class DebugContextTimer: Lifetime {
	let thread: DebugContextThread
	let rescheduleInterval: UInt64?
	weak var coordinator: DebugContextCoordinator?
	
	init() {
		thread = .unspecified
		coordinator = nil
		rescheduleInterval = nil
	}
	
	init(thread: DebugContextThread, rescheduleInterval: UInt64?, coordinator: DebugContextCoordinator) {
		self.thread = thread
		self.coordinator = coordinator
		self.rescheduleInterval = rescheduleInterval
	}
	
	/// Lifetime implementation
	public func cancel() {
		coordinator?.cancelTimer(self)
		coordinator = nil
	}
	
	deinit {
		cancel()
	}
}
