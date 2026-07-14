import SwiftUI

struct DateFolderView: View {
    @AppStorage("datefolder_prefix") private var prefix = ""
    @AppStorage("datefolder_suffix") private var suffix = "-"
    @State private var customFormat = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                defaultFormatsSection
                customSection
                behaviorSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appleCanvas)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日期文件夹")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("在 Finder 中右键文件 → 服务 → 文件夹·新建-XXX\n即可在同级目录创建以日期命名的文件夹")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - Section header（micro 样式：11/500/uppercase/0.066em tracking）

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(Color.appleMuted)
    }

    private var defaultFormatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("默认格式（右键服务菜单）")

            VStack(spacing: 6) {
                ForEach(DateFolderModule.defaultFormats, id: \.format) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Color.appleBlue)
                        Text(item.label)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.appleInk)
                        Spacer()
                        Text("示例: \(item.example)")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.appleSoft)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.appleCanvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(14)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("自定义（影响所有日期文件夹）")

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text("前缀")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 48, alignment: .leading)
                    TextField("如：项目_", text: $prefix)
                        .textFieldStyle(.roundedBorder)
                    Text(previewName)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 100)
                }

                HStack(spacing: 12) {
                    Text("后缀")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                        .frame(width: 48, alignment: .leading)
                    TextField("如：_备份", text: $suffix)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }

                Text("日期格式占位符：yy（年2位）yyyy（年4位）MM（月）dd（日）HH（时）mm（分）ss（秒）")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.appleMuted)
            }
            .padding(16)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("新建后行为")

            let hasPermission = DateFolderEngine.hasAccessibilityPermission()
            HStack(spacing: 8) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .frame(width: 16, height: 16)
                    .foregroundStyle(hasPermission ? .green : .orange)
                Text(hasPermission
                     ? "已获得辅助功能权限，新建后将自动进入重命名模式"
                     : "未获得辅助功能权限，新建后将仅选中文件夹。请在系统设置 → 隐私与安全性 → 辅助功能中授权。")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.appleSoft)
            }
            .padding(16)
            .background(Color.appleSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var previewName: String {
        "\(prefix)\(DateFolderEngine.formatName(format: "yyMMdd", prefix: "", suffix: ""))\(suffix)"
    }
}
