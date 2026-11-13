import SwiftUI
import SafariServices

struct WebSearchView: View {
    @State private var query = ""
    @State private var destination: WebDestination?
    var body: some View {
        Form {
            Section("Поиск Google") {
                TextField("Запрос или текст для перевода", text: $query, axis: .vertical).lineLimit(2...5)
                Button("Искать в Google") { open(translation: false) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Открыть Google Translate") { open(translation: true) }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Текст передаётся Google только после нажатия. Для вставки результата в чат скопируй нужный текст или ссылку и вернись к клавиатуре.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Поиск")
        .sheet(item: $destination) { SafariSurface(url: $0.url).ignoresSafeArea() }
    }
    private func open(translation: Bool) {
        var url = URLComponents(string: translation ? "https://translate.google.com/" : "https://www.google.com/search")!
        url.queryItems = translation ? [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: "en"), URLQueryItem(name: "text", value: query), URLQueryItem(name: "op", value: "translate")] : [URLQueryItem(name: "q", value: query)]
        if let address = url.url { destination = WebDestination(url: address) }
    }
    private struct WebDestination: Identifiable { let id = UUID(); let url: URL }
}

private struct SafariSurface: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
