import SwiftUI

struct SavyTabIcon: View {
    let section: SavyNavigationSection

    var body: some View {
        Image(systemName: section.symbolName)
            .font(.system(size: RootHomeLayout.bottomNavigationIconSize, weight: .semibold))
            .frame(width: RootHomeLayout.bottomNavigationIconSize, height: RootHomeLayout.bottomNavigationIconSize)
            .accessibilityHidden(true)
    }
}
