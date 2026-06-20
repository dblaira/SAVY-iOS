import CoreText
import OSLog
import SwiftUI
import UIKit

enum SavyTypography {
  private static let logger = Logger(subsystem: "com.savy.ios", category: "fonts")
  private static let variationAttribute = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)

  static let bodoniModaPostScriptName = "BodoniModa-Regular"
  static let robotoMediumPostScriptName = "Roboto-Medium"

  /// Call once at launch to log bundled font health in debug builds.
  static func auditBundledFonts() {
    let bundleURL = Bundle.main.url(forResource: "BodoniModa-Regular", withExtension: "ttf")
    let bundlePresent = bundleURL != nil
    let regularLoads = UIFont(name: bodoniModaPostScriptName, size: 20) != nil
    let boldLoads = resolvedUIFont(size: 20, weight: 700, opticalSize: 18) != nil
    let robotoLoads = UIFont(name: robotoMediumPostScriptName, size: 22) != nil
    let families = UIFont.familyNames
      .filter { $0.localizedCaseInsensitiveContains("Bodoni") || $0.localizedCaseInsensitiveContains("Roboto") }
      .sorted()

    logger.info(
      "Font audit bundle=\(bundlePresent, privacy: .public) regular=\(regularLoads, privacy: .public) boldAxis=\(boldLoads, privacy: .public) robotoMedium=\(robotoLoads, privacy: .public) families=\(families.joined(separator: ", "), privacy: .public)"
    )

    #if DEBUG
    print(
      "[SAVY fonts] bundle=\(bundlePresent) BodoniModa-Regular=\(regularLoads) wght700=\(boldLoads) Roboto-Medium=\(robotoLoads) families=\(families)"
    )
    #endif
  }

  static func bodoniModa(_ size: CGFloat, weight: CGFloat = 400, opticalSize: CGFloat? = nil) -> Font {
    if let uiFont = resolvedUIFont(size: size, weight: weight, opticalSize: opticalSize ?? size) {
      return Font(uiFont)
    }

    #if DEBUG
    assertionFailure("Bodoni Moda failed to load. Check UIAppFonts and BodoniModa-Regular.ttf in the app bundle.")
    #endif

    let swiftWeight: Font.Weight = weight >= 700 ? .bold : weight >= 600 ? .semibold : .regular
    return .system(size: size, weight: swiftWeight, design: .serif)
  }

  static func bodoniModaBold(_ size: CGFloat) -> Font {
    bodoniModa(size, weight: 700, opticalSize: max(size, 18))
  }

  static func robotoMedium(_ size: CGFloat) -> Font {
    if UIFont(name: robotoMediumPostScriptName, size: size) != nil {
      return .custom(robotoMediumPostScriptName, size: size)
    }

    #if DEBUG
    assertionFailure("Roboto Medium failed to load. Check UIAppFonts and Roboto-Medium.ttf in the app bundle.")
    #endif

    return .system(size: size, weight: .medium, design: .default)
  }

  private static func resolvedUIFont(size: CGFloat, weight: CGFloat, opticalSize: CGFloat) -> UIFont? {
    if weight <= 400, let regular = UIFont(name: bodoniModaPostScriptName, size: size) {
      return regular
    }

    guard let base = UIFont(name: bodoniModaPostScriptName, size: size) else {
      return nil
    }

    let attributes: [UIFontDescriptor.AttributeName: Any] = [
      variationAttribute: [
        "wght": weight,
        "opsz": opticalSize,
      ],
    ]

    let descriptor = base.fontDescriptor.addingAttributes(attributes)
    return UIFont(descriptor: descriptor, size: size)
  }
}
