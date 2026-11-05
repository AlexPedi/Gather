import SwiftUI

// Spell the property-wrapper type explicitly. Some Command Line Tools SDKs also
// export a State macro whose implementation ships only with full Xcode.
// A distinct alias keeps the macOS 14 property wrapper usable with those SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>
