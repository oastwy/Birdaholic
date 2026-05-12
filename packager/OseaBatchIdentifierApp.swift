import SwiftUI
import UniformTypeIdentifiers

struct ResultRow: Identifiable {
    let id = UUID()
    let file: String
    let status: String
    let stars: String
    let sharpness: String
    let exposure: String
    let top1: String
    let score1: String
    let top2: String
    let top3: String
    let error: String
}

@main
struct OseaBatchIdentifierApp: App {
    var body: some Scene {
        WindowGroup("鸟瘾 OSEA 批量识别") {
            ContentView()
                .frame(minWidth: 1100, minHeight: 680)
        }
    }
}

struct ContentView: View {
    @State private var modelPath = defaultResourcePath("models/osea/bird_model.onnx")
    @State private var infoPath = defaultResourcePath("models/osea/bird_info.json")
    @State private var pythonPath = detectPython()
    @State private var ebirdLocation = ""
    @State private var ebirdKey = UserDefaults.standard.string(forKey: "ebirdApiKey") ?? ""
    @State private var imagePaths: [String] = []
    @State private var rows: [ResultRow] = []
    @State private var status = "请选择图片或文件夹"
    @State private var topK = 5
    @State private var isRunning = false
    @State private var lastCSV = ""
    @State private var isDownloading = false

    var modelsReady: Bool {
        FileManager.default.fileExists(atPath: modelPath) &&
        FileManager.default.fileExists(atPath: infoPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("OSEA 模型") {
                VStack(alignment: .leading, spacing: 8) {
                    pathRow("Python", path: $pythonPath, choose: choosePython)
                    pathRow("模型", path: $modelPath, choose: chooseModel)
                    pathRow("标签", path: $infoPath, choose: chooseInfo)
                    HStack {
                        if modelsReady {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("模型已就绪")
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("模型文件缺失")
                                .foregroundStyle(.orange)
                            Button(isDownloading ? "下载中..." : "下载 bird_info.json") {
                                downloadInfoFile()
                            }
                            .disabled(isDownloading)
                        }
                        Spacer()
                        Button("打开模型目录") { openModelFolder() }
                        Text("依赖：python3 -m pip install onnxruntime pillow numpy")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
                .padding(4)
            }

            GroupBox("eBird 地点过滤（可选）") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("地点").frame(width: 42, alignment: .leading)
                        TextField("如 CN-53 / US-NY / L12345（留空跳过）", text: $ebirdLocation)
                            .textFieldStyle(.roundedBorder)
                        Text("API Key").frame(width: 56, alignment: .leading)
                        SecureField("eBird API Key", text: $ebirdKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .onChange(of: ebirdKey) { newVal in
                                UserDefaults.standard.set(newVal, forKey: "ebirdApiKey")
                            }
                    }
                    Text("填写后，模型输出会结合当地 eBird 名录加权，本地鸟种得分更高。API Key 申请：ebird.org/api/keygen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            HStack {
                Button("添加图片") { addImages() }
                Button("添加文件夹") { addFolder() }
                Button("清空") {
                    imagePaths.removeAll()
                    rows.removeAll()
                    status = "已清空"
                }
                Stepper("Top \(topK)", value: $topK, in: 1...20)
                    .frame(width: 120)
                Button(isRunning ? "识别中..." : "开始识别") { runBatch() }
                    .disabled(isRunning || imagePaths.isEmpty)
                Button("导出 CSV") { revealCSV() }
                    .disabled(lastCSV.isEmpty)
                Spacer()
                Text("\(imagePaths.count) 张")
                    .foregroundStyle(.secondary)
            }

            Table(rows) {
                TableColumn("文件") { row in Text(row.file).lineLimit(1) }
                    .width(min: 280, ideal: 360)
                TableColumn("状态", value: \.status)
                    .width(70)
                TableColumn("星级", value: \.stars)
                    .width(62)
                TableColumn("清晰", value: \.sharpness)
                    .width(70)
                TableColumn("曝光", value: \.exposure)
                    .width(70)
                TableColumn("Top 1", value: \.top1)
                    .width(min: 200, ideal: 250)
                TableColumn("分数", value: \.score1)
                    .width(70)
                TableColumn("Top 2", value: \.top2)
                    .width(min: 180, ideal: 220)
                TableColumn("Top 3", value: \.top3)
                    .width(min: 180, ideal: 220)
                TableColumn("错误", value: \.error)
                    .width(min: 180, ideal: 240)
            }

            Text(status)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    func pathRow(_ label: String, path: Binding<String>, choose: @escaping () -> Void) -> some View {
        HStack {
            Text(label).frame(width: 42, alignment: .leading)
            TextField("", text: path)
                .textFieldStyle(.roundedBorder)
            Button("选择", action: choose)
        }
    }

    func choosePython() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pythonPath = url.path
        }
    }

    func chooseModel() {
        if let url = chooseFile(allowed: ["onnx"]) {
            modelPath = url.path
        }
    }

    func chooseInfo() {
        if let url = chooseFile(allowed: ["json"]) {
            infoPath = url.path
        }
    }

    func addImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK {
            appendImages(panel.urls.map(\.path))
        }
    }

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK {
            appendImages(panel.urls.map(\.path))
        }
    }

    func appendImages(_ paths: [String]) {
        let existing = Set(imagePaths)
        for path in paths where !existing.contains(path) {
            imagePaths.append(path)
        }
        rows = imagePaths.map {
            ResultRow(file: $0, status: "pending", stars: "", sharpness: "", exposure: "", top1: "", score1: "", top2: "", top3: "", error: "")
        }
        status = "已载入 \(imagePaths.count) 个图片/文件夹输入"
    }

    func runBatch() {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: modelPath),
              FileManager.default.fileExists(atPath: infoPath) else {
            status = "缺少 bird_model.onnx 或 bird_info.json"
            return
        }
        let script = bundledScript()
        guard FileManager.default.fileExists(atPath: script) else {
            status = "找不到识别脚本：\(script)"
            return
        }

        isRunning = true
        status = "正在识别..."
        rows = imagePaths.map {
            ResultRow(file: $0, status: "running", stars: "", sharpness: "", exposure: "", top1: "", score1: "", top2: "", top3: "", error: "")
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("osea_predictions_\(Int(Date().timeIntervalSince1970)).csv")
            .path

        let resolvedPython = pythonPath
        let resolvedLocation = ebirdLocation.trimmingCharacters(in: .whitespaces)
        let resolvedKey = ebirdKey.trimmingCharacters(in: .whitespaces)
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: resolvedPython)
            var args = [
                script,
                "--model", modelPath,
                "--info", infoPath,
                "--output", output,
                "--top-k", "\(topK)",
            ]
            if !resolvedLocation.isEmpty && !resolvedKey.isEmpty {
                args += ["--location", resolvedLocation, "--ebird-key", resolvedKey]
            }
            args += ["--input"]
            args += imagePaths
            process.arguments = args

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let log = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    isRunning = false
                    if process.terminationStatus == 0 {
                        lastCSV = output
                        rows = parseCSV(output)
                        status = "识别完成：\(rows.filter { $0.status == "ok" }.count)/\(rows.count) 成功"
                    } else {
                        status = log.isEmpty ? "识别失败" : log
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isRunning = false
                    status = "启动 Python 失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func revealCSV() {
        guard !lastCSV.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastCSV)])
    }

    func openModelFolder() {
        let folder = URL(fileURLWithPath: defaultResourcePath("models/osea"))
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.open(folder)
        } else {
            NSWorkspace.shared.open(folder.deletingLastPathComponent())
        }
    }

    func downloadInfoFile() {
        let destDir = URL(fileURLWithPath: infoPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let destURL = URL(fileURLWithPath: infoPath)
        let srcURL = URL(string: "https://huggingface.co/sunjiao/osea/resolve/main/bird_info.json")!
        isDownloading = true
        status = "正在下载 bird_info.json..."
        URLSession.shared.downloadTask(with: srcURL) { tmp, _, err in
            DispatchQueue.main.async {
                isDownloading = false
                if let err = err {
                    status = "下载失败：\(err.localizedDescription)"
                    return
                }
                guard let tmp = tmp else {
                    status = "下载失败：无临时文件"
                    return
                }
                do {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tmp, to: destURL)
                    status = "bird_info.json 已下载"
                } catch {
                    status = "保存失败：\(error.localizedDescription)"
                }
            }
        }.resume()
    }
}

func detectPython() -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let candidates = [
        "\(home)/anaconda3/bin/python3",
        "\(home)/miniconda3/bin/python3",
        "\(home)/opt/anaconda3/bin/python3",
        "\(home)/opt/miniconda3/bin/python3",
        "/opt/anaconda3/bin/python3",
        "/opt/miniconda3/bin/python3",
        "/usr/local/anaconda3/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]
    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    return "/usr/bin/python3"
}

func chooseFile(allowed: [String]) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedFileTypes = allowed
    return panel.runModal() == .OK ? panel.url : nil
}

func bundledScript() -> String {
    if let resource = Bundle.main.resourcePath {
        let path = URL(fileURLWithPath: resource)
            .appendingPathComponent("packager/osea_batch_identifier.py")
            .path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return FileManager.default.currentDirectoryPath + "/packager/osea_batch_identifier.py"
}

func defaultResourcePath(_ relative: String) -> String {
    if let resource = Bundle.main.resourcePath {
        return URL(fileURLWithPath: resource).appendingPathComponent(relative).path
    }
    return FileManager.default.currentDirectoryPath + "/" + relative
}

func parseCSV(_ path: String) -> [ResultRow] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    let lines = text.split(whereSeparator: \.isNewline).map(String.init)
    guard lines.count > 1 else { return [] }
    let header = splitCSV(lines[0])
    func value(_ row: [String], _ name: String) -> String {
        guard let idx = header.firstIndex(of: name), idx < row.count else { return "" }
        return row[idx]
    }
    return lines.dropFirst().map { line in
        let row = splitCSV(line)
        let top1 = [value(row, "rank1_zh"), value(row, "rank1_en"), value(row, "rank1_sci")]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let top2 = [value(row, "rank2_zh"), value(row, "rank2_en"), value(row, "rank2_sci")]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let top3 = [value(row, "rank3_zh"), value(row, "rank3_en"), value(row, "rank3_sci")]
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        return ResultRow(
            file: value(row, "file"),
            status: value(row, "status"),
            stars: String(repeating: "★", count: Int(value(row, "stars")) ?? 0),
            sharpness: value(row, "sharpness"),
            exposure: value(row, "exposure"),
            top1: top1,
            score1: value(row, "rank1_score"),
            top2: top2,
            top3: top3,
            error: value(row, "error")
        )
    }
}

func splitCSV(_ line: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quoted = false
    var iterator = line.makeIterator()
    while let char = iterator.next() {
        if char == "\"" {
            if quoted, let next = iterator.next() {
                if next == "\"" {
                    current.append("\"")
                } else {
                    quoted = false
                    if next == "," {
                        result.append(current)
                        current = ""
                    } else {
                        current.append(next)
                    }
                }
            } else {
                quoted.toggle()
            }
        } else if char == ",", !quoted {
            result.append(current)
            current = ""
        } else {
            current.append(char)
        }
    }
    result.append(current)
    return result
}
