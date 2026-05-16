import SwiftUI

struct ContentView: View {
    @Environment(ServiceManager.self) private var serviceManager
    @State private var selectedDomain: ServiceDomain? = .userAgents
    @State private var selectedService: LaunchdService? = nil
    @State private var searchText: String = ""
    @State private var showCreateSheet: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedDomain: $selectedDomain)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 280)
        } content: {
            ServiceListView(
                selectedDomain: selectedDomain ?? .userAgents,
                selectedService: $selectedService,
                searchText: $searchText
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 480)
        } detail: {
            if let service = selectedService {
                ServiceDetailView(service: service) {
                    selectedService = nil
                }
                .id(service.id)
            } else {
                ContentUnavailableView(
                    "Select a Service",
                    systemImage: "gearshape.2",
                    description: Text("Choose a service from the list to view its details")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search services...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Service", systemImage: "plus")
                }
                .help("Create a new launchd service")

                Button {
                    Task { await serviceManager.loadAllServices() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh all services")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateServiceView()
        }
        .task {
            await serviceManager.loadAllServices()
        }
        .onChange(of: selectedDomain) { _, _ in
            selectedService = nil
        }
        .frame(minWidth: 900, minHeight: 550)
    }
}
