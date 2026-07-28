import SwiftUI

struct LinkCardWidget: View {
    let surfaceID: UUID
    let widgetID: UUID
    let service: SurfaceService

    @State private var links: [LinkCardsData.LinkCard] = []
    @State private var newTitle = ""
    @State private var newURL = ""
    @State private var showAddForm = false
    @State private var initialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.sm) {
            HStack {
                Label("Link Cards", systemImage: "link")
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textSecondary)
                Spacer()
                Button(action: { showAddForm.toggle() }) {
                    Image(systemName: showAddForm ? "xmark.circle" : "plus.circle")
                        .foregroundStyle(VFTheme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if showAddForm {
                addForm
            }

            if links.isEmpty && !showAddForm {
                Text("No links yet. Tap + to add a bookmark.")
                    .font(VFTheme.Typography.caption)
                    .foregroundStyle(VFTheme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(VFTheme.Spacing.md)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: VFTheme.Spacing.sm),
                    GridItem(.flexible(), spacing: VFTheme.Spacing.sm),
                ], spacing: VFTheme.Spacing.sm) {
                    ForEach(links) { link in
                        linkCard(link)
                    }
                }
            }
        }
        .padding(VFTheme.Spacing.md)
        .background(VFTheme.Colors.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.md)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onAppear {
            let data = service.linkCardsData(for: surfaceID, widgetID: widgetID)
            links = data.links
            initialized = true
        }
    }

    private var addForm: some View {
        VStack(spacing: VFTheme.Spacing.xs) {
            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .font(VFTheme.Typography.body)
            TextField("URL (https://...)", text: $newURL)
                .textFieldStyle(.roundedBorder)
                .font(VFTheme.Typography.body)
            HStack {
                Spacer()
                Button("Add") { addLink() }
                    .buttonStyle(.borderedProminent)
                    .tint(VFTheme.Colors.accent)
                    .controlSize(.small)
                    .disabled(newTitle.isEmpty || newURL.isEmpty)
            }
        }
        .padding(VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
    }

    private func linkCard(_ link: LinkCardsData.LinkCard) -> some View {
        VStack(alignment: .leading, spacing: VFTheme.Spacing.xxs) {
            HStack {
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(VFTheme.Colors.accent)
                Text(link.title)
                    .font(VFTheme.Typography.headline)
                    .foregroundStyle(VFTheme.Colors.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button(action: {
                    links.removeAll { $0.id == link.id }
                    saveData()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundStyle(VFTheme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text(link.urlString)
                .font(VFTheme.Typography.caption)
                .foregroundStyle(VFTheme.Colors.textTertiary)
                .lineLimit(1)
        }
        .padding(VFTheme.Spacing.sm)
        .background(VFTheme.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: VFTheme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: VFTheme.Radius.sm)
                .stroke(VFTheme.Colors.border, lineWidth: 1)
        )
        .onTapGesture {
            if let url = link.url {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func addLink() {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespaces)
        var trimmedURL = newURL.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !trimmedURL.isEmpty else { return }

        // Auto-prefix https if missing
        if !trimmedURL.hasPrefix("http://") && !trimmedURL.hasPrefix("https://") {
            trimmedURL = "https://" + trimmedURL
        }

        links.append(LinkCardsData.LinkCard(title: trimmedTitle, urlString: trimmedURL))
        newTitle = ""
        newURL = ""
        showAddForm = false
        saveData()
    }

    private func saveData() {
        guard initialized else { return }
        service.updateLinkCards(
            surfaceID: surfaceID,
            widgetID: widgetID,
            data: LinkCardsData(links: links)
        )
    }
}
