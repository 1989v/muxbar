import Foundation
import Core

public enum BuiltInTemplates {
    public static let all: [Template] = [dev, webDev, monitoring, ssh, docker]

    public static let dev = Template(
        name: "Dev",
        description: "에디터 + 빌드 + 로그",
        sessionNameHint: "dev",
        windows: [
            TemplateWindow(name: "edit"),
            TemplateWindow(name: "run"),
            TemplateWindow(name: "logs")
        ]
    )

    public static let webDev = Template(
        name: "WebDev",
        description: "Next/Vite dev server + 로그",
        sessionNameHint: "web",
        windows: [
            TemplateWindow(name: "edit"),
            TemplateWindow(name: "dev-server", command: "npm run dev"),
            TemplateWindow(name: "logs")
        ]
    )

    public static let monitoring = Template(
        name: "Monitoring",
        description: "htop + tail",
        sessionNameHint: "mon",
        windows: [
            TemplateWindow(name: "htop", command: "htop"),
            TemplateWindow(name: "syslog", command: "tail -f /var/log/system.log")
        ]
    )

    public static let ssh = Template(
        name: "SSH",
        description: "원격 접속 기본",
        sessionNameHint: "ssh",
        windows: [TemplateWindow(name: "remote")]
    )

    public static let docker = Template(
        name: "Docker",
        description: "docker ps + compose logs",
        sessionNameHint: "docker",
        windows: [
            TemplateWindow(name: "ps", command: "watch -n 2 docker ps"),
            TemplateWindow(name: "logs", command: "docker compose logs -f")
        ]
    )
}
