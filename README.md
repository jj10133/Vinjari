# Vinjari

A p2p browser for macOS built on the [Holepunch](https://holepunch.to) stack. Browse sites served directly from [Hyperdrive](https://github.com/holepunchto/hyperdrive) over [Hyperswarm](https://github.com/holepunchto/hyperswarm) — no servers, no CDN, no domain required.

## How it works

Every site is a Hyperdrive — a p2p filesystem identified by a public key. When you navigate to a `hyper://` address, Vinjari connects to peers in the Hyperswarm DHT who are seeding that drive and streams the content directly to WebKit. The experience is identical to browsing a normal website.

```
hyper://odf3uawx1369n1pcapby5dwhjr1h9p45r84hgpp3f3ua6crdetby/
```

## Features

- **`hyper://` browsing** — load any Hyperdrive site by key or z-base-32 address
- **Native macOS tabs** — full window tab support, ⌘T for new tab
- **Range requests** — video and audio streaming works out of the box
- **Back / forward / reload** — full browser navigation
- **External links** — `https://` links open in your default browser

## Stack

| Layer | Technology |
|-------|------------|
| Runtime | [BareKit](https://github.com/holepunchto/bare-kit-swift) — JS worklet embedded in the app |
| Transport | [bare-rpc-swift](https://github.com/holepunchto/bare-rpc-swift) — IPC between Swift and JS |
| Networking | [Hyperswarm](https://github.com/holepunchto/hyperswarm) — DHT peer discovery |
| Storage | [Hyperdrive](https://github.com/holepunchto/hyperdrive) — p2p filesystem |
| Rendering | WebKit — `hyper://` served via `URLSchemeHandler` |

## Concurrency note

WebKit fires concurrent requests for page assets (HTML, CSS, JS, fonts). [bare-rpc-swift](https://github.com/holepunchto/bare-rpc-swift) is intentionally single-threaded — thread safety lives in the wrapper, not the library.

Vinjari serialises all RPC access through `@MainActor`:

```swift
// All rpc.request() and rpc.receive() calls run on the main actor —
// one at a time, no concurrent mutation of bare-rpc's internal state.

@MainActor
final class RPCClient { ... }

@MainActor
private final class IPCBridge: RPCDelegate {
    // BareIPC.write() is also not concurrent-safe.
    // Fire-and-forget into @MainActor Task serialises writes.
    nonisolated func rpc(_ rpc: RPC, send data: Data) {
        Task { @MainActor in try? await ipc.write(data: data) }
    }

    func readLoop() async {
        for try await chunk in ipc {
            // Hop to MainActor before receive() so it never races
            // with a concurrent request() call
            await MainActor.run { rpc?.receive(chunk) }
        }
    }
}
```

If you are building something similar with bare-rpc-swift and WebKit, this is the pattern to follow.

## Publishing a site

Any static site works. Build it, mirror it to a Hyperdrive, seed it:

```bash
# Install the drives CLI
npm i -g drives

# Create a new drive
drives touch
# → New drive: <z32-key>

# Mirror your built site into the drive (Astro, Next.js, plain HTML — anything)
drives mirror ./dist/ <z32-key>

# Seed so others can reach it
drives seed <z32-key>
```

Then open Vinjari and navigate to `hyper://<z32-key>/`.

## Requirements

- macOS 26+
- Xcode 26+

## Building

```bash
git clone https://github.com/yourname/vinjari
cd vinjari
npm install
xcodegen generate
open Vinjari.xcodeproj
```

## License

GPL-3.0
