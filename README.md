# CloudKit Samples: Queries

### Goals

This project demonstrates use of CloudKit queries against a CloudKit Private Database. It shows how to filter a set of records by using a predicate against a property — in this case, a set of Contact records with a `name` property, and a `BEGINSWITH` predicate to query for records prefixed by a user-provided string.

### Prerequisites

* A Mac with [Xcode 13](https://developer.apple.com/xcode/) (or later) installed is required to build and test this project.
* An [Apple Developer Program membership](https://developer.apple.com/support/compare-memberships/) is needed if you wish to create your own CloudKit container.

### Setup Steps

* Ensure the simulator or device you run the project on is signed in to an Apple ID account with iCloud enabled. This can be done in the Settings app.
* If you wish to run the app on a device, ensure the correct developer team is selected in the “Signing & Capabilities” tab of the Queries app target, and a valid iCloud container is selected under the “iCloud” section.

#### Using Your Own iCloud Container

* Create a new iCloud container through Xcode’s “Signing & Capabilities” tab of the Queries app target.
* Update the `containerIdentifier` property in [Config.swift](Queries/Config.swift) with your new iCloud container ID.

### How It Works

* On first launch, the app fetches all Contact records from the remote database and displays the names of those records in the UI.
* When a user adds a new Contact record through the UI, the record is saved to the remote database and the records are retrieved and displayed again.
* When a user filters the list through the UI, a new query operation is performed using the `BEGINSWITH` predicate, and only records with the `name` field beginning with the given filter string are returned and displayed.

### Things To Learn

* How to create new records with the `CKModifyRecordsOperation`.
* How to use `CKQuery` and `CKQueryOperation` to build a query matching all or specific records, and retrieve and process the results with a `recordFetchedBlock`.
* How to use the `Result` type to provide clear information about the result of asynchronous operations with completion handlers.

### Note on Swift Concurrency

This project uses Swift concurrency APIs. A prior `completionHandler`-based implementation has been tagged [`pre-async`](https://github.com/apple/cloudkit-sample-queries/tree/pre-async).

### Further Reading

* [Running Your App in the Simulator or on a Device](https://developer.apple.com/documentation/xcode/running_your_app_in_the_simulator_or_on_a_device)
* [CloudKit Private Database](https://developer.apple.com/documentation/cloudkit/ckcontainer/1399205-privateclouddatabase)
