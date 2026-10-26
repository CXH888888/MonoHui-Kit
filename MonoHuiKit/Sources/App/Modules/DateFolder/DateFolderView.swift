import SwiftUI

struct DateFolderView: View {
    @AppStorage("datefolder_prefix") private var prefix = ""
    @AppStorage("datefolder_suffix") private var suffix = "-"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                defaultFormatsSection
                customSection
                behaviorSection
                quickRenameSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("文件命名扩展")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("在 Finder 中右键文件 → 服务 → 文件夹·新建-XXX\n即可在同级目录创建以日期命名的文件夹")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - Section header（13/semibold，与功能行形成层次）

    private func sectionHeader(_ text: String) -> some View { SectionHeader(text) }

    // MARK: - 分隔线

    private var divider: some View { SectionDivider() }

    private var defaultFormatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("默认格式")
            Text("右键服务菜单中显示的三种日期格式")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.top, -6)

            VStack(spacing: 0) {
                ForEach(Array(DateFolderModule.defaultFormats.enumerated()), id: \.element.format) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 16))
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.appleBlue)
                        Text(item.label)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.appleInk)
                        Spacer()
                        Text("示例: \(item.example)")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.appleSoft)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    if index < DateFolderModule.defaultFormats.count - 1 {
                        divider
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("自定义")
            Text("影响所有日期文件夹名称的前缀与后缀")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.top, -6)

            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Text("前缀")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 48, alignment: .leading)
                    TextField("如：项目_", text: $prefix)
                        .textFieldStyle(.roundedBorder)
                    Text(previewName)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 100)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                divider

                HStack(spacing: 14) {
                    Text("后缀")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 48, alignment: .leading)
                    TextField("如：_备份", text: $suffix)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("日期格式占位符：yy（年2位）yyyy（年4位）MM（月）dd（日）HH（时）mm（分）ss（秒）")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleMuted)
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("新建后行为")

            let hasPermission = DateFolderEngine.hasAccessibilityPermission()
            HStack(spacing: 12) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(hasPermission ? .green : .orange)
                Text(hasPermission
                     ? "已获得辅助功能权限，新建后将自动进入重命名模式"
                     : "未获得辅助功能权限，新建后将仅选中文件夹。请在系统设置 → 隐私与安全性 → 辅助功能中授权。")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var previewName: String {
        "\(prefix)\(DateFolderEngine.formatName(format: "yyMMdd", prefix: "", suffix: ""))\(suffix)"
    }

    // MARK: - 快速改名说明区块
    private var quickRenameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("快速改名")
            VStack(alignment: .leading, spacing: 8) {
                Text("在 Finder 中选中文件，按 ⌘R 或右键 → 服务 → 文件命名·快速改名")
                Text("智能识别原文件名格式，拆解为日期/渠道/名字/版本/状态可编辑字段")
                Text("状态标签可在弹窗中右键改名、单击新增/删除")
            }
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(Color.appleSoft)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appleSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appleDivider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
