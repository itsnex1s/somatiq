import SwiftUI

struct ErrorAlertModifier: ViewModifier {
    let title: String
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(title, isPresented: isPresentedBinding, presenting: message) { _ in
            Button("OK") {
                message = nil
            }
        } message: { message in
            Text(message)
        }
    }

    private var isPresentedBinding: Binding<Bool> {
        Binding {
            message != nil
        } set: { newValue in
            if !newValue {
                message = nil
            }
        }
    }
}

extension View {
    func errorAlert(title: String, message: Binding<String?>) -> some View {
        modifier(ErrorAlertModifier(title: title, message: message))
    }
}
