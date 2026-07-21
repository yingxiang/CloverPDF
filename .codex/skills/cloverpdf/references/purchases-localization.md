# Purchases And Localization

## Products

- `pdf_buy_three_month`
- `pdf_buy_six_month`
- `pdf_buy_one_year`
- `com.lingchen.pdf.unlockall`

The first three products are auto-renewable subscriptions in one App Store Connect subscription group. The lifetime product is non-consumable. Do not add a local StoreKit configuration unless the user requests it.

## Shared UI

- Reuse `../common/MacAppKit/Purchases/MacPaywallPresenter.swift` and `MacPurchaseManager.swift`.
- Keep WPDF-specific code limited to configuration, product mapping, benefits, policy URLs, and presentation triggers.
- Use the shared paywall's companion-app provider and catalog; do not fork the paywall to add cross-promotion UI. The paywall shows one Free Trial option that becomes `免费试用，剩X天` while the entitlement is active and expands a right-side list titled `免费下载，获取权益`. Each app row contains its icon, title, subtitle, and a right-aligned localized Download for 3 Days, Claimed, or Restore Benefit action. The shared catalog excludes the host app automatically: WPDF shows Clover and Maple, Clover shows Maple, and Maple shows Clover.
- Use `https://yingxiang.github.io/CloverPDF/index.html` for the Privacy link in both Settings and the paywall.
- Use sandbox accounts for purchase, renewal, cancellation, expiry, refund, and restore acceptance testing.

## Free Entitlement

- Merge remains unlimited and free.
- Allow three successful single-file conversions.
- Do not consume quota for failures or cancellations.
- Require premium before starting a multi-file conversion request.
- Detect installed companion apps by bundle identifier: Clover is `com.lingchen.clover` and Maple is `com.lingchen.omnicapture`. Detecting either app starts one shared three-day Premium trial stored in Keychain; detecting both never starts or extends a second period. Persist which app claimed the benefit so its row becomes Claimed while installed and Restore Benefit after deletion. Recheck on app start and activation, require at least one claimed companion app to remain installed, and treat the active companion trial as Premium for conversion entitlement checks. Reinstalling restores only the unexpired remainder and never resets the start date.
- Unit-test hosts must not claim or persist the companion-app trial; keep test-process detection covered by a unit test.

## Locales

Require `zh-Hans`, `en`, `ko`, `ja`, `de`, and `ru` in the app catalogs and common paywall strings used by WPDF. English is the source language and fallback.
