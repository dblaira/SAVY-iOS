import Foundation

enum AppRuntime: Equatable {
    case nativeSwift
}

enum DisallowedTechnology: Equatable {
    case webViewShell
    case progressiveWebApp
    case reactNative
    case capacitor
    case expo
    case typeScriptFrontend
}

enum BackendSurface: Equatable {
    case supabase
    case vercel
}

enum AppRuntimeBoundary {
    static let allowedRuntime: AppRuntime = .nativeSwift

    static let disallowedTechnologies: [DisallowedTechnology] = [
        .webViewShell,
        .progressiveWebApp,
        .reactNative,
        .capacitor,
        .expo,
        .typeScriptFrontend
    ]

    static let backendSurfaces: [BackendSurface] = [
        .supabase,
        .vercel
    ]
}
