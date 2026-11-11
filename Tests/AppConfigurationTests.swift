import Testing
@testable import pathly

@Suite("AppConfiguration")
struct AppConfigurationTests {
    @Test("Odczytuje klucz API z Info.plist")
    func readsAPIKey() {
        let configuration = AppConfiguration(infoDictionary: ["ORSAPIKey": "  abc123  "])
        #expect(configuration.openRouteServiceAPIKey == "abc123")
    }

    @Test(
        "Traktuje pustą lub nierozwiniętą wartość jako brak klucza",
        arguments: ["", "   ", "$(ORS_API_KEY)"]
    )
    func treatsPlaceholderAsMissing(value: String) {
        let configuration = AppConfiguration(infoDictionary: ["ORSAPIKey": value])
        #expect(configuration.openRouteServiceAPIKey == nil)
    }

    @Test("Brak wpisu w Info.plist oznacza brak klucza")
    func missingEntry() {
        #expect(AppConfiguration(infoDictionary: [:]).openRouteServiceAPIKey == nil)
    }
}
