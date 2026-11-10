//+------------------------------------------------------------------+
//| SMC_ICT_EURUSD_DEMO_v1_10.mq5                                    |
//| Safety-first EURUSD-only DEMO Expert Advisor                     |
//| M15 execution | H1 EMA50/EMA200 bias | 0.5% risk | 2R target       |
//| NOTE: Prototype implementation. Compile and test in MT5 Demo.    |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "EURUSD DEMO-only SMC/ICT-inspired EA. M15/H1, risk capped at 0.5%, target 2R."

#include <Trade/Trade.mqh>
CTrade trade;

//--------------------------- FIXED SPECIFICATION --------------------
// These are deliberately constants, not user inputs. Do not change.
#define TRADE_SYMBOL          "EURUSD"
#define ENTRY_TIMEFRAME       PERIOD_M15
#define BIAS_TIMEFRAME        PERIOD_H1
#define FAST_EMA_PERIOD       50
#define SLOW_EMA_PERIOD       200
#define RISK_PERCENT          0.50
#define REWARD_RISK           2.00
#define MAGIC_NUMBER          6111026
#define MAX_SPREAD_POINTS     25
#define MAX_DEVIATION_POINTS  10
#define SWING_LOOKBACK        40
#define PIVOT_STRENGTH        2
#define DAILY_LOSS_LIMIT_PCT  2.00
#define MAX_OPEN_POSITIONS    1
#define MIN_STOP_POINTS       10

int g_fast_ema = INVALID_HANDLE;
int g_slow_ema = INVALID_HANDLE;
datetime g_last_bar = 0;
string g_day_equity_key = "";
string g_day_lock_key = "";

//--------------------------- INITIALIZATION -------------------------
int OnInit()
{
   if(_Symbol != TRADE_SYMBOL)
   {
      Print("BLOCKED: Attach this EA to the exact EURUSD symbol only. Current: ", _Symbol);
      return INIT_FAILED;
   }

   // ACCOUNT_TRADE_MODE_DEMO is required. Contest/real accounts are rejected.
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("BLOCKED: Verified DEMO account required. EA will not initialize.");
      return INIT_FAILED;
   }

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      Print("BLOCKED: Terminal is not connected.");
      return INIT_FAILED;
   }

   g_fast_ema = iMA(TRADE_SYMBOL, BIAS_TIMEFRAME, FAST_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   g_slow_ema = iMA(TRADE_SYMBOL, BIAS_TIMEFRAME, SLOW_EMA_PERIOD, 0, MODE_EMA, PRICE_CLOSE);
   if(g_fast_ema == INVALID_HANDLE || g_slow_ema == INVALID_HANDLE)
   {
      Print("INIT FAILED: Could not create H1 EMA handles. Error=", GetLastError());
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)MAGIC_NUMBER);
   trade.SetDeviationInPoints(MAX_DEVIATION_POINTS);
   trade.SetTypeFillingBySymbol(TRADE_SYMBOL);
   trade.SetAsyncMode(false);

   UpdateDailyKeys();
   if(!GlobalVariableCheck(g_day_equity_key))
      GlobalVariableSet(g_day_equity_key, AccountInfoDouble(ACCOUNT_EQUITY));
   if(!GlobalVariableCheck(g_day_lock_key))
      GlobalVariableSet(g_day_lock_key, 0.0);

   Print("INITIALIZED: EURUSD DEMO only | M15 | H1 EMA50/200 | risk 0.5% | target 2R.");
   Print("Strategy is SMC/ICT-inspired and must be validated in Strategy Tester before use.");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fast_ema != INVALID_HANDLE) IndicatorRelease(g_fast_ema);
   if(g_slow_ema != INVALID_HANDLE) IndicatorRelease(g_slow_ema);
}

//--------------------------- MAIN LOOP ------------------------------
void OnTick()
{
   // Re-check account mode on every tick; changing account blocks further trading.
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
      return;

   UpdateDailyKeys();
   if(!IsNewM15Bar()) return;
   if(!SafetyChecks()) return;
   if(CountOurPositions() >= MAX_OPEN_POSITIONS) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   const int required = SWING_LOOKBACK + PIVOT_STRENGTH + 8;
   int copied = CopyRates(TRADE_SYMBOL, ENTRY_TIMEFRAME, 0, required, rates);
   if(copied < required)
   {
      Print("NO TRADE: Insufficient M15 history. Bars copied=", copied, " required=", required);
      return;
   }

   double swing_high = 0.0, swing_low = 0.0;
   int high_shift = -1, low_shift = -1;
   if(!FindLatestConfirmedSwings(rates, copied, swing_high, swing_low, high_shift, low_shift))
   {
      Print("NO TRADE: Confirmed swing high/low unavailable.");
      return;
   }

   double fast[3], slow[3];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(g_fast_ema, 0, 0, 3, fast) < 3 ||
      CopyBuffer(g_slow_ema, 0, 0, 3, slow) < 3)
   {
      Print("NO TRADE: Insufficient H1 EMA data.");
      return;
   }

   // Use last CLOSED H1 candle values only.
   bool bullish_bias = (fast[1] > slow[1]);
   bool bearish_bias = (fast[1] < slow[1]);
   if(!bullish_bias && !bearish_bias) return;

   // Closed M15 bars only:
   // bar[2] performs a liquidity raid and closes back inside the prior swing.
   // bar[1] confirms displacement by closing beyond the raid candle extreme.
   // Three-candle FVG condition is required as an additional imbalance filter.
   bool sellside_sweep = (rates[2].low < swing_low && rates[2].close > swing_low);
   bool buyside_sweep  = (rates[2].high > swing_high && rates[2].close < swing_high);

   bool bullish_displacement = (rates[1].close > rates[2].high && rates[1].close > rates[1].open);
   bool bearish_displacement = (rates[1].close < rates[2].low  && rates[1].close < rates[1].open);

   bool bullish_fvg = (rates[1].low > rates[3].high);
   bool bearish_fvg = (rates[1].high < rates[3].low);

   MqlTick tick;
   if(!SymbolInfoTick(TRADE_SYMBOL, tick)) return;

   if(bullish_bias && sellside_sweep && bullish_displacement && bullish_fvg)
   {
      // Structural invalidation below the sweep low.
      SubmitEntry(ORDER_TYPE_BUY, tick.ask, rates[2].low);
   }
   else if(bearish_bias && buyside_sweep && bearish_displacement && bearish_fvg)
   {
      // Structural invalidation above the sweep high.
      SubmitEntry(ORDER_TYPE_SELL, tick.bid, rates[2].high);
   }
}

//--------------------------- TIME / DAILY STATE ---------------------
bool IsNewM15Bar()
{
   datetime bar_time = iTime(TRADE_SYMBOL, ENTRY_TIMEFRAME, 0);
   if(bar_time <= 0 || bar_time == g_last_bar) return false;
   g_last_bar = bar_time;
   return true;
}

void UpdateDailyKeys()
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now); // Broker-server calendar day.
   string date_part = StringFormat("%04d%02d%02d", now.year, now.mon, now.day);
   string account_part = StringFormat("%I64d_%I64u", AccountInfoInteger(ACCOUNT_LOGIN), (ulong)MAGIC_NUMBER);
   g_day_equity_key = "SMC_EURUSD_EQ_" + account_part + "_" + date_part;
   g_day_lock_key   = "SMC_EURUSD_LOCK_" + account_part + "_" + date_part;

   if(!GlobalVariableCheck(g_day_equity_key))
      GlobalVariableSet(g_day_equity_key, AccountInfoDouble(ACCOUNT_EQUITY));
   if(!GlobalVariableCheck(g_day_lock_key))
      GlobalVariableSet(g_day_lock_key, 0.0);
}

bool DailyLossProtection()
{
   if(g_day_equity_key == "" || !GlobalVariableCheck(g_day_equity_key) ||
      !GlobalVariableCheck(g_day_lock_key))
      return false; // Fail closed.

   if(GlobalVariableGet(g_day_lock_key) >= 1.0)
      return false; // Lock persists for the remainder of the broker-server day.

   double day_start_equity = GlobalVariableGet(g_day_equity_key);
   double equity_now = AccountInfoDouble(ACCOUNT_EQUITY);
   if(day_start_equity <= 0.0 || equity_now <= 0.0) return false;

   double loss_pct = (day_start_equity - equity_now) / day_start_equity * 100.0;
   if(loss_pct >= DAILY_LOSS_LIMIT_PCT)
   {
      GlobalVariableSet(g_day_lock_key, 1.0);
      PrintFormat("DAILY LOCK ACTIVATED: equity drawdown %.2f%% >= %.2f%%. No more entries today.",
                  loss_pct, DAILY_LOSS_LIMIT_PCT);
      return false;
   }
   return true;
}

//--------------------------- SAFETY FILTERS -------------------------
bool SafetyChecks()
{
   if((ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
   {
      Print("BLOCKED: Account is not DEMO.");
      return false;
   }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
      !MQLInfoInteger(MQL_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
      !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      Print("NO TRADE: Algo trading/account expert permissions are disabled.");
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(TRADE_SYMBOL, tick) || tick.ask <= tick.bid || tick.bid <= 0.0)
      return false;

   double point = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_POINT);
   if(point <= 0.0) return false;
   double spread_points = (tick.ask - tick.bid) / point;
   if(spread_points > MAX_SPREAD_POINTS)
   {
      PrintFormat("NO TRADE: Spread %.1f points exceeds maximum %d.",
                  spread_points, MAX_SPREAD_POINTS);
      return false;
   }

   if(!DailyLossProtection())
   {
      Print("NO TRADE: Daily loss protection is active or unavailable.");
      return false;
   }
   return true;
}

int CountOurPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == TRADE_SYMBOL &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == (ulong)MAGIC_NUMBER)
         count++;
   }
   return count;
}

//--------------------------- MARKET STRUCTURE -----------------------
bool FindLatestConfirmedSwings(const MqlRates &rates[], const int count,
                               double &swing_high, double &swing_low,
                               int &high_shift, int &low_shift)
{
   swing_high = 0.0; swing_low = 0.0;
   high_shift = -1; low_shift = -1;
   int last_shift = MathMin(SWING_LOOKBACK, count - PIVOT_STRENGTH - 1);

   // Newest confirmed pivot first; current and still-forming candles excluded.
   for(int s = PIVOT_STRENGTH + 2; s <= last_shift; ++s)
   {
      bool is_high = true, is_low = true;
      for(int k = 1; k <= PIVOT_STRENGTH; ++k)
      {
         if(rates[s].high <= rates[s-k].high || rates[s].high <= rates[s+k].high)
            is_high = false;
         if(rates[s].low >= rates[s-k].low || rates[s].low >= rates[s+k].low)
            is_low = false;
      }
      if(is_high && high_shift < 0) { swing_high = rates[s].high; high_shift = s; }
      if(is_low && low_shift < 0)   { swing_low = rates[s].low;  low_shift = s; }
      if(high_shift >= 0 && low_shift >= 0) return true;
   }
   return false;
}

//--------------------------- POSITION SIZING ------------------------
double CalculateVolume(ENUM_ORDER_TYPE order_type, const double entry, const double sl)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_cash = equity * RISK_PERCENT / 100.0;
   if(equity <= 0.0 || risk_cash <= 0.0) return 0.0;

   double one_lot_result = 0.0;
   if(!OrderCalcProfit(order_type, TRADE_SYMBOL, 1.0, entry, sl, one_lot_result))
   {
      Print("NO TRADE: OrderCalcProfit failed. Error=", GetLastError());
      return 0.0;
   }

   double one_lot_loss = MathAbs(one_lot_result);
   if(one_lot_loss <= 0.0) return 0.0;

   double raw_volume = risk_cash / one_lot_loss;
   double min_volume = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || max_volume < min_volume || volume_step <= 0.0) return 0.0;

   // Round down only. Never force minimum volume if it exceeds the risk budget.
   double volume = MathFloor(raw_volume / volume_step + 1e-10) * volume_step;
   if(volume < min_volume)
   {
      Print("NO TRADE: Broker minimum volume would exceed the 0.5% risk budget.");
      return 0.0;
   }
   volume = MathMin(volume, max_volume);

   int volume_digits = 0;
   double step_check = volume_step;
   while(volume_digits < 8 && MathAbs(step_check - MathRound(step_check)) > 1e-8)
   {
      step_check *= 10.0;
      volume_digits++;
   }
   volume = NormalizeDouble(volume, volume_digits);

   // Recalculate estimated cash loss using the normalized volume.
   double estimated_result = 0.0;
   if(!OrderCalcProfit(order_type, TRADE_SYMBOL, volume, entry, sl, estimated_result))
      return 0.0;
   if(MathAbs(estimated_result) > risk_cash + 0.01)
   {
      Print("NO TRADE: Normalized volume exceeds risk budget.");
      return 0.0;
   }
   return volume;
}

//--------------------------- ORDER VALIDATION / EXECUTION ------------
void SubmitEntry(ENUM_ORDER_TYPE order_type, const double requested_entry, double sl)
{
   MqlTick tick;
   if(!SymbolInfoTick(TRADE_SYMBOL, tick)) return;

   // Use current executable side for pre-trade sizing.
   double entry = (order_type == ORDER_TYPE_BUY) ? tick.ask : tick.bid;
   int digits = (int)SymbolInfoInteger(TRADE_SYMBOL, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_TRADE_TICK_SIZE);
   long stops_level = SymbolInfoInteger(TRADE_SYMBOL, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(TRADE_SYMBOL, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * point;
   min_distance = MathMax(min_distance, MIN_STOP_POINTS * point);

   sl = NormalizeDouble(sl, digits);
   if((order_type == ORDER_TYPE_BUY && sl >= entry) ||
      (order_type == ORDER_TYPE_SELL && sl <= entry))
      return;

   double stop_distance = MathAbs(entry - sl);
   if(stop_distance < min_distance || stop_distance <= 0.0)
   {
      Print("NO TRADE: Stop distance violates broker/minimum safety distance.");
      return;
   }

   // Align SL to tick size where required.
   if(tick_size > 0.0)
      sl = NormalizeDouble(MathRound(sl / tick_size) * tick_size, digits);

   double volume = CalculateVolume(order_type, entry, sl);
   if(volume <= 0.0) return;

   double risk_distance = MathAbs(entry - sl);
   double tp = (order_type == ORDER_TYPE_BUY)
               ? entry + risk_distance * REWARD_RISK
               : entry - risk_distance * REWARD_RISK;
   tp = NormalizeDouble(tp, digits);

   // Validate broker volume limits and stop distances.
   if(volume < SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_VOLUME_MIN) ||
      volume > SymbolInfoDouble(TRADE_SYMBOL, SYMBOL_VOLUME_MAX))
      return;

   bool sent = false;
   if(order_type == ORDER_TYPE_BUY)
      sent = trade.Buy(volume, TRADE_SYMBOL, 0.0, sl, tp, "SMC_ICT_DEMO_BUY");
   else
      sent = trade.Sell(volume, TRADE_SYMBOL, 0.0, sl, tp, "SMC_ICT_DEMO_SELL");

   uint retcode = trade.ResultRetcode();
   if(!sent || (retcode != TRADE_RETCODE_DONE &&
                retcode != TRADE_RETCODE_PLACED &&
                retcode != TRADE_RETCODE_DONE_PARTIAL))
   {
      PrintFormat("ORDER REJECTED: retcode=%u description=%s",
                  retcode, trade.ResultRetcodeDescription());
      return;
   }

   PrintFormat("ORDER ACCEPTED: %s volume=%.*f entry~%.*f SL=%.*f TP=%.*f estimated risk=%.2f%%",
               (order_type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               3, volume, digits, entry, digits, sl, digits, tp, RISK_PERCENT);
   Print("WARNING: Actual realized loss can differ due to gaps, slippage, commissions and execution.");
}
//+------------------------------------------------------------------+
