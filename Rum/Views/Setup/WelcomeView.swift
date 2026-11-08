//
//  WelcomeView.swift
//  Rum
//
//  This file is part of Rum.
//
//  Rum is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  Rum is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with Rum.
//  If not, see https://www.gnu.org/licenses/.
//

import SwiftUI
import RumKit

/// The dependency overview shown on first launch and from Settings. Rum supports several Wine
/// engines (Gcenx, Sikarugir, CrossOver, GPTK) and several graphics runtimes, so this screen
/// only insists on the essentials, Rosetta and one usable engine, and leaves the rest to the
/// Wine manager.
struct WelcomeView: View {
    @State private var status: DependencyStatus?
    @State private var showWineManager = false
    @Binding var path: [SetupStage]
    @Binding var showSetup: Bool
    var firstTime: Bool

    var body: some View {
        VStack {
            VStack {
                Text(firstTime ? "setup.welcome" : "setup.title")
                    .font(.title)
                    .fontWeight(.bold)
                Text(firstTime ? "setup.welcome.subtitle" : "setup.subtitle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            if let status, !status.requiredReady {
                SetupChooser(path: $path)
            } else {
                overview
            }
        }
        .frame(width: 440, height: 360)
        .onAppear(perform: refresh)
        // The overview stays alive underneath the install steps, so `onAppear` alone misses the
        // result of an install. Re-check whenever the user lands back here.
        .onChange(of: path) { _, newPath in
            if newPath.isEmpty { refresh() }
        }
        .sheet(isPresented: $showWineManager, onDismiss: refresh) {
            WineManagerView()
        }
    }

    @ViewBuilder
    private var overview: some View {
            Form {
                Section("Required") {
                    DependencyRow(name: "Rosetta", detail: nil, state: status.map { $0.rosetta ? .ready : .missing })
                    DependencyRow(
                        name: "Wine engine",
                        detail: status?.wineEngine ?? (status == nil ? nil : "Not installed"),
                        state: status.map { $0.wineEngine != nil ? .ready : .missing }
                    ) {
                        Button(status?.wineEngine == nil ? "Choose…" : "Manage…") {
                            showWineManager = true
                        }
                    }
                }
                Section("Graphics (optional)") {
                    DependencyRow(name: "DXVK", detail: nil, state: status.map { $0.dxvk ? .ready : .optional }) {
                        if status?.dxvk == false {
                            Button("Install") { path.append(.dxvkDownload) }
                        }
                    }
                    DependencyRow(
                        name: "DXMT",
                        detail: status?.dxmt,
                        state: status.map { $0.dxmt != nil ? .ready : .optional }
                    ) {
                        if status?.dxmt == nil {
                            Button("Install…") { showWineManager = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                if let status {
                    if !status.requiredReady {
                        Button("setup.quit") {
                            exit(0)
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    Button(status.requiredReady ? "setup.done" : "setup.next") {
                        advanceSetup(status)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
    }

    private func refresh() {
        status = DependencyStatus.current()
    }

    private func advanceSetup(_ status: DependencyStatus) {
        if !status.rosetta {
            path.append(.rosetta)
        } else if status.wineEngine == nil {
            path.append(.rumWineDownload)
        } else {
            showSetup = false
        }
    }
}

/// First-run choice between the one-click Basic install and the Advanced options.
private struct SetupChooser: View {
    enum Mode: Hashable { case basic, advanced }

    @Binding var path: [SetupStage]
    @State private var mode = Mode.basic
    @State private var plan = SetupPlan.basic
    @State private var externalEngines: [SetupPlan.ExternalEngineChoice] = []

    var body: some View {
        VStack {
            Picker("", selection: $mode) {
                Text("Basic").tag(Mode.basic)
                Text("Advanced").tag(Mode.advanced)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            Form {
                if mode == .basic {
                    Section {
                        Label("Sikarugir Wine engine", systemImage: "wineglass")
                        Label("DXVK and DXMT for DirectX games", systemImage: "gamecontroller")
                        Label("A Default bottle, ready for your games", systemImage: "shippingbox")
                    } footer: {
                        Text("Downloads about 500 MB. Sikarugir is a third-party Wine build; "
                             + "you can switch engines any time in Settings.")
                    }
                } else {
                    Section {
                        Picker("Wine engine", selection: $plan.engine) {
                            Text(SetupPlan.Engine.sikarugir.title).tag(SetupPlan.Engine.sikarugir)
                            Text(SetupPlan.Engine.gcenx.title).tag(SetupPlan.Engine.gcenx)
                            ForEach(externalEngines, id: \.self) { choice in
                                Text(choice.name).tag(SetupPlan.Engine.external(choice))
                            }
                        }
                        Toggle("DXVK (DirectX 9–11 via Vulkan)", isOn: $plan.installDXVK)
                        Toggle("DXMT (DirectX 10–11 via Metal)", isOn: $plan.installDXMT)
                        Toggle("Create a Default bottle", isOn: $plan.createDefaultBottle)
                    } footer: {
                        Text("WineD3D comes with every engine, so games still run with both "
                             + "graphics runtimes off. DXMT is skipped if the engine can't use it.")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Button("setup.quit") { exit(0) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .basic ? "Install" : "Install Selected") {
                    path.append(.install(mode == .basic ? .basic : plan))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { externalEngines = SetupPlan.detectedExternalEngines() }
    }
}

struct DependencyStatus: Equatable {
    var rosetta: Bool
    /// Display name of the usable global default engine, if any.
    var wineEngine: String?
    var dxvk: Bool
    /// Installed DXMT version, if any.
    var dxmt: String?

    var requiredReady: Bool { rosetta && wineEngine != nil }

    static func current() -> DependencyStatus {
        let engine = try? RumWineInstaller.wineEngine(for: nil)
        return DependencyStatus(
            rosetta: Rosetta2.isRosettaInstalled,
            wineEngine: engine.map { "\($0.displayName) · \($0.kind.displayName)" },
            dxvk: RumWineInstaller.isDXVKInstalled(),
            dxmt: RumWineInstaller.installedDXMTVersion()
        )
    }
}

private struct DependencyRow<Actions: View>: View {
    enum State { case ready, missing, optional }

    let name: String
    let detail: String?
    /// `nil` while checking.
    let state: State?
    @ViewBuilder var actions: () -> Actions

    init(name: String, detail: String?, state: State?, @ViewBuilder actions: @escaping () -> Actions) {
        self.name = name
        self.detail = detail
        self.state = state
        self.actions = actions
    }

    var body: some View {
        HStack {
            Group {
                if let state {
                    Circle().foregroundStyle(color(for: state))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail ?? label(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            actions()
        }
    }

    private func color(for state: State) -> Color {
        switch state {
        case .ready: .green
        case .missing: .red
        case .optional: .secondary
        }
    }

    private func label(for state: State?) -> String {
        let format = switch state {
        case .ready: String(localized: "setup.install.installed")
        case .missing, .optional: String(localized: "setup.install.notInstalled")
        case nil: String(localized: "setup.install.checking")
        }
        return String(format: format, name)
    }
}

extension DependencyRow where Actions == EmptyView {
    init(name: String, detail: String?, state: State?) {
        self.init(name: name, detail: detail, state: state) { EmptyView() }
    }
}
