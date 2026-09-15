#!/usr/bin/env bash
#
# Run native renderer loader canaries against disposable Wine prefixes.
#
# This script deliberately uses an installed CrossOver payload; it never downloads, copies,
# or modifies an external engine. The only files it creates are temporary prefix files.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: graphics-canary.sh [--backend all|dxmt|d3dmetal] [--require]

Run a disposable CrossOver renderer loader canary. Without --require, missing external
engines or payloads are reported as skipped and return success.

Environment:
  RUM_CROSSOVER_ROOT              Override the CrossOver engine root.
  RUM_GRAPHICS_CANARY_TIMEOUT     Per-process timeout in seconds (default: 60).
EOF
}

backend_selection="all"
require_engine=false
while (($# > 0)); do
    case "$1" in
        --backend)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            backend_selection="$2"
            shift 2
            ;;
        --require)
            require_engine=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

case "$backend_selection" in
    all|dxmt|d3dmetal) ;;
    *)
        echo "Unsupported backend: $backend_selection" >&2
        exit 2
        ;;
esac

if [[ -x /usr/bin/perl ]]; then
    perl_bin="/usr/bin/perl"
else
    echo "The graphics canary requires Perl for portable process timeouts." >&2
    exit 2
fi

canary_timeout="${RUM_GRAPHICS_CANARY_TIMEOUT:-60}"
crossover_root="${RUM_CROSSOVER_ROOT:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
wine_executable="$crossover_root/lib/wine/x86_64-unix/wine"
wineserver_executable="$crossover_root/CrossOver-Hosted Application/wineserver"

run_with_timeout() {
    "$perl_bin" -e 'alarm shift; exec @ARGV' "$@"
}

has_file() {
    [[ -e "$1" ]]
}

payload_available() {
    local backend="$1"
    case "$backend" in
        dxmt)
            has_file "$crossover_root/lib/dxmt/x86_64-unix/winemetal.so" \
                && has_file "$crossover_root/lib/dxmt/x86_64-windows/winemetal.dll" \
                && has_file "$crossover_root/lib/dxmt/x86_64-windows/d3d11.dll" \
                && has_file "$crossover_root/lib/dxmt/x86_64-windows/dxgi.dll"
            ;;
        d3dmetal)
            has_file "$crossover_root/lib64/apple_gptk/external/D3DMetal.framework" \
                && has_file "$crossover_root/lib64/apple_gptk/external/libd3dshared.dylib" \
                && has_file "$crossover_root/lib64/apple_gptk/wine/x86_64-windows/d3d11.dll" \
                && has_file "$crossover_root/lib64/apple_gptk/wine/x86_64-windows/d3d12.dll" \
                && has_file "$crossover_root/lib64/apple_gptk/wine/x86_64-windows/dxgi.dll"
            ;;
    esac
}

cleanup_current() {
    if [[ -z "${active_temp_dir:-}" ]]; then
        return
    fi

    local prefix="$active_temp_dir/prefix"
    local cleanup_environment=(
        "WINEPREFIX=$prefix"
        "WINEDEBUG=-all"
        "WINEESYNC=0"
        "WINEMSYNC=0"
        "CX_ROOT=$crossover_root"
        "WINESERVER=$wineserver_executable"
    )
    run_with_timeout 15 env "${cleanup_environment[@]}" "$wineserver_executable" -k \
        >/dev/null 2>&1 || true
    run_with_timeout 15 env "${cleanup_environment[@]}" "$wineserver_executable" -w \
        >/dev/null 2>&1 || true
    rm -rf "$active_temp_dir"
    active_temp_dir=""
}

trap cleanup_current EXIT

run_backend_canary() {
    local backend="$1"
    local renderer_windows
    local renderer_unix
    local dll_overrides
    local extra_environment=()

    case "$backend" in
        dxmt)
            renderer_windows="$crossover_root/lib/dxmt/x86_64-windows"
            renderer_unix="$crossover_root/lib/dxmt/x86_64-unix"
            dll_overrides="dxgi,d3d11,d3d10core=n,b"
            ;;
        d3dmetal)
            renderer_windows="$crossover_root/lib64/apple_gptk/wine/x86_64-windows"
            renderer_unix="$crossover_root/lib64/apple_gptk/wine/x86_64-unix"
            dll_overrides="dxgi,d3d11,d3d12=n,b"
            extra_environment=(
                "CX_APPLEGPTK_LIBD3DSHARED_PATH=$crossover_root/lib64/apple_gptk/external/libd3dshared.dylib"
                "GPTK_METAL_LIB_PATH=$crossover_root/lib64/apple_gptk/external/libd3dshared.dylib"
                "DYLD_FALLBACK_LIBRARY_PATH=$crossover_root/lib64/apple_gptk/external:$crossover_root/lib64:$crossover_root/lib"
                "DYLD_FALLBACK_FRAMEWORK_PATH=$crossover_root/lib64/apple_gptk/external"
            )
            ;;
    esac

    active_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/RumGraphicsCanary.XXXXXX")"
    local prefix="$active_temp_dir/prefix"
    local log="$active_temp_dir/canary.log"
    local base_dll_paths="$crossover_root/lib/wine/x86_64-windows:$crossover_root/lib/wine/x86_64-unix:$crossover_root/lib/wine/i386-windows:$crossover_root/lib/wine"
    local path_value="$crossover_root/lib/wine/x86_64-unix:$crossover_root/CrossOver-Hosted Application:$crossover_root/lib:$crossover_root/bin:${PATH:-/usr/bin:/bin}"
    local library_path="$crossover_root/lib:$crossover_root/lib64:${LD_LIBRARY_PATH:-}"
    local environment=(
        "WINEPREFIX=$prefix"
        "WINEDEBUG=-all"
        "WINEESYNC=0"
        "WINEMSYNC=0"
        "CX_ROOT=$crossover_root"
        "CX_GRAPHICS_BACKEND=$backend"
        "PATH=$path_value"
        "LD_LIBRARY_PATH=$library_path"
        "WINELOADER=$wine_executable"
        "WINESERVER=$wineserver_executable"
        "WINEDLLPATH=$renderer_windows:$renderer_unix:$base_dll_paths"
        "WINEDLLOVERRIDES=$dll_overrides"
    )
    environment+=("${extra_environment[@]}")

    echo "Running $backend canary with CrossOver payload..."
    if ! run_with_timeout "$canary_timeout" env "${environment[@]}" "$wine_executable" \
        wineboot -u >"$log" 2>&1; then
        echo "FAIL: $backend prefix initialization failed or timed out." >&2
        tail -120 "$log" >&2 || true
        return 1
    fi

    local system32="$prefix/drive_c/windows/system32"
    local syswow64="$prefix/drive_c/windows/syswow64"
    mkdir -p "$system32" "$syswow64"

    shopt -s nullglob
    local renderer_dlls=("$renderer_windows"/*.dll)
    local renderer_x86_dlls=()
    if [[ "$backend" == "dxmt" && -d "$crossover_root/lib/dxmt/i386-windows" ]]; then
        renderer_x86_dlls=("$crossover_root/lib/dxmt/i386-windows"/*.dll)
    fi
    shopt -u nullglob
    if ((${#renderer_dlls[@]} == 0)); then
        echo "FAIL: $backend has no native renderer DLLs to stage." >&2
        return 1
    fi
    cp "${renderer_dlls[@]}" "$system32/"
    if ((${#renderer_x86_dlls[@]} > 0)); then
        cp "${renderer_x86_dlls[@]}" "$syswow64/"
    fi

    environment+=("WINEDEBUG=+loaddll")
    local load_status=0
    run_with_timeout "$canary_timeout" env "${environment[@]}" "$wine_executable" \
        regsvr32.exe /s d3d11.dll >>"$log" 2>&1 || load_status=$?
    # regsvr32 returns 4 when the DLL loads but does not export DllRegisterServer. That is the
    # expected result for D3D renderer DLLs; import failures and timeouts remain fatal.
    if ((load_status != 0 && load_status != 4)); then
        echo "FAIL: $backend d3d11.dll loader process exited with $load_status." >&2
        tail -120 "$log" >&2 || true
        return 1
    fi
    if grep -Eiq 'err:module:import_dll|status c0000135|Library d3d11\.dll.*not found' "$log"; then
        echo "FAIL: $backend loader reported a missing D3D11 dependency." >&2
        tail -120 "$log" >&2 || true
        return 1
    fi
    if ! grep -Eiq 'd3d11\.dll' "$log"; then
        echo "FAIL: $backend loader produced no d3d11.dll load record." >&2
        tail -120 "$log" >&2 || true
        return 1
    fi

    echo "PASS: $backend loaded d3d11.dll in a disposable prefix."
    cleanup_current
}

if [[ ! -x "$wine_executable" || ! -x "$wineserver_executable" ]]; then
    if "$require_engine"; then
        echo "FAIL: CrossOver Wine executables were not found under $crossover_root." >&2
        exit 1
    fi
    echo "SKIP: CrossOver is not installed at $crossover_root."
    exit 0
fi

backends=(dxmt d3dmetal)
if [[ "$backend_selection" != "all" ]]; then
    backends=("$backend_selection")
fi

for backend in "${backends[@]}"; do
    if ! payload_available "$backend"; then
        if "$require_engine"; then
            echo "FAIL: $backend payload is incomplete in $crossover_root." >&2
            exit 1
        fi
        echo "SKIP: $backend payload is incomplete in $crossover_root."
        continue
    fi
    run_backend_canary "$backend"
done
