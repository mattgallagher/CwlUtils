
//
//  CwlCountdownLatch.swift
//  CwlUtils
//
//  Created by Raphael Reitzig on 2017/02/16.
//  Copyright © 2017 Raphael Reitzig. All rights reserved.
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

/**
    A simple countdown latch that uses busy waiting.
    Created with a number of steps to wait for, callers
    can count down one by one.

    A step is performed by calling `countDown()` which is,
    obviously, thread-safe.

    Instances are single-use: once the latch has counted down to zero,
    all future calls to `await()` return immediately.

    - Author: Raphael Reitzig
    - Date: 16/02/17
*/
public class CountdownLatch {
    private let counter: AtomicBox<Int>

    /**
        Creates a new countdown latch that blocks callers of `await()`
        until the specified number of steps have been.

        - Parameter from: The number of steps to wait for.
    */
    public init(from start: Int) {
        precondition(start >= 0, "Latch can not work with negative goal.")
        assert(start > 0, "Latch with goal 0 will have no effect.")

        self.counter = AtomicBox(start)
    }

    /**
        Count this latch down by one step.

        - Note: Thread-safe.
    */
    public func countDown() throws {
        let newValue = self.counter.mutate { $0 -= 1 }

        if newValue < 0 {
            throw LatchError.alreadyZero
        }
    }

    /**
        Does not return before this latch has been counted down to zero.
    */
    public func await() {
        // TODO: is there something better than busy waiting?
        while self.counter.value > 0 {}
    }

    /**
        Does not return before this latch has been counted down to zero.
        However, aborts waiting after the specified time has elapsed.

        - Parameter for: The number of milliseconds to wait before throwing.
        - Throws: If the specified time has elapsed before the latch reached
            zero.
    */
    public func await(for ms: Int) throws {
        let start = currentTimeMillis()
        while self.counter.value > 0 {
            let expired = currentTimeMillis() - start
            if expired > Int64(ms) {
                throw LatchError.expired(deadline: ms, waited: expired)
            }
        }
    }

    /**
        - Returns: UNIX timestamp, i.e. a time in milliseconds.
    */
    private func currentTimeMillis() -> Int64{
        let nowDouble = NSDate().timeIntervalSince1970
        return Int64(nowDouble*1000)
    }

    private enum LatchError: Error, CustomStringConvertible {
        case expired(deadline: Int, waited: Int64)
        case alreadyZero

        var description: String {
            switch self {
                case .expired(let goal, let waited): return "Waited for \(waited)ms, limit was \(goal)ms."
                case .alreadyZero: return "Latch has already been counted down to zero"
            }
        }
    }
}
