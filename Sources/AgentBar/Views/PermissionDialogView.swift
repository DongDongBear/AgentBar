import SwiftUI

/// Displays a permission request with Allow/Deny buttons
struct PermissionDialogView: View {
    let request: PermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)

                Text("Permission Request")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
            }

            // Tool name
            HStack(spacing: 6) {
                Text("Tool:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text(request.tool)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Description
            Text(request.description)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            // Parameters
            if !request.parameters.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(request.parameters.keys.sorted()), id: \.self) { key in
                        HStack(spacing: 4) {
                            Text(key + ":")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Text(request.parameters[key] ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Action buttons
            HStack(spacing: 10) {
                Button(action: onDeny) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                        Text("Deny")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

                Button(action: onAllow) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                        Text("Allow")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
