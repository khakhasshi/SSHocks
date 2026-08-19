# SSHocks

SSHocks is a macOS SwiftUI menu bar app for turning any reachable SSH server into a local SOCKS5 proxy.

It wraps the system `/usr/bin/ssh` command with a desktop interface, remembers authenticated servers, can switch macOS system SOCKS proxy settings, and includes diagnostics for common SSH/proxy failures.

## What It Does

- Starts an SSH dynamic port-forwarding tunnel with `ssh -N -D 127.0.0.1:<local-port>`.
- Supports password login and private-key login.
- Stores saved server profiles in `UserDefaults`.
- Stores saved SSH passwords in macOS Keychain.
- Shows a menu bar status item for quick connect, disconnect, copy, system proxy, TUN mode, and server-pool actions.
- Can enable or disable macOS system SOCKS proxy via `/usr/sbin/networksetup`.
- Generates a Clash/ClashX Pro YAML snippet for the current local SOCKS5 proxy.
- Runs diagnostics for `/usr/bin/ssh`, local port occupancy, remote SSH reachability, and SOCKS5 egress.
- Optionally launches a local `sing-box` TUN engine so routable traffic can go through the SSH-backed SOCKS5 proxy.

## Project Layout

```text
SSHocks.xcodeproj/
SSHocks/
  SSHocksApp.swift           App entrypoint, menu bar integration, shutdown cleanup
  ContentView.swift          Main SwiftUI UI, profile store, Clash YAML, settings
  SSHocksMenuBarView.swift   Menu bar controls and status label
  SSHTunnelManager.swift     /usr/bin/ssh process lifecycle and auto reconnect
  SystemProxyManager.swift   macOS networksetup SOCKS proxy control
  TUNModeManager.swift       sing-box based TUN mode
  ProxyHealthMonitor.swift   SOCKS5 probe and adaptive health checks
  DiagnosticRunner.swift     Local SSH/proxy diagnostic report
  KeychainStore.swift        Password persistence in macOS Keychain
```

## Requirements

- macOS with Xcode installed.
- `/usr/bin/ssh`, `/usr/bin/nc`, `/usr/bin/curl`, `/usr/sbin/lsof`, and `/usr/sbin/networksetup`.
- A reachable SSH server that allows TCP forwarding.
- Optional for TUN mode: `sing-box`, installed by Homebrew or placed in the app bundle.

The current project is an Xcode app target named `SSHocks`.

## Build And Run

Open the project in Xcode:

```sh
open SSHocks.xcodeproj
```

Then select the `SSHocks` scheme and run it.

Command-line build:

```sh
xcodebuild -project SSHocks.xcodeproj -scheme SSHocks -configuration Debug build
```

## Basic Usage

1. Open SSHocks.
2. Go to **新建连接**.
3. Enter the SSH host, SSH port, username, local SOCKS5 port, and proxy name.
4. Choose either password auth or private-key auth.
5. Click connect.
6. Point a browser, Clash profile, or macOS system proxy at:

```text
socks5://127.0.0.1:1080
```

The local port is configurable. `1080` is the default.

Under the hood, SSHocks starts an equivalent command:

```sh
ssh -N -D 127.0.0.1:1080 -p 22 user@example.com
```

## Server Pool

After a successful connection, SSHocks records the server as a profile. Profiles include:

- display name
- host and SSH port
- username
- local SOCKS5 port
- auth method
- private-key path, when used
- group and tags
- favorite status
- last connection time and connection count

Password values are saved in macOS Keychain under the SSHocks service name. They are not written into the Git repository.

## System Proxy Mode

SSHocks can write macOS SOCKS proxy settings for a selected network service, usually `Wi-Fi`.

This uses:

```sh
networksetup -setsocksfirewallproxy <service> 127.0.0.1 <port>
networksetup -setsocksfirewallproxystate <service> on
```

Use **关闭系统代理** before quitting if you do not want macOS to keep sending traffic to the local SOCKS5 port.

The app also has preferences for:

- automatically enabling system proxy after connection
- automatically disabling system proxy after disconnection
- selecting the active network service

## Clash Snippet

The Clash tab generates a SOCKS5 proxy node, a `PROXY` select group, and rules such as:

```yaml
proxies:
  - name: "Termius SSH SOCKS"
    type: socks5
    server: 127.0.0.1
    port: 1080

proxy-groups:
  - name: "PROXY"
    type: select
    proxies:
      - "Termius SSH SOCKS"
      - DIRECT

rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - DOMAIN-SUFFIX,youtube.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
```

Copy this into an existing Clash/ClashX Pro configuration and adjust rules as needed.

## TUN Mode

TUN mode tries to route system traffic through the local SOCKS5 proxy by launching `sing-box` with a temporary TUN configuration.

Important notes:

- The SSH SOCKS5 tunnel must already be running.
- `sing-box` must be available at `/opt/homebrew/bin/sing-box`, `/usr/local/bin/sing-box`, `/usr/bin/sing-box`, or inside the app bundle.
- Starting TUN mode may trigger a macOS administrator authorization prompt.
- The generated `sing-box` config and logs are temporary files under the system temporary directory.

If Homebrew is installed, the app can attempt:

```sh
brew install sing-box
```

## Diagnostics

The diagnostics tab checks:

- whether `/usr/bin/ssh` is available
- whether the selected local SOCKS5 port is occupied
- whether the remote SSH host and port are reachable
- whether `curl` can reach `https://www.apple.com` through the local SOCKS5 proxy

Use this tab first when a tunnel fails to connect or a browser cannot use the proxy.

## Common Problems

### SSH connects but the proxy does not work

Check whether the remote server allows TCP forwarding:

```text
AllowTcpForwarding yes
```

Also confirm that the SSH command is still running and that the local SOCKS5 port is listening.

### Local port is already in use

Change the local SOCKS5 port in SSHocks, or stop the process currently using it. The diagnostics tab runs `lsof` for the selected port.

### Password login fails

SSHocks uses a temporary `SSH_ASKPASS` script to pass the password to `/usr/bin/ssh`. If the server disallows password auth, use a private key instead.

### Private-key login fails

Confirm the key path, file permissions, and server-side `authorized_keys`. SSHocks passes the key through `ssh -i <key> -o IdentitiesOnly=yes`.

### System proxy remains enabled after disconnect

Open SSHocks and click **关闭系统代理**, or run:

```sh
networksetup -setsocksfirewallproxystate Wi-Fi off
```

Replace `Wi-Fi` with the network service selected in the app.

### TUN mode fails immediately

Check whether `sing-box` is installed and whether macOS administrator authorization was granted. TUN mode is optional; the normal SOCKS5 tunnel can still be used without it.

## Security Notes

- Do not commit private keys, passwords, host-specific secrets, or production proxy credentials.
- Saved passwords belong in macOS Keychain.
- Private keys should stay in `~/.ssh` or another local secure path.
- The app intentionally uses loopback binding, `127.0.0.1:<port>`, for the SOCKS5 listener.
- System proxy and TUN mode change host-level networking behavior; verify they are disabled when you are done.

## Development Notes

Useful local checks:

```sh
xcodebuild -list -project SSHocks.xcodeproj
xcodebuild -project SSHocks.xcodeproj -scheme SSHocks -configuration Debug build
git status --short --branch
```

There is currently no dedicated XCTest target. Manual validation should cover:

- password SSH tunnel
- private-key SSH tunnel
- menu bar connect/disconnect
- server profile save/load/delete
- system proxy enable/disable
- Clash YAML copy
- diagnostics output
- optional TUN mode with `sing-box`
