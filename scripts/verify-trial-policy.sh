#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONETIZATION="$ROOT/Sources/App/Monetization.swift"
PERSISTENCE="$ROOT/Sources/App/TrialPersistence.swift"
PAYWALL="$ROOT/Sources/App/PaywallWindow.swift"
DOCS="$ROOT/docs/APP-STORE.md"
METADATA="$ROOT/marketing/app-store/metadata-en-US.md"
CHECKLIST="$ROOT/marketing/app-store/revenuecat-config-checklist.md"

require_text() {
    local text="$1"
    local file="$2"
    /usr/bin/grep -Fq "$text" "$file" || {
        echo "error: missing '$text' in $file" >&2
        exit 1
    }
}

require_text 'static let trialProductID = "com.cosmintrica.airfliq.trial7day"' "$MONETIZATION"
require_text 'Purchases.shared.purchase(product: trialProduct)' "$MONETIZATION"
require_text 'info.nonSubscriptions' "$MONETIZATION"
require_text '.filter(Self.isVerifiedAppleTrialTransaction)' "$MONETIZATION"
require_text 'case .appStore, .macAppStore:' "$MONETIZATION"
require_text '.map(\.purchaseDate)' "$MONETIZATION"
require_text 'trustedReferenceDate: info.requestDate' "$MONETIZATION"
require_text 'product.productType == .nonConsumable' "$MONETIZATION"
require_text 'product.price == Decimal.zero' "$MONETIZATION"
require_text 'Publishing trialProduct only after the exact' "$MONETIZATION"
require_text 'product.price > Decimal.zero' "$MONETIZATION"
require_text '#if MAC_APP_STORE' "$MONETIZATION"
require_text 'TrialPersistence.verifiedState(startedAt:' "$MONETIZATION"
require_text 'TrialPersistence.currentDevelopmentState()' "$MONETIZATION"
require_text 'The App Store path never creates a start date.' "$PERSISTENCE"
require_text '#if !MAC_APP_STORE' "$PERSISTENCE"
require_text 'Start free 7-day trial' "$PAYWALL"
require_text 'No automatic renewal or charge.' "$PAYWALL"
require_text 'When it ends, you keep' "$PAYWALL"
require_text 'free sends per day; unlimited sending then needs Lifetime Pro.' "$PAYWALL"
require_text 'static let dailyLimit = 5' "$MONETIZATION"
require_text 'localized one-time Lifetime Pro price' "$PAYWALL"
require_text 'named exactly `7-day Trial`' "$DOCS"
require_text 'Do not attach `com.cosmintrica.airfliq.trial7day`' "$DOCS"
require_text 'does not begin on download, first launch, onboarding, or a send attempt' "$METADATA"
require_text 'Attach only `com.cosmintrica.airfliq.lifetime` to entitlement `Pro`' "$CHECKLIST"

if /usr/bin/grep -Fq 'The 7-day full trial begins locally on first launch.' "$METADATA"; then
    echo "error: metadata still claims the App Store trial starts automatically" >&2
    exit 1
fi

APP_BINARY="${1:-$ROOT/build/AirFliq.app/Contents/MacOS/AirFliq}"
if [ -f "$APP_BINARY" ]; then
    for source in "$MONETIZATION" "$PERSISTENCE" "$PAYWALL"; do
        if [ "$source" -nt "$APP_BINARY" ]; then
            echo "error: built app is older than $source; rebuild before validating" >&2
            exit 1
        fi
    done
    /usr/bin/grep -aFq 'com.cosmintrica.airfliq.trial7day' "$APP_BINARY" || {
        echo "error: built app does not contain the trial product identifier" >&2
        exit 1
    }
    for architecture in arm64 x86_64; do
        /usr/bin/lipo "$APP_BINARY" -verify_arch "$architecture"
    done
fi

echo "✅ Trial policy checks passed"
