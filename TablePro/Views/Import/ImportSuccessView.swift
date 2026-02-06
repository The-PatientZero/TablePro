//
//  ImportSuccessView.swift
//  TablePro
//
//  Success dialog shown after successful SQL import.
//

import SwiftUI

struct ImportSuccessView: View {
    let result: ImportResult?
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Import Successful")
                    .font(.system(size: 15, weight: .semibold))

                if let result = result {
                    Text("\(result.executedStatements) statements executed")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Text(String(format: "%.2f seconds", result.executionTime))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Button("Close") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
