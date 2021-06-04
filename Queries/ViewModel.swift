//
//  ViewModel.swift
//  (cloudkit-samples) queries
//

import os.log
import CloudKit

final class ViewModel: ObservableObject {

    // MARK: - VM State

    enum State {
        case idle
        case loading
        case loaded(names: [String], prefix: String?)
        case error(Error)

        var isLoading: Bool {
            switch self {
            case .loading:
                return true
            default:
                return false
            }
        }

        var isError: Bool {
            switch self {
            case .error:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var state = State.idle
    var activeFilterPrefix: String? = nil

    private lazy var container = CKContainer(identifier: Config.containerIdentifier)
    private lazy var database = container.privateCloudDatabase

    private let contactsZoneID = CKRecordZone.ID(zoneName: "Contacts")

    // MARK: - API

    func initializeAndRefresh() {
        initialize { result in
            switch result {
            case .failure(let error):
                self.state = .error(error)
            case .success:
                self.refresh()
            }
        }
    }

    func initialize(completionHandler: @escaping (Result<Void, Error>) -> Void) {
        createContactsZoneIfNeeded(completionHandler: completionHandler)
    }

    func refresh() {
        self.state = .loading

        getContactNames(startingWith: activeFilterPrefix) { result in
            switch result {
            case .failure(let error):
                self.state = .error(error)
            case .success(let names):
                self.state = .loaded(names: names, prefix: self.activeFilterPrefix)
            }
        }
    }

    /// Saves a set of names to our private database as Contact records.
    /// - Parameters:
    ///   - contactNames: A list of names representing contacts to save to the database.
    ///   - completionQueue: The [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) on which the completion handler will be called. Defaults to `main`.
    ///   - completionHandler: Handler called on operation completion with success or failure.
    func saveContacts(_ contactNames: [String], completionQueue: DispatchQueue = .main, completionHandler: @escaping (Result<[CKRecord], Error>) -> Void) {
        /// Convert our strings (names) to `CKRecord` objects with our helper function.
        let records = contactNames.map { createContactRecord(forName: $0) }

        let saveOperation = CKModifyRecordsOperation(recordsToSave: records)
        saveOperation.savePolicy = .allKeys

        var recordsSaved: [CKRecord] = []

        saveOperation.perRecordSaveBlock = { id, result in
            if let record = try? result.get() {
                recordsSaved.append(record)
            }
        }

        saveOperation.modifyRecordsResultBlock = { result in
            if case .failure(let error) = result {
                self.reportError(error)
            }

            completionQueue.async {
                completionHandler(result.map { recordsSaved })
            }
        }

        database.add(saveOperation)
    }

    /// Retrieves names of Contacts from the database with an optional **case-sensitive** prefix to query with.
    /// - Parameters:
    ///   - prefix: Prefix to query names against.
    ///   - completionQueue: The [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) on which the completion handler will be called. Defaults to `main`.
    ///   - completionHandler: Handler called on operation completion with success (array of names) or failure.
    func getContactNames(startingWith prefix: String?, completionQueue: DispatchQueue = .main, completionHandler: @escaping (Result<[String], Error>) -> Void) {
        guard let prefix = prefix else {
            getAllContactNames(completionQueue: completionQueue, completionHandler: completionHandler)
            return
        }

        let predicate = NSPredicate(format: "name BEGINSWITH %@", prefix)

        // Using CKQueryOperation, the records will come in via the closure one at a time.
        // Store results in a temporary array for returning after completion.
        var fetchedNames: [String] = []

        let query = CKQuery(recordType: "Contact", predicate: predicate)
        let queryOperation = CKQueryOperation(query: query)
        queryOperation.zoneID = contactsZoneID

        queryOperation.recordMatchedBlock = { _, result in
            if let record = try? result.get(), let name = record["name"] as? String {
                fetchedNames.append(name)
            }
        }

        queryOperation.queryResultBlock = { result in
            if case .failure(let error) = result {
                self.reportError(error)
            }

            completionQueue.async {
                completionHandler(result.map { _ in fetchedNames })
            }
        }

        database.add(queryOperation)
    }

    /// Fetches _all_ contact names from the database.
    /// - Parameters:
    ///   - completionQueue: The [DispatchQueue](https://developer.apple.com/documentation/dispatch/dispatchqueue) on which the completion handler will be called. Defaults to `main`.
    ///   - completionHandler: Handler called on operation completion with success (array of names) or failure.
    func getAllContactNames(completionQueue: DispatchQueue = .main, completionHandler: @escaping (Result<[String], Error>) -> Void) {
        var fetchedNames: [String] = []

        let fetchOperation = CKFetchRecordZoneChangesOperation(recordZoneIDs: [contactsZoneID], configurationsByRecordZoneID: nil)

        fetchOperation.recordWasChangedBlock = { _, result in
            if let record = try? result.get(), let name = record["name"] as? String {
                fetchedNames.append(name)
            }
        }

        fetchOperation.fetchRecordZoneChangesResultBlock = { result in
            completionQueue.async {
                completionHandler(result.map { fetchedNames })
            }
        }

        database.add(fetchOperation)
    }

    // MARK: - Helpers

    private func createContactRecord(forName name: String) -> CKRecord {
        let recordID = CKRecord.ID(zoneID: contactsZoneID)
        let record = CKRecord(recordType: "Contact", recordID: recordID)
        record["name"] = name
        return record
    }

    /// Creates a custom CKRecordZone and saves it to the database if needed,
    /// checking `UserDefaults` if this has been done before on this device.
    /// - Parameter completionQueue: Queue to run completion handler on.
    /// - Parameter completionHandler: Handler to process `success` or `failure`.
    private func createContactsZoneIfNeeded(completionQueue: DispatchQueue = .main, completionHandler: @escaping (Result<Void, Error>) -> Void) {
        guard !UserDefaults.standard.bool(forKey: "contactZoneCreated") else {
            completionHandler(.success(()))
            return
        }

        let newZone = CKRecordZone(zoneID: contactsZoneID)
        let createZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [newZone])

        createZoneOperation.modifyRecordZonesResultBlock = { result in
            switch result {
            case .failure(let error):
                self.reportError(error)

            case .success:
                UserDefaults.standard.set(true, forKey: "contactZoneCreated")
            }

            completionQueue.async {
                completionHandler(result)
            }
        }

        database.add(createZoneOperation)
    }

    private func reportError(_ error: Error) {
        guard let ckerror = error as? CKError else {
            os_log("Not a CKError: \(error.localizedDescription)")
            return
        }

        switch ckerror.code {
        case .partialFailure:
            // Iterate through error(s) in partial failure and report each one.
            let dict = ckerror.userInfo[CKPartialErrorsByItemIDKey] as? [NSObject: CKError]
            if let errorDictionary = dict {
                for (_, error) in errorDictionary {
                    reportError(error)
                }
            }

        // This switch could explicitly handle as many specific errors as needed, for example:
        case .unknownItem:
            os_log("CKError: Record not found.")

        case .notAuthenticated:
            os_log("CKError: An iCloud account must be signed in on device or Simulator to write to a PrivateDB.")

        case .permissionFailure:
            os_log("CKError: An iCloud account permission failure occured.")

        case .networkUnavailable:
            os_log("CKError: The network is unavailable.")

        default:
            os_log("CKError: \(error.localizedDescription)")
        }
    }
}
