import SwiftUI

/// All three task lists share hit areas, text alignment, surfaces, and deletion.
struct TaskRowCard<Leading: View, Content: View>: View {
    let title: String
    let onOpen: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            leading().frame(width: 44, height: 44)
            Button(action: onOpen) {
                content()
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("task-\(title)")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(title)")
        }
        .padding(.horizontal, 6).padding(.vertical, 10)
        .cardBackground()
    }
}

struct TaskFilterMenu<Option: Hashable>: View {
    let label: String
    @Binding var selection: Option
    let options: [Option]
    let optionTitle: (Option) -> String
    let isFiltered: Bool

    var body: some View {
        Menu {
            Picker("Status", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.10), in: Circle())
                .overlay(alignment: .topTrailing) {
                    if isFiltered {
                        Circle().fill(AppTheme.accent).frame(width: 7, height: 7).padding(3)
                    }
                }
                .contentShape(Circle())
        }
        .accessibilityLabel(label)
        .accessibilityValue(optionTitle(selection))
        .accessibilityIdentifier("taskFilter")
    }
}
