import Foundation

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
                args = ["--quality=\(qualityArg)", "--output", output, "--", input]
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
                    args = ["-c", "export DYLD_LIBRARY_PATH='\(ld)'; '\(toolsDir)/djpeg' '\(ei)' | '\(toolsDir)/cjpeg' -quality \(q) -outfile '\(eo)' /dev/stdin"]
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
            args = ["-s", "8", "--min", "0", "--max", "0", "-q", "\(q)", input, "-o", output]

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
}

private func pngQualityArg(_ q: QualityLevel) -> String {
    switch q {
    case .lossless: return "100"
    case .highest:  return "80-95"
    case .high:     return "65-80"
    case .medium:   return "50-65"
    case .low:      return "30-50"
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
    switch q {
    case .lossless: return 256
    case .highest:  return 256
    case .high:     return 200
    case .medium:   return 128
    case .low:      return 64
    case .lowest:   return 32
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
