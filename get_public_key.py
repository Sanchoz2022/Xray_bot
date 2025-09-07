#!/usr/bin/env python3
import subprocess
import re
import os

def get_public_key_from_private(private_key):
    """Попытка получить публичный ключ из приватного через xray x25519"""
    try:
        # Попытка 1: передать приватный ключ через stdin
        result = subprocess.run(
            ['xray', 'x25519', '-i'],
            input=private_key,
            text=True,
            capture_output=True,
            timeout=10
        )
        
        if result.returncode == 0:
            # Парсим вывод
            output = result.stdout
            if 'Password:' in output:
                public_key = re.search(r'Password:\s*(\S+)', output)
                if public_key:
                    return public_key.group(1).strip()
            elif 'Public key:' in output:
                public_key = re.search(r'Public key:\s*(\S+)', output)
                if public_key:
                    return public_key.group(1).strip()
        
        print(f"Ошибка при получении публичного ключа: {result.stderr}")
        return None
        
    except Exception as e:
        print(f"Исключение при выполнении xray x25519: {e}")
        return None

def generate_new_keypair():
    """Генерация новой пары ключей Reality"""
    try:
        result = subprocess.run(
            ['xray', 'x25519'],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode == 0:
            output = result.stdout
            
            # Парсинг для нового формата (PrivateKey/Password)
            private_match = re.search(r'PrivateKey:\s*(\S+)', output)
            public_match = re.search(r'Password:\s*(\S+)', output)
            
            # Парсинг для старого формата (Private key/Public key)
            if not private_match:
                private_match = re.search(r'Private key:\s*(\S+)', output)
            if not public_match:
                public_match = re.search(r'Public key:\s*(\S+)', output)
            
            if private_match and public_match:
                return private_match.group(1).strip(), public_match.group(1).strip()
        
        print(f"Ошибка при генерации новых ключей: {result.stderr}")
        return None, None
        
    except Exception as e:
        print(f"Исключение при генерации ключей: {e}")
        return None, None

def update_env_file(private_key, public_key):
    """Обновление .env файла с новыми ключами"""
    try:
        with open('.env', 'r') as f:
            content = f.read()
        
        # Обновляем ключи
        content = re.sub(r'XRAY_REALITY_PRIVKEY=.*', f'XRAY_REALITY_PRIVKEY={private_key}', content)
        content = re.sub(r'XRAY_REALITY_PUBKEY=.*', f'XRAY_REALITY_PUBKEY={public_key}', content)
        
        with open('.env', 'w') as f:
            f.write(content)
        
        print("✓ .env файл обновлен")
        return True
        
    except Exception as e:
        print(f"Ошибка при обновлении .env: {e}")
        return False

if __name__ == "__main__":
    # Приватный ключ из config.json на сервере
    server_private_key = "gOL6yFxAqJ59nULXaaheXMXh3vOGIsV5-CFyL1iMuGI"
    
    print("Попытка получить публичный ключ для существующего приватного ключа...")
    public_key = get_public_key_from_private(server_private_key)
    
    if public_key:
        print(f"✓ Публичный ключ найден: {public_key}")
        update_env_file(server_private_key, public_key)
    else:
        print("Не удалось получить публичный ключ. Генерируем новую пару...")
        new_private, new_public = generate_new_keypair()
        
        if new_private and new_public:
            print(f"✓ Новые ключи сгенерированы:")
            print(f"  Private: {new_private}")
            print(f"  Public: {new_public}")
            
            update_env_file(new_private, new_public)
            
            print("\n⚠ ВНИМАНИЕ: Необходимо обновить config.json на сервере!")
            print(f"Замените privateKey на: {new_private}")
            print("И перезапустите xray: sudo systemctl restart xray")
        else:
            print("❌ Не удалось сгенерировать ключи")
