# QuickGig Backend API (Laravel)

## Stack
- Laravel 12
- Sanctum token auth
- SQLite (default)

## Quick start
```bash
cd backend
cp .env.example .env
php artisan key:generate
php artisan migrate:fresh --seed
php artisan serve
```

API base URL: `http://127.0.0.1:8000/api`

## Demo accounts
- Worker: `380673334455` / `123456`
- Employer: `380671112233` / `123456`

## Endpoints
### Public
- `POST /register`
- `POST /login`
- `GET /shifts`
- `GET /shifts/{id}`

### Auth (`Authorization: Bearer <token>`)
- `GET /me`
- `POST /logout`
- `POST /shifts` (employer)
- `GET /my/shifts` (employer)
- `POST /shifts/{id}/apply` (worker)
- `GET /my/applications` (worker)
- `PATCH /applications/{id}/status` (employer)
- `POST /reviews`

## Example login
```bash
curl -X POST http://127.0.0.1:8000/api/login \
  -H 'Content-Type: application/json' \
  -d '{"phone":"380673334455","password":"123456"}'
```
