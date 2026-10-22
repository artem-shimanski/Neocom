//
//  TrainingKitTests.swift
//  TrainingKit
//

import Testing
@testable import TrainingKit

@Suite("Package skeleton")
struct TrainingKitTests {
    @Test("package builds and the test target links")
    func packageSkeleton() {
        #expect(1 + 1 == 2)
    }
}
