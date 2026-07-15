import SwiftUI

struct AboutDiagnosticsView: View {
    @State private var showDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                aboutSection
                diagnosticsSection
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollContentBackground(.hidden)
        .background(Color.appleCanvas)
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
    }

    // MARK: - 顶部条

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("关于与诊断")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Color.appleInk)
            Text("应用信息与诊断日志")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.appleInk)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?.?.?"
    }

    // MARK: - 关于

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("关于")
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("QuickActions")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appleInk)
                    Text("快捷右键工具箱")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color.appleSoft)
                    Text("版本 \(appVersion)")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.appleMuted)
                }
                Spacer()
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

    // MARK: - 诊断日志

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("诊断")
            Text("查看运行日志与手动测试服务菜单触发")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Color.appleSoft)
                .padding(.top, -6)

            Button {
                showDiagnostics = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 14, weight: .regular))
                    Text("打开诊断日志")
                        .font(.system(size: 14, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(Color.appleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 980))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
