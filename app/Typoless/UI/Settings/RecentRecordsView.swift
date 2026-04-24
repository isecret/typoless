import SwiftUI

struct RecentRecordsView: View {
    let recentRecordStore: RecentRecordStore

    var body: some View {
        Group {
            if recentRecordStore.records.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无记录")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordsList: some View {
        List {
            ForEach(recentRecordStore.records) { record in
                RecordRow(record: record)
            }
        }
    }
}

// MARK: - Record Row

private struct RecordRow: View {
    let record: RecentRecord
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: record.status.iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .lineLimit(2)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(record.status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(record.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help("复制文本")
        }
        .padding(.vertical, 2)
    }

    private var iconColor: Color {
        switch record.status {
        case .success: .green
        case .fallbackSuccess: .orange
        case .failed: .red
        }
    }
}
