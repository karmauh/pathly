import SwiftUI

/// Pola formularza adresu. Używane w ustawieniach bazy i na ekranie podglądu przesyłki.
struct AddressFormFields: View {
    @Binding var form: AddressForm
    /// Pola do sprawdzenia przez kuriera (np. kod poprawiony przez parser).
    var highlighted: Set<AddressForm.Field> = []
    var focus: FocusState<Bool>.Binding

    var body: some View {
        TextField("Ulica (np. ul. Długa)", text: $form.street)
            .textContentType(.streetAddressLine1)
            // Prefiks „ul.”, „al.” piszemy małą literą — bez automatycznej wielkiej litery.
            .textInputAutocapitalization(.never)
            .modifier(FieldStyle(isHighlighted: highlighted.contains(.street), focus: focus))
        HStack {
            TextField("Nr budynku", text: $form.buildingNumber)
                .modifier(FieldStyle(isHighlighted: highlighted.contains(.buildingNumber), focus: focus))
            TextField("Nr lokalu", text: $form.apartmentNumber)
                .modifier(FieldStyle(isHighlighted: highlighted.contains(.apartmentNumber), focus: focus))
        }
        TextField("Kod pocztowy (00-000)", text: $form.postalCode)
            .textContentType(.postalCode)
            .keyboardType(.numbersAndPunctuation)
            .modifier(FieldStyle(isHighlighted: highlighted.contains(.postalCode), focus: focus))
        TextField("Miejscowość", text: $form.city)
            .textContentType(.addressCity)
            .textInputAutocapitalization(.words)
            .modifier(FieldStyle(isHighlighted: highlighted.contains(.city), focus: focus))
    }
}

/// Wspólny wygląd pola: fokus, wyłączona autokorekta i ewentualne wyróżnienie.
private struct FieldStyle: ViewModifier {
    let isHighlighted: Bool
    let focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            // Autokorekta „poprawia” nazwy własne ulic i miejscowości — wyłączamy ją.
            .autocorrectionDisabled()
            .focused(focus)
            .padding(.vertical, 2)
            .background(alignment: .leading) {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.18))
                        .padding(.horizontal, -6)
                }
            }
            .accessibilityHint(isHighlighted ? "Sprawdź to pole" : "")
    }
}
