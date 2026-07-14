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
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("在 Finder 中右键文件 → 服务 → 文件夹·新建-XXX\n即可在同级目录创建以日期命名的文件夹")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    private var defaultFormatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("默认格式（右键服务菜单）")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            ForEach(DateFolderModule.defaultFormats, id: \.format) { item in
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.appleBlue)
                    Text(item.label)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleInk)
                    Spacer()
                    Text("示例: \(item.example)")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleSoft)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Color.appleSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义（影响所有日期文件夹）")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

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
            Text("新建后行为")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.appleInk)

            let hasPermission = DateFolderEngine.hasAccessibilityPermission()
            HStack(spacing: 8) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
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
