import SwiftUI

/// 三个列表页（图片压缩 / 视频压缩 / 格式转化）共用的参数区构件。
///
/// 之前每页各写各的：标签宽度 24 和 32 混用、主按钮宽度 180 和 190 混用、
/// 有的页把主按钮塞进「参数行」右端（和开关抢位置），有的页单独一行。
/// 这里把结构固定成：
///
///     参数行（左标签 + 胶囊组 + 可选右端辅助控件）× N
///     操作行（左：状态/提示，右：取消 + 主按钮）
///
/// 三页都按这个来，横向左边缘和纵向节奏就自然对齐了。
enum ParamLayout {
    /// 左侧标签固定宽度：「格式」「质量」两字与「分辨率」三字都在这一栏里对齐
    static let labelWidth: CGFloat = 36
    static let rowSpacing: CGFloat = 8
    static let rowGap: CGFloat = 10
    /// 主按钮统一尺寸，三页一致
    static let actionWidth: CGFloat = 180
    static let actionHeight: CGFloat = 40
}

// MARK: - 参数行

/// 左侧标签 + 内容 + 右端辅助控件
struct ParamRow<Content: View, Trailing: View>: View {
    let label: String
    let content: Content
    let trailing: Trailing

    init(_ label: String,
         @ViewBuilder content: () -> Content,
         @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: ParamLayout.rowSpacing) {
            ParamLabel(text: label)
            content
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension ParamRow where Trailing == EmptyView {
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.init(label, content: content, trailing: { EmptyView() })
    }
}

/// 参数行左端的标签
struct ParamLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.appleSoft)
            .lineLimit(1)
            .frame(width: ParamLayout.labelWidth, alignment: .leading)
    }
}

// MARK: - 操作行

/// 左：状态/提示文字；右：取消 + 主按钮。
/// 主按钮尺寸、颜色、转圈样式三页统一。
struct PrimaryActionBar<Leading: View>: View {
    let title: String
    let isBusy: Bool
    let isEnabled: Bool
    let onCancel: (() -> Void)?
    let action: () -> Void
    let leading: Leading

    init(title: String,
         isBusy: Bool = false,
         isEnabled: Bool = true,
         onCancel: (() -> Void)? = nil,
         action: @escaping () -> Void,
         @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.isBusy = isBusy
        self.isEnabled = isEnabled
        self.onCancel = onCancel
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            Spacer(minLength: 0)

            if isBusy, let onCancel {
                Button("取消", action: onCancel)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appleSoft)
            }

            Button(action: action) {
                HStack(spacing: 6) {
                    if isBusy {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(title)
                        .font(.system(size: 15, weight: .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(width: ParamLayout.actionWidth, height: ParamLayout.actionHeight)
                .background(isBusy ? Color.appleBlue.opacity(0.7) : Color.appleBlue)
                .clipShape(RoundedRectangle(cornerRadius: 980))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !isEnabled)
            // 没有文件时按钮要看得出来「现在点不了」，之前只是不可点、颜色照旧
            .opacity(isEnabled || isBusy ? 1 : 0.45)
        }
    }
}

extension PrimaryActionBar where Leading == EmptyView {
    init(title: String,
         isBusy: Bool = false,
         isEnabled: Bool = true,
         onCancel: (() -> Void)? = nil,
         action: @escaping () -> Void) {
        self.init(title: title,
                  isBusy: isBusy,
                  isEnabled: isEnabled,
                  onCancel: onCancel,
                  action: action,
                  leading: { EmptyView() })
    }
}
