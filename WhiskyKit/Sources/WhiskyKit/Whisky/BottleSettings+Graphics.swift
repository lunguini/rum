//
//  BottleSettings+Graphics.swift
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

extension BottleSettings {
    /// The renderer selected for this bottle. Existing bottles without this key preserve their
    /// previous behavior: `dxvk == true` maps to DXVK and `dxvk == false` maps to WineD3D.
    public var graphicsBackend: GraphicsBackend {
        get { selectedGraphicsBackend ?? (dxvkConfig.dxvk ? .dxvk : .wineD3D) }
        set {
            selectedGraphicsBackend = newValue
            // Keep the legacy field synchronized for older Rum versions and older diagnostics.
            dxvkConfig.dxvk = newValue == .dxvk
        }
    }

    /// Compatibility view for callers and metadata written by older Rum versions.
    public var dxvk: Bool {
        get { graphicsBackend == .dxvk }
        set { graphicsBackend = newValue ? .dxvk : .wineD3D }
    }

    public var dxvkAsync: Bool {
        get { dxvkConfig.dxvkAsync }
        set { dxvkConfig.dxvkAsync = newValue }
    }

    public var dxvkHud: DXVKHUD {
        get { dxvkConfig.dxvkHud }
        set { dxvkConfig.dxvkHud = newValue }
    }

    /// Frame rate cap applied via `DXVK_FRAME_RATE`. `0` means unlimited.
    public var dxvkFrameRate: Int {
        get { dxvkConfig.dxvkFrameRate }
        set { dxvkConfig.dxvkFrameRate = newValue }
    }

    public func environmentVariables(wineEnv: inout [String: String]) {
        if architecture == .win32 {
            wineEnv.updateValue(architecture.rawValue, forKey: "WINEARCH")
        }
        applyGraphicsBackendEnvironment(to: &wineEnv)
        applySyncEnvironment(to: &wineEnv)
        applyMetalEnvironment(to: &wineEnv)
    }

    private func applyGraphicsBackendEnvironment(to wineEnv: inout [String: String]) {
        switch graphicsBackend {
        case .dxvk:
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=n,b", forKey: "WINEDLLOVERRIDES")
            switch dxvkHud {
            case .full:
                wineEnv.updateValue("full", forKey: "DXVK_HUD")
            case .partial:
                wineEnv.updateValue("devinfo,fps,frametimes", forKey: "DXVK_HUD")
            case .fps:
                wineEnv.updateValue("fps", forKey: "DXVK_HUD")
            case .off:
                break
            }

            if dxvkFrameRate > 0 {
                wineEnv.updateValue(String(dxvkFrameRate), forKey: "DXVK_FRAME_RATE")
            }
            if dxvkAsync {
                wineEnv.updateValue("1", forKey: "DXVK_ASYNC")
            }

        case .dxmt:
            // DXMT's native/builtin layout is supplied by the selected Wine engine. The native
            // first order lets the engine's renderer DLLs win over WineD3D without copying them
            // into the bottle.
            wineEnv.updateValue("dxgi,d3d11,d3d10core=n,b", forKey: "WINEDLLOVERRIDES")

        case .d3dmetal:
            // CrossOver ships D3DMetal's D3D modules as native Windows DLLs. Keep builtin as a
            // fallback for engines that integrate the modules into Wine itself.
            wineEnv.updateValue("dxgi,d3d11,d3d12=n,b", forKey: "WINEDLLOVERRIDES")

        case .wineD3D:
            // Force Wine's builtin path so a legacy DXVK DLL left by an older Rum version
            // cannot take precedence in a terminal or shortcut launch.
            wineEnv.updateValue("dxgi,d3d9,d3d10core,d3d11=b", forKey: "WINEDLLOVERRIDES")
        }
    }

    private func applySyncEnvironment(to wineEnv: inout [String: String]) {
        switch enhancedSync {
        case .none:
            break
        case .esync:
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        case .msync:
            wineEnv.updateValue("1", forKey: "WINEMSYNC")
            // D3DM detects ESYNC and changes behaviour accordingly, so we have to lie to it so
            // that it doesn't break under MSYNC. Values are hardcoded in lid3dshared.dylib.
            wineEnv.updateValue("1", forKey: "WINEESYNC")
        }
    }

    private func applyMetalEnvironment(to wineEnv: inout [String: String]) {
        if metalHud {
            wineEnv.updateValue("1", forKey: "MTL_HUD_ENABLED")
        }
        if metalTrace {
            wineEnv.updateValue("1", forKey: "METAL_CAPTURE_ENABLED")
        }
        if avxEnabled {
            wineEnv.updateValue("1", forKey: "ROSETTA_ADVERTISE_AVX")
        }
        if dxrEnabled {
            wineEnv.updateValue("1", forKey: "D3DM_SUPPORT_DXR")
        }
    }
}
