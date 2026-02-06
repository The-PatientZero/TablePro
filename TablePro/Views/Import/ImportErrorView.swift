//
//  ImportErrorView.swift
//  TablePro
//
//  Error dialog shown when SQL import fails.
//

import SwiftUI

struct ImportErrorView: View {
    let error: ImportError?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 6) {
                Text("Import Failed")
                    .font(.system(size: 15, weight: .semibold))

                if case .importFailed(let statement, let line, let errorMsg) = error {
                    Text("Failed at line \(line)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Statement:")
                                .font(.system(size: 12, weight: .medium))
                            Text(statement)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Error:")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.top, 8)
                            Text(errorMsg)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(4)
                } else {
                    Text(error?.localizedDescription ?? "Unknown error")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button("Close") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
