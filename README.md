# Vinjari

A p2p browser for macOS built on the [Holepunch](https://holepunch.to) stack. Browse sites served directly from [Hyperdrive](https://github.com/holepunchto/hyperdrive) over [Hyperswarm](https://github.com/holepunchto/hyperswarm) — no servers, no CDN, no domain required.

## How it works

Every site is a Hyperdrive — a p2p filesystem identified by a public key. When you navigate to a `hyper://` address, Vinjari connects to peers in the Hyperswarm DHT who are seeding that drive and streams the content directly to WebKit. The experience is identical to browsing a normal website.

```
hyper://73kf7pzbtcy9f4jtxssy941adse9jheddqx3f931o9d65k13g99y/
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

## Getting your environment set up

### Prerequisites

- macOS 26+
- Xcode 26+
- Node.js 18+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- [GitHub CLI](https://cli.github.com): `brew install gh`

### Steps

**1. Clone and install JS dependencies**

```sh
git clone https://github.com/your-org/Vinjari
cd Vinjari
npm install
```

**2. Download BareKit**

BareKit is the Swift package that embeds the Bare JS runtime inside a macOS app. You need its prebuilt framework.

```sh
gh release download --repo holepunchto/bare-kit <version>
```

Unpack `prebuilds.zip` and move `macos/BareKit.xcframework` into `app/frameworks/`:

```
app/
  frameworks/
    BareKit.xcframework/   ← here
```

**3. Generate the Xcode project**

```sh
xcodegen generate
```

Re-run this any time you edit `project.yml`.



## License

GPL-3.0
