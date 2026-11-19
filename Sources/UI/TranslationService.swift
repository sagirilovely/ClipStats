import AppKit
import SwiftUI
import Translation

// MARK: - 方向

/// 英汉互译的方向。这一层不依赖系统框架，方便在 macOS 15 以下也能用。
enum TranslationDirection {
    case enToZh
    case zhToEn

    var title: String {
        self == .enToZh ? "英 → 中" : "中 → 英"
    }

    var sourceIdentifier: String {
        self == .enToZh ? "en" : "zh-Hans"
    }

    var targetIdentifier: String {
        self == .enToZh ? "zh-Hans" : "en"
    }

    /// 只要出现中日韩表意文字（含假名）就按中→英，其余一律英→中。
    /// 变量名场景下输入的多半是英文单词，默认方向要稳。
    static func detect(_ text: String) -> TranslationDirection {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF,          // 假名
                 0x3400...0x4DBF,          // 扩展 A
                 0x4E00...0x9FFF,          // 基本汉字
                 0xF900...0xFAFF:          // 兼容汉字
                return .zhToEn
            default:
                continue
            }
        }
        return .enToZh
    }
}

/// 翻译结果：成功给出译文，失败给出可直接展示的说明
enum TranslationOutcome {
    case success(String)
    case failure(String)
}

// MARK: - 引擎

/// 用系统「翻译」框架做英汉互译：离线、不需要 API key、不联网到第三方。
///
/// 原理（按系统文档自行实现，未复制任何第三方代码）：
/// 1. TranslationSession.Configuration 描述语言对；
/// 2. SwiftUI 的 .translationTask(configuration) 在配置变化 / invalidate 时回调一个 TranslationSession；
/// 3. 在 session 上先 prepareTranslation()（语言包没下载时由系统弹窗下载），再 translate(text)。
/// 因此宿主视图必须真实存在于一个窗口里，这里把它塞进翻译面板的背景层。
final class TranslationService: ObservableObject {
    @Published private(set) var isBusy = false
    @Published private(set) var errorText: String?
    @Published private(set) var lastDirection: TranslationDirection?
    /// 系统还没下载英汉语言包时为 true
    @Published private(set) var needsLanguagePack = false

    /// 成功回调（主线程），参数为目标语言文本
    var onResult: ((String) -> Void)?
    /// 失败回调（主线程），参数为可直接展示的说明
    var onError: ((String) -> Void)?

    private var backend: AnyObject?

    var isSupported: Bool {
        if #available(macOS 15.0, *) { return backend != nil }
        return false
    }

    init() {
        if #available(macOS 15.0, *) {
            let backend = AppleTranslationBackend()
            backend.onResult = { [weak self] outcome in
                guard let self else { return }
                self.isBusy = false
                switch outcome {
                case .success(let text):
                    self.errorText = nil
                    self.onResult?(text)
                case .failure(let message):
                    self.errorText = message
                    self.onError?(message)
                }
            }
            self.backend = backend
        }
        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
            NSLog("%@", "DIAG translation service init supported=\(isSupported)")
        }
    }

    @available(macOS 15.0, *)
    var appleBackend: AppleTranslationBackend? {
        backend as? AppleTranslationBackend
    }

    /// 检查系统语言包是否就绪（不触发下载，很快返回）
    func refreshAvailability() {
        guard #available(macOS 15.0, *) else { return }
        Task { [weak self] in
            guard let self else { return }
            let availability = LanguageAvailability()
            let source = Locale.Language(identifier: TranslationDirection.enToZh.sourceIdentifier)
            let target = Locale.Language(identifier: TranslationDirection.enToZh.targetIdentifier)
            let status = await availability.status(from: source, to: target)
            await MainActor.run {
                self.needsLanguagePack = (status != .installed)
            }
        }
    }

    private var watchdog: Int = 0

    func translate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isBusy = false
            errorText = nil
            return
        }
        let direction = TranslationDirection.detect(trimmed)
        lastDirection = direction

        if #available(macOS 15.0, *), let backend = appleBackend {
            isBusy = true
            errorText = nil
            backend.request(text: trimmed,
                            source: direction.sourceIdentifier,
                            target: direction.targetIdentifier)
            // 看门狗：系统翻译在语言包缺失时可能一直不回调，不能让它永远转圈
            watchdog &+= 1
            let token = watchdog
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, self.isBusy, token == self.watchdog else { return }
                self.isBusy = false
                let message = "系统翻译超时：语言包可能还没下载（系统设置 › 通用 › 语言与地区 → 翻译语言）"
                self.errorText = message
                self.needsLanguagePack = true
                self.onError?(message)
            }
        } else {
            isBusy = false
            let message = "系统翻译需要 macOS 15 及以上版本"
            errorText = message
            onError?(message)
        }
    }
}

// MARK: - 系统框架后端（macOS 15+）

@available(macOS 15.0, *)
final class AppleTranslationBackend: ObservableObject {
    /// 语言对配置；每次请求都 invalidate 让 translationTask 重新执行
    @Published var configuration: TranslationSession.Configuration?

    /// 主线程回调：成功给出译文，失败给出可展示的说明
    var onResult: ((TranslationOutcome) -> Void)?

    private var pending: (text: String, source: Locale.Language, target: Locale.Language)?
    private var generation = 0

    func request(text: String, source: String, target: String) {
        generation &+= 1
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        pending = (text, sourceLanguage, targetLanguage)

        if configuration == nil {
            configuration = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
        } else {
            configuration?.source = sourceLanguage
            configuration?.target = targetLanguage
            configuration?.invalidate()
        }
    }

    func run(_ session: TranslationSession) async {
        guard let request = pending else { return }
        let generation = self.generation
        if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
            NSLog("%@", "DIAG translation task start text=\(request.text)")
        }
        do {
            // 语言包未安装时，这一步会触发系统的下载流程
            try await session.prepareTranslation()
            if ProcessInfo.processInfo.environment["CLIPSTATS_DIAG"] == "1" {
                NSLog("%@", "DIAG translation prepared")
            }
            let response = try await session.translate(request.text)
            guard generation == self.generation else { return }
            await MainActor.run { self.onResult?(.success(response.targetText)) }
        } catch {
            guard generation == self.generation else { return }
            let description = Self.describe(error)
            await MainActor.run { self.onResult?(.failure(description)) }
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain.localizedCaseInsensitiveContains("translation") {
            return "系统翻译失败：\(nsError.localizedDescription)"
        }
        return "翻译失败：\(nsError.localizedDescription)"
    }
}

// MARK: - translationTask 宿主

/// 放在翻译面板背景里的 1×1 宿主视图，负责把 SwiftUI 的 translationTask 挂进窗口。
struct TranslationTaskHost: View {
    @ObservedObject var service: TranslationService

    var body: some View {
        Group {
            if #available(macOS 15.0, *), let backend = service.appleBackend {
                AppleTranslationTaskView(backend: backend)
            } else {
                Color.clear
            }
        }
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
}

@available(macOS 15.0, *)
private struct AppleTranslationTaskView: View {
    @ObservedObject var backend: AppleTranslationBackend

    var body: some View {
        Color.clear
            .translationTask(backend.configuration) { session in
                await backend.run(session)
            }
    }
}
