import StoreKit
import SwiftUI

/// Section displaying the StoreKit 2 consumable tip jar tiers.
/// Displays localized prices (`product.displayPrice`), handles purchase state,
/// and explains that tips are voluntary with no feature unlock.
struct DeveloperTipJarSection: View {
    @Bindable var service: DeveloperTipJarService
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    var body: some View {
        FleetSettingsSection("Developer Tip Jar") {
            FleetSettingsRow {
                Text("Hash Fleet is free and open-source. Tipping is completely optional and supports ongoing development. No features or capabilities are locked or unlocked.")
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }

            if service.isLoadingProducts && service.products.isEmpty {
                FleetSettingsRow(showsSeparator: false) {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading tip options…")
                            .fleetFont(.footnote)
                            .foregroundStyle(FleetTheme.secondary)
                    }
                }
            } else if let error = service.loadError, service.products.isEmpty {
                FleetSettingsRow(showsSeparator: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tip options aren't available right now.")
                            .fleetFont(.subheadline)
                            .foregroundStyle(FleetTheme.ink)
                        Text("Check your connection and tap Retry. Hash Fleet works fully without a tip.")
                            .fleetFont(.caption)
                            .foregroundStyle(FleetTheme.secondary)
                            .help(error)
                        Button("Retry") {
                            Task { await service.loadProducts() }
                        }
                        .fleetFont(.caption)
                    }
                }
            } else if service.products.isEmpty && service.hasAttemptedLoad {
                // Empty product response after loading completed
                FleetSettingsRow(showsSeparator: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tip options are currently unavailable.")
                            .fleetFont(.subheadline)
                            .foregroundStyle(FleetTheme.ink)
                        Text("App Store products could not be retrieved. You can try again later.")
                            .fleetFont(.caption)
                            .foregroundStyle(FleetTheme.secondary)
                        Button("Retry") {
                            Task { await service.loadProducts() }
                        }
                        .fleetFont(.caption)
                    }
                }
            } else {
                ForEach(service.products) { product in
                    FleetSettingsRow {
                        tipRow(for: product)
                    }
                }
            }
        }
        .fleetSettingsSectionIdentifier("about.tipjar")
        .task {
            if service.products.isEmpty {
                await service.loadProducts()
            }
        }
        .onChange(of: service.purchaseState) { _, state in
            handleStateChange(state)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {
                service.resetState()
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func tipRow(for product: Product) -> some View {
        let tipProduct = DeveloperTipProduct(rawValue: product.id)
        let isPurchasingThis = service.purchaseState == .purchasing(product.id)
        let isPurchasingAny = service.isPurchaseInProgress

        return HStack(spacing: 12) {
            Image(systemName: tipProduct?.iconName ?? "heart.fill")
                .fleetFont(.title3)
                .foregroundStyle(FleetTheme.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName.isEmpty ? (tipProduct?.defaultTitle ?? "Developer Tip") : product.displayName)
                    .fleetFont(.headline)
                    .foregroundStyle(FleetTheme.ink)

                Text(product.description.isEmpty ? (tipProduct?.defaultDescription ?? "") : product.description)
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
            }

            Spacer()

            Button {
                Task {
                    await service.purchase(product)
                }
            } label: {
                if isPurchasingThis {
                    ProgressView()
                        .frame(minWidth: 70)
                } else {
                    Text(product.displayPrice)
                        .fleetFont(.subheadline, weight: .semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(FleetTheme.accent.opacity(0.12), in: Capsule())
                        .foregroundStyle(FleetTheme.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(isPurchasingAny)
            .accessibilityIdentifier("about.tipjar.buy.\(product.id)")
            .accessibilityLabel("Tip \(product.displayPrice)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleStateChange(_ state: DeveloperTipPurchaseState) {
        switch state {
        case .idle, .purchasing:
            break
        case .success:
            alertTitle = "Thank You!"
            alertMessage = "Your tip was received. Thank you for supporting Hash Fleet!"
            showingAlert = true
        case .pending:
            alertTitle = "Purchase Pending"
            alertMessage = "Your purchase requires authorization (such as Ask to Buy). It will be completed once approved."
            showingAlert = true
        case .cancelled:
            // No alert needed on cancellation
            service.resetState()
        case .failed(let message):
            alertTitle = "Purchase Incomplete"
            alertMessage = message
            showingAlert = true
        }
    }
}
