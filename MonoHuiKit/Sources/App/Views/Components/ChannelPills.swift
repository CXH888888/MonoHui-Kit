import SwiftUI

/// 渠道标签的两种排版：单文件弹窗用横向行（32pt 高、左右 12 内边距），
/// 批量弹窗用网格列（28pt 高、撑满列宽）。
enum ChannelPillLayout: Equatable {
    case row
    case grid
}

/// 自定义渠道标签：点击切换选中，hover 时右上角浮出删除按钮。
/// 选中态与 hover 态都由调用方持有，组件只负责渲染与交互回调。
struct ChannelCustomPill: View {
    let title: String
    let isSelected: Bool
    let layout: ChannelPillLayout
    @Binding var hovering: String?
    let onTap: () -> Void
    let onDelete: () -> Void

    private var isHovering: Bool { hovering == title }

    var body: some View {
        Group {
            if layout == .row {
                rowPill
            } else {
                gridPill
            }
        }
        .onHover { hover in
            withAnimation(Motion.moveFast) {
                hovering = hover ? title : nil
            }
        }
    }

    private var rowPill: some View {
        Text(title)
            .font(.system(size: 12, weight: .regular))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isSelected ? .white : Color.appleInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            // 圆角背景用 shape 画（不再用 clipShape，避免裁到右上角溢出的删除按钮）
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
            )
            .overlay(alignment: .topTrailing) {
                if isHovering {
                    Button(action: onDelete) {
                        deleteIcon
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
    }

    private var gridPill: some View {
        ZStack(alignment: .topTrailing) {
            // 圆角背景（独立，不裁剪任何前景内容）
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.appleBlue : Color.appleSurface2)
            // 文字（撑满网格列居中，不被红叉遮挡）
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(isSelected ? .white : Color.appleInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 删除按钮：骑在标签右上角、向外突出（经典角标），纯淡入即时出现
            if isHovering {
                Button(action: onDelete) {
                    deleteIcon
                }
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .offset(x: 6, y: -6)
                .buttonStyle(.plain)
                .transition(.opacity)
                .help("删除「\(title)」")
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var deleteIcon: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.white, Color.red.opacity(0.9))
            .background(
                Circle()
                    .fill(Color.appleCardOnCanvas)
                    .frame(width: 18, height: 18)
            )
    }
}

/// 「其他」渠道：未选中时是灰色入口 pill，选中时变成内联输入框（铅笔图标 + 右侧 ×）。
struct ChannelOtherPill: View {
    let isActive: Bool
    let layout: ChannelPillLayout
    @Binding var text: String
    var textFocus: FocusState<Bool>.Binding
    let onToggle: () -> Void
    let onRemove: () -> Void
    var onSubmit: (() -> Void)? = nil
    var onTextChange: (() -> Void)? = nil

    var body: some View {
        if isActive {
            if layout == .row {
                rowInput
            } else {
                gridInput
            }
        } else {
            if layout == .row {
                rowEntry
            } else {
                gridEntry
            }
        }
    }

    private var rowInput: some View {
        HStack(spacing: 4) {
            pencilIcon
            TextField("输入", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .frame(width: 60)
                .focused(textFocus)
                .onSubmit { onSubmit?() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(Color.appleSurface2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleBlue, lineWidth: 1.5)
        )
        .overlay(alignment: .trailing) {
            // × 退出"其他"：Image + frame(28,28) + contentShape 保证整个区域可点击
            removeButton(size: 28, action: remove)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { textFocus.wrappedValue = true }
    }

    private var gridInput: some View {
        HStack(spacing: 4) {
            pencilIcon
            TextField("输入", text: $text)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.appleInk)
                .focused(textFocus)
                .onSubmit { onSubmit?() }
                .onChange(of: text) { _, _ in onTextChange?() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleBlue, lineWidth: 1.5)
                .overlay(alignment: .trailing) {
                    removeButton(size: 24, action: remove)
                }
        )
    }

    private var rowEntry: some View {
        // "其他"未选中：比固定标签稍微暗一些的灰底色块（无描边），表示可输入入口
        Button {
            onToggle()
            // 切换后等 TextField 渲染完成再聚焦
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textFocus.wrappedValue = true
            }
        } label: {
            Text("其他")
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(Color.appleInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(Color.appleSurface3)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gridEntry: some View {
        ZStack {
            Text("其他")
                .font(.system(size: 12, weight: .regular))
                .lineLimit(1)
                .foregroundStyle(Color.appleInk)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textFocus.wrappedValue = true
            }
        }
    }

    private var pencilIcon: some View {
        Image(systemName: "pencil")
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(Color.appleBlue)
    }

    private func removeButton(size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.appleSoft)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func remove() {
        onRemove()
        textFocus.wrappedValue = false
    }
}

/// 「+新增」渠道标签：未展开时是虚线按钮，展开后是内联输入框（回车提交、× 取消）。
struct ChannelAddControl: View {
    let layout: ChannelPillLayout
    @Binding var isAdding: Bool
    @Binding var text: String
    var textFocus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        if isAdding {
            if layout == .row {
                rowInput
            } else {
                gridInput
            }
        } else {
            if layout == .row {
                rowButton
            } else {
                gridButton
            }
        }
    }

    private var rowInput: some View {
        HStack(spacing: 4) {
            newTagField
                .frame(width: 70)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background(Color.appleSurface2)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleBlue, lineWidth: 1.5)
        )
        .overlay(alignment: .trailing) {
            // × 取消新增：Image + frame(28,28) + contentShape 保证整个区域可点击
            cancelButton(size: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textFocus.wrappedValue = true
            }
        }
    }

    private var gridInput: some View {
        HStack(spacing: 4) {
            newTagField
            cancelButton(size: 24)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appleBlue, lineWidth: 1.5))
    }

    private var rowButton: some View {
        Button {
            isAdding = true
        } label: {
            addLabel(fontSize: 12)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 32)
                .background(Color.clear)
                .overlay(dashedBorder)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var gridButton: some View {
        Button {
            isAdding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textFocus.wrappedValue = true
            }
        } label: {
            addLabel(fontSize: 11)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .background(Color.clear)
                .overlay(dashedBorder)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var newTagField: some View {
        TextField("输入标签名", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(Color.appleInk)
            .focused(textFocus)
            .onSubmit { onSubmit() }
    }

    private func cancelButton(size: CGFloat) -> some View {
        Button {
            isAdding = false
            text = ""
            textFocus.wrappedValue = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.appleSoft)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addLabel(fontSize: CGFloat) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .regular))
            Text("新增")
                .font(.system(size: fontSize, weight: .regular))
        }
        .foregroundStyle(Color.appleSoft.opacity(0.7))
    }

    private var dashedBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(
                Color.appleSoft.opacity(0.35),
                style: StrokeStyle(
                    lineWidth: 1,
                    dash: [4, 3]
                )
            )
    }
}
