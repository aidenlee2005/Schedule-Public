import SwiftData
import SwiftUI

enum Persistence {
    static let didSave = Notification.Name("Schedule.didSaveDisplayData")
    /// Every user mutation saves explicitly; failed writes restore the last saved state.
    @MainActor
    static func save(_ context: ModelContext, error message: inout String?) -> Bool {
        do {
            try context.save()
            NotificationCenter.default.post(name: didSave, object: context)
            return true
        } catch {
            context.rollback()
            message = error.localizedDescription
            return false
        }
    }
}

extension View {
    func persistenceAlert(_ message: Binding<String?>) -> some View {
        alert("Unable to Save", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK", role: .cancel) { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "Please try again.")
        }
    }
}
