import AVKit
import SwiftUI

/// Системная кнопка выбора вывода звука (AirPlay, Bluetooth).
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(named: "AccentColor")
        view.activeTintColor = UIColor(named: "AccentColor")
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
