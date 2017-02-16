//
//  CwlCountdownLatchTests.swift
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

import Foundation
import XCTest
import CwlUtils

class CountdownLatchTests: XCTestCase {
    private let n = 10

    /// Test that the latch works properly in a single-thread setting
    func testDirectCountdown() {
        let latch = CountdownLatch(from: n)
        var iterations = 0

        for _ in 1...n {
            do {
                try latch.countDown()
                iterations += 1
            } catch {}
        }

        latch.await()
        XCTAssertEqual(iterations, n)
    }

    /// Test that the latch works properly with a single asynchronous accessor.
    func testSingleAsyncCountdown() {
        let latch = CountdownLatch(from: n)
        let iterations = AtomicBox(0)

        DispatchQueue.global(qos: .background).async {
            for _ in 1...self.n {
                do {
                    try latch.countDown()
                    iterations.mutate { $0 += 1 }
                } catch {}
            }
        }

        latch.await()
        XCTAssertEqual(iterations.value, n)
    }

    /// Test that the latch works properly with multiple asynchronous accessors.
    // TODO: Do all of them get dispatched to the same thread? If so, this test is moot.
    func testManyAsyncCountdowns() {
        let latch = CountdownLatch(from: n)
        let iterations = AtomicBox(0)

        for _ in 1...n {
            DispatchQueue.global(qos: .background).async {
                do {
                    try latch.countDown()
                    iterations.mutate { $0 += 1 }
                } catch {}
            }
        }

        latch.await()
        XCTAssertEqual(iterations.value, n)
    }

    /// Test that countDown does indeed throw an error if the latch is already at zero
    func testTooManyCountdowns() throws {
        let latch = CountdownLatch(from: n)
        var iterations = 0

        for _ in 1...n {
            do {
                try latch.countDown()
                iterations += 1
            } catch {
                XCTFail("Should not throw an error before zero!")
            }
        }

        do {
            try latch.countDown()
            XCTFail("Should not count below zero!")
        } catch {
            // All is good, we expected this!
        }
    }

    /// Test that await with time limit does indeed throw an error if it waits too long
    func testAwaitExpired() {
        let latch = CountdownLatch(from: 1)

        DispatchQueue.global(qos: .background).async {
            do {
                sleep(1) // seconds
                try latch.countDown()
            } catch {}
        }

        do {
            try latch.await(for: 10) // milliseconds
            XCTFail("We should not wait longer than specified!")
        } catch {
            // All is good, we expected this!
        }
    }
}
