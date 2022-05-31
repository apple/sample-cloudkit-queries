//
//  QueriesTests.swift
//  (cloudkit-samples) queries-tests
//

import XCTest
import CloudKit
@testable import Queries

/// Note: As these tests perform actions on an iCloud Private Database, a signed-in iCloud account
/// is required on the device or simulator that the tests are run on.
class QueriesTests: XCTestCase {

    let viewModel = ViewModel()
    var idsToDelete: [CKRecord.ID] = []

    override func setUpWithError() throws {
        let expectation = self.expectation(description: "Expect ViewModel initialization completed")

        Task {
            do {
                try await viewModel.initialize()
                expectation.fulfill()
            } catch {
                XCTFail("ViewModel initialization failed: \(error)")
            }
        }

        waitForExpectations(timeout: 10)
    }

    override func tearDownWithError() throws {
        if !idsToDelete.isEmpty {
            let container = CKContainer(identifier: Config.containerIdentifier)
            let database = container.privateCloudDatabase
            let deleteExpectation = expectation(description: "Expect CloudKit to delete testing records")

            let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: idsToDelete)

            deleteOperation.modifyRecordsResultBlock = { result in
                deleteExpectation.fulfill()

                if case .failure(let error) = result {
                    XCTFail("Error deleting temporary IDs: \(error.localizedDescription)")
                } else {
                    self.idsToDelete = []
                }
            }

            database.add(deleteOperation)

            waitForExpectations(timeout: 10, handler: nil)
        }
    }

    func test_CloudKitReadiness() throws {
        // Fetch zones from the Private Database of the CKContainer for the current user to test for valid/ready state
        let container = CKContainer(identifier: Config.containerIdentifier)
        let database = container.privateCloudDatabase

        let fetchExpectation = expectation(description: "Expect CloudKit fetch to complete")
        database.fetchAllRecordZones { _, error in
            if let error = error as? CKError {
                switch error.code {
                case .badContainer, .badDatabase:
                    XCTFail("Create or select a CloudKit container in this app target's Signing & Capabilities in Xcode")

                case .permissionFailure, .notAuthenticated:
                    XCTFail("Simulator or device running this app needs a signed-in iCloud account")

                default:
                    XCTFail("CKError: \(error)")
                }
            }
            fetchExpectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testSavingRecords() async throws {
        try await createTemporaryRecordsAsync(names: ["Madi", "Simon", "Bob"])
    }

    func testQueryingRecords() async throws {
        try await createTemporaryRecordsAsync(names: ["Madi", "Simon"])

        Thread.sleep(forTimeInterval: 5.0)

        let matches = try await viewModel.getContactNames(startingWith: "M")

        XCTAssert(!matches.isEmpty, "Query for prefix: \"M\" should return at least one record")
        matches.forEach { XCTAssert($0.starts(with: "M"), "Received name not starting with given prefix (M): \($0)")}
    }

    // MARK: - Test Helpers

    private func createTemporaryRecordsAsync(names: [String]) async throws {
        idsToDelete = try await viewModel.saveContacts(names)
    }
}
