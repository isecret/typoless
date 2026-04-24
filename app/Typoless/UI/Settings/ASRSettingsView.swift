import SwiftUI

struct ASRSettingsView: View {
    let configStore: ConfigStore

    @State private var secretId: String = ""
    @State private var secretKey: String = ""
    @State private var region: TencentRegion = .guangzhou
    @State private var saveMessage: String?
    @State private var isError: Bool = false

    var body: some View {
        Form {
            Section {
                TextField("SecretId", text: $secretId)
                    .textFieldStyle(.roundedBorder)
                SecureField("SecretKey", text: $secretKey)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("腾讯云凭证")
            }

            Section {
                Picker("地域", selection: $region) {
                    ForEach(TencentRegion.allCases, id: \.self) { r in
                        Text(r.displayName).tag(r)
                    }
                }
            } header: {
                Text("服务地域")
            }

            Section {
                HStack {
                    Spacer()
                    Button("保存") {
                        save()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }

                if let message = saveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(isError ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadDraft() }
    }

    private func loadDraft() {
        secretId = configStore.tencentSecretId
        secretKey = configStore.tencentSecretKey
        region = configStore.asrConfig.region
    }

    private func save() {
        saveMessage = nil
        do {
            let config = ASRConfig(region: region)
            try configStore.saveASRConfig(config, secretId: secretId, secretKey: secretKey)
            saveMessage = "已保存"
            isError = false
        } catch {
            saveMessage = error.localizedDescription
            isError = true
        }
    }
}
