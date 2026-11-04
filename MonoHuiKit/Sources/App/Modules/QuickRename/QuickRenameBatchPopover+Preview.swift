import SwiftUI
import AppKit

// MARK: - 更名预览区
extension QuickRenameBatchPopover {
    // MARK: - 预览区

    var previewArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("更名预览")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appleSoft)
                Spacer()
                if hasDuplicates {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .regular))
                        Text("检测到重名，已自动加序号")
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            // 默认 3 行 + 2 个行间距；超出后内部滚动（AppKit 通知驱动渐变与细滚动条）
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(Array(files.enumerated()), id: \.offset) { idx, _ in
                        previewRow(idx: idx)
                    }
                }
                .background(
                    ScrollEdgeObserver(axis: .vertical) { geom in
                        previewScrollGeom = geom
                    }
                )
            }
            .frame(height: previewListFitHeight)
            // 顶/底渐变：滚动离开边界后淡出内容。本区直接铺在弹窗底上，
            // 之前用的 appleSurface2 比弹窗底亮 10/255，会浮出一条浅灰带（改成 mask 后无需配色）
            .scrollEdgeFade(top: showPreviewTopFade, bottom: showPreviewBottomFade, length: 14)
            // 自绘细滚动条：贴右侧边缘；仅滚动期间显示，停止 0.9s 后淡出（macOS 覆盖式滚动条行为）
            .overlay(alignment: .trailing) {
                GeometryReader { geo in
                    let trackHeight = geo.size.height - 8
                    let ratio = previewScrollGeom.viewportLength > 0
                        ? previewScrollGeom.viewportLength / previewScrollGeom.contentLength
                        : 1
                    let thumbHeight = max(24, trackHeight * ratio)
                    let maxOffset = previewScrollGeom.contentLength - previewScrollGeom.viewportLength
                    let yOffset = maxOffset > 0
                        ? previewScrollGeom.offset / maxOffset * (trackHeight - thumbHeight)
                        : 0
                    Capsule()
                        .fill(Color.appleMuted.opacity(0.4))
                        .frame(width: 3, height: thumbHeight)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: 4 + yOffset)
                }
                .padding(.trailing, 3)
                .allowsHitTesting(false)
                .opacity(previewOverflow && scrollbarVisible ? 1 : 0)
            }
            .onChange(of: previewScrollGeom.offset) { _, _ in
                withAnimation(Motion.easeFast) { scrollbarVisible = true }
                scrollbarHideTask?.cancel()
                let task = DispatchWorkItem {
                    withAnimation(Motion.easeStandard) { scrollbarVisible = false }
                }
                scrollbarHideTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: task)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appleSurface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func previewRow(idx: Int) -> some View {
        let suffixes = duplicateSuffixes
        let dupSuffix = idx < suffixes.count ? suffixes[idx] : nil

        VStack(alignment: .leading, spacing: 4) {
            // 第一行：序号 + 原始文件名（删除线）+ 更改后完整文件名（右对齐）
            HStack(spacing: 6) {
                Text("\(idx + 1)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.appleMuted)
                    .frame(width: 18, height: 18)
                    .background(Color.appleSurface3)
                    .clipShape(Circle())
                Text(originalFullName(fileIdx: idx))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.appleMuted.opacity(0.6))
                    .strikethrough()
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
                Spacer(minLength: 8)
                Text(fullNewName(fileIdx: idx))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.appleBlue)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 第二行：新文件名标签组（左上对齐）
            HStack(spacing: 3) {
                // 先算出实际可见（有值）的字段，+ 只出现在非首个可见字段之前，避免行首孤儿 +
                let visibleKeys = fieldConfigs
                    .filter { !fieldValue(fileIdx: idx, key: $0.key).isEmpty }
                    .map(\.key)
                ForEach(Array(fieldConfigs.enumerated()), id: \.element.key) { _, config in
                    let val = fieldValue(fileIdx: idx, key: config.key)
                    // 没值的字段不显示
                    if !val.isEmpty {
                        // 分隔符：仅当前面已有可见字段时显示
                        if visibleKeys.first != config.key {
                            Text("+")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(Color.appleMuted.opacity(0.4))
                        }
                        // 标签或编辑框
                        if editingTag == EditingTag(fileIdx: idx, fieldKey: config.key) {
                            batchTagEditField(fileIdx: idx, fieldKey: config.key, currentVal: val)
                        } else {
                            batchTagLabel(fileIdx: idx, fieldKey: config.key, value: val)
                        }
                    }
                }
                // 重名后缀：重名组内所有文件（含第 1 个）都显示序号，样式与其他小标签同款
                if let suffix = dupSuffix {
                    Text("\(suffix)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 16, alignment: .center)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                // 扩展名
                let ext = extForFile(fileIdx: idx)
                if !ext.isEmpty {
                    Text(".\(ext)")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.appleMuted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 26)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.applePopupCanvas)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appleDivider.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // 固定每行高度（含标题行与重名气泡所在标签行），垂直居中：行高恒定，重名不撑开窗口
        .frame(height: previewRowHeight, alignment: .center)
    }

    // 预览区标签：名字标签伸展占据中间富余空间；其他字段固定 5 字宽，长内容截断
    @ViewBuilder
    private func batchTagLabel(fileIdx: Int, fieldKey: String, value: String) -> some View {
        let displayText: String = fieldKey == "version" ? "v\(value)" : value
        let fieldConfig = fieldConfigs.first(where: { $0.key == fieldKey })
        let isUnify = fieldConfig?.mode == .unify
        Group {
            if fieldKey == "name" {
                // 名字：占据四个固定标签之外的剩余宽度，内容居中，超长截断
                Text(displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(isUnify ? Color.appleBlue : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 60, maxWidth: .infinity, alignment: .center)
                    .padding(6)
            } else {
                // 小标签：文字区固定 36pt，居中
                Text(displayText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(isUnify ? Color.appleBlue : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 36, alignment: .center)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
            }
        }
        .background(isUnify ? Color.appleBlue.opacity(0.10) : Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            editingTag = EditingTag(fileIdx: fileIdx, fieldKey: fieldKey)
        }
    }

    // 预览区标签编辑框
    @ViewBuilder
    private func batchTagEditField(fileIdx: Int, fieldKey: String, currentVal: String) -> some View {
        let binding = Binding<String>(
            get: { overrides[fileIdx][fieldKey] ?? currentVal },
            set: { newVal in
                if fileIdx < overrides.count {
                    overrides[fileIdx][fieldKey] = newVal
                }
            }
        )
        TextField(fieldKey, text: binding, onCommit: {
            editingTag = nil
        })
        .textFieldStyle(.plain)
        .multilineTextAlignment(.center)
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.appleInk)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: 60)
        .background(Color.applePopupCanvas)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.appleBlue, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .focused($batchTagFocused)
    }

}
