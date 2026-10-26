import Foundation

enum DateFolderModule {
    static let serviceActions: [ServiceAction] = [
        ServiceAction(
            id: "datefolder.ym",
            menuName: "文件夹·新建-年月",
            bundleIdentifier: "com.monohui.kit.workflow.datefolder.ym",
            acceptedFileTypes: ["public.folder", "public.item"],
            launchArgs: ["--module", "datefolder", "--format", "yyMM"]
        ),
        ServiceAction(
            id: "datefolder.md",
            menuName: "文件夹·新建-月日",
            bundleIdentifier: "com.monohui.kit.workflow.datefolder.md",
            acceptedFileTypes: ["public.folder", "public.item"],
            launchArgs: ["--module", "datefolder", "--format", "MMdd"]
        ),
        ServiceAction(
            id: "datefolder.ymd",
            menuName: "文件夹·新建-年月日",
            bundleIdentifier: "com.monohui.kit.workflow.datefolder.ymd",
            acceptedFileTypes: ["public.folder", "public.item"],
            launchArgs: ["--module", "datefolder", "--format", "yyMMdd"]
        ),
        ServiceAction(
            id: "datefolder.interactive",
            menuName: "文件夹·新建（弹窗）",
            bundleIdentifier: "com.monohui.kit.workflow.datefolder.interactive",
            acceptedFileTypes: ["public.folder", "public.item"],
            launchArgs: ["--module", "datefolder", "--mode", "interactive"]
        )
    ]

    static let defaultFormats: [(label: String, format: String, example: String)] = [
        ("年月", "yyMM", "2605"),
        ("月日", "MMdd", "0530"),
        ("年月日", "yyMMdd", "260530")
    ]
}
