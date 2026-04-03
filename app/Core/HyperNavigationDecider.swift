// HyperNavigationDecider.swift
// Controls WebKit navigation policy for hyper:// pages.
// WebPage.NavigationAction only exposes: action.request (URLRequest)
// No targetFrame — that's WKNavigationAction (old API).

import WebKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

final class HyperNavigationDecider: WebPage.NavigationDeciding {

    func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {

        guard let url = action.request.url else {
            print("[nav] ❌ no URL")
            return .cancel
        }

        print("[nav] → \(url.absoluteString)")

        switch url.scheme {
        case "hyper":
            print("[nav] ✓ allow")
            return .allow

        case "https", "http":
            print("[nav] opening externally: \(url)")
            #if os(iOS)
            await UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
            return .cancel

        case "mailto", "tel":
            #if os(iOS)
            await UIApplication.shared.open(url)
            #endif
            return .cancel

        case "about":
            return .allow

        default:
            print("[nav] ❌ unknown scheme: \(url.scheme ?? "nil")")
            return .cancel
        }
    }

    func decidePolicy(
        for response: WebPage.NavigationResponse
    ) async -> WKNavigationResponsePolicy {
        print("[nav] response → allow \(response.response.url?.absoluteString ?? "")")
        return .allow
    }
}
