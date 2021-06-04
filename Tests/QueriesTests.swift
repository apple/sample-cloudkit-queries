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

        viewModel.initialize { result in
            expectation.fulfill()

            if case .failure(let error) = result {
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
            deleteOperation.modifyRecordsCompletionBlock = { _, idsDeleted, error in
                deleteExpectation.fulfill()

                if let error = error {
                    XCTFail("Error deleting temporary IDs: \(error.localizedDescription)")
                } else {
                    XCTAssert(idsDeleted == self.idsToDelete, "IDs deleted did not match targeted IDs for deletion.")
                }

                self.idsToDelete = []
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

    func testSavingRecords() throws {
        let saveExpectation = expectation(description: "Expect CloudKit save operation to complete.")

        try createTemporaryRecords(names: ["Madi", "Simon", "Bob"]) {
            saveExpectation.fulfill()
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testQueryingRecords() throws {
        let saveExpectation = expectation(description: "Expect CloudKit save operation to complete.")
        let queryExpectation = expectation(description: "Expect query operation to complete.")

        try createTemporaryRecords(names: ["Madi", "Simon"], completionQueue: .global()) {
            saveExpectation.fulfill()

            // Query operations rely on database indexing. New records will not be indexed instantly,
            // so wait to ensure our new record is picked up by the query.
            Thread.sleep(forTimeInterval: 5.0)

            self.viewModel.getContactNames(startingWith: "M") { result in
                queryExpectation.fulfill()

                switch result {
                case .failure(let error):
                    XCTFail("Error fetching filtered contacts: \(error)")
                case .success(let names):
                    XCTAssert(!names.isEmpty, "Query for prefix: \"M\" should return at least one record")
                    names.forEach { XCTAssert($0.starts(with: "M"), "Received name not starting with given prefix (M): \($0)")}
                }
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    // MARK: - Test Helpers

    private func createTemporaryRecords(names: [String], completionQueue: DispatchQueue = .main, completion: @escaping (() -> Void)) throws {
        viewModel.saveContacts(names) { result in
            switch result {
            case .failure(let error):
                XCTFail("Error saving records: \(error.localizedDescription)")
            case .success(let records):
                if let records = records {
                    self.idsToDelete = records.map { $0.recordID }
                }
            }

            completionQueue.async {
                completion()
            }
        }
    }
}
