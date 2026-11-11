import SwiftUI

/// Tymczasowy ekran startowy (etap 0). Zostanie zastąpiony nawigacją
/// między funkcjami aplikacji w kolejnych etapach.
struct ContentView: View {
    var body: some View {
        ContentUnavailableView(
            "Pathly",
            systemImage: "shippingbox",
            description: Text("Aplikacja dla kurierów — wkrótce tutaj pojawi się lista przesyłek.")
        )
    }
}

#Preview {
    ContentView()
}
