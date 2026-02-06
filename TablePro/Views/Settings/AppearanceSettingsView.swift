//
//  AppearanceSettingsView.swift
//  TablePro
//
//  Settings for theme and accent color
//

import SwiftUI

struct AppearanceSettingsView: View {
    @Binding var settings: AppearanceSettings

    var body: some View {
        Form {
            Picker("Appearance:", selection: $settings.theme) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
            .pickerStyle(.segmented)

            Picker("Accent Color:", selection: $settings.accentColor) {
                ForEach(AccentColorOption.allCases) { option in
                    HStack {
                        if option != .system {
                            Circle()
                                .fill(option.color)
                                .frame(width: 12, height: 12)
                        }
                        Text(option.displayName)
                    }
                    .tag(option)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    AppearanceSettingsView(settings: .constant(.default))
        .frame(width: 450, height: 200)
}
