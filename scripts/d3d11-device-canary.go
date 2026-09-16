//go:build windows

// Build with GOOS=windows GOARCH=amd64 go build -o /tmp/rum-d3d11.exe scripts/d3d11-device-canary.go.
// This probe creates a real hardware D3D11 device and rejects WineD3D fallback.
package main

import (
	"fmt"
	"os"
	"syscall"
	"unsafe"
)

func main() {
	dll, err := syscall.LoadDLL("d3d11.dll")
	if err != nil {
		panic(err)
	}
	defer dll.Release()
	create, err := dll.FindProc("D3D11CreateDevice")
	if err != nil {
		panic(err)
	}
	var device, context uintptr
	var feature uint32
	hr, _, _ := create.Call(0, 1, 0, 0, 0, 0, 7,
		uintptr(unsafe.Pointer(&device)), uintptr(unsafe.Pointer(&feature)), uintptr(unsafe.Pointer(&context)))
	fmt.Printf("D3D11CreateDevice HRESULT=0x%08x feature=0x%x device=%x\n", uint32(hr), feature, device)
	if int32(hr) < 0 || device == 0 {
		os.Exit(1)
	}
	getModule := syscall.NewLazyDLL("kernel32.dll").NewProc("GetModuleHandleW")
	name, _ := syscall.UTF16PtrFromString("wined3d.dll")
	fallback, _, _ := getModule.Call(uintptr(unsafe.Pointer(name)))
	if fallback != 0 {
		fmt.Println("FAIL: WineD3D fallback loaded")
		os.Exit(2)
	}
	fmt.Println("PASS: hardware D3D11 device created without WineD3D fallback")
	if len(os.Args) > 1 {
		if err := os.WriteFile(os.Args[1], []byte("PASS"), 0600); err != nil {
			panic(err)
		}
	}
}
