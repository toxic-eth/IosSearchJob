# QuickGig MVP (iOS)

Минимальная версия приложения для подработки на 1+ дней:
- роли: работник/работодатель;
- карта с метками смен;
- фильтры по оплате и длительности;
- создание смен работодателем;
- рейтинг и отзывы 1-5 звезд в обе стороны.

## Mapbox (Stage 1)
- Mapbox SDK подключен через Swift Package Manager (`MapboxMaps`).
- Ключ Mapbox берется из `MBXAccessToken` в Info.plist (сейчас стоит заглушка `YOUR_MAPBOX_PUBLIC_TOKEN`).
- Чтобы изменить ключ: обнови `INFOPLIST_KEY_MBXAccessToken` в `/Users/toxic.eth/Documents/New project/QuickGigMVP/project.yml`.
- После изменений перегенерируй проект:
  - `xcodegen generate`
- Рекомендуемый резолв зависимостей с отдельным кэшем:
  - `xcodebuild -resolvePackageDependencies -project QuickGigMVP.xcodeproj -scheme QuickGigMVP -clonedSourcePackagesDirPath /tmp/quickgig-spm`

## Что внутри
- `QuickGigMVPApp.swift` - точка входа приложения.
- `ContentView.swift` - маршрутизация login/main.
- `Models.swift` - модели пользователя, смены, отзыва.
- `ViewModels/AppState.swift` - in-memory состояние MVP.
- `Views/*.swift` - экраны login, map, add shift, profile, shift detail.

## Запуск (вариант 1: XcodeGen)
1. Установить XcodeGen: `brew install xcodegen`
2. Из папки проекта выполнить: `xcodegen generate`
3. Открыть `QuickGigMVP.xcodeproj` в Xcode.
4. Выбрать iOS Simulator и нажать Run.

## Запуск (вариант 2: вручную в Xcode)
1. Создать новый iOS App проект `QuickGigMVP` (SwiftUI).
2. Добавить в него все `.swift` файлы из этой папки.
3. Запустить на симуляторе.

## Технические ограничения MVP
- Нет backend/базы данных.
- Авторизация локальная (по имени + роли).
- Данные хранятся только в памяти (сбросятся после перезапуска).

## Что логично сделать следующим шагом
1. Firebase/Supabase для auth + хранения вакансий и отзывов.
2. Реальные геоданные и поиск по радиусу.
3. Отклики на смены и статусы (pending/accepted/completed).
