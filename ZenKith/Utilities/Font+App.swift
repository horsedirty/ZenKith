import SwiftUI
import AppKit

extension Font {

    static func appFont(size: CGFloat) -> Font {
        let timesDesc = NSFontDescriptor(name: "Times New Roman", size: size)
        let songtiDesc = NSFontDescriptor(name: "Songti SC", size: size)
        let cascadeDesc = timesDesc.addingAttributes([.cascadeList: [songtiDesc]])
        let nsFont = NSFont(descriptor: cascadeDesc, size: size)
            ?? NSFont(name: "Times New Roman", size: size)
            ?? .systemFont(ofSize: size)
        return Font(nsFont)
    }

    static let appLargeTitle: Font = appFont(size: 34)
    static let appTitle2: Font = appFont(size: 22)
    static let appTitle3: Font = appFont(size: 20)
    static let appHeadline: Font = appFont(size: 17)
    static let appBody: Font = appFont(size: 17)
    static let appCallout: Font = appFont(size: 16)
    static let appSubheadline: Font = appFont(size: 15)
    static let appCaption: Font = appFont(size: 12)
    static let appCaption2: Font = appFont(size: 11)
}
