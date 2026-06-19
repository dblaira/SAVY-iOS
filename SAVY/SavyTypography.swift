import SwiftUI
import UIKit

enum SavyTypography {
    static let bodoniModaPostScriptName = "BodoniModa-Regular"

    static func bodoniModa(_ size: CGFloat) -> Font {
        if UIFont(name: bodoniModaPostScriptName, size: size) != nil {
            return .custom(bodoniModaPostScriptName, size: size)
        }

        #if DEBUG
        assertionFailure("Bodoni Moda failed to load. Check UIAppFonts and BodoniModa-Regular.ttf in the app bundle.")
        #endif

        return .system(size: size, weight: .regular, design: .serif)
    }
}
