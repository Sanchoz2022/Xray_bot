<<<<<<< HEAD
# Xray_bot
=======
# Xray VPN Bot with Reality Protocol

A Telegram bot that provides VPN access through Xray with VLESS and Reality protocol. The bot generates unique VLESS configuration URLs for users who are subscribed to a specific Telegram channel.

## ✨ Features

- 🤖 User-friendly Telegram bot interface
- 🔒 Secure VLESS protocol with Reality transport
- 🌐 No domain or CDN required
- 📊 User management and subscription system
- 📱 Easy-to-use configuration generator
- ⚙️ Automatic server deployment and management
- 🔄 Background tasks for subscription checks and service monitoring
- 📈 Traffic usage statistics
- 🛡️ gRPC API for dynamic user management

## 🚀 Prerequisites

- Ubuntu/Debian VPS (recommended: Ubuntu 20.04/22.04 LTS)
- Python 3.10+
- Root access to the server
- Port 443 open (for VLESS traffic)
- Port 50051 open (for gRPC API, localhost only by default)
- Telegram Bot Token from [@BotFather](https://t.me/botfather)
- Telegram channel for subscription verification

## 🛠 Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Sanchoz2022/Xray_bot.git
   cd Xray_bot
   ```

2. **Run the setup script**
   ```bash
   chmod +x setup.sh
   sudo ./setup.sh
   ```
   This will:
   - Install Xray with Reality support
   - Set up a Python virtual environment
   - Install all required dependencies
   - Generate necessary configuration files
   - Create a systemd service for the bot

3. **Configure the bot**
   Copy the example environment file and update it with your details:
   ```bash
   cp .env.example .env
   nano .env
   ```
   
   Update the following values:
   ```
   # Telegram Bot Settings
   BOT_TOKEN=your_bot_token_here
   ADMIN_IDS=your_telegram_id_here
   CHANNEL_USERNAME=your_channel_username
   
   # Server Settings
   SERVER_IP=your_server_ip
   SERVER_DOMAIN=your_domain.com  # Optional, for better UX
   
   # Subscription Settings
   DEFAULT_SUBSCRIPTION_DAYS=30
   DEFAULT_DATA_LIMIT_GB=100
   ```bash
   nano /usr/local/etc/xray/config.json
   ```
   Replace `yourdomain.com` with your actual domain.

5. **Start the bot**
   ```bash
   sudo systemctl start xray-bot
   ```

## Usage

### User Commands

- `/start` - Start the bot and check subscription
- `/help` - Show help message
- `/status` - Check your subscription status

### Admin Commands

- `/admin` - Open admin panel
  - View statistics
  - Manage users
  - Monitor server status

## Project Structure

```
.
├── bot.py                # Main bot application
├── config.py             # Configuration settings
├── db.py                 # Database operations
├── server_manager.py     # Server and Xray management
├── requirements.txt      # Python dependencies
├── setup.sh              # Setup script
└── README.md             # This file
```

## Security Considerations

- 🔑 Always use strong, unique passwords
- 🔄 Keep the system and dependencies updated
- 🔒 Use a non-root user for running the bot in production
- 🔐 Regularly back up your database and configuration
- 🛡️ Configure a firewall to allow only necessary ports

## Troubleshooting

### Common Issues

1. **Bot not starting**
   - Check logs: `journalctl -u xray-bot -f`
   - Verify bot token in `.env`
   - Check if port is in use: `sudo lsof -i :5000`

2. **Xray service not running**
   - Check status: `systemctl status xray`
   - View logs: `journalctl -u xray -f`
   - Verify config: `xray -test -config /usr/local/etc/xray/config.json`

3. **SSL certificate issues**
   - Check certificate path and permissions
   - Renew certificate: `certbot renew --dry-run`

## Contributing

1. Fork the repository
2. Create a new branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'Add some feature'`
4. Push to the branch: `git push origin feature/your-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, please open an issue in the GitHub repository or contact the maintainer.

---

<div align="center">
  Made with ❤️ by Your Name
</div>
>>>>>>> 6e1774d (Первый коммит)
