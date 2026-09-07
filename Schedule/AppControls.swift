import SwiftUI
import UIKit

struct HeaderActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct CompletionButton: View {
    let isCompleted: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 23, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCompleted ? "Reopen \(title)" : "Complete \(title)")
    }
}

struct FilterMenuLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(AppTheme.Typography.control)
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .background(AppTheme.accent.opacity(0.09), in: Capsule())
        .contentShape(Capsule())
    }
}

struct AppEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 66, height: 66)
                .background(AppTheme.accent.opacity(0.08), in: Circle())
            Text(title).font(AppTheme.Typography.cardTitle)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Native segmented controls preserve accessibility and share one appearance.
struct AppSegmentedPicker<Option: Hashable>: View {
    let label: String
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .font(AppTheme.Typography.control)
        } else {
            NativeSegments(label: label, selection: $selection, options: options, title: title)
                .frame(height: 40)
        }
    }
}

private struct NativeSegments<Option: Hashable>: UIViewRepresentable {
    let label: String
    @Binding var selection: Option
    let options: [Option]
    let title: (Option) -> String
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> SegmentedControlCoordinator { SegmentedControlCoordinator() }

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: options.map(title))
        control.addTarget(context.coordinator, action: #selector(SegmentedControlCoordinator.changed(_:)), for: .valueChanged)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateUIView(control, context: context)
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.onSelect = { index in
            guard options.indices.contains(index) else { return }
            selection = options[index]
        }
        if control.numberOfSegments != options.count {
            control.removeAllSegments()
            for (index, option) in options.enumerated() { control.insertSegment(withTitle: title(option), at: index, animated: false) }
        }
        for (index, option) in options.enumerated() { control.setTitle(title(option), forSegmentAt: index) }
        control.accessibilityLabel = label
        control.selectedSegmentIndex = options.firstIndex(of: selection) ?? UISegmentedControl.noSegment
        control.backgroundColor = .clear
        control.selectedSegmentTintColor = AppTheme.selectedFillUI
        let font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15, weight: .medium), compatibleWith: control.traitCollection)
        control.setTitleTextAttributes([.font: font, .foregroundColor: UIColor.secondaryLabel], for: .normal)
        control.setTitleTextAttributes([.font: font, .foregroundColor: AppTheme.accentUI], for: .selected)
    }

}

/// Keep UIKit's Objective-C target independent of the generic SwiftUI view.
/// This also avoids Swift 6.3's optimized generic-coordinator deinit crash.
private final class SegmentedControlCoordinator: NSObject {
    var onSelect: (Int) -> Void = { _ in }

    @objc func changed(_ control: UISegmentedControl) {
        onSelect(control.selectedSegmentIndex)
    }
}
