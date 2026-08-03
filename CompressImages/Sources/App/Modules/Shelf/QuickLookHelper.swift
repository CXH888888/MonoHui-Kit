import AppKit
import Quartz

/// 空格快速预览封装：基于系统 QLPreviewPanel
final class QuickLookHelper: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookHelper()

    private var currentURLs: [URL] = []
    private var panel: QLPreviewPanel?

    private override init() {
        super.init()
    }

    /// 显示快速预览
    @MainActor
    func preview(urls: [URL]) {
        guard !urls.isEmpty else { return }
        currentURLs = urls

        let panel = QLPreviewPanel.shared()!
        panel.dataSource = self
        panel.currentPreviewItemIndex = 0
        // 先更新数据再显示
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        AppLog.shared.log("快速预览：\(urls.count) 个文件，首个：\(urls[0].lastPathComponent)", category: "Shelf")
    }

    /// 关闭预览
    @MainActor
    func close() {
        panel?.close()
        panel = nil
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < currentURLs.count else { return nil }
        return currentURLs[index] as NSURL
    }
}
