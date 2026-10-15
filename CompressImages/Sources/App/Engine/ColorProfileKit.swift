import Foundation

/// 色彩配置（ICC profile）工具。
///
/// 背景：JPEG 有损压缩链路 `djpeg | cjpeg` 不传递 ICC profile
/// （djpeg 解码为不带 profile 的位图，cjpeg 也不再写回）。
/// 源文件若带 Adobe RGB / Display P3 等非 sRGB profile，压缩后
/// profile 丢失，查看器按 sRGB 解释像素，颜色会出现整体偏差。
/// 这里在编码完成后把源 profile 以标准 APP2 "ICC_PROFILE" marker
/// 写回输出（纯字节级操作，不触碰已编码的像素数据）。
///
/// 注：PNG 有损路径（pngquant）本身会用 lcms 把非 sRGB 源转换为
/// sRGB 并写入 gAMA/sRGB chunk，色彩解释是正确的，无需本工具介入。
enum ColorProfileKit {

    /// 从 JPEG 中提取嵌入的 ICC profile（重组 APP2 "ICC_PROFILE" marker 分片）；
    /// 文件不是 JPEG 或没有嵌入 profile 时返回 nil。
    static func profile(of url: URL) -> Data? {
        guard let data = FileManager.default.contents(atPath: url.path),
              data.count > 1,
              data[data.startIndex] == 0xFF,
              data[data.startIndex + 1] == 0xD8 else {
            return nil
        }
        var chunks: [(sequence: Int, total: Int, payload: Data)] = []
        var index = data.startIndex + 2  // 跳过 SOI
        while index + 4 <= data.endIndex {
            guard data[index] == 0xFF else { break }
            let marker = data[index + 1]
            // EOI / SOS：marker 区结束
            if marker == 0xD9 || marker == 0xDA { break }
            // 独立 marker（无长度字段）
            if marker == 0x01 || (0xD0...0xD7).contains(marker) {
                index += 2
                continue
            }
            let length = Int(data[index + 2]) << 8 | Int(data[index + 3])
            guard length >= 2, index + 2 + length <= data.endIndex else { break }
            let payloadStart = index + 4
            let payloadEnd = index + 2 + length
            if marker == 0xE2, payloadEnd - payloadStart >= 14,
               String(decoding: data.subdata(in: payloadStart..<(payloadStart + 12)), as: UTF8.self) == "ICC_PROFILE\0" {
                let sequence = Int(data[payloadStart + 12])
                let total = Int(data[payloadStart + 13])
                chunks.append((sequence, total, data.subdata(in: (payloadStart + 14)..<payloadEnd)))
            }
            index += 2 + length
        }
        guard !chunks.isEmpty else { return nil }
        let total = chunks[0].total
        guard total >= 1, chunks.count == total else { return nil }  // 分片不全则放弃
        var profile = Data()
        for expected in 1...total {
            guard let chunk = chunks.first(where: { $0.sequence == expected }) else { return nil }
            profile.append(chunk.payload)
        }
        return profile
    }

    /// 把 ICC profile 以 APP2 "ICC_PROFILE" marker 写入 JPEG（插在 SOI 之后）。
    /// 已带 ICC profile 的文件不重复写入；非 JPEG 结构的数据直接忽略。
    static func embedProfile(_ profile: Data, intoJPEGAt url: URL) {
        guard !profile.isEmpty,
              self.profile(of: url) == nil,  // 已有 ICC 则不叠加
              let data = FileManager.default.contents(atPath: url.path),
              data.count > 2 else {
            return
        }
        // JPEG SOI: FF D8
        guard data[data.startIndex] == 0xFF,
              data[data.startIndex + 1] == 0xD8 else {
            return
        }

        // APP2 段总长上限 65535：2 字节长度字段 + "ICC_PROFILE\0"(12) + 序号 + 总数 + 数据
        let maxChunkSize = 65519
        var chunks: [Data] = []
        var offset = profile.startIndex
        while offset < profile.endIndex {
            let end = min(offset + maxChunkSize, profile.endIndex)
            chunks.append(profile.subdata(in: offset..<end))
            offset = end
        }
        guard chunks.count <= 255 else { return }

        var markers = Data()
        for (index, chunk) in chunks.enumerated() {
            var payload = Data("ICC_PROFILE\0".utf8)
            payload.append(UInt8(index + 1))
            payload.append(UInt8(chunks.count))
            payload.append(chunk)
            let length = UInt16(payload.count + 2)
            var segment = Data([0xFF, 0xE2])
            segment.append(UInt8(truncatingIfNeeded: length >> 8))
            segment.append(UInt8(truncatingIfNeeded: length))
            segment.append(payload)
            markers.append(segment)
        }

        var output = data.subdata(in: data.startIndex..<(data.startIndex + 2))  // SOI
        output.append(markers)
        output.append(data.subdata(in: (data.startIndex + 2)..<data.endIndex))
        try? output.write(to: url, options: .atomic)
    }
}
