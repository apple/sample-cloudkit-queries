//
//  ViewModel.swift
//  (cloudkit-samples) queries
//

import os.log
import CloudKit

@MainActor
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

    // MARK: - Init

    nonisolated init() {}

    // MARK: - API

    /// Initializes the CloudKit Database with a custom zone if needed.
    func initialize() async throws {
        do {
            try await createContactsZoneIfNeeded()
        } catch {
            state = .error(error)
            throw error
        }
    }

    func refresh() async {
        state = .loading

        do {
            let names = try await getContactNames(startingWith: activeFilterPrefix)
            state = .loaded(names: names, prefix: activeFilterPrefix)
        } catch {
            state = .error(error)
        }
    }

    /// Saves a set of names to our private database as Contact records.
    /// - Parameter names: A list of names representing contacts to save to the database.
    /// - Returns: The set of newly created record IDs after saving.
    func saveContacts(_ names: [String]) async throws -> [CKRecord.ID] {
        /// Convert our strings (names) to `CKRecord` objects with our helper function.
        let records = names.map { createContactRecord(forName: $0) }

        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys)

        // Determine successfully saved records via inner Results.
        let savedRecords = result.saveResults.values.compactMap { try? $0.get() }
        return savedRecords.map { $0.recordID }
    }

    /// Retrieves names of Contacts from the database with an optional **case-sensitive** prefix to query with.
    /// - Parameters:
    ///   - prefix: Prefix to query names against.
    /// - Returns: Names from the database matching the prefix query.
    func getContactNames(startingWith prefix: String?) async throws -> [String] {
        guard let prefix = prefix else {
            return try await getAllContactNames()
        }

        let predicate = NSPredicate(format: "name BEGINSWITH %@", prefix)
        let query = CKQuery(recordType: "Contact", predicate: predicate)
        let (matchResults, _) = try await database.records(matching: query, inZoneWith: contactsZoneID)

        let names = matchResults
            .compactMap { _, result in try? result.get() }
            .compactMap { $0["name"] as? String }

        return names
    }

    /// Fetches _all_ contact names from the database.
    /// - Returns: All names found in our custom zone.
    func getAllContactNames() async throws -> [String] {
        var allContactNames: [String] = []

        /// `recordZoneChanges` can return multiple consecutive changesets before completing, so
        /// we use a loop to process multiple results if needed, indicated by the `moreComing` flag.
        var awaitingChanges = true
        /// After each loop, if more changes are coming, they are retrieved by using the `changeToken` property.
        var nextChangeToken: CKServerChangeToken? = nil

        while awaitingChanges {
            let changes = try await database.recordZoneChanges(inZoneWith: contactsZoneID, since: nextChangeToken)
            let contactNames = changes.modificationResultsByID
                .compactMap { _, result in try? result.get().record }
                .compactMap { $0["name"] as? String }
            allContactNames.append(contentsOf: contactNames)

            awaitingChanges = changes.moreComing
            nextChangeToken = changes.changeToken
        }

        return allContactNames
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
    private func createContactsZoneIfNeeded() async throws {
        guard !UserDefaults.standard.bool(forKey: "contactZoneCreated") else {
            return
        }

        let newZone = CKRecordZone(zoneID: contactsZoneID)
        _ = try await database.modifyRecordZones(saving: [newZone], deleting: [])

        UserDefaults.standard.set(true, forKey: "contactZoneCreated")
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
