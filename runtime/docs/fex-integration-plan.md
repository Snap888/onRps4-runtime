# План интеграции FEXCore в onRps4-runtime

**Репозиторий:** https://github.com/Snap888/onRps4-runtime  
**Базовая ветка:** `ps4emu`  
**Рабочая ветка:** `fex-core-integration`  
**Рабочая директория:** `runtime/`  
**Источник лучших практик:** https://github.com/Snap888/Bloodborne-Android/tree/master/cpu  

**Дата создания:** 24 октября 2026  
**Статус документа:** Живой план  
**Текущая фаза:** 0 — Анализ и подготовка (основной анализ выполнен)

**Базовый SHA ветки `ps4emu` на момент ответвления:** `22ee8422926b5960f9767a3d99eefe0373aa0067`

---

## Как пользоваться этим файлом

- Отмечайте выполненные пункты: `- [x]`
- Добавляйте дату и краткий комментарий рядом с выполненным пунктом
- В конце каждого этапа обновляйте раздел **«Статус этапа»**
- При значительных изменениях в репозитории — обновляйте ссылки и разделы «Текущее состояние»
- Ведите лог изменений в самом низу файла

---

## 1. Текущее состояние репозитория (ps4emu)

### Структура `runtime/`

| Путь | Описание |
|------|----------|
| `runtime/build/` | Артефакты сборки (box64-host-stage, fexcore-smoke-stage и др.) |
| `runtime/scripts/` | Скрипты сборки Box64, FEX, shadPS4, Turnip, Vortek |
| `runtime/sources/shadps4/` | Vendored исходники shadPS4 (уже содержит FEX guest_cpu слой) |
| `runtime/sources/fex/` | Checkout FEX (через components.lock) |
| `runtime/patches/` | Патчи (в т.ч. `fex-fexcore-only.patch`) |
| `runtime/locks/components.lock.json` | Зафиксированные ревизии компонентов |
| `runtime/settings/` | Настройки |
| `runtime/kotlin/` | Kotlin-часть (Android) |
| `runtime/probes/` | Smoke/probe-тесты (`fexcore-smoke.cpp`, `fexcore-guest-harness.cpp`) |
| `runtime/tests/` | Верификаторы сборки |
| `runtime/docs/` | Документация (этот план) |

### Ключевые скрипты

| Скрипт | Назначение |
|--------|------------|
| `build-box64.sh` | Сборка Box64 под Android NDK (`libbox64.so`) |
| `build-box64-host.sh` | Host-stage Box64 (glibc aarch64) |
| `build-fexcore-smoke-aarch64.sh` | Сборка FEXCore-only + smoke + guest-harness |
| `build-shadps4-x86_64.sh` | Сборка x86_64 shadPS4 |
| `build-shadps4-arm64.sh` | Сборка ARM64 shadPS4 (FEX-путь) |
| `package-runtime.mjs` | Упаковка runtime.zip + патчи glibc |
| `stage-debian-runtime.mjs` | Staging Debian rootfs |
| `checkout-component.sh` | Checkout компонента по lock-файлу |

### Зафиксированные ревизии (`components.lock.json`)

| Компонент | Ревизия | Репозиторий |
|-----------|---------|-------------|
| **fex** | `f2b679f6028ce1c38875233aecfcf5d3f8ebecec` | https://github.com/FEX-Emu/FEX.git |
| box64 | `50c8b90b09b433ab0767de44af2d0731cb0748b7` | https://github.com/ptitSeb/box64.git |
| vortek-client | `ab7329c4b445a4abd9b9af91b8148e1ca41464fa` | https://github.com/brunodev85/vortek.git |

### Уже существующий FEX-слой внутри shadPS4

**`src/core/guest_cpu/`**

- `fex_guest_cpu.cpp` / `.h` — backend поверх `Fex::GuestEngine`
- `fex_hle_bridge.cpp` / `.h` — `HleGuestBridge` (реестр HLE, host ranges)
- `hle_call_adapter.cpp` / `.h` — typed adapters, veneers, SysV decode
- `guest_cpu.cpp` / `.h` — абстрактный `GuestCpuBackend`
- `guest_callback.h`, `guest_memory_validation_cache.h`

**`src/core/fex/`**

- `fex_guest_engine.cpp` / `.h` — FEX Context/Thread, сигналы Orbis, CallGuest

### Источник лучших практик (Bloodborne-Android)

| Файл | Назначение |
|------|------------|
| `cpu/bbcpu.cmake` | Сборка `libbbcpu` |
| `cpu/fex_project.cmake` | Настройка сборки FEX |
| `cpu/guest_cpu_fex.cpp` | Основная обёртка FEXCore |
| `cpu/host_call_arm64.S` | Ассемблерный мост SysV → AAPCS64 |

---

## 2. Цели интеграции

1. Усилить и унифицировать уже существующий FEX-путь (`guest_cpu` + `fex_guest_engine`) идеями из Bloodborne-Android.
2. Сохранить Box64 как надёжный fallback.
3. Снизить оверхед трансляции на hot path HLE.
4. Сделать сборку FEXCore более «библиотечной» и переиспользуемой (по возможности).
5. Интегрировать всё в существующий pipeline (`scripts/` + `package-runtime.mjs` + lock-файл).

---

## 3. Этапы работ

### Этап 0. Анализ и подготовка

**Статус этапа:** ✅ Основной анализ выполнен (24.10.2026)

#### Чеклист

- [x] Изучить `build-fexcore-smoke-aarch64.sh` (24.10.2026)
- [x] Изучить подключение Box64 и dual-path в `package-runtime.mjs` (24.10.2026)
- [x] Сравнить версию FEX (ps4emu vs Bloodborne) (24.10.2026)
- [x] Проанализировать `fex-fexcore-only.patch` (24.10.2026)
- [x] Проанализировать guest_cpu слой в shadPS4 (24.10.2026)
- [x] Сравнить с Bloodborne `guest_cpu_fex.cpp` + `host_call_arm64.S` (24.10.2026)
- [x] Зафиксировать SHA ветки `ps4emu` при ответвлении: `22ee8422926b5960f9767a3d99eefe0373aa0067`
- [x] Создать рабочую ветку `fex-core-integration`
- [x] Создать `runtime/docs/fex-integration-plan.md`
- [ ] Прочитать `fex_guest_engine.cpp` (Impl): SyscallHandler, stubs/veneers, invalidation
- [ ] Понять выбор пути Box64 vs FEX в runtime (Kotlin / settings)

#### Ключевые выводы Этапа 0

1. В ps4emu уже есть **два CPU-пути**: Box64 + x86_64 shadPS4 и FEX + ARM64 shadPS4.
2. FEX уже частично интегрирован (`guest_cpu` + `fex_guest_engine`).
3. Сборка FEXCore вынесена в smoke-скрипт с `BUILD_FEXCORE_ONLY`.
4. Bloodborne даёт более лёгкую модель (`libbbcpu` + `host_call_arm64.S` + SyscallHandler) — использовать как **референс**, не как drop-in.
5. **Не начинаем с нуля:** улучшаем существующий слой, не переписываем.

#### Архитектурное сравнение

| Аспект | ps4emu (shadPS4 guest_cpu) | Bloodborne (libbbcpu) |
|--------|----------------------------|------------------------|
| Модель | Слоистый C++: Backend → Engine → Bridge | Плоский C API |
| HLE | Реестр + typed adapters + veneers | Stubs 16 B + `SyscallHandler` |
| Host call | C++ `HleCallFrame` + `CallCursor` | `bbcpu_host_call` (asm) |
| Сборка | `BUILD_FEXCORE_ONLY` + harness | `libbbcpu.so` внутри FEX CMake |
| Цель | Полный PS4 userland | Одна игра |

#### Таблица: есть / не хватает / лучше у Bloodborne

| Компонент | ps4emu | Bloodborne | Действие Этапа 1–2 |
|-----------|--------|------------|---------------------|
| FEX Context/Thread lifecycle | ✅ `GuestEngine` | ✅ `Context::CreateThread` | Оставить ps4emu |
| Guest → Host call | ✅ typed HLE + veneers | ✅ stubs + syscall | Улучшить маршалинг (опц. asm) |
| Host → Guest call | ✅ `CallGuest` | ✅ `guest_cpu_call` | Оставить ps4emu |
| Syscall trap | ❓ проверить Impl | ✅ Fatal на real syscall | Аудит + усиление |
| Code invalidation | ✅ API есть | ✅ multi-thread | Сверить семантику |
| Signal handling | ✅ Orbis + guest | ✅ host JIT/unaligned | Перенять host-side при нужде |
| Build as library | ❌ smoke binary | ✅ `libbbcpu.so` | Низкий приоритет |
| NDK vs gnu | FEX = aarch64-linux-gnu | Android/NDK path | Не смешивать без нужды |

#### Что сильно в ps4emu

- Полный lifecycle: CreateThread / Run / CallGuest / Invalidate / DestroyThread
- HLE: typed adapters, валидация указателей, publish/revoke host ranges, ENOSYS→0
- Сигналы Orbis: `DeliverGuestOrbisSignal`, `FlushPendingGuestOrbisSignal`, query RIP/syscall
- Pipeline: lock, smoke, package-runtime

#### Кандидаты на перенос идей из Bloodborne

1. **host_call_arm64.S** — hot path с float/vector и >6 args
2. **Жёсткий trap настоящих syscall** — Fatal вместо silent path
3. **Multi-thread code invalidation** — сверить с текущим `Invalidate`
4. **Host-side fault handling** — JIT guard page, unaligned SIGBUS

---

### Этап 1. Подготовка инфраструктуры / усиление FEX-пути

**Статус этапа:** ⏳ Не начат

**Цель:** усилить `guest_cpu` / `fex`, не создавать новый `runtime/cpu/` с нуля.

- [ ] Детальный разбор `fex_guest_engine.cpp` (SyscallHandler, veneers, invalidation)
- [ ] Определить, нужен ли перенос `host_call_arm64.S` (или достаточно C++)
- [ ] Решить: оставить `BUILD_FEXCORE_ONLY` или добавить более «библиотечный» target
- [ ] Обновить `build-fexcore-smoke-aarch64.sh` при необходимости

---

### Этап 2. Улучшение стабов, HLE-bridge и host-call

**Статус этапа:** ⏳ Не начат

- [ ] Аудит `hle_call_adapter` + `fex_hle_bridge` vs Bloodborne CallHost
- [ ] Усилить защиту от настоящих syscall
- [ ] Опционально: asm host_call для hot path
- [ ] Улучшить регистрацию host-функций / veneers при необходимости

---

### Этап 3. Интеграция в pipeline runtime.zip

**Статус этапа:** ⏳ Не начат

- [ ] Проверить `package-runtime.mjs` после изменений
- [ ] Уточнить переключение Box64 ↔ FEX (settings / env / Kotlin)
- [ ] Совместимость с Vortek и glibc-патчами

---

### Этап 4. Оптимизации и стабилизация

**Статус этапа:** ⏳ Не начат

- Code cache, invalidation, хуки, сигналы, TSC, multithreading

---

### Этап 5. Тестирование и квалификация

**Статус этапа:** ⏳ Не начат

- `runtime/tests/`, `runtime/probes/`, qualification / evidence

---

### Этап 6. Документация и релиз

**Статус этапа:** ⏳ Не начат

---

## 4. Технические детали

### Как сейчас собирается FEXCore

```bash
# Упрощённо из build-fexcore-smoke-aarch64.sh
cmake -S runtime/sources/fex -B runtime/build/fexcore-smoke-build -G Ninja \
  -DCMAKE_SYSTEM_NAME=Linux \
  -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_COMPILER_TARGET=aarch64-linux-gnu \
  -DCMAKE_CXX_COMPILER_TARGET=aarch64-linux-gnu \
  -DBUILD_FEXCORE_ONLY=ON \
  -DFEXCORE_PROJECT_SOURCE_DIR=.../sources/shadps4/src \
  -DFEXCORE_GUEST_HARNESS_SOURCES="fex_guest_engine.cpp;fex_guest_cpu.cpp;hle_call_adapter.cpp;fex_hle_bridge.cpp;..." \
  -DBUILD_THUNKS=OFF \
  -DBUILD_TESTING=OFF
```

### Что кладётся в runtime.zip (релевантное)

| Путь в zip | Источник |
|------------|----------|
| `host/box64` | host-stage Box64 |
| `host/fexcore-smoke` | smoke-сборка FEX |
| `host/shadps4-arm64-fex` | ARM64 shadPS4 (FEX-путь) |
| `bin/shadps4` | x86_64 shadPS4 (Box64-путь) |

### Два параллельных пути запуска

| Путь | Транслятор | Бинарник shadPS4 |
|------|------------|------------------|
| Классический | Box64 | x86_64 `shadps4` |
| FEX | FEXCore | ARM64 `shadps4-arm64-fex` |

---

## 5. Риски

| Риск | Статус | Комментарий |
|------|--------|-------------|
| Разница версий FEX (Bloodborne vs ps4emu) | Открыт | Переносим паттерны, не код 1-в-1 |
| Сложность существующего guest_cpu | Открыт | Аккуратный diff, не «переписать всё» |
| Регрессии текущего FEX-пути | Открыт | Изменения за флагом / сохранение поведения |
| Cross-compile vs NDK | Открыт | FEX = aarch64-linux-gnu, Box64 = NDK |

---

## 6. Следующие конкретные действия

1. Прочитать `runtime/sources/shadps4/src/core/fex/fex_guest_engine.cpp` (SyscallHandler, veneers).
2. Найти переключатель Box64 / FEX в Kotlin и settings.
3. Составить короткий список патчей Этапа 1 (syscall trap, optional host_call).
4. Только после этого — код Этапа 1.

---

## 7. Лог изменений этого документа

| Дата | Что изменено | Автор |
|------|--------------|-------|
| 2026-10-24 | Создан документ; заполнен Этап 0; сравнение с Bloodborne | Grok |
| 2026-10-24 | Ветка `fex-core-integration` от `ps4emu@22ee842`; файл в `runtime/docs/` | Grok |
