# Исправление ключей Reality

## Проблема
В config.json на сервере и .env файле используются разные ключи Reality, что препятствует подключению.

## Решение

### Вариант 1: Получить публичный ключ для существующего приватного ключа
Выполните на сервере:
```bash
echo "gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI" | xray x25519 -i
```

Затем обновите XRAY_REALITY_PUBKEY в .env файле полученным значением.

### Вариант 2: Сгенерировать новую пару ключей
1. Выполните на сервере:
```bash
xray x25519
```

2. Обновите config.json на сервере с новым privateKey
3. Обновите .env файл с новыми ключами
4. Перезапустите xray: `sudo systemctl restart xray`

### Текущие ключи в config.json:
- privateKey: `gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI`
- shortId: `f81bd29d3685d224`

### Обновленные ключи в .env:
- XRAY_REALITY_PRIVKEY: `gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI`
- XRAY_REALITY_SHORT_IDS: `["", "f81bd29d3685d224"]`
- XRAY_REALITY_PUBKEY: нужно получить правильный
