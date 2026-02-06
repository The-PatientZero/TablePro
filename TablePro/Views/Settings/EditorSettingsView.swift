//
//  EditorSettingsView.swift
//  TablePro
//
//  Settings for SQL editor font and behavior
//

import SwiftUI

struct EditorSettingsView: View {
    @Binding var settings: EditorSettings

    var body: some View {
        Form {
            Section("Font") {
                Picker("Font:", selection: $settings.fontFamily) {
                    ForEach(EditorFont.allCases.filter { $0.isAvailable }) { font in
                        Text(font.displayName).tag(font)
                    }
                }

                Picker("Size:", selection: $settings.fontSize) {
                    ForEach(11...18, id: \.self) { size in
                        Text("\(size) pt").tag(size)
                    }
                }

                // Preview
                GroupBox("Preview") {
                    Text("SELECT * FROM users WHERE id = 1;")
                        .font(.custom(settings.fontFamily.displayName, size: CGFloat(settings.clampedFontSize)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
            }

            Section("Display") {
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
                Toggle("Highlight current line", isOn: $settings.highlightCurrentLine)
                Toggle("Auto-indent", isOn: $settings.autoIndent)
                Toggle("Word wrap", isOn: $settings.wordWrap)
            }

            Section("Editing") {
                Picker("Tab width:", selection: $settings.tabWidth) {
                    Text("2 spaces").tag(2)
                    Text("4 spaces").tag(4)
                    Text("8 spaces").tag(8)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    EditorSettingsView(settings: .constant(.default))
        .frame(width: 450, height: 350)
}
