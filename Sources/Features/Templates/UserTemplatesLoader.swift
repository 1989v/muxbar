import Foundation
import Yams
import Core
import MuxLogging

public enum UserTemplatesLoader {
    /// `~/Library/Application Support/muxbar/Templates/`
    public static let directory: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("muxbar/Templates", isDirectory: true)
    }()

    /// 디렉터리가 없으면 만들고 README 템플릿 하나를 샘플로 생성.
    public static func bootstrapDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let sample = directory.appendingPathComponent("_example.yaml")
            let yaml = """
            # muxbar 사용자 템플릿 예시 — 이 파일을 복사해 본인 워크플로우에 맞게 편집하세요
            name: MyDev
            description: 개인 개발 환경 예시
            sessionNameHint: mydev
            windows:
              - name: edit
                command: nvim .
                cwd: ~
              - name: run
                command: npm run dev
              - name: logs
                command: tail -f logs/app.log
            """
            try? yaml.write(to: sample, atomically: true, encoding: .utf8)
        }
    }

    public static func load() -> [Template] {
        bootstrapDirectoryIfNeeded()
        let logger = MuxLogging.logger("Features.UserTemplates")

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else {
            return []
        }

        let yamlFiles = files.filter {
            let ext = $0.pathExtension.lowercased()
            return (ext == "yaml" || ext == "yml") && !$0.lastPathComponent.hasPrefix("_")
        }

        var loaded: [Template] = []
        for file in yamlFiles {
            do {
                let content = try String(contentsOf: file, encoding: .utf8)
                let template = try YAMLDecoder().decode(Template.self, from: content)
                loaded.append(template)
            } catch {
                logger.warning("템플릿 로드 실패 \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return loaded
    }
}
