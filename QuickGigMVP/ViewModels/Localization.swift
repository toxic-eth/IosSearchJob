import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case uk
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uk: return "Українська"
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

func resolvedLanguage(from rawValue: String) -> AppLanguage {
    AppLanguage(rawValue: rawValue) ?? .uk
}

enum I18n {
    static func t(_ key: String, _ language: AppLanguage) -> String {
        let value = table[key] ?? (uk: key, ru: key, en: key)
        switch language {
        case .uk: return value.uk
        case .ru: return value.ru
        case .en: return value.en
        }
    }

    private static let table: [String: (uk: String, ru: String, en: String)] = [
        "tab.shifts": ("Зміни", "Смены", "Shifts"),
        "tab.activity": ("Активність", "Активность", "Activity"),
        "tab.notifications": ("Сповіщення", "Уведомления", "Notifications"),
        "tab.profile": ("Профіль", "Профиль", "Profile"),

        "mode.list": ("Списком", "Списком", "List"),
        "mode.map": ("На мапі", "На карте", "Map"),
        "search.placeholder": ("Пошук за назвою або описом", "Поиск по названию или описанию", "Search by title or description"),
        "format.all": ("Усі", "Все", "All"),
        "format.online": ("Онлайн", "Онлайн", "Online"),
        "format.offline": ("Офлайн", "Офлайн", "Offline"),
        "filters.no_results": ("Нічого не знайдено. Спробуйте змінити місто або фільтри.", "Ничего не найдено. Попробуйте изменить город или фильтры.", "Nothing found. Try changing city or filters."),
        "filters.min_pay": ("Мін. оплата", "Мин. оплата", "Min pay"),
        "filters.max_duration": ("Макс. тривалість", "Макс. длительность", "Max duration"),
        "filters.verified": ("Лише перевірені роботодавці", "Только проверенные работодатели", "Verified employers only"),
        "filters.max_distance": ("Макс. дистанція", "Макс. дистанция", "Max distance"),
        "filters.distance_km": ("км", "км", "km"),

        "summary.available_now": ("доступно зараз", "доступно сейчас", "available now"),
        "summary.city_radius": ("Показуємо тільки вакансії у радіусі обраного міста.", "Показываем только вакансии в радиусе выбранного города.", "Only shifts within selected city radius are shown."),

        "empty.city": ("У цьому місті поки немає змін за вибраними фільтрами", "В этом городе пока нет смен по выбранным фильтрам", "No shifts in this city for selected filters"),

        "onb.skip": ("Пропустити", "Пропустить", "Skip"),
        "onb.next": ("Далі", "Далее", "Next"),
        "onb.pick_role": ("Оберіть роль, щоб продовжити", "Выберите роль, чтобы продолжить", "Choose a role to continue"),
        "onb.quick_title": ("Швидкий старт у зміні", "Быстрый старт в сменах", "Fast start in shifts"),
        "onb.quick_sub": ("Знаходьте підробіток поруч, відгукуйтесь за хвилину та виходьте вже сьогодні або завтра.", "Находите подработку рядом, откликайтесь за минуту и выходите уже сегодня или завтра.", "Find nearby gigs, apply in a minute, and start today or tomorrow."),
        "onb.clear_title": ("Прозорі умови", "Прозрачные условия", "Transparent conditions"),
        "onb.clear_sub": ("Оплата, час, адреса та опис задачі видно до відгуку. Жодних сюрпризів на місці.", "Оплата, время, адрес и описание видны до отклика. Никаких сюрпризов на месте.", "Pay, time, address, and task details are visible before applying."),
        "onb.safe_title": ("Безпека виплат", "Безопасность выплат", "Payment safety"),
        "onb.safe_sub": ("Після підтвердження виконаної зміни ви гарантовано отримуєте оплату. Ми фіксуємо домовленості в застосунку.", "После подтверждения выполненной смены вы гарантированно получаете оплату. Мы фиксируем договоренности в приложении.", "After shift completion is confirmed, payment is guaranteed. Agreements are recorded in the app."),
        "onb.role_title": ("Хто ви в QuickGig?", "Кто вы в QuickGig?", "Who are you in QuickGig?"),
        "onb.role_sub": ("Оберіть сценарій входу. Ми покажемо тільки потрібні поля реєстрації та функції.", "Выберите сценарий входа. Мы покажем только нужные поля и функции.", "Choose your flow. We will show only relevant sign-in fields and features."),
        "onb.worker": ("Я шукаю підробіток", "Я ищу подработку", "I am looking for work"),
        "onb.employer": ("Я роботодавець", "Я работодатель", "I am an employer"),

        "settings.title": ("Налаштування", "Настройки", "Settings"),
        "settings.appearance": ("Зовнішній вигляд", "Внешний вид", "Appearance"),
        "settings.theme": ("Тема", "Тема", "Theme"),
        "settings.notifications": ("Сповіщення", "Уведомления", "Notifications"),
        "settings.local_notifications": ("Локальні сповіщення", "Локальные уведомления", "Local notifications"),
        "settings.language": ("Мова", "Язык", "Language"),
        "settings.security": ("Безпека", "Безопасность", "Security"),
        "settings.security.email": ("Email для підтвердження", "Email для подтверждения", "Email for verification"),
        "settings.security.save_email": ("Зберегти email", "Сохранить email", "Save email"),
        "settings.done": ("Готово", "Готово", "Done"),

        "theme.dark": ("Темна", "Тёмная", "Dark"),
        "theme.light": ("Світла", "Светлая", "Light"),

        "profile.title": ("Профіль", "Профиль", "Profile"),
        "profile.settings": ("Налаштування", "Настройки", "Settings"),
        "profile.resume": ("Резюме", "Резюме", "Resume"),
        "profile.resume_placeholder": ("Досвід, навички, бажані задачі...", "Опыт, навыки, желаемые задачи...", "Experience, skills, preferred tasks..."),
        "profile.resume_save": ("Зберегти резюме", "Сохранить резюме", "Save resume"),
        "profile.account": ("Акаунт", "Аккаунт", "Account"),
        "profile.logout": ("Вийти", "Выйти", "Log out"),
        "profile.change_role": ("Змінити тип акаунта", "Сменить тип аккаунта", "Change account type"),
        "profile.reviews": ("Останні відгуки", "Последние отзывы", "Recent reviews"),
        "profile.review_empty": ("Поки немає відгуків", "Пока нет отзывов", "No reviews yet"),
        "profile.write_review": ("Залишити відгук", "Оставить отзыв", "Leave review"),
        "profile.review_for": ("Оберіть користувача", "Выберите пользователя", "Select user"),
        "profile.send": ("Надіслати", "Отправить", "Send")
    ]
}
