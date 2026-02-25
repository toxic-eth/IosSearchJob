# QuickGig iOS Release Checklist

Дата создания: 2026-02-25
Версия релиза: __________
Владелец релиза: __________

Инструкция:
- Отмечайте `[x]` когда пункт полностью закрыт.
- Для каждого пункта фиксируйте владельца и дату в колонке `Owner/Date`.
- Пункты `P0` обязательны для выхода в App Store.

## 1) P0 Blockers (must-have)

| Status | Priority | Item | Owner/Date | Notes |
|---|---|---|---|---|
| [ ] | P0 | Прод backend + БД готовы (без демо-хранилища) |  |  |
| [ ] | P0 | Реальная auth: Apple/Google/Phone OTP end-to-end |  |  |
| [x] | P0 | Privacy Policy + Terms опубликованы и доступны по URL | Codex/2026-02-26 | Реализовано на backend: `/legal/privacy`, `/legal/terms` |
| [ ] | P0 | Убраны/выключены демо-данные и demo-flow в production build |  |  |
| [ ] | P0 | Нет критических крэшей/фризов в ключевых сценариях |  |  |
| [ ] | P0 | Карта/геолокация стабильны при слабой сети и denied permissions |  |  |
| [ ] | P0 | Все секреты вынесены из кода (tokens/keys/env) |  |  |
| [ ] | P0 | Signing/Provisioning/Bundle ID настроены корректно |  |  |
| [ ] | P0 | Smoke-pass на реальном iPhone (финальный) |  |  |

## 2) Trust, Safety, Finance

| Status | Priority | Item | Owner/Date | Notes |
|---|---|---|---|---|
| [ ] | P0 | KYC/moderation работает с backend-ролями (RBAC) |  |  |
| [ ] | P0 | Escrow/payout flow production-ready или выключен для релиза |  |  |
| [ ] | P1 | Reconciliation и audit trail сохраняются на сервере |  |  |
| [ ] | P1 | Recovery-сценарии ошибок (KYC/risk/payout) покрыты UI |  |  |
| [ ] | P1 | Антиспам/rate-limit и базовый antifraud включены |  |  |

## 3) UX and Accessibility

| Status | Priority | Item | Owner/Date | Notes |
|---|---|---|---|---|
| [ ] | P1 | Контраст соответствует доступности на light/dark теме |  |  |
| [ ] | P1 | Dynamic Type и VoiceOver пройдены на основных экранах |  |  |
| [ ] | P1 | Hit-area контролов соответствует iOS рекомендациям |  |  |
| [ ] | P1 | Нет layout-jump/overlap в onboarding, map/list, profile |  |  |
| [ ] | P1 | Empty/error states имеют явные recovery-действия |  |  |

## 4) App Store Readiness

| Status | Priority | Item | Owner/Date | Notes |
|---|---|---|---|---|
| [ ] | P0 | App icon, launch screen, app name готовы |  |  |
| [ ] | P0 | App Store metadata: description, keywords, category |  |  |
| [ ] | P0 | Скриншоты для iPhone (все локали релиза) |  |  |
| [ ] | P0 | App Privacy section в App Store Connect заполнен |  |  |
| [x] | P0 | Support URL и contact email опубликованы | Codex/2026-02-26 | `/legal/support`, `support@quickgig.app` |
| [ ] | P0 | Review notes и тестовый аккаунт для Apple подготовлены |  |  |

## 5) QA Matrix (devices + scenarios)

### Devices
- [ ] iPhone SE (small screen)
- [ ] iPhone 13/14 (standard)
- [ ] iPhone 15/16 Pro Max (large screen)

### Core scenarios
- [ ] Onboarding -> role select -> registration/login
- [ ] Worker: search/filter/list/map -> shift details -> apply
- [ ] Employer: create shift -> applicants -> progress statuses
- [ ] Chat: send/receive, offer accept/reject, unread badges
- [ ] Profile: KYC/risk/audit/reconciliation sections
- [ ] Theme switch (light/dark) without UI regressions

## 6) Release Operations

| Status | Priority | Item | Owner/Date | Notes |
|---|---|---|---|---|
| [ ] | P0 | Crash/analytics monitoring configured |  |  |
| [ ] | P1 | Alerting on API failures and auth errors |  |  |
| [ ] | P1 | Support SLA and escalation flow documented |  |  |
| [ ] | P1 | Hotfix rollout plan and owner assigned |  |  |

## 7) Go/No-Go

- Go/No-Go дата: __________
- Решение:
  - [ ] GO
  - [ ] NO-GO
- Финальное решение принял(а): __________
- Комментарий: __________________________________________
