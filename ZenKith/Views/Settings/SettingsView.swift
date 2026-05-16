import SwiftUI
import Security

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gear") }
            TranslationSettingsView()
                .tabItem { Label("翻译", systemImage: "translate") }
            AISettingsView()
                .tabItem { Label("AI", systemImage: "brain") }
            EditorSettingsView()
                .tabItem { Label("编辑器", systemImage: "pencil") }
        }
        .frame(width: 480, height: 360)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("启动时打开上次文件", isOn: $settings.openLastFileOnLaunch)
            Toggle("自动保存", isOn: $settings.autoSave)
            Picker("主题", selection: $settings.theme) {
                Text("跟随系统").tag(AppTheme.system)
                Text("浅色").tag(AppTheme.light)
                Text("深色").tag(AppTheme.dark)
            }
        }
        .padding()
    }
}

// MARK: - Translation

struct TranslationSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var secretKeyInput: String = ""

    var body: some View {
        Form {
            Section("翻译引擎") {
                Picker("引擎", selection: $settings.translationEngine) {
                    ForEach(TranslationEngine.allCases, id: \.self) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.radioGroup)

                if settings.translationEngine == .apple {
                    Text("使用系统内置翻译，隐私安全，支持离线")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if settings.translationEngine == .tencent {
                Section("腾讯云 API 密钥") {
                    TextField("SecretId", text: $settings.tencentSecretId)
                        .textContentType(.username)

                    SecureField("SecretKey", text: $secretKeyInput)
                        .onChange(of: secretKeyInput) { _, newValue in settings.tencentSecretKey = newValue }
                        .onAppear { secretKeyInput = settings.tencentSecretKey }
                }

                Section("语言设置") {
                    Picker("源语言", selection: $settings.tencentSourceLanguage) {
                        Text("自动检测").tag("auto")
                        Text("中文").tag("zh")
                        Text("繁体中文").tag("zh-TW")
                        Text("英语").tag("en")
                        Text("日语").tag("ja")
                        Text("韩语").tag("ko")
                        Text("法语").tag("fr")
                        Text("西班牙语").tag("es")
                        Text("意大利语").tag("it")
                        Text("德语").tag("de")
                        Text("土耳其语").tag("tr")
                        Text("俄语").tag("ru")
                        Text("葡萄牙语").tag("pt")
                        Text("越南语").tag("vi")
                        Text("印尼语").tag("id")
                        Text("泰语").tag("th")
                        Text("马来语").tag("ms")
                        Text("阿拉伯语").tag("ar")
                        Text("印地语").tag("hi")
                    }

                    Picker("目标语言", selection: $settings.tencentTargetLanguage) {
                        Text("中文").tag("zh")
                        Text("繁体中文").tag("zh-TW")
                        Text("英语").tag("en")
                        Text("日语").tag("ja")
                        Text("韩语").tag("ko")
                        Text("法语").tag("fr")
                        Text("西班牙语").tag("es")
                        Text("意大利语").tag("it")
                        Text("德语").tag("de")
                        Text("土耳其语").tag("tr")
                        Text("俄语").tag("ru")
                        Text("葡萄牙语").tag("pt")
                        Text("越南语").tag("vi")
                        Text("印尼语").tag("id")
                        Text("泰语").tag("th")
                        Text("马来语").tag("ms")
                        Text("阿拉伯语").tag("ar")
                        Text("印地语").tag("hi")
                    }
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("SecretKey 存储在系统钥匙串中，仅本应用可读取")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Link("开通机器翻译服务", destination: URL(string: "https://console.cloud.tencent.com/tmt")!)
                        .font(.caption)

                    Link("获取 API 密钥", destination: URL(string: "https://console.cloud.tencent.com/cam/capi")!)
                        .font(.caption)
                }

                Section("费用说明") {
                    Text("每月 500 万字符免费额度，超出后 ¥50 / 百万字符")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
}

// MARK: - AI

struct AISettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            SecureField("API Key", text: $settings.aiAPIKey)
            TextField("API 端点", text: $settings.aiEndpoint)
            TextField("模型名称", text: $settings.aiModel)
        }
        .padding()
    }
}

// MARK: - Editor

struct EditorSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Toggle("显示行号", isOn: $settings.showLineNumbers)
            Toggle("自动换行", isOn: $settings.wordWrap)
        }
        .padding()
    }
}
