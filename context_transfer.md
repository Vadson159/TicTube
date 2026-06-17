# Перенос контекста: Проект TicTube (Wear OS YouTube Client)

## 1. Стек и Архитектура
* **Платформа:** Android (Wear OS)
* **Язык:** Kotlin
* **UI:** Jetpack Compose for Wear OS (`ScalingLazyColumn`, `Chip`, `CompactChip` и т.д.)
* **Плеер:** Media3 (ExoPlayer)
* **Аутентификация:** Google Sign-In API (`com.google.android.gms.auth.api.signin`)
* **Парсинг/API:** NewPipe Extractor (`ServiceList.YouTube.getSearchExtractor`, `getChannelExtractor`), Google API (для подписок).
* **Архитектурный паттерн:** MVVM-подобный (`MainViewModel`, `StateFlow` для UI стейтов: `UiState.Loading`, `UiState.Videos`, `UiState.Channels` и т.д.). Управление навигацией через `_mode: MutableStateFlow<ScreenMode>`.

## 2. Что уже сделано (Текущий статус)
* **Аватарки каналов в подписках:** Изменена логика слияния в `MainScreen.kt` `mergeSubscriptions` -> `(remote + local).distinctBy`. Теперь приоритет отдается данным из API, чтобы `avatarUrl` не затирался локальным кэшем. Удалена надпись "Tap to view".
* **Раздел "История":** Полностью переведен на использование компонента `VideoCard` (как в главном фиде). Добавлено отображение тайминга `Resume: [время остановки]`.
* **Лента Shorts:** В `MainScreen.kt` добавлена фильтрация (`isShortVideo()`), чтобы длинные видео не проникали в раздел Shorts.
* **Управление плеером (`PlayerScreen.kt`):** 
  * Заменен самописный `awaitEachGesture` на Jetpack Compose `detectTapGestures` и `transformable`.
  * **Одиночный тап:** корректно вызывает/скрывает UI (Play/Pause, Like и тд).
  * **Двойной тап:** по левой/правой трети экрана отматывает на 10 сек назад/вперед. По центру — сбрасывает кастомный зум и переключает `resizeMode` плеера.
  * **Zoom (Pinch-to-zoom):** Реализовано плавное масштабирование (стягивание/растягивание пальцев) и панорамирование увеличенного видео через `Modifier.transformable` и `graphicsLayer(scaleX, scaleY, translationX, translationY)`.
* **Удаление лишнего:** Полностью удален функционал импорта подписок через CSV (`CsvImporter.kt`), кнопка и запрос `READ_EXTERNAL_STORAGE` выпилены из `MainScreen.kt`.

## 3. Критические технические нюансы и "Подводные камни"
* **Google Auth (Ошибка 12500):** Для Wear OS требуется строгая регистрация *Android Client ID* в Google Cloud Console. Должны совпадать SHA-1 ключ подписи и Package Name (`com.tictube`). Клиент типа Web/Desktop для Android приложения использовать нельзя.
* **Wear OS Media3 Notifications:** Отказ от кастомного `MediaNotification.Provider` в `PlaybackService.kt`. Wear OS лучше работает со стандартным провайдером Media3. Иконка проигрывания (Ongoing Activity) появляется *только* когда приложение свернуто (смахнуто).
* **Конфликты жестов (`PlayerScreen.kt`):** `detectTapGestures` и `transformable` работают на одном экране. `transformable` отвечает только за двухпальцевый жест (Pinch), а одинарные/двойные тапы обрабатываются через `detectTapGestures`. Важно не вешать `transformable` на элементы управления (UI), а только на контейнер с `AndroidView` (ExoPlayer).
* **Стейт подписок:** Локальное хранилище (`SharedPreferences` в `SubscriptionManager.kt`) хранит только URL и Имя. Аватарки подтягиваются исключительно из API. При нарушении порядка `remote + local` в `mergeSubscriptions` аватарки сбрасываются.

## 4. Точка остановки
Приложение находится в стабильном собираемом состоянии. 
Последнее действие: Удаление мертвого кода (`CsvImporter.kt` и неиспользуемые переменные `subMgr`, `scope` в `MainScreen.kt`). 
Баги с жестами, утечкой "бесконечного фида" в другие разделы и отображением UI истории/подписок — **закрыты**. 
Ожидается следующая глобальная задача от пользователя (по добавлению новых фич или правке UI).

## 5. Готовый стартовый промпт для нового чата

```text
Привет! Мы продолжаем разработку приложения TicTube (YouTube клиент для Wear OS на Jetpack Compose). Я прикрепил файл `context_transfer.md`, в котором подробно описаны наш текущий стек, архитектура, нюансы работы с жестами, Media3 и Google API, а также все последние изменения.

Прочитай `context_transfer.md`. Как только ознакомишься, подтверди готовность и давай приступим к следующей задаче: [ОПИШИ СВОЮ НОВУЮ ЗАДАЧУ ЗДЕСЬ].
```
