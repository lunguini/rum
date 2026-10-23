//
//  LibraryView.swift
//  Rum
//
//  This file is part of Whisky.
//
//  Whisky is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Whisky.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import WhiskyKit

enum LibraryPage: Hashable {
    case home, library, recent, found, settings

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .library: "Games & Apps"
        case .recent: "Recently Played"
        case .found: "Found in Bottles"
        case .settings: "Settings"
        }
    }
}

enum LibrarySort: String, CaseIterable {
    case name = "Name"
    case recent = "Recently Played"
}

/// The main window: a sidebar, the Library grid (or run history / suggestions), and a details
/// panel for the selected program. Programs from every bottle are shown together.
struct LibraryView: View {
    @EnvironmentObject var bottleVM: BottleVM
    @ObservedObject private var navigator = LibraryNavigator.shared

    @AppStorage(BottleVM.defaultBottleKey) var defaultBottleURL: URL?
    @AppStorage("libraryDismissedSuggestions") var dismissedSuggestionsRaw: String = ""
    @AppStorage("librarySort") var sort: LibrarySort = .name
    @AppStorage("libraryShowsInspector") var showsInspector = true
    @AppStorage("librarySidebarCompact") private var isSidebarCompact = false

    @State var page: LibraryPage? = .home
    @State var settingsProgram: Program?
    @State private var window: NSWindow?
    /// The bottle whose own settings are open on the Settings page, if any.
    @State private var managedBottleURL: URL?
    @State var selection: LibraryPinItem.ID?
    @State var searchText = ""
    @State var inspectorTab: LibraryInspectorTab = .overview
    @State var suggestions: [LibrarySuggestion] = []
    @State var renameItem: LibraryPinItem?
    @State var artworkItem: LibraryPinItem?
    @State var launchError: String?
    @State private var isDropTargeted = false
    /// Bumped whenever any bottle publishes a change, so the aggregated lists re-render.
    @State private var changeCounter = 0
    /// Bumped when Rum comes to the front, so programs installed meanwhile show up.
    @State var activationCounter = 0

    private let gridColumns = [GridItem(.adaptive(minimum: LibraryCardMetrics.minWidth,
                                                  maximum: LibraryCardMetrics.maxWidth),
                                        spacing: 16, alignment: .top)]

    private var currentPage: LibraryPage { page ?? .home }

    /// Pages showing program cards, which can be selected for the details panel.
    private var showsDetails: Bool { currentPage == .home || currentPage == .library }

    private var showsSearch: Bool { currentPage != .settings }

    var body: some View {
        Group {
            if availableBottles.isEmpty {
                LibraryEmptyState(isCreating: bottleVM.bottles.contains(where: \.inFlight),
                                  onCreate: createDefaultBottle)
            } else {
                splitView
            }
        }
        .onChange(of: navigator.request, initial: true) { _, request in
            guard let request else { return }
            page = request.page
            if let bottleURL = request.bottleURL {
                managedBottleURL = bottleURL
            }
            navigator.request = nil
        }
        .onReceive(bottleChanges) { _ in
            changeCounter &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            activationCounter &+= 1
        }
        .task(id: scanKey) {
            scanForSuggestions()
        }
        .sheet(item: $renameItem) { item in
            RenameView("rename.pin.title", name: item.pin.name) { newName in
                guard let index = item.bottle.settings.pins.firstIndex(where: { $0.url == item.url }) else { return }
                item.bottle.settings.pins[index].name = newName
            }
        }
        .sheet(item: $artworkItem) { item in
            ArtworkPickerSheet(item: item)
        }
        .alert("alert.message", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("button.ok", role: .cancel) {}
        } message: {
            Text(launchError ?? "")
        }
    }

    /// Sidebar, page and details panel, laid out by hand: the system split view can't collapse
    /// its sidebar to icons, and its toolbar puts the search field above the details panel.
    private var splitView: some View {
        // Read so SwiftUI re-evaluates the aggregated lists when a bottle changes.
        let _ = changeCounter // swiftlint:disable:this redundant_discardable_let
        return HStack(spacing: 0) {
            LibrarySidebar(page: $page,
                           isCompact: isSidebarCompact,
                           libraryCount: pinnedItems.count,
                           recentCount: recentEntries.count,
                           foundCount: visibleSuggestions.count,
                           runningCount: runningItems.count,
                           window: window)
            .frame(width: sidebarWidth)
            Divider()
                .ignoresSafeArea()
            // The page's controls live in the page itself, so they follow both side panels.
            VStack(spacing: 0) {
                LibraryTitleBar(title: currentPage.title,
                                searchText: $searchText,
                                showsSearch: showsSearch,
                                isSidebarCompact: isSidebarCompact,
                                showsDetailsToggle: showsDetails,
                                isDetailsShown: showsInspector,
                                onToggleSidebar: toggleSidebar,
                                onToggleDetails: { withAnimation { showsInspector.toggle() } })
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                if currentPage != .home {
                    LibraryLaunchToast(names: launchingNames)
                }
            }
            .animation(.smooth(duration: 0.25), value: launchingNames)
            .background(VisualEffectBackground().ignoresSafeArea())
            // The inspector hosts this column in its own container, which would bring back the
            // space the title bar reserved.
            .ignoresSafeArea(.container, edges: .top)
            .inspector(isPresented: inspectorPresented) {
                inspector
                    .ignoresSafeArea(.container, edges: .top)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
        }
        // The top of the window is the Library's: no system title bar (see HiddenSystemTitleBar).
        .ignoresSafeArea(.container, edges: .top)
        .background(HiddenSystemTitleBar(window: $window))
        // On the container rather than in withAnimation: changes to @AppStorage values don't
        // reliably pick up the transaction.
        .animation(.smooth(duration: 0.28), value: isSidebarCompact)
        .sheet(item: $settingsProgram) { program in
            NavigationStack {
                ProgramView(program: program)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { settingsProgram = nil }
                        }
                    }
            }
            .frame(minWidth: 560, minHeight: 520)
        }
    }

    private var sidebarWidth: CGFloat {
        isSidebarCompact ? LibrarySidebarMetrics.compactWidth : LibrarySidebarMetrics.width
    }

    private func toggleSidebar() {
        isSidebarCompact.toggle()
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch currentPage {
        case .home: homePage
        case .library: libraryPage
        case .recent: recentPage
        case .found: foundPage
        case .settings: SettingsView(managedBottleURL: $managedBottleURL)
        }
    }

    private var libraryPage: some View {
        let items = filteredPinnedItems
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader(count: items.count) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { sort in
                                Text(LocalizedStringKey(sort.rawValue)).tag(sort)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label(LocalizedStringKey(sort.rawValue), systemImage: "arrow.up.arrow.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .help("Sort by")
                }
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        LibraryCard(bottle: item.bottle,
                                    item: item,
                                    isSelected: selection == item.id,
                                    showsBottle: showsBottleNames,
                                    actions: itemActions) {
                            selection = item.id
                            showsInspector = true
                        }
                    }
                    if searchText.isEmpty {
                        LibraryAddCard(action: chooseAndAdd)
                    }
                }
                if items.isEmpty && !searchText.isEmpty {
                    noMatches
                }
            }
            .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                bottom: LibrarySidebarMetrics.margin, trailing: LibrarySidebarMetrics.margin))
            .frame(maxWidth: .infinity, alignment: .leading)
            // Behind the cards rather than around them, so a click on a card never reaches it.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.rum, lineWidth: 2)
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

}

// MARK: - Secondary pages & shared pieces

extension LibraryView {
    private var recentPage: some View {
        let entries = filteredRecentEntries
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                pageHeader(count: entries.count) { EmptyView() }
                if entries.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView("Nothing Played Yet", systemImage: "clock",
                                               description: Text("Programs you run show up here."))
                            .padding(.top, 40)
                    } else {
                        noMatches
                    }
                } else {
                    groupedRows(entries) { item in
                        LibraryRecentRow(bottle: item.bottle,
                                         entry: item.entry,
                                         showsBottle: showsBottleNames,
                                         onRun: { run(item.entry.url, in: item.bottle) })
                    }
                }
            }
            .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                bottom: LibrarySidebarMetrics.margin, trailing: LibrarySidebarMetrics.margin))
        }
    }

    private var homePage: some View {
        LibraryHomePage(running: runningItems,
                        favourites: favouriteItems,
                        recent: recentItems,
                        selection: selection,
                        showsBottleNames: showsBottleNames,
                        actions: itemActions,
                        onSelect: { item in
                            selection = item.id
                            showsInspector = true
                        },
                        onSeeAllRecent: { page = .recent },
                        runControls: { runControls })
    }

    private var foundPage: some View {
        let found = visibleSuggestions.filter { matchesSearch($0.name) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Programs installed in your bottles that have a Start Menu shortcut.")
                    .foregroundStyle(.secondary)
                groupedRows(found) { suggestion in
                    LibrarySuggestionRow(suggestion: suggestion,
                                         showsBottle: showsBottleNames,
                                         onAdd: { add(suggestion) },
                                         onDismiss: { dismiss(suggestion) })
                }
            }
            .padding(EdgeInsets(top: 10, leading: LibrarySidebarMetrics.margin,
                                bottom: LibrarySidebarMetrics.margin, trailing: LibrarySidebarMetrics.margin))
        }
    }

    /// Item count on the left; page controls, the bottle choice and Run on the right.
    private func pageHeader<Controls: View>(count: Int, @ViewBuilder controls: () -> Controls) -> some View {
        HStack(spacing: 12) {
            Text("^[\(count) item](inflect: true)")
                .foregroundStyle(.secondary)
            Spacer()
            controls()
            runControls
        }
    }

    /// The bottle choice (when there is one) and Run Windows App…, at the right of each page's header.
    private var runControls: some View {
        HStack(spacing: 12) {
            if showsBottleNames {
                bottleMenu
            }
            Button(action: chooseAndRun) {
                Label("Run Windows App…", systemImage: "plus")
            }
            .buttonStyle(RumProminentButtonStyle())
            .keyboardShortcut("o", modifiers: .command)
            .disabled(defaultBottle == nil)
            .help("Run a game, app or installer from anywhere on your Mac (⌘O)")
        }
    }

    // MARK: - Inspector

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { showsInspector && showsDetails },
            set: { showsInspector = $0 }
        )
    }

    @ViewBuilder
    private var inspector: some View {
        if let item = selectedItem {
            LibraryInspector(bottle: item.bottle, item: item, actions: itemActions, tab: $inspectorTab)
                .id(item.id)
        } else {
            ContentUnavailableView("No Selection", systemImage: "gamecontroller",
                                   description: Text("Select a game or app to see its details."))
        }
    }
}
