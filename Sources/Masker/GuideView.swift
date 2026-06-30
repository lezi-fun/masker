import SwiftUI

struct GuideView: View {
    @EnvironmentObject var appState: AppState
    @State private var promptCopied = false
    @State private var exampleCopied = false

    private let promptText = """
请严格按照以下规则处理我发给你的文本：

1. 文本中的 🔒XXXXXXXX.类型🔒 是脱敏占位符（如 🔒A1B2C3D4.姓名🔒），
   表示此处原本是敏感信息，已被替换为 UUID。
2. **不得修改、删除或动任何占位符**，包括 🔒 符号和 UUID。
3. 输出结果中必须完整保留所有占位符的原样。
4. 占位符后的 ".类型" 提示了原始信息的类别（如 .姓名 / .手机 / .邮箱），
   供你理解上下文，但不要用它来猜测原始值。
"""

    private let exampleSanitized = """
【项目汇报】
项目经理：🔒A1B2.姓名🔒 于 🔒C3D4.日期🔒 提交了技术方案，
联系电话：🔒E5F6.手机🔒，如有问题请联系产品负责人 🔒G7H8.姓名🔒。
合作方邮箱：🔒I9J0.邮箱🔒
"""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // ── Title ──
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "book.fill")
                            .font(.title2)
                        Text("Masker 使用指南")
                            .font(.title2).bold()
                    }
                    Text("三步完成「文本脱敏 → 交给AI → 还原敏感信息」")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Divider()

                // ── Step 1 ──
                StepCard(number: "1", icon: "lock.shield", title: "脱敏", color: .blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在「脱敏」标签页：")
                            .font(.headline)
                        BulletText("粘贴文本或拖入文件")
                        BulletText("点击「执行脱敏」")
                        BulletText("敏感信息 → 🔒UUID.类型🔒 占位符")
                        BulletText("导出映射 JSON（还原时需要）")

                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                            Text("脱敏结果示例:")
                                .font(.caption).bold()
                        }
                        .padding(.top, 4)

                        Text(exampleSanitized)
                            .font(.caption.monospaced())
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)

                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.orange)
                            Text("✓ 带类型标签（.姓名 / .手机 / .邮箱），AI 能理解上下文")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // ── Step 2 ──
                StepCard(number: "2", icon: "brain.head.profile", title: "发给AI处理", color: .purple) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("把脱敏后的文本 + 下方提示词一起发给 ChatGPT / Claude / DeepSeek：")
                            .font(.headline)

                        // Prompt box
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "quote.bubble.fill")
                                    .foregroundColor(.purple)
                                Text("提示词（直接复制）")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(promptText, forType: .string)
                                    promptCopied = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        promptCopied = false
                                    }
                                }) {
                                    Label(promptCopied ? "✅ 已复制" : "📋 复制", systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(promptText)
                                .font(.caption.monospaced())
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.05))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                                )
                        }

                        // Example usage
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundColor(.yellow)
                                Text("使用方式示例")
                                    .font(.subheadline.bold())
                            }

                            Text("发给 AI 的消息 = 提示词 + 脱敏后文本")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("""
                            [提示词]
                            🔒A1B2.姓名🔒 于 🔒C3D4.日期🔒 提交了技术方案...
                            """)
                            .font(.caption.monospaced())
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)

                            HStack {
                                Image(systemName: "checkmark.shield.fill")
                                    .foregroundColor(.green)
                                Text("AI 输出中所有占位符会原样保留，方便后续还原")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // ── Step 3 ──
                StepCard(number: "3", icon: "lock.shield.fill", title: "还原", color: .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("在「还原」标签页：")
                            .font(.headline)
                        BulletText("粘贴 AI 返回的文本（含 🔒UUID.类型🔒）")
                        BulletText("导入之前保存的映射 JSON")
                        BulletText("点击「执行还原」")
                        BulletText("所有占位符恢复为原始敏感信息 🎉")

                        HStack {
                            Image(systemName: "arrow.right.square.fill")
                                .foregroundColor(.green)
                            Text("或者也可以直接拖入映射 JSON 文件到输入框")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    }

                    // ── AI 模型下载 ──
                    #if !NO_AI
                    VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .font(.title3)
                            .foregroundColor(.purple)
                        Text("AI 模型管理")
                            .font(.title3).bold()
                    }

                    if appState.modelDownloader.isDownloaded {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("AI 模型已就绪（\(appState.aiDetector.isAvailable ? "可用" : "加载中")）")
                        }
                        .font(.subheadline)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("启用 AI 增强检测需要下载 Privacy Filter 模型（~2.6GB）")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            if appState.modelDownloader.isDownloading {
                                ProgressView(value: appState.modelDownloader.progress)
                                    .progressViewStyle(.linear)
                                    .frame(maxWidth: 300)
                                Text(appState.modelDownloader.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Button(action: { Task { await appState.modelDownloader.download() } }) {
                                    Label("下载 AI 模型 (2.6GB)", systemImage: "icloud.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                            }
                        }
                    }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.03))
                    .cornerRadius(10)
                    #endif

                    // ── Tips ──
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                        Text("小贴士")
                            .font(.headline)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("映射 JSON 是还原的关键，脱敏后一定记得导出保存", systemImage: "1.circle.fill")
                        Label("同一个映射文件可反复使用（支持追加新映射）", systemImage: "2.circle.fill")
                        Label("开启「AI 增强检测」可额外识别地址、密码、密钥等", systemImage: "3.circle.fill")
                        Label("脱敏后文本中的 .类型 标签只供 AI 理解上下文，不会泄露原文", systemImage: "4.circle.fill")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.06))
                .cornerRadius(10)

                Spacer(minLength: 40)
            }
            .padding()
        }
    }
}

// ── Helper Views ──

struct StepCard<Content: View>: View {
    let number: String
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Text(number)
                        .font(.headline.bold())
                        .foregroundColor(color)
                }
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.title3).bold()
            }
            content
                .padding(.leading, 44)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.03))
        .cornerRadius(10)
    }
}

struct BulletText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}
