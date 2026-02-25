# QuickGig Legal Release Baseline

Last update: 2026-02-26
Owner: Product/Legal

## Public legal endpoints
- Privacy Policy: `http://127.0.0.1:8000/legal/privacy`
- Terms of Use: `http://127.0.0.1:8000/legal/terms`
- Support page: `http://127.0.0.1:8000/legal/support`
- Support email: `support@quickgig.app`

## App-side wiring
Legal links are available in Settings -> "Правова інформація" and are read from Info.plist keys:
- `PrivacyPolicyURL`
- `TermsOfUseURL`
- `SupportURL`
- `SupportEmail`

## App Store Connect fields to fill
- Privacy Policy URL -> public HTTPS URL of `/legal/privacy`
- Support URL -> public HTTPS URL of `/legal/support`
- Contact email -> `support@quickgig.app`
- Terms of Use URL (if required by territory/category) -> public HTTPS URL of `/legal/terms`

## Before production submission
- Replace local `127.0.0.1` URLs with production HTTPS domain.
- Validate policy texts with legal counsel for UA/EU processing scope.
- Ensure policy pages are reachable without authorization.
