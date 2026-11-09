import Foundation
import HashFleetCore
import StoreKit
import Testing
@testable import HashFleet

@MainActor
struct DeveloperTipJarServiceTests {
    @Test func approvedProductIDsMatchCoreDefinition() {
        #expect(DeveloperTipJarService.approvedProductIDs == DeveloperSupport.appStoreTipProductIDs)
        let expected: Set<String> = [
            "app.hashfleet.tip.small",
            "app.hashfleet.tip.medium",
            "app.hashfleet.tip.large",
            "app.hashfleet.tip.supporter",
            "app.hashfleet.tip.champion",
            "app.hashfleet.tip.patron"
        ]
        #expect(DeveloperTipJarService.approvedProductIDs == expected)
        #expect(DeveloperTipJarService.approvedProductIDs.count == 6)
        #expect(DeveloperTipProduct.allCases.count == 6)
        #expect(DeveloperTipProduct.allCases.map(\.rawValue) == [
            "app.hashfleet.tip.small",
            "app.hashfleet.tip.medium",
            "app.hashfleet.tip.large",
            "app.hashfleet.tip.supporter",
            "app.hashfleet.tip.champion",
            "app.hashfleet.tip.patron"
        ])
    }

    @Test func defaultTitlesAndDescriptionsArePresent() {
        for tier in DeveloperTipProduct.allCases {
            #expect(!tier.defaultTitle.isEmpty)
            #expect(!tier.defaultDescription.isEmpty)
            #expect(!tier.iconName.isEmpty)
        }
        #expect(DeveloperTipProduct.small.defaultTitle == "Small Tip")
        #expect(DeveloperTipProduct.medium.defaultTitle == "Medium Tip")
        #expect(DeveloperTipProduct.large.defaultTitle == "Generous Tip")
        #expect(DeveloperTipProduct.supporter.defaultTitle == "Supporter Tip")
        #expect(DeveloperTipProduct.champion.defaultTitle == "Champion Tip")
        #expect(DeveloperTipProduct.patron.defaultTitle == "Patron Tip")

        #expect(DeveloperTipProduct.small.iconName == "cup.and.saucer")
        #expect(DeveloperTipProduct.medium.iconName == "bolt")
        #expect(DeveloperTipProduct.large.iconName == "heart.fill")
        #expect(DeveloperTipProduct.supporter.iconName == "star.fill")
        #expect(DeveloperTipProduct.champion.iconName == "crown.fill")
        #expect(DeveloperTipProduct.patron.iconName == "rosette")
    }

    @Test func performPurchaseApprovedPathSucceedsForEveryTierWithoutStoreKitOrListener() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        for tier in DeveloperTipProduct.allCases {
            let productID = tier.rawValue
            var operationInvoked = false
            await service.performPurchase(productID: productID) {
                operationInvoked = true
                return .success(productID)
            }
            #expect(operationInvoked)
            #expect(service.purchaseState == .success(productID))
            #expect(!service.isPurchaseInProgress)
            service.resetState()
            #expect(service.purchaseState == .idle)
        }
    }

    @Test func initialPurchaseStateIsIdleWithoutTaskLeak() {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        #expect(service.purchaseState == .idle)
        #expect(!service.isLoadingProducts)
        #expect(!service.hasAttemptedLoad)
        #expect(!service.isPurchaseInProgress)
        #expect(service.loadError == nil)
    }

    @Test func performPurchaseSuspendsAndBlocksConcurrentAttempt() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        let smallID = DeveloperTipProduct.small.rawValue
        let mediumID = DeveloperTipProduct.medium.rawValue

        var firstEntered = false
        var secondAttemptInvoked = false
        var resumeFirstContinuation: CheckedContinuation<DeveloperTipPurchaseState, Never>?

        let firstTask = Task { @MainActor in
            await service.performPurchase(productID: smallID) {
                firstEntered = true
                return await withCheckedContinuation { cont in
                    resumeFirstContinuation = cont
                }
            }
        }

        // Wait until firstTask enters the operation closure
        while !firstEntered {
            await Task.yield()
        }

        #expect(service.isPurchaseInProgress)
        #expect(service.purchaseState == .purchasing(smallID))

        // Concurrent attempt while first is in-flight must NOT invoke its operation closure
        await service.performPurchase(productID: mediumID) {
            secondAttemptInvoked = true
            return .success(mediumID)
        }
        #expect(!secondAttemptInvoked)
        #expect(service.purchaseState == .purchasing(smallID))

        // Reset and external completion while locked must NOT overwrite purchasing or release lock
        service.resetState()
        #expect(service.purchaseState == .purchasing(smallID))
        service.recordExternalCompletion(productID: smallID)
        #expect(service.purchaseState == .purchasing(smallID))
        #expect(service.isPurchaseInProgress)

        // Resume and join first purchase
        resumeFirstContinuation?.resume(returning: .success(smallID))
        await firstTask.value

        #expect(!service.isPurchaseInProgress)
        #expect(service.purchaseState == .success(smallID))
    }

    @Test func performPurchaseReleasesLockOnCancelledPendingAndError() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        let smallID = DeveloperTipProduct.small.rawValue

        // 1. Cancelled
        await service.performPurchase(productID: smallID) { .cancelled }
        #expect(!service.isPurchaseInProgress)
        #expect(service.purchaseState == .cancelled)

        // 2. Pending
        await service.performPurchase(productID: smallID) { .pending(smallID) }
        #expect(!service.isPurchaseInProgress)
        #expect(service.purchaseState == .pending(smallID))

        // 3. Error / throw
        struct TestError: LocalizedError {
            var errorDescription: String? { "simulated error" }
        }
        await service.performPurchase(productID: smallID) { throw TestError() }
        #expect(!service.isPurchaseInProgress)
        #expect(service.purchaseState == .failed("simulated error"))
    }

    @Test func performPurchaseRejectsUnsupportedProductID() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        var invoked = false
        await service.performPurchase(productID: "com.unsupported.item") {
            invoked = true
            return .success("com.unsupported.item")
        }
        #expect(!invoked)
        #expect(service.purchaseState == .idle)
        #expect(!service.isPurchaseInProgress)
    }

    @Test func recordExternalCompletionUpdatesOnlyIdleOrMatchingPending() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        let smallID = DeveloperTipProduct.small.rawValue
        let mediumID = DeveloperTipProduct.medium.rawValue

        // Unapproved ID ignored
        service.recordExternalCompletion(productID: "unapproved.id")
        #expect(service.purchaseState == .idle)

        // From idle -> success
        service.recordExternalCompletion(productID: smallID)
        #expect(service.purchaseState == .success(smallID))

        // From pending matching ID -> success
        service.resetState()
        await service.performPurchase(productID: smallID) { .pending(smallID) }
        #expect(service.purchaseState == .pending(smallID))

        // External completion for a different product while pending does not clobber
        service.recordExternalCompletion(productID: mediumID)
        #expect(service.purchaseState == .pending(smallID))

        // Matching product external completion transitions pending to success
        service.recordExternalCompletion(productID: smallID)
        #expect(service.purchaseState == .success(smallID))
    }

    @Test func finishTransactionOnceSharesTaskAndInvokesFinishOnce() async {
        let service = DeveloperTipJarService(startUpdatesListener: false)
        let testID: UInt64 = 42

        var finishCount = 0
        var resumeFinish: CheckedContinuation<Void, Never>?
        var finishEntered = false

        let task1 = Task { @MainActor in
            await service.finishTransactionOnce(id: testID) {
                finishCount += 1
                finishEntered = true
                await withCheckedContinuation { cont in
                    resumeFinish = cont
                }
            }
        }

        while !finishEntered {
            await Task.yield()
        }

        var task2CompletedEarly = false
        var task2Entered = false
        let task2 = Task { @MainActor in
            task2Entered = true
            await service.finishTransactionOnce(id: testID) {
                finishCount += 1
            }
            task2CompletedEarly = true
        }

        while !task2Entered { await Task.yield() }
        // task2 must wait for task1's finish operation; neither reports completion yet
        #expect(finishCount == 1)
        #expect(!task2CompletedEarly)

        // Release the shared finish task
        resumeFinish?.resume()
        await task1.value
        await task2.value

        #expect(finishCount == 1)
        #expect(task2CompletedEarly)

        // Calling again with the already finished ID does not invoke finish closure
        await service.finishTransactionOnce(id: testID) {
            finishCount += 1
        }
        #expect(finishCount == 1)
    }

    @Test func appStoreBuildHidesExternalCheckoutAndCrypto() {
        #if !(os(macOS) && HASHFLEET_DIRECT_DISTRIBUTION)
        let availability = DeveloperSupportAvailability(currentCountryCode: { "USA" })
        #expect(availability.checkoutURL == nil)
        #expect(availability.cryptoDestinations.isEmpty)
        #expect(availability.usesNativeTipJar)
        #endif
    }

    @Test func directDistributionMacGatingMatchesBuildTarget() {
        let availability = DeveloperSupportAvailability(currentCountryCode: { nil })
        #if os(macOS) && HASHFLEET_DIRECT_DISTRIBUTION
        #expect(availability.directDistribution)
        #expect(!availability.usesNativeTipJar)
        #expect(availability.checkoutURL != nil)
        #expect(!availability.cryptoDestinations.isEmpty)
        #else
        #expect(!availability.directDistribution)
        #expect(availability.usesNativeTipJar)
        #expect(availability.checkoutURL == nil)
        #expect(availability.cryptoDestinations.isEmpty)
        #endif
    }
}
