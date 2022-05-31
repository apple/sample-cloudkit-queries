//
//  ContentView.swift
//  (cloudkit-samples) queries
//

import SwiftUI

struct ContentView: View {

    // MARK: - View State

    @EnvironmentObject var vm: ViewModel
    @State var isFiltering: Bool = false
    @State var isAddingContact: Bool = false
    @State var name: String = ""
    @State var filterPrefix: String = ""

    // MARK: - Main View

    var body: some View {
        UITableView.appearance().backgroundColor = .clear

        return NavigationView {
            VStack {
                content.navigationBarTitle("Queries")
                Spacer()
                Button("Refresh", action: { Task { await vm.refresh() } })
            }
            .onAppear {
                Task {
                    try? await vm.initialize()
                    await vm.refresh()
                }
            }
            .navigationBarItems(
                leading: Button("Filter", action: { self.isFiltering = true })
                    .sheet(isPresented: $isFiltering, content: {
                        self.filterNamesView
                    }),
                trailing: Button("Add Contact", action: { self.isAddingContact = true })
                    .sheet(isPresented: $isAddingContact, content: {
                        self.addContactView
                    })
            )
        }
    }

    // MARK: - Dynamic Content

    private var content: some View {
        switch vm.state {
        case .idle:
            return AnyView(EmptyView())
        case .loading:
            return AnyView(ProgressView())
        case .loaded(let names, let prefix):
            return AnyView(filteredListView(of: names.sorted(), prefix: prefix))
        case .error(let error):
            return AnyView(Text("Error: \(error.localizedDescription)"))
        }
    }

    // MARK: - Private Subviews

    /// Build a list view of contact names with filtered state.
    private func filteredListView(of contactNames: [String], prefix: String?) -> some View {
        let headerText: String = {
            if let prefix = prefix {
                return "Contacts starting with “\(prefix)”"
            } else {
                return "All Contacts"
            }
        }()

        return List {
            Section(header: Text(headerText)) {
                ForEach(contactNames) { name in
                    Text(name)
                }
            }
        }.listStyle(GroupedListStyle())
    }

    /// View for adding a new Contact.
    private var addContactView: some View {
        NavigationView {
            VStack {
                TextField("Name", text: $name)
                    .font(.body)
                    .textContentType(.name)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .navigationTitle("Add New Contact")
            .navigationBarItems(leading: Button("Cancel", action: { self.isAddingContact = false }),
                                trailing: Button("Add", action: {
                Task {
                    _ = try? await self.vm.saveContacts([name])
                    self.isAddingContact = false
                    await vm.refresh()
                }
            }))
        }.onDisappear {
            self.name = ""
        }
    }

    /// View for configuring active filter/prefix query.
    private var filterNamesView: some View {
        NavigationView {
            VStack {
                TextField("Filter names starting with...", text: $filterPrefix)
                    .font(.body)
                    .textContentType(.name)
                    .padding(.horizontal, 16)
                Spacer()
            }
            .navigationTitle("Filter Records")
            .navigationBarItems(leading: Button("Reset", action: {
                self.vm.activeFilterPrefix = nil
                self.filterPrefix = ""
                self.isFiltering = false
                Task {
                    await self.vm.refresh()
                }
            }),
            trailing: Button("Filter", action: {
                self.vm.activeFilterPrefix = filterPrefix
                self.isFiltering = false
                Task {
                    await self.vm.refresh()
                }
            }))
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ViewModel())
    }
}

// MARK: - Helper Extensions

extension String: Identifiable {
    public typealias ID = Int
    public var id: Int {
        return hash
    }
}
