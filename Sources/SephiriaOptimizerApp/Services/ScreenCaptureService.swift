import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case gameWindowNotFound
    case invalidWindowSize

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "화면 기록 권한이 필요합니다. 시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 기록에서 허용해 주세요."
        case .gameWindowNotFound: "실행 중인 Sephiria 창을 찾지 못했습니다. 게임을 실행하고 인벤토리를 연 뒤 다시 시도해 주세요."
        case .invalidWindowSize: "Sephiria 창의 크기를 읽지 못했습니다."
        }
    }
}

actor ScreenCaptureService {
    func captureGameWindow() async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows
            .filter({ $0.frame.width >= 640 && $0.frame.height >= 360 })
            .first(where: {
                let appName = $0.owningApplication?.applicationName.lowercased() ?? ""
                let title = $0.title?.lowercased() ?? ""
                return appName.contains("sephiria") || title.contains("sephiria") || appName.contains("세피리아")
            }) else {
            throw ScreenCaptureError.gameWindowNotFound
        }

        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        let width = Int(window.frame.width * scale)
        let height = Int(window.frame.height * scale)
        guard width > 0, height > 0 else { throw ScreenCaptureError.invalidWindowSize }

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
