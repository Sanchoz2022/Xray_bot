#!/bin/bash

# Скрипт для генерации публичного ключа из приватного ключа Reality

PRIVATE_KEY="gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI"

echo "Генерация публичного ключа из приватного ключа Reality..."
echo "Приватный ключ: $PRIVATE_KEY"

# Попробуем несколько способов получить публичный ключ
echo "Попытка 1: xray x25519 -i"
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | xray x25519 -i 2>/dev/null | grep -E "(Public|Password)" | awk '{print $NF}' | tr -d '\r\n ')

if [ -z "$PUBLIC_KEY" ]; then
    echo "Попытка 2: Генерация новой пары ключей"
    REALITY_OUTPUT=$(xray x25519 2>&1)
    echo "Вывод xray x25519: $REALITY_OUTPUT"
    
    # Парсинг новых ключей
    if echo "$REALITY_OUTPUT" | grep -q "PrivateKey:"; then
        NEW_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "PrivateKey:" | awk '{print $2}' | tr -d '\r\n ')
        NEW_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Password:" | awk '{print $2}' | tr -d '\r\n ')
    elif echo "$REALITY_OUTPUT" | grep -q "Private key:"; then
        NEW_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep "Private key:" | awk '{print $3}' | tr -d '\r\n ')
        NEW_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep "Public key:" | awk '{print $3}' | tr -d '\r\n ')
    fi
    
    echo "Новая пара ключей:"
    echo "Private Key: $NEW_PRIVATE_KEY"
    echo "Public Key: $NEW_PUBLIC_KEY"
    
    # Обновляем .env с новыми ключами
    if [ -n "$NEW_PRIVATE_KEY" ] && [ -n "$NEW_PUBLIC_KEY" ]; then
        sed -i "s/XRAY_REALITY_PRIVKEY=.*/XRAY_REALITY_PRIVKEY=$NEW_PRIVATE_KEY/" .env
        sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$NEW_PUBLIC_KEY/" .env
        echo "✓ .env файл обновлен с новыми ключами"
        
        # Также нужно обновить config.json на сервере
        echo "⚠ ВНИМАНИЕ: Необходимо обновить privateKey в /usr/local/etc/xray/config.json на сервере:"
        echo "Замените: \"privateKey\": \"gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI\""
        echo "На: \"privateKey\": \"$NEW_PRIVATE_KEY\""
    fi
else
    echo "Публичный ключ для существующего приватного ключа: $PUBLIC_KEY"
    sed -i "s/XRAY_REALITY_PUBKEY=.*/XRAY_REALITY_PUBKEY=$PUBLIC_KEY/" .env
    echo "✓ .env файл обновлен с правильным публичным ключом"
fi

echo "Готово!"
