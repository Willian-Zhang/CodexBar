import Foundation

public enum ClaudePlatformAWSProviderDescriptor {
    public static let apiKeyEnvironmentKey = "ANTHROPIC_AWS_API_KEY"
    /// Not a user setting: a one-way digest of the API key, so the script can scope its caches to the key
    /// without reading it.
    static let keyFingerprintSettingKey = "ANTHROPIC_AWS_KEY_FINGERPRINT"
    public static let regionsEnvironmentKey = "ANTHROPIC_AWS_REGIONS"
    public static let monthlyBudgetEnvironmentKey = "ANTHROPIC_AWS_MONTHLY_BUDGET"
    public static let dailyBudgetEnvironmentKey = "ANTHROPIC_AWS_DAILY_BUDGET"
    /// `local` (the default) or `utc`: where days and months begin.
    public static let timeZoneEnvironmentKey = "ANTHROPIC_AWS_TIME_ZONE"
    /// Each configured region costs a handful of sequential requests, and more when a series spans several
    /// pages, as the hourly series behind local-time days can.
    static let timeout: TimeInterval = 120

    public static let spec = PluginProviderSpec(
        id: .claudeplatformaws,
        displayName: "Claude Platform on AWS",
        // Windows exist only when the optional budgets are set: today's spend, then the month's.
        sessionLabel: "Today",
        weeklyLabel: "This month",
        dashboardURL: nil,
        color: .init(hex: 0xD97757),
        confetti: [0xD97757, 0xFF9900],
        noDataMessage: "Claude Platform on AWS spend history needs the cost and usage analytics permissions.",
        supportsTokenCost: true,
        // The history is the analytics API's own figures, not an estimate from local logs.
        tokenCostHintLines: [.literal("Anthropic analytics · may differ from AWS invoice")],
        environmentKey: Self.apiKeyEnvironmentKey,
        missingCredentialMessage: { _ in
            "Set an API key and regions for Claude Platform on AWS in Settings."
        },
        additionalProjections: [
            .init(
                key: Self.monthlyBudgetEnvironmentKey,
                value: { $0.pluginSettings?[Self.monthlyBudgetEnvironmentKey] }),
            .init(
                key: Self.dailyBudgetEnvironmentKey,
                value: { $0.pluginSettings?[Self.dailyBudgetEnvironmentKey] }),
            .init(
                key: Self.timeZoneEnvironmentKey,
                value: { $0.pluginSettings?[Self.timeZoneEnvironmentKey] }),
        ],
        // The projected 30-day history drives the inline spend chart and its Today/30-day summary.
        presentation: ProviderUsagePresentation(menuCard: ProviderMenuCardPresentation(
            supportsInlineTokenCostDashboard: true)),
        apiKeyField: .init(
            id: "claudeplatformaws-api-key",
            title: "API key",
            subtitle: "AWS-generated API key allowed to read Claude Platform on AWS cost and usage. "
                + "Or set ANTHROPIC_AWS_API_KEY.",
            placeholder: "Paste API key…"),
        workspaceField: .init(
            environmentKey: Self.regionsEnvironmentKey,
            field: .init(
                id: "claudeplatformaws-regions",
                title: "Regions",
                subtitle: "Required. Comma-separated AWS regions that hold your workspaces. "
                    + "Or set ANTHROPIC_AWS_REGIONS.",
                placeholder: "us-east-1")))

    private static let requiredKeys = [Self.apiKeyEnvironmentKey, Self.regionsEnvironmentKey]

    /// One strategy for the process: it owns the plugin runtime, whose in-memory cache holds each region's last
    /// result between refreshes. A strategy per refresh would start every refresh with an empty cache.
    private static let strategy = ScriptFetchStrategy(
        id: "claudeplatformaws.js",
        provider: .claudeplatformaws,
        bundledPlugin: "claudeplatformaws",
        sourceLabel: "api",
        timeout: Self.timeout,
        validateContext: { context in
            guard Self.requiredKeys.allSatisfy({ SettingsValue.cleaned(context.env[$0]) != nil }) else {
                throw ProviderFetchClassifiedError(
                    kind: .missingCredential,
                    message: "Claude Platform on AWS requires an API key and at least one region.")
            }
        },
        resolveValues: { context in
            let cleaned: (String) -> String? = { SettingsValue.cleaned(context.env[$0]) }
            let apiKey = cleaned(Self.apiKeyEnvironmentKey)
            var settings = [
                Self.regionsEnvironmentKey,
                Self.monthlyBudgetEnvironmentKey,
                Self.dailyBudgetEnvironmentKey,
                Self.timeZoneEnvironmentKey,
            ].reduce(into: [String: String]()) { values, key in values[key] = cleaned(key) ?? "" }
            settings[Self.keyFingerprintSettingKey] = apiKey.map(Self.keyFingerprint) ?? ""
            return .init(
                settings: settings,
                secrets: apiKey.map { [Self.apiKeyEnvironmentKey: $0] } ?? [:])
        },
        isEnabled: { _ in true })

    static func keyFingerprint(_ apiKey: String) -> String {
        String(CookieHeaderCache.credentialFingerprint(apiKey).prefix(12))
    }

    public static let descriptor = Self.spec.makeDescriptor(fetchPlan: ProviderFetchPlan(
        sourceModes: [.auto, .api],
        pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [Self.strategy] })))
}
