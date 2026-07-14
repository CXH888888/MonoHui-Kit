import Foundation

enum QualityLevel: String, CaseIterable, Identifiable, Codable {
    case lossless, highest, high, medium, low, lowest

    var id: String { rawValue }

    /// UI 显示名（带压缩数值）
    var displayName: String {
        switch self {
        case .lossless: return "无损"
        case .highest:  return "最高（100）"
        case .high:     return "高（90）"
        case .medium:   return "中（75）"
        case .low:      return "低（50）"
        case .lowest:   return "极低（20）"
        }
    }

    /// 文件名用的简短标签（如 q90、lossless）
    var shortLabel: String {
        switch self {
        case .lossless: return "lossless"
        case .highest: return "q100"
        case .high: return "q90"
        case .medium: return "q75"
        case .low: return "q50"
        case .lowest: return "q20"
        }
    }
}
