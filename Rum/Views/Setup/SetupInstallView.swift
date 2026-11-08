//
//  SetupInstallView.swift
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

enum SetupStepState: Equatable { case pending, running, done, skipped(String), failed(String) }
enum SetupStepKind { case rosetta, engine, dxvk, dxmt, bottle }

struct SetupStep: Identifiable {
    let kind: SetupStepKind
    let title: String
    let required: Bool
    var state: SetupStepState = .pending
    var id: SetupStepKind { kind }
}

/// Runs a `SetupPlan` step by step and shows a checklist. Only Rosetta and the engine are
/// required; an optional step that fails is shown as a warning and setup still finishes.
struct SetupInstallView: View {
    let plan: SetupPlan
    @Binding var showSetup: Bool
    private var bottleVM: BottleVM { .shared }

    @State private var steps: [SetupStep] = []
    @State private var finished = false
    @State private var failedRequired = false

    var body: some View {
        VStack(alignment: .leading) {
            Text(finished ? (failedRequired ? "Setup didn't finish" : "You're all set") : "Setting up Rum…")
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
            Form {
                ForEach(steps) { step in
                    HStack(alignment: .firstTextBaseline) {
                        icon(for: step.state).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                            if let note = note(for: step.state) {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("setup.done") { showSetup = false }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!finished)
            }
        }
        .frame(width: 440, height: 360)
        .navigationBarBackButtonHidden(!finished)
        .task {
            guard steps.isEmpty else { return }
            steps = Self.steps(for: plan)
            await run()
        }
    }

    static func steps(for plan: SetupPlan) -> [SetupStep] {
        var steps: [SetupStep] = []
        if !Rosetta2.isRosettaInstalled {
            steps.append(SetupStep(kind: .rosetta, title: "Install Rosetta", required: true))
        }
        let engineTitle = switch plan.engine {
        case .sikarugir: "Install the Sikarugir Wine engine"
        case .gcenx: "Install Gcenx Wine"
        case .external(let choice): "Use \(choice.name)"
        }
        steps.append(SetupStep(kind: .engine, title: engineTitle, required: true))
        if plan.installDXVK { steps.append(SetupStep(kind: .dxvk, title: "Install DXVK", required: false)) }
        if plan.installDXMT { steps.append(SetupStep(kind: .dxmt, title: "Install DXMT", required: false)) }
        if plan.createDefaultBottle {
            steps.append(SetupStep(kind: .bottle, title: "Create your Default bottle", required: false))
        }
        return steps
    }

    @MainActor
    private func run() async {
        for index in steps.indices {
            steps[index].state = .running
            do {
                steps[index].state = try await perform(steps[index].kind)
            } catch {
                steps[index].state = .failed(error.localizedDescription)
            }
            if case .failed = steps[index].state, steps[index].required {
                failedRequired = true
                for rest in steps.indices where rest > index {
                    steps[rest].state = .skipped("Needs the step above.")
                }
                break
            }
        }
        finished = true
    }

    /// Returns `.done` or `.skipped`; throws on failure.
    @MainActor
    private func perform(_ kind: SetupStepKind) async throws -> SetupStepState {
        switch kind {
        case .rosetta:
            guard try await Rosetta2.installRosetta() else { throw SetupError("Rosetta could not be installed.") }
        case .engine:
            await RumApp.killBottlesAndWait()
            try await installEngine()
        case .dxvk:
            try await installDXVK()
        case .dxmt:
            return try await installDXMT()
        case .bottle:
            bottleVM.loadBottles()
            if !bottleVM.bottles.isEmpty {
                return .skipped("You already have a bottle, so none was created.")
            }
            _ = try await bottleVM.createDefaultBottle()
        }
        return .done
    }

    private func installDXVK() async throws {
        guard let url = await RumWineInstaller.fetchLatestDXVKRelease() else {
            throw SetupError("Couldn't find a DXVK download. You can install it later from Settings.")
        }
        let (tarball, _) = try await URLSession.shared.download(from: url)
        await Task.detached { RumWineInstaller.installDXVK(from: tarball) }.value
        guard RumWineInstaller.isDXVKInstalled() else { throw SetupError("DXVK could not be installed.") }
    }

    private func installDXMT() async throws -> SetupStepState {
        if let capabilities = RumWineInstaller.wineGraphicsCapabilities(for: nil),
           !capabilities.macDriverExportsRequiredAPI {
            return .skipped("\(capabilities.engineName) can't use DXMT, so it was skipped.")
        }
        guard let release = await RumWineInstaller.fetchLatestDXMTRelease() else {
            throw SetupError("Couldn't find a DXMT download. You can install it later from the Wine manager.")
        }
        let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
        try await RumWineInstaller.installDXMT(from: tarball, version: release.version)
        return .done
    }

    private func installEngine() async throws {
        switch plan.engine {
        case .sikarugir:
            try await installFirstWorkingSikarugirEngine()
        case .gcenx:
            guard let release = await RumWineInstaller.fetchLatestRelease() else {
                throw SetupError("Couldn't reach the Wine download list. Check your connection and try again.")
            }
            let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
            try await RumWineInstaller.install(from: tarball, version: release.version, activate: false)
            let id = WineEngine.managedID(kind: .gcenx, version: release.version)
            guard await RumWineInstaller.engineStarts(id) else {
                throw SetupError("Wine \(release.version) installed but couldn't start on this Mac. "
                    + "Try the Sikarugir engine instead.")
            }
            try RumWineInstaller.activateWineEngine(id)
        case .external(let choice):
            let engine = switch choice.kind {
            case .crossOver: try RumWineInstaller.importCrossOverEngine(at: choice.appURL)
            case .gamePortingToolkit: try RumWineInstaller.importGamePortingToolkitEngine(at: choice.appURL)
            }
            try RumWineInstaller.activateExternalWineEngine(engine.id)
        }
    }

    /// Install the newest Sikarugir engine that actually starts on this Mac. A brand-new Wine line
    /// can install cleanly yet fail to launch anything, so try the newest build of each Wine
    /// version in turn and remove the ones that don't start.
    private func installFirstWorkingSikarugirEngine() async throws {
        let releases = await RumWineInstaller.fetchAvailableSikarugirReleases()
            .filter { $0.version.hasPrefix("WS12") && !$0.version.lowercased().contains("battle") }
        guard !releases.isEmpty else {
            throw SetupError("Couldn't reach the Sikarugir engine list. Check your connection and try again.")
        }
        // Newest build per Wine version ("WS12WineSikarugir11.0_1" → "11"), newest version first.
        var seenLines = Set<String>()
        let candidates = releases.filter { release in
            let line = release.version.replacingOccurrences(of: "WS12WineSikarugir", with: "")
                .split(separator: ".").first.map(String.init) ?? release.version
            return seenLines.insert(line).inserted
        }.prefix(3)

        for release in candidates {
            let (tarball, _) = try await URLSession.shared.download(from: release.downloadURL)
            try await RumWineInstaller.installSikarugirEngine(from: tarball, version: release.version, activate: false)
            if await RumWineInstaller.engineStarts(release.id) {
                try RumWineInstaller.activateWineEngine(release.id)
                return
            }
            try? RumWineInstaller.removeWineEngine(release.id)
        }
        throw SetupError("None of the recent Sikarugir engines could start on this Mac. "
            + "Try Advanced setup with the Gcenx engine.")
    }

    @ViewBuilder
    private func icon(for state: SetupStepState) -> some View {
        switch state {
        case .pending: Image(systemName: "circle").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func note(for state: SetupStepState) -> String? {
        switch state {
        case .skipped(let note), .failed(let note): note
        default: nil
        }
    }
}

private struct SetupError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
