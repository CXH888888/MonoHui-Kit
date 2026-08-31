import Foundation

enum QuickRenameModule {
    static let serviceActions: [ServiceAction] = [
        ServiceAction(
            id: "quickrename.interactive",
            menuName: "文件命名·快速改名",
            bundleIdentifier: "com.quickactions.workflow.quickrename.interactive",
            acceptedFileTypes: ["public.item"],
            launchArgs: ["--module", "quickrename", "--mode", "interactive"]
        ),
        ServiceAction(
            id: "quickrename.batch",
            menuName: "文件命名·批量重命名",
            bundleIdentifier: "com.quickactions.workflow.quickrename.batch",
            acceptedFileTypes: ["public.item"],
            launchArgs: ["--module", "quickrenamebatch", "--mode", "interactive"]
        )
    ]
}
