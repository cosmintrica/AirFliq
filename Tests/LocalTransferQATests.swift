import AppKit

@main struct LocalTransferQATests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let access = Monetization.shared
        access.configure()
#if AIRFLIQ_LOCAL_QA && DEBUG
        precondition(Monetization.isLocalTransferTest)
        precondition(access.canSend && !access.isConfigured)
        precondition(!access.isPro && !access.isTrialStarted)
        precondition(access.trialStatusText == "Local transfer test (purchases disabled)")
        var rejected = 0
        let result: (Monetization.PurchaseOutcome) -> Void = {
            if case .failed = $0 { rejected += 1 }
        }
        access.startTrial(completion: result)
        access.purchase(completion: result)
        access.restore(completion: result)
        precondition(rejected == 3 && !access.isTrialStarted && !access.isPro)
        print("PASS: local transfer QA enables sending without SDK, purchase, trial or Pro mutation")
#else
        precondition(!Monetization.isLocalTransferTest)
        precondition(!access.hasUnlimitedSending && !access.isTrialStarted && !access.isPro)
        precondition(access.canSend == (access.freeSendsRemainingToday > 0))
        print("PASS: normal App Store build allows only the free daily sends without a verified trial or Pro")
#endif
    }
}
