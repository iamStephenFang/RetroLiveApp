import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "未发现设备",
                systemImage: "iphone.radiowaves.left.and.right",
                description: Text("请确保 RetroLive Camera 已打开传输模式，并与此设备连接到同一 Wi-Fi 网络。")
            )
            .navigationTitle("设备")
        }
    }
}
