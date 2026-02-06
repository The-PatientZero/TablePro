//
//  ImportProgressView.swift
//  TablePro
//
//  Progress dialog shown during SQL import.
//

import SwiftUI

struct ImportProgressView: View {
    let currentStatement: String
    let statementIndex: Int
    let totalStatements: Int
    let statusMessage: String
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Import SQL")
                .font(.system(size: 15, weight: .semibold))

            VStack(spacing: 8) {
                HStack {
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Statement \(statementIndex) of \(totalStatements)")
                            .font(.system(size: 13))

                        Spacer()

                        Text(currentStatement)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                if !statusMessage.isEmpty {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                }
            }

            Button("Stop") {
                onStop()
            }
            .frame(width: 80)
        }
        .padding(24)
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progressValue: Double {
        guard totalStatements > 0 else { return 0 }
        return Double(statementIndex) / Double(totalStatements)
    }
}
