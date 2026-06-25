import SwiftUI
import UIKit

enum SavyTypography {
    /// Same face Notorious Recall uses — built into iOS, always available on device.
    static let recallSerifName = "Bodoni 72 Oldstyle"
    static let bodoniModaPostScriptName = "BodoniModa-Regular"
    static let robotoMediumPostScriptName = "Roboto-Medium"
    static let timesNewRomanRegular = "TimesNewRomanPSMT"
    static let timesNewRomanBold = "TimesNewRomanPS-BoldMT"

    struct Audit: Equatable {
        let bodoni72OldstyleAvailable: Bool
        let bodoniModaBundled: Bool
        let bodoniModaRegistered: Bool
        let robotoMediumBundled: Bool
        let robotoMediumRegistered: Bool
        let displaySerifSource: String
    }

    @discardableResult
    static func performAudit() -> Audit {
        let bodoni72 = UIFont(name: recallSerifName, size: 12) != nil
        let modaBundled = Bundle.main.url(forResource: "BodoniModa-Regular", withExtension: "ttf") != nil
        let modaRegistered = UIFont(name: bodoniModaPostScriptName, size: 12) != nil
        let robotoBundled = Bundle.main.url(forResource: "Roboto-Medium", withExtension: "ttf") != nil
        let robotoRegistered = UIFont(name: robotoMediumPostScriptName, size: 12) != nil

        let displaySerifSource: String
        if bodoni72 {
            displaySerifSource = recallSerifName
        } else if modaRegistered {
            displaySerifSource = bodoniModaPostScriptName
        } else {
            displaySerifSource = "system-serif"
        }

        let result = Audit(
            bodoni72OldstyleAvailable: bodoni72,
            bodoniModaBundled: modaBundled,
            bodoniModaRegistered: modaRegistered,
            robotoMediumBundled: robotoBundled,
            robotoMediumRegistered: robotoRegistered,
            displaySerifSource: displaySerifSource
        )

        #if DEBUG
        print("[SAVY Fonts] display=\(displaySerifSource) bodoni72=\(bodoni72) modaBundled=\(modaBundled) modaRegistered=\(modaRegistered) robotoRegistered=\(robotoRegistered)")
        #endif

        return result
    }

    /// Editorial serif — Bodoni 72 Oldstyle first (Recall), then bundled Moda, then system serif.
    static func displaySerif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if UIFont(name: recallSerifName, size: size) != nil {
            return Font.custom(recallSerifName, size: size).weight(weight)
        }
        if UIFont(name: bodoniModaPostScriptName, size: size) != nil {
            return Font.custom(bodoniModaPostScriptName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func bodoniModa(_ size: CGFloat, weight: CGFloat = 400, opticalSize: CGFloat? = nil) -> Font {
        let swiftWeight: Font.Weight = weight >= 700 ? .bold : weight >= 600 ? .semibold : .regular
        return displaySerif(size, weight: swiftWeight)
    }

    static func bodoniModaBold(_ size: CGFloat) -> Font {
        displaySerif(size, weight: .bold)
    }

    static func robotoMedium(_ size: CGFloat) -> Font {
        if UIFont(name: robotoMediumPostScriptName, size: size) != nil {
            return .custom(robotoMediumPostScriptName, size: size)
        }
        return .system(size: size, weight: .medium, design: .default)
    }

    /// Times New Roman — ships on every iPhone; used for home carousel section cards.
    static func timesNewRoman(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let usesBold = weight == .bold || weight == .heavy || weight == .semibold
        let name = usesBold ? timesNewRomanBold : timesNewRomanRegular
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight, design: .serif)
    }
}
