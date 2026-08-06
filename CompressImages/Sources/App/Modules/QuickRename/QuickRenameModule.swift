import Foundation

enum QuickRenameModule {
    static let serviceActions: [ServiceAction] = [
        ServiceAction(
            id: "quickrename.interactive",
            menuName: "文件命名·快速改名",
            bundleIdentifier: "com.quickactions.workflow.quickrename.interactive",
            acceptedFileTypes: ["public.item"],
            launchArgs: ["--module", "quickrename", "--mode", "interactive"]
        )
    ]
}
