import Foundation

enum CompressModule {
    static let serviceActions: [ServiceAction] = [
        ServiceAction(
            id: "compress.quick",
            menuName: "图片·快速压缩",
            bundleIdentifier: "com.quickactions.workflow.compress.quick",
            acceptedFileTypes: ["public.image"],
            launchArgs: ["--module", "compress", "--mode", "quick"]
        ),
        ServiceAction(
            id: "compress.interactive",
            menuName: "图片·压缩为…",
            bundleIdentifier: "com.quickactions.workflow.compress.interactive",
            acceptedFileTypes: ["public.image"],
            launchArgs: ["--module", "compress", "--mode", "interactive"]
        )
    ]
}
