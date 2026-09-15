//
//  GraphicsBackend.swift
//  WhiskyKit
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

import Foundation

/// Direct3D translation path used by a bottle.
///
/// `dxvk` is retained as a case name and as a compatibility property on `BottleSettings` because
/// it is already part of Rum's on-disk format. New code should use this enum instead of a Boolean.
public enum GraphicsBackend: String, Codable, CaseIterable, Equatable, Sendable {
    case wineD3D
    case dxvk
    case dxmt
    case d3dmetal

    public var displayName: String {
        switch self {
        case .wineD3D:
            return "WineD3D"
        case .dxvk:
            return "DXVK"
        case .dxmt:
            return "DXMT"
        case .d3dmetal:
            return "D3DMetal"
        }
    }

    /// Whether the current supported runtime contract requires a 64-bit Windows prefix.
    /// DXVK and WineD3D remain available for the legacy 32-bit path.
    public var requiresWin64: Bool {
        switch self {
        case .wineD3D, .dxvk:
            return false
        case .dxmt, .d3dmetal:
            return true
        }
    }

    public var supportedDirectXVersions: String {
        switch self {
        case .wineD3D:
            return "Wine's built-in Direct3D implementation"
        case .dxvk:
            return "Direct3D 9/10/11 via Vulkan"
        case .dxmt:
            return "Direct3D 10/11 via Metal"
        case .d3dmetal:
            return "Direct3D 11/12 via Metal"
        }
    }

    /// CrossOver's bottle environment uses a different spelling for the WineD3D backend.
    var crossOverValue: String {
        switch self {
        case .wineD3D:
            return "wined3d"
        case .dxvk:
            return "dxvk"
        case .dxmt:
            return "dxmt"
        case .d3dmetal:
            return "d3dmetal"
        }
    }
}

public enum GraphicsBackendError: Error, LocalizedError, Equatable, Sendable {
    case unavailable(GraphicsBackend, String)
    case unsupportedArchitecture(GraphicsBackend, BottleArchitecture)
    case conflictingBackend(String, GraphicsBackend, GraphicsBackend)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let backend, let reason):
            return "\(backend.displayName) is unavailable: \(reason) \(recoveryAdvice)"
        case .unsupportedArchitecture(let backend, let architecture):
            return "\(backend.displayName) does not support \(architecture.pretty()) bottles. "
                + "Use a 64-bit bottle or choose WineD3D/DXVK."
        case .conflictingBackend(let bottlePath, let active, let requested):
            return "Bottle \(bottlePath) is already running with \(active.displayName); "
                + "cannot start \(requested.displayName) concurrently."
        }
    }

    private var recoveryAdvice: String {
        switch self {
        case .unavailable(let backend, _):
            switch backend {
            case .wineD3D:
                return ""
            case .dxvk:
                return "Install DXVK or choose WineD3D."
            case .dxmt, .d3dmetal:
                return "Select a Wine engine with Metal support in Configuration → Runtime, "
                    + "or choose another renderer."
            }
        case .unsupportedArchitecture, .conflictingBackend:
            return ""
        }
    }
}

/// Result shown by the UI and used to prevent a backend from being selected when its runtime is
/// not present or when the active Wine engine cannot load it.
public struct GraphicsBackendAvailability: Identifiable, Equatable, Sendable {
    public let backend: GraphicsBackend
    public let isAvailable: Bool
    public let reason: String?

    public var id: GraphicsBackend { backend }

    public init(backend: GraphicsBackend, isAvailable: Bool, reason: String? = nil) {
        self.backend = backend
        self.isAvailable = isAvailable
        self.reason = reason
    }
}

/// Static information discovered from a particular Wine tree. This is deliberately
/// separate from `GraphicsBackendAvailability`: a tree may contain a payload which is only a
/// candidate until a runtime canary has proved that it loads.
public struct WineGraphicsCapabilities: Equatable, Sendable {
    public let engineID: String
    public let engineName: String
    public let wineRootURL: URL
    public let macDriverExportsRequiredAPI: Bool
    public let dxmtRootURL: URL?
    public let d3dmetalRootURL: URL?

    public var supportsDXMT: Bool {
        macDriverExportsRequiredAPI && dxmtRootURL != nil
    }

    public var supportsD3DMetal: Bool {
        macDriverExportsRequiredAPI && d3dmetalRootURL != nil
    }

    public init(
        engineID: String,
        engineName: String,
        wineRootURL: URL,
        macDriverExportsRequiredAPI: Bool,
        dxmtRootURL: URL?,
        d3dmetalRootURL: URL?
    ) {
        self.engineID = engineID
        self.engineName = engineName
        self.wineRootURL = wineRootURL
        self.macDriverExportsRequiredAPI = macDriverExportsRequiredAPI
        self.dxmtRootURL = dxmtRootURL
        self.d3dmetalRootURL = d3dmetalRootURL
    }

    public func availability(
        for backend: GraphicsBackend,
        architecture: BottleArchitecture,
        dxvkInstalled: Bool
    ) -> GraphicsBackendAvailability {
        if backend.requiresWin64 && architecture != .win64 {
            return GraphicsBackendAvailability(
                backend: backend,
                isAvailable: false,
                reason: "Only 64-bit prefixes are supported by this backend."
            )
        }

        switch backend {
        case .wineD3D:
            return GraphicsBackendAvailability(backend: backend, isAvailable: true)
        case .dxvk:
            return GraphicsBackendAvailability(
                backend: backend,
                isAvailable: dxvkInstalled,
                reason: dxvkInstalled ? nil : "DXVK is not installed."
            )
        case .dxmt:
            if !macDriverExportsRequiredAPI {
                return GraphicsBackendAvailability(
                    backend: backend,
                    isAvailable: false,
                    reason: "The selected Wine engine does not export DXMT's required macOS driver API."
                )
            }
            return GraphicsBackendAvailability(
                backend: backend,
                isAvailable: supportsDXMT,
                reason: supportsDXMT ? nil : "No compatible DXMT payload was found in the selected Wine engine."
            )
        case .d3dmetal:
            if !macDriverExportsRequiredAPI {
                return GraphicsBackendAvailability(
                    backend: backend,
                    isAvailable: false,
                    reason: "The selected Wine engine does not expose the required Metal integration."
                )
            }
            return GraphicsBackendAvailability(
                backend: backend,
                isAvailable: supportsD3DMetal,
                reason: supportsD3DMetal
                    ? nil
                    : "No complete GPTK/D3DMetal payload was found in the selected Wine engine."
            )
        }
    }
}
