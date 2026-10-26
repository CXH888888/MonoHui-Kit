import Foundation

/// mozjpeg 色度抽样参数（Y,Cb,Cr 三分量采样因子）。
/// libjpeg 默认 4:2:0（色度分辨率减半），高对比彩色边缘与暖色细节会糊化；
/// 改为 1x1 即 4:4:4，最大限度保住色彩，代价是体积增大约 10~16%。
private let mozjpegChromaSampling = "1x1,1x1,1x1"

struct ToolResolver {
    let toolsDir: String
    var libDir: String { "\(toolsDir)/lib" }

    var libExists: Bool {
        FileManager.default.fileExists(atPath: libDir)
    }

    init(toolsDir: String? = nil) {
        if let dir = toolsDir {
            self.toolsDir = dir
        } else {
            let bundleTools = Bundle.main.resourcePath.map { "\($0)/tools" }
            let devTools = FileManager.default.currentDirectoryPath + "/Sources/App/Resources/tools"
            self.toolsDir = bundleTools ?? devTools
        }
    }

    func toolExists(_ name: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: "\(toolsDir)/\(name)")
    }

    func buildProcess(format: CompressionFormat, quality: QualityLevel, input: String, output: String) throws -> Process {
        let proc = Process()
        var args: [String] = []

        switch format {
        case .png:
            if quality == .lossless {
                proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/oxipng")
                args = ["-o", "4", "--strip", "safe", "--out", output, input]
            } else {
                let qualityArg = pngQualityArg(quality)
                proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/pngquant")
                // --force：pngquant 默认拒绝覆盖已存在的输出（退出码 15），
                // 重复压缩同一张图时允许刷新输出文件
                args = ["--force", "--quality=\(qualityArg)", "--output", output, "--", input]
            }

        case .jpeg:
            let ext = (input as NSString).pathExtension.lowercased()
            let isJpegInput = (ext == "jpg" || ext == "jpeg")
            let hasMozjpeg = toolExists("djpeg") && toolExists("cjpeg")

            if isJpegInput && hasMozjpeg {
                if quality == .lossless && toolExists("jpegtran") {
                    proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/jpegtran")
                    args = ["-copy", "all", "-optimize", "-outfile", output, input]
                } else {
                    proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    let q = jpegQualityValue(quality)
                    let ei = input.replacingOccurrences(of: "'", with: "'\\''")
                    let eo = output.replacingOccurrences(of: "'", with: "'\\''")
                    let ld = libDir.replacingOccurrences(of: "'", with: "'\\''")
                    args = ["-c", "export DYLD_LIBRARY_PATH='\(ld)'; '\(toolsDir)/djpeg' '\(ei)' | '\(toolsDir)/cjpeg' -quality \(q) -sample \(mozjpegChromaSampling) -outfile '\(eo)' /dev/stdin"]
                }
            } else {
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                let q = jpegQualityValue(quality)
                args = ["-s", "format", "jpeg", "-s", "formatOptions", "\(q)", input, "--out", output]
            }

        case .gif:
            proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/gifsicle")
            let colors = gifColorCount(quality)
            args = ["-O3", "--colors", "\(colors)", "-o", output, input]

        case .webp:
            proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/cwebp")
            let q = webpQuality(quality)
            args = ["-q", "\(q)", input, "-o", output]

        case .avif:
            proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/avifenc")
            let q = avifQuality(quality)
            // 不要加 --min 0 --max 0：这两个参数会把质量锁死在 100，
            // 让「中/低」档完全失效（实测同一张图 q75 与 q100 体积差 10 倍以上）。
            args = ["-s", "8", "-q", "\(q)", input, "-o", output]

        case .jxl:
            proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/cjxl")
            let q = jxlQuality(quality)
            args = ["-q", "\(q)", input, output]

        case .svg:
            proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/svgop")
            guard let infile = FileHandle(forReadingAtPath: input) else {
                throw CompressionEngine.CompressionError.invalidInput
            }
            FileManager.default.createFile(atPath: output, contents: nil)
            guard let outfile = FileHandle(forWritingAtPath: output) else {
                throw CompressionEngine.CompressionError.invalidInput
            }
            proc.standardInput = infile
            proc.standardOutput = outfile
        }

    proc.arguments = args
    return proc
}

/// pngquant 在即使 256 色也达不到质量下限时会跳过文件（退出码 99、无输出）。
/// 此时改用宽松区间重试，保证一定产出文件（色彩仍由 pngquant 自行决定）。
func buildPNGRetryProcess(input: String, output: String) -> Process {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/pngquant")
    proc.arguments = ["--force", "--quality=20-100", "--output", output, "--", input]
    return proc
}

/// PNG 无损重编码（oxipng）。pngquant 两次都无法产出时的兜底，保证必有文件。
func buildLosslessProcess(input: String, output: String) -> Process {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "\(toolsDir)/oxipng")
    proc.arguments = ["-o", "4", "--strip", "safe", "--out", output, input]
    return proc
}
}

private func pngQualityArg(_ q: QualityLevel) -> String {
    // pngquant --quality=min-max 中 min 为质量下限：min 越高色板越大、越保色。
    // 区间与 QualityLevel.displayName 的标称值对齐（例如「中（75）」→ 65-80）。
    // 注意：若某张图即使 256 色也达不到 min，pngquant 会跳过该文件（无输出），
    // 此时由 CompressionEngine 用 buildPNGRetryProcess 放宽区间重试。
    switch q {
    case .lossless: return "100"
    case .highest:  return "85-100"
    case .high:     return "75-90"
    case .medium:   return "65-80"
    case .low:      return "40-55"
    case .lowest:   return "10-30"
    }
}

private func jpegQualityValue(_ q: QualityLevel) -> Int {
    switch q {
    case .lossless: return 100
    case .highest:  return 100
    case .high:     return 90
    case .medium:   return 75
    case .low:      return 50
    case .lowest:   return 20
    }
}

private func gifColorCount(_ q: QualityLevel) -> Int {
    // GIF 调色板上限 256 色，中档从 128 提到 192，减少减色造成的色偏
    switch q {
    case .lossless: return 256
    case .highest:  return 256
    case .high:     return 224
    case .medium:   return 192
    case .low:      return 128
    case .lowest:   return 64
    }
}

private func webpQuality(_ q: QualityLevel) -> Int {
    switch q {
    case .lossless: return 100
    case .highest:  return 100
    case .high:     return 90
    case .medium:   return 75
    case .low:      return 50
    case .lowest:   return 20
    }
}

private func avifQuality(_ q: QualityLevel) -> Int {
    switch q {
    case .lossless: return 100
    case .highest:  return 100
    case .high:     return 80
    case .medium:   return 60
    case .low:      return 40
    case .lowest:   return 20
    }
}

private func jxlQuality(_ q: QualityLevel) -> Int {
    switch q {
    case .lossless: return 100
    case .highest:  return 99
    case .high:     return 90
    case .medium:   return 75
    case .low:      return 50
    case .lowest:   return 20
    }
}
