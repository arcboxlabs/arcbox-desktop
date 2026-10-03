import ArcBoxClient
import Foundation
import OSLog

extension SandboxesViewModel {
    // MARK: - Template Catalog Operations (TemplateService)

    /// Load the template catalog. One entry per version, drafts included.
    func loadTemplates(client: ArcBoxClient?) async {
        guard let client else {
            if templatesLoadState == .loading {
                templatesLoadState = .waiting
            }
            return
        }

        let isRefresh = templatesLoadState.beginLoading()
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        do {
            var entries: [Arcbox_Sandbox_V1_Template] = []
            var pageToken = ""
            repeat {
                var request = Arcbox_Sandbox_V1_ListTemplatesRequest()
                request.pageSize = 1_000
                request.pageToken = pageToken
                let response = try await client.templates.list(
                    request,
                    metadata: metadata,
                    options: ArcBoxClient.defaultCallOptions
                )
                entries.append(contentsOf: response.templates)
                pageToken = response.nextPageToken
            } while !pageToken.isEmpty

            templates = entries.map(SandboxTemplateViewModel.init(from:))
            templatesLoadState = .loaded
            templatesRefreshError = nil
        } catch is CancellationError {
            templatesLoadState = isRefresh ? .loaded : .waiting
        } catch {
            if templatesLoadState.cancelLoading(for: error, retainingLoadedContent: isRefresh) {
                return
            }
            let message = reportError(error, operation: "list_templates", surface: false)
            templatesRefreshError = templatesLoadState.fail(
                message,
                retainingLoadedContent: isRefresh
            )
        }
    }

    /// Promote a snapshot into a catalog template. Returns the draft on success.
    ///
    /// No build runs: the checkpoint becomes the template's warm snapshot, so
    /// sandboxes created from it restore instead of booting.
    @discardableResult
    func promoteSnapshotToTemplate(
        snapshotID: String,
        name: String,
        client: ArcBoxClient?
    ) async -> SandboxTemplateViewModel? {
        guard let client else { return nil }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_BuildTemplateRequest()
        request.name = name
        request.source = .snapshotID(snapshotID)
        do {
            // No per-call timeout: Build blocks for the whole catalog mutation,
            // which for other sources covers image export and rootfs
            // conversion. The daemon applies no read deadline to sandbox RPCs.
            let template = try await client.templates.build(request, metadata: metadata)
            Log.sandbox.info(
                "Promoted snapshot \(snapshotID, privacy: .public) → template \(template.name, privacy: .public)"
            )
            await loadTemplates(client: client)
            return SandboxTemplateViewModel(from: template)
        } catch is CancellationError {
            return nil
        } catch {
            reportError(error, operation: "build_template")
            return nil
        }
    }

    /// Freeze a draft's current content as an immutable version.
    /// Bare-name references then resolve to the newest published version.
    @discardableResult
    func publishTemplate(
        name: String,
        version: String,
        client: ArcBoxClient?
    ) async -> Bool {
        guard let client else { return false }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_PublishTemplateRequest()
        request.name = name
        request.version = version
        do {
            _ = try await client.templates.publish(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            await loadTemplates(client: client)
            return true
        } catch is CancellationError {
            return false
        } catch {
            reportError(error, operation: "publish_template")
            return false
        }
    }

    /// Delete one version, or — for a bare name — the template and every
    /// version of it. Sandboxes already created from it are unaffected.
    func deleteTemplate(reference: String, client: ArcBoxClient?) async {
        guard let client else { return }
        let metadata = SandboxMetadata.forMachine(activeMachineID)
        var request = Arcbox_Sandbox_V1_DeleteTemplateRequest()
        request.reference = reference
        do {
            _ = try await client.templates.delete(
                request,
                metadata: metadata,
                options: ArcBoxClient.defaultCallOptions
            )
            // A bare name takes every version of the template with it, so
            // matching on `reference` alone would leave the versioned rows on
            // screen until the next full load.
            if reference.contains(":") {
                templates.removeAll { $0.reference == reference }
            } else {
                templates.removeAll { $0.name == reference }
            }
        } catch is CancellationError {
            return
        } catch {
            reportError(error, operation: "delete_template")
        }
    }
}
