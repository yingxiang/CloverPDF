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
- Use sandbox accounts for purchase, renewal, cancellation, expiry, refund, and restore acceptance testing.

## Free Entitlement

- Merge remains unlimited and free.
- Allow three successful single-file conversions.
- Do not consume quota for failures or cancellations.
- Require premium before starting a multi-file conversion request.

## Locales

Require `zh-Hans`, `en`, `ko`, `ja`, `de`, and `ru` in the app catalogs and common paywall strings used by WPDF. English is the source language and fallback.
