# Reusable Swift Sonar Kit consumer

The free-analysis bridge now lives in a separate sibling Git repository, swift-sonar-kit. It has no HashFleet runtime dependency and supports configurable Swift source directories. Set SWIFT_SONAR_KIT_ROOT if the checkout is elsewhere.

Tools/swift-sonar-kit.sh delegates to that checkout using Python 3.11+. Examples from the HashFleet root:

    PYTHON=python3.12 bash Tools/swift-sonar-kit.sh --help
    PYTHON=python3.12 bash Tools/swift-sonar-kit.sh issues --input build/sonar/swiftlint-current.json --output build/sonar/kit-issues.json
    PYTHON=python3.12 bash Tools/swift-sonar-kit.sh doctor

Doctor uses SONAR_TOKEN from the environment and performs authenticated read-only checks. Offline conversion does not establish report freshness. No tokens or reports belong in either repository.

The optional toolkit scan command is focused on Swift sources and uses its own test receipt and scanner properties. It does NOT replace Tools/sonar-scan.sh, the existing multi-language configuration, native xcresult import, independent exhaustive test-identity checks, or the application. The established HashFleet scan remains the comprehensive dashboard path.

Use the toolkit standalone for new Swift projects, or use its exported generic reports in a reviewed existing pipeline. Native plugin SwiftLint findings and generic external issues can overlap. Choose one rule-import strategy per project before enabling both, and preserve independent lint gates.

Integration evidence and limitations are recorded in the toolkit docs/VALIDATION.md. Public GitHub publication is separate from creating and validating the local repository.
