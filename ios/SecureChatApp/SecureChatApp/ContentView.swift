import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Image(systemName: "message.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.teal)
                Text("SecureChat iOS")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Güvenli haberleşme uygulaması")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .navigationTitle("SecureChat")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}