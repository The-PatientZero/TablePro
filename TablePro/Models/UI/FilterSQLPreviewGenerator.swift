//
//  FilterSQLPreviewGenerator.swift
//  TablePro
//
//  SQL preview generation extracted from FilterStateManager
//

import Foundation
import TableProPluginKit

/// Generates SQL preview strings from filter state
@MainActor
struct FilterSQLPreviewGenerator {
    /// Generate preview SQL for the "SQL" button.
    /// Uses selected filters if any are selected, otherwise uses all valid filters.
    static func generatePreviewSQL(
        filters: [TableFilter],
        filterLogicMode: FilterLogicMode,
        databaseType: DatabaseType
    ) -> String {
        guard let dialect = PluginManager.shared.sqlDialect(for: databaseType) else {
            return "-- Filters are applied natively"
        }
        let generator = FilterSQLGenerator(dialect: dialect)
        let filtersToPreview = selectFiltersForPreview(from: filters)

        // If no valid filters but filters exist, show helpful message
        if filtersToPreview.isEmpty && !filters.isEmpty {
            let invalidCount = filters.count(where: { !$0.isValid })
            if invalidCount > 0 {
                return "-- No valid filters to preview\n-- Complete \(invalidCount) filter(s) by:\n--   • Selecting a column\n--   • Entering a value (if required)\n--   • Filling in second value for BETWEEN"
            }
        }

        return generator.generateWhereClause(from: filtersToPreview, logicMode: filterLogicMode)
    }

    /// Get filters to use for preview/application.
    /// If some (but not all) filters are selected, use only those.
    /// Otherwise use all valid filters (single-pass).
    static func selectFiltersForPreview(from filters: [TableFilter]) -> [TableFilter] {
        var valid: [TableFilter] = []
        var selectedValid: [TableFilter] = []
        for filter in filters where filter.isValid {
            valid.append(filter)
            if filter.isSelected { selectedValid.append(filter) }
        }
        // Only use selective mode when SOME (but not all) are selected
        if selectedValid.count == valid.count || selectedValid.isEmpty {
            return valid
        }
        return selectedValid
    }
}
