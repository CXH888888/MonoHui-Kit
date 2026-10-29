import SwiftUI

struct DateFolderView: View {
    @AppStorage("datefolder_prefix") private var prefix = ""
    @AppStorage("datefolder_suffix") private var suffix = "-"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader("文件命名扩展", subtitle: "在 Finder 右键 → 服务，按日期新建文件夹")

                VStack(alignment: .leading, spacing: 8) {
                    namingCard
                    Text("占位符：yy yyyy MM dd HH mm ss")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                        .padding(.leading, 4)
                        .help("yy 年2位 · yyyy 年4位 · MM 月 · dd 日 · HH 时 · mm 分 · ss 秒")
                }

                actionsCard
            }
            .pagePadding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
    }

    // MARK: - 命名规则

    private var namingCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("默认格式")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleSoft)

                HStack(spacing: 12) {
                    ForEach(Array(DateFolderModule.defaultFormats.enumerated()), id: \.element.format) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.appleBlue)
                                Text(item.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color.appleInk)
                            }
                            Text(item.example)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.appleSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if index < DateFolderModule.defaultFormats.count - 1 {
                            Rectangle()
                                .fill(Color.appleDivider)
                                .frame(width: 1, height: 30)
                        }
                    }
                }
            }
            .padding(16)

            SectionDivider()

            fieldRow("前缀", placeholder: "如：项目_", text: $prefix)
            SectionDivider()
            fieldRow("后缀", placeholder: "如：_备份", text: $suffix)

            SectionDivider()

            HStack(spacing: 6) {
                Text("预览")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appleSoft)
                Text(previewName)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleInk)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appleDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fieldRow(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .frame(width: 40, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - 快捷操作

    private var actionsCard: some View {
        let hasPermission = DateFolderEngine.hasAccessibilityPermission()

        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(hasPermission ? Color.green : Color.orange)
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hasPermission ? "新建后自动进入重命名" : "新建后仅选中文件夹")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Text(hasPermission ? "已获得辅助功能权限" : "请在系统设置 → 隐私与安全性 → 辅助功能中授权")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            SectionDivider()

            HStack(spacing: 12) {
                Text("⌘R")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.appleInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.appleSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .frame(width: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("快速改名")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.appleInk)
                    Text("选中文件按 ⌘R，或右键 → 服务 → 文件命名·快速改名")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .help("智能识别原文件名格式，拆解为日期/渠道/名字/版本/状态可编辑字段；状态标签可右键改名、单击新增/删除")
        }
        .background(Color.appleSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appleDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var previewName: String {
        "\(prefix)\(DateFolderEngine.formatName(format: "yyMMdd", prefix: "", suffix: ""))\(suffix)"
    }
}
