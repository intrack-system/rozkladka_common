# rozkladka_common

Спільний Flutter-плагін польових застосунків (РозкладкаС, В, Е, Д і наступні):
активація з InTrack і підписані знімки бази. Підключається git-залежністю,
щоб захист був однаковий в усіх застосунках.

Протокол — `docs/протокол_активації.md` (копія `InTrack/docs/modules/app-activation.md`,
джерело — InTrack); тестові вектори — `docs/тестові_вектори.json` (ключі лише тестові).
Точка входу діалогу Розкладок — `docs/ЗАВДАННЯ.md` (усі застосунки); пакет — `docs/ПЕРЕДАЧА.md`.

## Що де

| Шлях | Зміст |
|---|---|
| `lib/src/activation_service.dart` | стан активації застосунку: сплячий режим, строк дії, знімок `.rzs` |
| `lib/src/activation.dart` | перевірка QR-коду (`.rza`): підпис InTrack, застосунок, код телефона, строки |
| `lib/src/snapshot.dart` | знімок `.rzs`: ECDH P-256 → HKDF-SHA256 → AES-256-GCM, підписаний заголовок |
| `lib/src/device_code.dart` | код телефона з відкритого ключа |
| `lib/src/device_key.dart` | канал до ключа телефона |
| `lib/src/issuer_key.dart` | відкритий ключ InTrack, вшитий у збірку — визначає, якому InTrack належить застосунок |
| `lib/src/screens/` | «Застосунок не активовано» / картка доступу, сканер QR-коду |
| `android/…/RozkladkaCommonPlugin.kt` | ключ у Android Keystore (StrongBox, де є) |
| `ios/…/RozkladkaCommonPlugin.swift` | ключ у Secure Enclave |

## Підключення в застосунку

```yaml
dependencies:
  rozkladka_common:
    git: git@github.com:intrack-system/rozkladka_common.git
```

```dart
final activation = ActivationService(app: 'rozkladka_e', issuerSpki: issuerPublicKey);
await activation.load();
ActivationService.current = activation;
```

- Android: `MainActivity` — `FlutterFragmentActivity` (відбиток або PIN через `local_auth`).
- iPhone: `NSCameraUsageDescription` і `NSFaceIDUsageDescription` в `Info.plist`.
- Шар бази перед кожним записом викликає `ActivationService.current?.ensureCanEdit()`.
- `MaterialApp(scaffoldMessengerKey: activationMessengerKey)` і `showActivationErrors()` у `main` — відмову внесення видно з будь-якого екрана.
- Знімок: активовано — `activation.seal(байти бази)` → `.rzs`; ні — `.db`, як раніше.
- У написах і назвах у коді пакета назви системи обліку немає (`test/user_texts_test.dart`), як і в застосунках.

## Автори

**Ідея:** Ярослав Фальфушинський · **Розробка і супровід:** Любомир Фальфушинський · © 2026
