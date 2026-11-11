import logging
import os

from dotenv import load_dotenv
from telegram import Update
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

load_dotenv()

BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED_USER_ID = os.getenv("TELEGRAM_ALLOWED_USER_ID", "").strip()

logging.basicConfig(
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger("smc_ict_telegram")


def is_authorized(update: Update) -> bool:
    if not ALLOWED_USER_ID:
        return True
    user = update.effective_user
    return bool(user and str(user.id) == ALLOWED_USER_ID)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_authorized(update):
        await update.effective_message.reply_text("غير مصرح لك باستخدام هذا البوت.")
        return

    await update.effective_message.reply_text(
        "مرحباً بك في بوت SMC-ICT EURUSD.\n"
        "حالة Telegram: متصل ويعمل.\n"
        "حالة MT5: غير مربوط حالياً.\n"
        "التداول: معطّل — نسخة متابعة فقط.\n\n"
        "الأوامر المتاحة حالياً:\n"
        "/start - بدء التشغيل\n"
        "/status - عرض الحالة"
    )


async def status(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not is_authorized(update):
        await update.effective_message.reply_text("غير مصرح لك باستخدام هذا البوت.")
        return

    await update.effective_message.reply_text(
        "📊 حالة بوت SMC-ICT\n"
        "Telegram: متصل ✅\n"
        "MT5: غير مربوط ⏳\n"
        "الحساب المستهدف: DEMO فقط\n"
        "الرمز المستهدف: EURUSD\n"
        "تنفيذ الصفقات: معطّل 🔒\n"
        "أوامر الشراء/البيع/الإغلاق: غير مفعّلة"
    )


async def disabled_command(
    update: Update, context: ContextTypes.DEFAULT_TYPE
) -> None:
    if not is_authorized(update):
        await update.effective_message.reply_text("غير مصرح لك باستخدام هذا البوت.")
        return

    await update.effective_message.reply_text(
        "هذا الأمر غير مفعّل في هذه المرحلة. "
        "المتاح حالياً هو /start و /status فقط. "
        "لم يتم إرسال أي أمر تداول إلى MT5."
    )


async def unknown_text(
    update: Update, context: ContextTypes.DEFAULT_TYPE
) -> None:
    if is_authorized(update):
        await update.effective_message.reply_text(
            "استخدم /start أو /status. التداول معطّل حالياً."
        )


def main() -> None:
    if not BOT_TOKEN:
        raise RuntimeError(
            "TELEGRAM_BOT_TOKEN is missing. Set it in the .env file."
        )

    application = Application.builder().token(BOT_TOKEN).build()
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("status", status))
    application.add_handler(MessageHandler(filters.COMMAND, disabled_command))
    application.add_handler(
        MessageHandler(filters.TEXT & ~filters.COMMAND, unknown_text)
    )

    logger.info("Telegram bot starting; trading functions are disabled.")
    application.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
