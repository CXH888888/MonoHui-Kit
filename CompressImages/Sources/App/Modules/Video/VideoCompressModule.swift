import Foundation

enum VideoCompressModule {
    static let serviceActions: [ServiceAction] = [
        ServiceAction(
            id: "video.quick",
            menuName: "视频·压缩",
            bundleIdentifier: "com.quickactions.workflow.video.quick",
            acceptedFileTypes: ["public.movie"],
            launchArgs: ["--module", "video", "--mode", "quick"]
        )
    ]
}
