# Purchases And Localization

## Products

- `com.lingchen.cloverpdf.subscription.3months`
- `com.lingchen.cloverpdf.subscription.6months`
- `com.lingchen.cloverpdf.subscription.12months`
- `com.lingchen.cloverpdf.lifetime`

The first three products are auto-renewable subscriptions in one App Store Connect subscription group. The lifetime product is non-consumable. Do not add a local StoreKit configuration unless the user requests it.

## Shared UI

- Reuse `../common/MacAppKit/Purchases/MacPaywallPresenter.swift` and `MacPurchaseManager.swift`.
- Keep CloverPDF-specific code limited to configuration, product mapping, benefits, policy URLs, and presentation triggers.
- Use sandbox accounts for purchase, renewal, cancellation, expiry, refund, and restore acceptance testing.

## Free Entitlement

- Merge remains unlimited and free.
- Allow three successful single-file conversions.
- Do not consume quota for failures or cancellations.
- Require premium before starting a multi-file conversion request.

## Locales

Require `zh-Hans`, `en`, `ko`, `ja`, `de`, and `ru` in the app catalogs and common paywall strings used by CloverPDF. English is the source language and fallback.
