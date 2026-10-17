import Foundation

enum L10n {
    private static var russian: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("ru") == true
    }

    static func t(_ en: String, _ ru: String) -> String { russian ? ru : en }

    static var connectTitle: String { t("Computer address running the server", "Адрес компьютера, где запущен сервер") }
    static var connect: String { t("Connect", "Подключиться") }
    static var stop: String { t("Stop", "Стоп") }
    static var layout: String { t("Layout", "Раскладка") }
    static var done: String { t("Done", "Готово") }
    static var sizeOf: String { t("Size", "Размер") }
    static var resetLayout: String { t("Reset", "Сбросить") }
    static var editHint: String { t("Drag to move. The slider resizes the selected control. Remove it, or add one back.", "Тяните, чтобы сдвинуть. Ползунок меняет размер. Кнопку можно убрать и вернуть.") }
    static var addControl: String { t("Add", "Добавить") }
    static var removeControl: String { t("Remove", "Убрать") }
    static var exportLayout: String { t("Export", "Экспорт") }
    static var importLayout: String { t("Import", "Импорт") }
    static var importFailed: String { t("That file is not a layout.", "Этот файл не является раскладкой.") }
    static var pickControl: String { t("Drag any control", "Потяните любой элемент") }
    static var scanHint: String { t("Point the camera at the code on the computer", "Наведите камеру на код на компьютере") }
    static var enterManually: String { t("Enter address", "Ввести адрес") }
    static var scanCode: String { t("Scan code", "Сканировать код") }
    static var cameraDenied: String { t("Camera access is off. Enter the address instead.", "Нет доступа к камере. Введите адрес вручную.") }
    static func controlName(_ id: String) -> String {
        switch id {
        case "ls": return t("Left stick", "Левый стик")
        case "rs": return t("Right stick", "Правый стик")
        case "l3": return "L3"
        case "r3": return "R3"
        case "dpad": return t("D-pad", "Крестовина")
        case "lt": return "LT"
        case "rt": return "RT"
        case "lb": return "LB"
        case "rb": return "RB"
        case "back": return "Back"
        case "start": return "Start"
        case "guide": return "Guide"
        default: return id.uppercased()
        }
    }
    static var offline: String { t("offline", "нет связи") }
    static var connecting: String { t("connecting…", "подключение…") }
    static func connectedTo(_ host: String) -> String { t("Connected to \(host)", "Подключено к \(host)") }
    static func connectedPad(_ host: String) -> String { t("Connected to \(host) · controller", "Подключено к \(host) · свой геймпад") }
    static var close: String { t("Close", "Закрыть") }
    static var taken: String { t("pad is in use on another phone", "геймпад занят другим телефоном") }
    static var badAddress: String { t("invalid address", "неверный адрес") }
    static var needAddress: String { t("enter an address and port", "укажите адрес и порт") }
    static var port: String { t("Port", "Порт") }
    static var home: String { t("Home", "Главная") }
    static var settings: String { t("Settings", "Настройки") }
    static var haptics: String { t("Haptics", "Виброотклик") }
    static var intensity: String { t("Intensity", "Интенсивность") }
    static var play: String { t("Play", "Играть") }
    static var edit: String { t("Edit", "Изменить") }
    static var createLayout: String { t("New layout", "Новая раскладка") }
    static var layoutName: String { t("Name", "Название") }
    static var create: String { t("Create", "Создать") }
    static var cancel: String { t("Cancel", "Отмена") }
    static var delete: String { t("Delete", "Удалить") }
    static var disconnect: String { t("Disconnect", "Отключиться") }
    static var presets: String { t("Presets", "Пресеты") }
    static var myLayouts: String { t("My layouts", "Мои раскладки") }
    static var untitled: String { t("Layout", "Раскладка") }
    static var presetStandard: String { t("Standard", "Стандарт") }
    static var presetLefty: String { t("Lefty", "Левша") }
    static var savedLayout: String { t("Saved", "Сохранённая") }
}
