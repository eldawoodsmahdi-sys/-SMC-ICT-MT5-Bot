# SMC-ICT Telegram Status Bot

Read-only Telegram stage for the SMC-ICT EURUSD MT5 demo project.

## Enabled commands
- `/start`: welcome and connection summary.
- `/status`: Telegram/MT5/trading status.

All other commands are rejected. No order is sent to MT5.

## Setup
1. Install Python 3.10 or newer.
2. Install dependencies: `pip install -r requirements.txt`
3. Copy `.env.example` to `.env`.
4. Put your Telegram bot token in `.env`.
5. Optionally set `TELEGRAM_ALLOWED_USER_ID` to your own numeric Telegram user ID.
6. Start the bot: `python bot.py`

## Safety state
- MT5 connection: not implemented in this stage.
- Buy/sell/close: disabled.
- Do not commit `.env` or share the bot token.

This process is separate from the MQL5 Expert Advisor. A separately tested bridge is required before MT5 status or trading can be controlled.
