#if os(macOS)
import AppKit
import SwiftUI

enum MenuBarShelfLayout {
    case compact
    case management
}

struct MenuBarShelfView: View {
    let layout: MenuBarShelfLayout
    var onOpenSettings: (() -> Void)?
    private let showsHeader: Bool
    private let showsPermissionNotice: Bool

    @ObservedObject private var store: MenuBarShelfStore
    @ObservedObject private var permissions = MenuBarShelfPermissions.shared
    @ObservedObject private var thumbnails = MenuBarShelfThumbnailCache.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    init(
        layout: MenuBarShelfLayout = .management,
        showsHeader: Bool = true,
        showsPermissionNotice: Bool = true,
        store: MenuBarShelfStore? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.layout = layout
        self.showsHeader = showsHeader
        self.showsPermissionNotice = showsPermissionNotice
        _store = ObservedObject(wrappedValue: store ?? .shared)
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: layout == .compact ? 10 : 12) {
            if showsHeader {
                header
            }
            if showsPermissionNotice {
                permissionNotice
            }
            searchField
            if layout == .management {
                discoveryHint
            }

            if layout == .compact {
                compactShelf
            } else {
                managementShelf
            }

            operationNotice
        }
        .padding(layout == .compact ? 14 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if layout == .compact {
                ZStack {
                    VisualEffectBlur(
                        material: colorScheme == .dark ? .hudWindow : .menu,
                        blendingMode: .behindWindow
                    )
                    AppTheme.canvas(colorScheme)
                }
            }
        }
        .onAppear {
            store.start()
            if layout == .compact {
                store.setShelfPresented(true)
            }
            refreshThumbnails()
        }
        .onDisappear {
            if layout == .compact {
                store.setShelfPresented(false)
            }
        }
        .task { await permissions.monitorWhileVisible() }
        .onChange(of: store.items) { _, _ in refreshThumbnails() }
        .onChange(of: permissions.hasScreenCapture) { _, _ in refreshThumbnails() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(AppTheme.accent.opacity(colorScheme == .dark ? 0.2 : 0.12))
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(copy(en: "Menu Bar Shelf", zh: "菜单栏抽屉", ja: "メニューバーシェルフ", ko: "메뉴 막대 보관함"))
                    .font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if case .limited = store.discoveryMode {
                statusPill(
                    text: copy(en: "Limited", zh: "受限", ja: "制限中", ko: "제한됨"),
                    color: AppTheme.warning
                )
            }

            Toggle("", isOn: $store.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(copy(en: "Enable menu bar visibility management", zh: "启用菜单栏显示管理", ja: "メニューバー表示管理を有効化", ko: "메뉴 막대 표시 관리 켜기"))

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .background(AppTheme.chromeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(copy(en: "Refresh menu bar items", zh: "刷新菜单栏图标", ja: "メニューバー項目を更新", ko: "메뉴 막대 항목 새로 고침"))

            settingsControl
        }
    }

    private var settingsControl: some View {
        SettingsLink {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .simultaneousGesture(TapGesture().onEnded { onOpenSettings?() })
        .buttonStyle(.plain)
        .background(AppTheme.chromeSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(copy(en: "Open settings", zh: "打开设置", ja: "設定を開く", ko: "설정 열기"))
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField(
                copy(en: "Search apps or menu bar items", zh: "搜索软件或菜单栏图标", ja: "アプリまたは項目を検索", ko: "앱 또는 메뉴 막대 항목 검색"),
                text: $store.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy(en: "Clear search", zh: "清除搜索", ja: "検索を消去", ko: "검색 지우기"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }

    private var discoveryHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 1)
            Text(copy(
                en: "Menu bar items can be pinned or stored. Other running apps appear separately and open their application when selected.",
                zh: "有菜单栏图标的软件可以常驻或收纳；其他后台软件单独列出，点击可切回应用。",
                ja: "メニューバー項目は固定または収納できます。その他の実行中アプリは別に表示され、選択するとアプリへ戻ります。",
                ko: "메뉴 막대 항목은 고정하거나 보관할 수 있습니다. 다른 실행 중 앱은 별도로 표시되며 선택하면 앱으로 전환됩니다."
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var permissionNotice: some View {
        if !permissions.hasAccessibility {
            permissionRow(
                symbol: "hand.raised.fill",
                title: accessibilityPermissionNotice,
                actionTitle: copy(en: "Allow", zh: "去授权", ja: "許可", ko: "허용"),
                action: permissions.requestAccessibility,
                secondaryAction: permissions.refresh
            )
        } else if !permissions.hasScreenCapture && layout == .compact {
            permissionRow(
                symbol: "photo.badge.exclamationmark",
                title: copy(en: "Using app icons. Screen recording adds live item previews.", zh: "当前使用应用图标；录屏权限可提供实时预览。", ja: "アプリアイコンを使用中。画面収録でプレビューを表示できます。", ko: "앱 아이콘 사용 중. 화면 기록 권한으로 미리보기를 표시할 수 있습니다."),
                actionTitle: copy(en: "Optional", zh: "可选授权", ja: "任意", ko: "선택 사항"),
                action: permissions.requestScreenCapture
            )
        }
    }

    private func permissionRow(
        symbol: String,
        title: String,
        actionTitle: String,
        action: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.warning)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let secondaryAction {
                Button(action: secondaryAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help(copy(en: "Check permission again", zh: "重新检测权限", ja: "権限を再確認", ko: "권한 다시 확인"))
                .accessibilityLabel(copy(en: "Check permission again", zh: "重新检测权限", ja: "権限を再確認", ko: "권한 다시 확인"))
            }
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var accessibilityPermissionNotice: String {
        if permissions.applicationIdentity.usesAdHocSignature {
            return copy(
                en: "This build may not match an older CoolRun permission entry. Re-add the current app in Accessibility.",
                zh: "当前构建可能与旧 CoolRun 授权不匹配，请在辅助功能中重新添加当前版本。",
                ja: "このビルドは以前のCoolRun権限と一致しない可能性があります。現在のアプリを再追加してください。",
                ko: "현재 빌드가 이전 CoolRun 권한과 일치하지 않을 수 있습니다. 현재 앱을 다시 추가하세요."
            )
        }
        return copy(
            en: "Accessibility permission is required to move and open items.",
            zh: "需要辅助功能权限才能移动和打开图标。",
            ja: "項目の移動と操作にはアクセシビリティ権限が必要です。",
            ko: "항목 이동 및 열기에는 손쉬운 사용 권한이 필요합니다."
        )
    }

    private var compactShelf: some View {
        let items = store.filteredItems(includeAlwaysHidden: false)
        let applications = store.filteredBackgroundApplications()
        return Group {
            if items.isEmpty && applications.isEmpty {
                emptyState(searching: !store.searchText.isEmpty)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        if !items.isEmpty {
                            ShelfTrackMarker(
                                symbol: "rectangle.bottomhalf.inset.filled",
                                label: copy(en: "Shelf", zh: "收纳", ja: "シェルフ", ko: "보관함")
                            )
                            ForEach(items) { item in
                                MenuBarShelfItemButton(
                                    item: item,
                                    store: store,
                                    image: thumbnails.image(for: item),
                                    compact: true
                                )
                            }
                        }
                        if !applications.isEmpty {
                            ShelfTrackMarker(
                                symbol: "app.badge",
                                label: copy(en: "Running", zh: "后台", ja: "実行中", ko: "실행 중")
                            )
                            ForEach(applications) { application in
                                MenuBarBackgroundApplicationButton(
                                    application: application,
                                    store: store,
                                    image: thumbnails.image(for: application)
                                )
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 82, maxHeight: 92)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(AppTheme.surface(colorScheme))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
                }
            }
        }
    }

    private var managementShelf: some View {
        Group {
            if !store.searchText.isEmpty {
                let matches = store.filteredItems(includeAlwaysHidden: true)
                let applicationMatches = store.filteredBackgroundApplications()
                if matches.isEmpty && applicationMatches.isEmpty {
                    emptyState(searching: true)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !matches.isEmpty {
                                searchResultSection(matches)
                            }
                            if !applicationMatches.isEmpty {
                                backgroundApplicationSection(applicationMatches)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            } else if store.items.isEmpty && store.backgroundApplications.isEmpty {
                emptyState(searching: false)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !store.items.isEmpty {
                            ForEach(MenuBarShelfGroup.allCases) { group in
                                managementSection(group)
                            }
                        }
                        if !store.backgroundApplications.isEmpty {
                            backgroundApplicationSection(store.backgroundApplications)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private func searchResultSection(_ items: [MenuBarItemSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                symbol: "menubar.rectangle",
                title: copy(en: "Menu bar items", zh: "菜单栏图标", ja: "メニューバー項目", ko: "메뉴 막대 항목"),
                count: items.count,
                color: AppTheme.accent
            )
            LazyVStack(spacing: 5) {
                ForEach(items) { item in
                    MenuBarShelfItemRow(item: item, store: store, image: thumbnails.image(for: item))
                }
            }
        }
    }

    private func backgroundApplicationSection(_ applications: [MenuBarBackgroundApplicationSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                symbol: "app.badge",
                title: copy(en: "Running without a menu bar item", zh: "仅后台运行", ja: "メニューバー項目なしで実行中", ko: "메뉴 막대 항목 없이 실행 중"),
                count: applications.count,
                color: AppTheme.warning
            )
            LazyVStack(spacing: 5) {
                ForEach(applications) { application in
                    MenuBarBackgroundApplicationRow(
                        application: application,
                        store: store,
                        image: thumbnails.image(for: application)
                    )
                }
            }
        }
    }

    private func sectionHeader(symbol: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func managementSection(_ group: MenuBarShelfGroup) -> some View {
        let items = store.items(in: group)
        return VStack(alignment: .leading, spacing: 7) {
            sectionHeader(
                symbol: group.symbolName,
                title: group.displayName(lang: settings.language),
                count: items.count,
                color: groupColor(group)
            )

            if items.isEmpty {
                Text(groupEmptyText(group))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                LazyVStack(spacing: 5) {
                    ForEach(items) { item in
                        MenuBarShelfItemRow(item: item, store: store, image: thumbnails.image(for: item))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var operationNotice: some View {
        switch store.operationState {
        case .failed(let message):
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                Text(message)
                    .font(.caption2)
                    .lineLimit(2)
                Spacer()
                Button {
                    store.setOperationState(.idle)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copy(en: "Dismiss", zh: "关闭", ja: "閉じる", ko: "닫기"))
            }
            .padding(8)
            .background(AppTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        case .moving, .activating, .refreshing:
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(operationText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .idle:
            EmptyView()
        }
    }

    private func emptyState(searching: Bool) -> some View {
        return VStack(spacing: 7) {
            Image(systemName: searching ? "magnifyingglass" : "menubar.arrow.up.rectangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching
                 ? copy(en: "No matching apps or menu bar items", zh: "没有匹配的软件或菜单栏图标", ja: "一致するアプリまたは項目がありません", ko: "일치하는 앱 또는 메뉴 막대 항목이 없습니다")
                 : copy(en: "No third-party applications found", zh: "没有发现第三方软件", ja: "他社製アプリが見つかりません", ko: "서드파티 앱을 찾지 못했습니다"))
                .font(.system(size: 12, weight: .medium))
            if !searching {
                Text(copy(
                    en: "Launch an application, then refresh. Apps without a native menu bar item will appear as running applications.",
                    zh: "请先启动软件再刷新；没有原生菜单栏图标的软件会显示为“仅后台运行”。",
                    ja: "アプリを起動して更新してください。項目のないアプリは実行中アプリとして表示されます。",
                    ko: "앱을 실행한 다음 새로 고치세요. 메뉴 막대 항목이 없는 앱은 실행 중 앱으로 표시됩니다."
                ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: layout == .compact ? 78 : 150)
        .padding(.horizontal, 16)
        .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerSubtitle: String {
        let applicationCount = managedApplicationCount + store.backgroundApplications.count
        guard store.isEnabled else {
            return copy(
                en: "Off · \(applicationCount) apps discovered",
                zh: "已关闭 · \(applicationCount) 个软件",
                ja: "オフ · \(applicationCount)アプリ",
                ko: "꺼짐 · \(applicationCount)개 앱"
            )
        }
        let count = store.items(in: .hidden).count + store.items(in: .alwaysHidden).count
        return copy(
            en: "\(applicationCount) apps · \(count) hidden · Option-click",
            zh: "\(applicationCount) 个软件 · 已收纳 \(count) 个 · Option 点击",
            ja: "\(applicationCount)アプリ · \(count)項目を非表示 · Optionクリック",
            ko: "\(applicationCount)개 앱 · \(count)개 숨김 · Option-클릭"
        )
    }

    private var managedApplicationCount: Int {
        Set(store.items.map {
            $0.ownerBundleIdentifier ?? $0.ownerName.lowercased()
        }).count
    }

    private var operationText: String {
        switch store.operationState {
        case .refreshing:
            copy(en: "Refreshing items…", zh: "正在刷新图标…", ja: "項目を更新中…", ko: "항목 새로 고치는 중…")
        case .moving:
            copy(en: "Moving item…", zh: "正在移动图标…", ja: "項目を移動中…", ko: "항목 이동 중…")
        case .activating:
            copy(en: "Opening original item…", zh: "正在打开原始菜单…", ja: "元の項目を開いています…", ko: "원본 항목 여는 중…")
        default: ""
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.11), in: Capsule())
    }

    private func groupColor(_ group: MenuBarShelfGroup) -> Color {
        switch group {
        case .pinned: AppTheme.healthy
        case .hidden: AppTheme.accent
        case .alwaysHidden: .secondary
        }
    }

    private func groupEmptyText(_ group: MenuBarShelfGroup) -> String {
        switch group {
        case .pinned:
            copy(en: "No pinned items", zh: "没有常驻图标", ja: "常時表示の項目はありません", ko: "항상 표시할 항목 없음")
        case .hidden:
            copy(en: "No shelf items", zh: "没有收纳图标", ja: "シェルフ項目はありません", ko: "보관함 항목 없음")
        case .alwaysHidden:
            copy(en: "No search-only items", zh: "没有深度隐藏图标", ja: "検索専用項目はありません", ko: "검색 전용 항목 없음")
        }
    }

    private func refreshThumbnails() {
        guard permissions.hasScreenCapture else {
            thumbnails.removeAll()
            return
        }
        thumbnails.refresh(items: store.items)
    }

    private func copy(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct ShelfTrackMarker: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(AppTheme.accent)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.trailing, 3)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(width: 1, height: 48)
        }
    }
}

private struct MenuBarShelfItemButton: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var store: MenuBarShelfStore
    let image: NSImage?
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button {
            store.activate(item)
        } label: {
            VStack(spacing: 5) {
                itemImage
                    .frame(width: compact ? 30 : 26, height: compact ? 30 : 26)
                    .background(
                        isHovered ? AppTheme.accent.opacity(0.12) : AppTheme.elevatedSurface(colorScheme),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                if compact {
                    Text(item.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .frame(width: 54)
                }
            }
            .foregroundStyle(AppTheme.textPrimary(colorScheme))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu { itemContextMenu }
        .help(item.displayName)
        .accessibilityLabel(item.displayName)
        .accessibilityHint(LocalizedString.l(AppSettings.shared.language, en: "Open the original menu bar item", zh: "打开原始菜单栏图标", ja: "元のメニューバー項目を開く", ko: "원본 메뉴 막대 항목 열기"))
    }

    @ViewBuilder
    private var itemImage: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(4)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var itemContextMenu: some View {
        Button {
            store.activate(item)
        } label: {
            Label(
                LocalizedString.l(AppSettings.shared.language, en: "Open", zh: "打开", ja: "開く", ko: "열기"),
                systemImage: "cursorarrow.click"
            )
        }
        Button {
            store.activate(item, rightClick: true)
        } label: {
            Label(
                LocalizedString.l(AppSettings.shared.language, en: "Right-click original", zh: "右键原始图标", ja: "元の項目を右クリック", ko: "원본 항목 우클릭"),
                systemImage: "cursorarrow.rays"
            )
        }
        Divider()
        Menu {
            ForEach(MenuBarShelfGroup.allCases) { group in
                Button {
                    store.setGroup(group, for: item)
                } label: {
                    Label(group.displayName(), systemImage: group.symbolName)
                }
            }
        } label: {
            Label(
                LocalizedString.l(AppSettings.shared.language, en: "Move to", zh: "移到", ja: "移動先", ko: "이동"),
                systemImage: "rectangle.3.group"
            )
        }
        .disabled(!item.canMove)
    }
}

private struct MenuBarBackgroundApplicationButton: View {
    let application: MenuBarBackgroundApplicationSnapshot
    @ObservedObject var store: MenuBarShelfStore
    let image: NSImage?
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button {
            store.activate(application)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        } else {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(
                        isHovered ? AppTheme.accent.opacity(0.12) : AppTheme.elevatedSurface(colorScheme),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                    Circle()
                        .fill(AppTheme.warning)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(AppTheme.surface(colorScheme), lineWidth: 1.5))
                        .offset(x: 1, y: 1)
                }

                Text(application.displayName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppTheme.textPrimary(colorScheme))
                    .lineLimit(1)
                    .frame(width: 54)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(text(
            en: "Running without a menu bar item · Open application",
            zh: "正在运行但没有菜单栏图标 · 点击打开应用",
            ja: "メニューバー項目なしで実行中 · アプリを開く",
            ko: "메뉴 막대 항목 없이 실행 중 · 앱 열기"
        ))
        .accessibilityLabel(application.displayName)
        .accessibilityHint(text(en: "Activate application", zh: "切回应用", ja: "アプリをアクティブにする", ko: "앱 활성화"))
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

private struct MenuBarShelfItemRow: View {
    let item: MenuBarItemSnapshot
    @ObservedObject var store: MenuBarShelfStore
    let image: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 9) {
            MenuBarShelfItemButton(item: item, store: store, image: image, compact: false)
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(item.detailName())
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !item.canMove {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help(LocalizedString.l(AppSettings.shared.language, en: "Managed by macOS", zh: "由 macOS 管理", ja: "macOSが管理", ko: "macOS에서 관리"))
            }

            Picker("", selection: Binding(
                get: { store.group(for: item) },
                set: { store.setGroup($0, for: item) }
            )) {
                ForEach(MenuBarShelfGroup.allCases) { group in
                    Label(group.displayName(), systemImage: group.symbolName).tag(group)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 116)
            .disabled(!item.canMove)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(AppTheme.surface(colorScheme), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
        }
    }
}

private struct MenuBarBackgroundApplicationRow: View {
    let application: MenuBarBackgroundApplicationSnapshot
    @ObservedObject var store: MenuBarShelfStore
    let image: NSImage?
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button {
            store.activate(application)
        } label: {
            HStack(spacing: 9) {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(3)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)
                .background(AppTheme.elevatedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppTheme.textPrimary(colorScheme))
                        .lineLimit(1)
                    Text(text(
                        en: "Running · No menu bar item",
                        zh: "正在运行 · 无菜单栏图标",
                        ja: "実行中 · メニューバー項目なし",
                        ko: "실행 중 · 메뉴 막대 항목 없음"
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(text(en: "Open", zh: "打开", ja: "開く", ko: "열기"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(AppTheme.accent.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                isHovered ? AppTheme.accent.opacity(0.06) : AppTheme.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(AppTheme.stroke(colorScheme), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(text(
            en: "This app has no native menu bar item. Open the application instead.",
            zh: "这个软件没有原生菜单栏图标，点击切回应用。",
            ja: "このアプリには項目がありません。アプリを開きます。",
            ko: "이 앱에는 메뉴 막대 항목이 없습니다. 앱을 엽니다."
        ))
        .accessibilityLabel(application.displayName)
        .accessibilityHint(text(en: "Activate application", zh: "切回应用", ja: "アプリをアクティブにする", ko: "앱 활성화"))
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}

struct MenuBarShelfSettingsPanel: View {
    @ObservedObject private var store: MenuBarShelfStore
    @ObservedObject private var permissions: MenuBarShelfPermissions
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    init(
        store: MenuBarShelfStore? = nil,
        permissions: MenuBarShelfPermissions? = nil
    ) {
        _store = ObservedObject(wrappedValue: store ?? .shared)
        _permissions = ObservedObject(wrappedValue: permissions ?? .shared)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingRow(
                symbol: "menubar.dock.rectangle",
                title: text(en: "Menu Bar Shelf", zh: "菜单栏抽屉", ja: "メニューバーシェルフ", ko: "메뉴 막대 보관함"),
                subtitle: text(en: "Option-click CoolRun to open hidden items", zh: "按住 Option 点击 CoolRun，随时打开隐藏图标", ja: "Optionクリックで非表示項目を開く", ko: "Option-클릭으로 숨긴 항목 열기")
            ) {
                Toggle("", isOn: $store.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider().padding(.leading, 44)

            permissionSettingRow(
                granted: permissions.hasAccessibility,
                symbol: "hand.raised.fill",
                title: text(en: "Accessibility", zh: "辅助功能", ja: "アクセシビリティ", ko: "손쉬운 사용"),
                subtitle: accessibilitySubtitle,
                action: permissions.requestAccessibility,
                recheckAction: permissions.refresh
            )

            if !permissions.hasAccessibility && permissions.applicationIdentity.usesAdHocSignature {
                Divider().padding(.leading, 44)
                adHocPermissionGuidance
            }

            Divider().padding(.leading, 44)

            permissionSettingRow(
                granted: permissions.hasScreenCapture,
                symbol: "photo.on.rectangle",
                title: text(en: "Item previews", zh: "图标预览", ja: "項目プレビュー", ko: "항목 미리보기"),
                subtitle: text(en: "Optional; images never leave this Mac", zh: "可选；图像只保存在本机内存中", ja: "任意。画像はMacの外へ送信されません", ko: "선택 사항. 이미지는 Mac 밖으로 전송되지 않음"),
                action: permissions.requestScreenCapture,
                recheckAction: permissions.refresh
            )

            Divider().padding(.leading, 44)

            settingRow(
                symbol: "arrow.clockwise",
                title: text(en: "Refresh discovered items", zh: "刷新已发现图标", ja: "検出項目を更新", ko: "발견된 항목 새로 고침"),
                subtitle: discoverySubtitle
            ) {
                Button(text(en: "Refresh", zh: "刷新", ja: "更新", ko: "새로 고침")) {
                    store.refresh()
                }
                .controlSize(.small)
            }
        }
        .background(AppTheme.elevatedSurface(colorScheme))
        .onAppear {
            store.start()
            store.setShelfPresented(true)
        }
        .onDisappear {
            store.setShelfPresented(false)
        }
        .task { await permissions.monitorWhileVisible() }
    }

    private func settingRow<Accessory: View>(
        symbol: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func permissionSettingRow(
        granted: Bool,
        symbol: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        recheckAction: @escaping () -> Void
    ) -> some View {
        settingRow(symbol: symbol, title: title, subtitle: subtitle) {
            if granted {
                Label(text(en: "Allowed", zh: "已授权", ja: "許可済み", ko: "허용됨"), systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.healthy)
            } else {
                HStack(spacing: 6) {
                    Button(text(en: "Recheck", zh: "重新检测", ja: "再確認", ko: "다시 확인"), action: recheckAction)
                    Button(text(en: "Allow…", zh: "授权…", ja: "許可…", ko: "허용…"), action: action)
                }
                .controlSize(.small)
            }
        }
    }

    private var accessibilitySubtitle: String {
        guard !permissions.hasAccessibility,
              permissions.applicationIdentity.usesAdHocSignature else {
            return text(
                en: "Required to move and activate original items",
                zh: "移动并操作原始菜单栏图标所必需",
                ja: "元の項目の移動と操作に必要",
                ko: "원본 항목 이동 및 실행에 필요"
            )
        }
        return text(
            en: "A rebuilt temporary-signature app must be added again",
            zh: "临时签名版本重新编译后，需要重新添加当前应用",
            ja: "一時署名の再ビルド後は現在のアプリを再追加してください",
            ko: "임시 서명 앱을 다시 빌드한 후 현재 앱을 다시 추가해야 합니다"
        )
    }

    private var adHocPermissionGuidance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(text(
                    en: "System Settings can keep an enabled-looking entry for an older build. Remove the old CoolRun entry, use + to add the path below, then reopen CoolRun if recheck still fails.",
                    zh: "系统设置可能保留旧构建且显示为已开启。请删除旧 CoolRun，点“+”重新添加下方路径；若重新检测仍失败，请退出并重开 CoolRun。",
                    ja: "システム設定に古いビルドの有効な項目が残る場合があります。古いCoolRunを削除し、下のパスを「+」で追加してください。",
                    ko: "시스템 설정에 이전 빌드가 켜진 상태로 남을 수 있습니다. 이전 CoolRun을 삭제하고 +로 아래 경로를 다시 추가하세요."
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Text(permissions.applicationIdentity.bundlePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppTheme.warning.opacity(0.07))
    }

    private var discoverySubtitle: String {
        let representedApplicationCount = Set(store.items.map {
            $0.ownerBundleIdentifier ?? $0.ownerName.lowercased()
        }).count
        let applicationCount = representedApplicationCount + store.backgroundApplications.count
        return switch store.discoveryMode {
        case .full:
            text(
                en: "\(applicationCount) apps · \(store.items.count) menu bar items · \(store.backgroundApplications.count) background only",
                zh: "\(applicationCount) 个软件 · \(store.items.count) 个菜单栏图标 · \(store.backgroundApplications.count) 个仅后台运行",
                ja: "\(applicationCount)アプリ · \(store.items.count)項目 · \(store.backgroundApplications.count)個はバックグラウンドのみ",
                ko: "\(applicationCount)개 앱 · \(store.items.count)개 메뉴 막대 항목 · \(store.backgroundApplications.count)개 백그라운드 전용"
            )
        case .limited(let reason):
            reason
        }
    }

    private func text(en: String, zh: String, ja: String, ko: String) -> String {
        LocalizedString.l(settings.language, en: en, zh: zh, ja: ja, ko: ko)
    }
}
#endif
