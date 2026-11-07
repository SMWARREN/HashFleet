import SwiftUI
import HashFleetCore

extension MinerEndpointView {
    var overview: some View {
        FleetSettingsSection {
            Text("\(resolvedEndpoint.method) \(resolvedEndpoint.path)")
                .fleetFont(.callout, design: .monospaced)
                .textSelection(.enabled)
            LabeledContent("Target", value: device.address)
            Label(model.capability, systemImage: "questionmark.circle")
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
            Text(
                "An upstream catalog entry is not a capability guarantee. Older or custom firmware "
                    + "may return 404, 405 or another firmware error. Requests are never retried as a "
                    + "different endpoint."
            )
            .fleetFont(.footnote)
        }
        .listRowBackground(FleetTheme.surface)
    }

    var poolSection: some View {
        FleetSettingsSection("Pool slot") {
            Picker("NVS slot", selection: $poolSlot) {
                ForEach(0..<8) { Text("Slot \($0)").tag($0) }
            }
            Text(
                "Slots are persistent IDs 0–7, not the array position in info.pools. Read system info "
                    + "first. Deleting an active pool can interrupt mining. Update primaryPoolIndex / "
                    + "secondaryPoolIndex separately if needed."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }.disabled(model.isRunning)
            .listRowBackground(FleetTheme.surface)
    }

    var statisticsSection: some View {
        FleetSettingsSection("Statistics query") {
            TextField("columns (comma-separated, optional)", text: $columns)
                .fleetFont(.callout, design: .monospaced)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(
                "Examples: hashrate,hashrate_1m,asicTemp,vrTemp,power,fanSpeed,fanRpm,wifiRssi. "
                    + "Leave empty to use firmware defaults. Column names are case-sensitive."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }.disabled(model.isRunning)
            .listRowBackground(FleetTheme.surface)
    }

    var querySection: some View {
        FleetSettingsSection {
            DisclosureGroup("Additional query parameters") {
                Text(
                    "One name=value per line. Values are URL-encoded by the client. Only add "
                        + "parameters your firmware documents."
                )
                .fleetFont(.footnote)
                TextEditor(text: $extraQuery)
                    .fleetFont(.caption, design: .monospaced)
                    .frame(minHeight: 80)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Additional query parameters, one name equals value per line")
            }
        }.disabled(model.isRunning)
            .listRowBackground(FleetTheme.surface)
    }

    var jsonSection: some View {
        FleetSettingsSection("JSON request body") {
            Text(
                "Only included keys will be sent. Use the exact firmware field names and types. "
                    + "Unknown fields are forwarded for custom firmware and may be ignored or rejected."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
            TextEditor(text: $jsonText)
                .fleetFont(.caption, design: .monospaced)
                .frame(minHeight: 230)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("JSON request body")
                .accessibilityIdentifier("endpoint.json")
            if endpoint == .settings {
                DisclosureGroup("All upstream PATCH fields") {
                    Text(MinerSettingsReference.fields)
                        .fleetFont(.caption, design: .monospaced)
                        .textSelection(.enabled)
                    Text(
                        "Settings allows additional properties. This editor can send any JSON field, "
                            + "including firmware-specific additions. Pool objects support the complete "
                            + "nested Pool schema. Do not copy read-only telemetry into a PATCH."
                    )
                    .fleetFont(.footnote)
                }
            }
        }.disabled(model.isRunning)
            .listRowBackground(FleetTheme.surface)
    }

    var binarySection: some View {
        FleetSettingsSection("Raw .bin image") {
            Label(
                "High risk: verify board and image compatibility",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(FleetTheme.accent)
            Text(
                endpoint == .otaWWW
                    ? "Choose a SPIFFS/custom web UI .bin image, not a ZIP or HTML file. This "
                        + "uploads to /OTAWWW. The useCustomWWW setting selects the custom UI separately."
                    : "Choose an OTA firmware .bin built for this exact board. Do not upload a "
                        + "merged factory image unless your firmware explicitly supports it."
            )
            .fleetFont(.footnote)
            Button("Choose .bin file", systemImage: "doc.badge.plus") { importing = true }
                .disabled(model.isRunning)
            if let filename = selectedFilename, let data = selectedData {
                LabeledContent("Selected", value: filename)
                LabeledContent(
                    "Size",
                    value: ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                )
            }
            Text(
                "Files must be nonempty .bin files, at most 16 MiB. This is an app memory guard, "
                    + "not a device partition-size guarantee. The firmware performs its own validation. "
                    + "No upload starts until you review and type APPLY."
            )
            .fleetFont(.footnote)
            .foregroundStyle(FleetTheme.secondary)
        }
        .listRowBackground(FleetTheme.surface)
    }

    @ViewBuilder var resultSection: some View {
        if let error = model.error {
            FleetSettingsSection("Request error") {
                Text(error).foregroundStyle(FleetTheme.warning).textSelection(.enabled)
                Text(
                    "For a timed-out write, the outcome may be unknown. Read system info before "
                        + "retrying. Network errors do not prove an endpoint is unsupported."
                )
                .fleetFont(.footnote)
            }
            .listRowBackground(FleetTheme.surface)
        }
        if !model.response.isEmpty {
            FleetSettingsSection("Response") {
                Button("Prepare export file", systemImage: "doc.badge.arrow.up") {
                    model.prepareExport(isLog: endpoint == .logs)
                }
                Text(
                    "Exporting creates a temporary local file. It is removed on the next request "
                        + "or when leaving this screen. Review private data before sharing."
                )
                .fleetFont(.footnote)
                .foregroundStyle(FleetTheme.secondary)
                if let exportError = model.exportError {
                    Text(exportError).foregroundStyle(FleetTheme.warning)
                }
                if let file = model.exportedFile {
                    ShareLink(item: file) {
                        Label(
                            endpoint == .logs ? "Share downloaded logs" : "Share complete response",
                            systemImage: "square.and.arrow.up"
                        )
                    }
                    Text(
                        "Responses and logs can contain network names, pool credentials or other "
                            + "private data. Review before sharing."
                    )
                    .fleetFont(.footnote)
                    .foregroundStyle(FleetTheme.secondary)
                }
                Text(model.response)
                    .fleetFont(.caption, design: .monospaced)
                    .textSelection(.enabled)
            }
            .listRowBackground(FleetTheme.surface)
        }
    }

}
