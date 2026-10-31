import AVKit
import SwiftUI

/// Системная кнопка выбора вывода звука (AirPlay, Bluetooth).
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor = UIColor(named: "AccentColor")!

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = tint
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
