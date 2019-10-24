//
//  CwlCaseNameCodableTests.swift
//  CwlUtils
//
//  Created by Matt Gallagher on 9/3/19.
//  Copyright © 2019 Matt Gallagher ( https://www.cocoawithlove.com ). All rights reserved.
//

import Foundation
import XCTest
import CwlUtils

struct A: Codable {
	var value: Int = 123
}

struct B: Codable {
}

enum Sum: CaseNameCodable {
	enum CaseName: String, CaseNameDecoder {
		case a
		case b
		case c
		
		func decode(from container: KeyedDecodingContainer<CaseName>) throws -> Sum {
			switch self {
			case .a: return .a(try container.decode(A.self, forKey: self))
			case .b: return .b(B())
			case .c: return .c
			}
		}
	}
	
	case a(A)
	case b(B)
	case c
}

class CaseNameCodableTests: XCTestCase {
	func testCaseNameCodableAssociatedValue() {
		let x = Sum.a(A())
		let data = try! JSONEncoder().encode(x)
		let string = String(data: data, encoding: .utf8)!
		XCTAssertEqual(string, #"{"a":{"value":123}}"#)
		
		let y = try! JSONDecoder().decode(Sum.self, from: data)
		if case .a(let a) = y, a.value == 123 {
		} else {
			XCTFail("Failed to decode as expected")
		}
	}

	func testCaseNameCodableEmptyAssociatedValue() {
		let x = Sum.b(B())
		let data = try! JSONEncoder().encode(x)
		let string = String(data: data, encoding: .utf8)!
		XCTAssertEqual(string, #"{"b":{}}"#)
		
		let y = try! JSONDecoder().decode(Sum.self, from: data)
		if case .b = y {
		} else {
			XCTFail("Failed to decode as expected")
		}
	}

	func testCaseNameCodableNoAssociatedValue() {
		let x = Sum.c
		let data = try! JSONEncoder().encode(x)
		let string = String(data: data, encoding: .utf8)!
		XCTAssertEqual(string, #"{"c":null}"#)
		
		let y = try! JSONDecoder().decode(Sum.self, from: data)
		if case .c = y {
		} else {
			XCTFail("Failed to decode as expected")
		}
	}
}
