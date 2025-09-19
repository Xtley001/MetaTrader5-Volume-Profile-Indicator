#property copyright "Christley OLubela (https://x.com/xtley001)"
#property link      "https://x.com/xtley001"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

// Input Parameters
input group "General Settings"
input bool EnableDailyProfile = true;              // Enable Daily Profile (default: true)
input bool EnableWeeklyProfile = false;           // Enable Weekly Profile
input bool EnableSessionProfile = false;          // Enable Session Profile
input bool EnableFlexibleProfile = false;         // Enable Flexible Profile
input double ValueAreaPercentage = 70.0;          // Value Area Percentage (60-80)
input double HistogramWidth = 10.0;               // Histogram Bar Width (pixels)
input ENUM_BASE_CORNER ProfilePosition = CORNER_RIGHT_UPPER; // Profile Position
input bool EnableFailedAuction = false;           // Enable Failed Auction Detection
input bool ExtendLines = false;                   // Extend POC/VAH/VAL Lines
input bool ShowBuySellVolumes = true;             // Show Buy/Sell Volumes (TradingView style)
input double ThinProfileThreshold = 0.1;          // Thin Profile Threshold (0-1, relative to max volume)

input group "Session Time Customization"
input string SessionStartTime = "09:00";          // Session Start Time (HH:MM)
input string SessionEndTime = "17:00";            // Session End Time (HH:MM)

input group "Flexible Profile Settings"
input datetime FlexibleStartTime = 0;             // Flexible Profile Start Time
input datetime FlexibleEndTime = 0;               // Flexible Profile End Time

input group "Color Settings"
input color POCColor = clrLightYellow;            // POC Line Color
input color VAHVALColor = clrLightGreen;          // VAH/VAL Line Color
input color BuyHistogramColor = clrLightBlue;     // Buy Histogram Color
input color SellHistogramColor = clrLightPink;    // Sell Histogram Color
input color ThinProfileColor = clrLightGray;      // Thin Profile Color
input color DailyShadingColor = C'200,255,200';   // Daily Shading Color (Light Mint)
input color WeeklyHistogramColor = clrLightCyan;  // Weekly Histogram Color
input color WeeklyShadingColor = C'200,240,240';  // Weekly Shading Color (Light Teal)
input color SessionHistogramColor = C'220,200,255'; // Session Histogram Color (Light Purple)
input color SessionShadingColor = C'230,220,255'; // Session Shading Color (Light Lavender)
input color FlexibleShadingColor = C'200,255,200'; // Flexible Shading Color (Light Mint)
input color FailedAuctionAboveColor = C'255,200,200'; // Failed Auction Above VAH Color (Light Coral)
input color FailedAuctionBelowColor = C'200,255,220'; // Failed Auction Below VAL Color (Light Sea Green)
input int Transparency = 50;                      // Transparency (0-255)

// Profile Data Structure
struct VolumeProfileData
{
   double price;
   long buy_volume;
   long sell_volume;
   bool isPOC;
   bool isVAH;
   bool isVAL;
   bool isThin;
};

// Second-Based Data Structure for Fallback
struct SecondData
{
   datetime time;
   double price;
   long buy_volume;
   long sell_volume;
};

// Profile Class
class CVolumeProfile
{
private:
   string m_symbol;
   datetime m_start_time;
   datetime m_end_time;
   VolumeProfileData m_profile[];
   SecondData m_second_data[];
   double m_poc_price;
   double m_vah_price;
   double m_val_price;
   long m_total_volume;
   string m_prefix;
   bool m_enabled;
   bool m_use_ticks;
   bool m_use_seconds;

public:
   CVolumeProfile(string symbol, datetime start, datetime end, string prefix)
   {
      m_symbol = symbol;
      m_start_time = start;
      m_end_time = end;
      m_prefix = prefix;
      m_enabled = true;
      m_use_ticks = true;
      m_use_seconds = false;
      ArraySetAsSeries(m_profile, true);
      ArraySetAsSeries(m_second_data, true);
   }

   void Enable(bool state) { m_enabled = state; }

   bool IsEnabled() { return m_enabled; }

   void CalculateProfile()
   {
      if(!m_enabled) return;

      // Try tick data first
      MqlTick ticks[];
      ResetLastError();
      int copied = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, m_start_time * 1000, (m_end_time - m_start_time) * 1000);
      if(copied <= 0)
      {
         Print("No tick data available: ", GetLastError(), ". Falling back to 1-second aggregation.");
         m_use_ticks = false;
         m_use_seconds = true;
         CalculateSecondProfile();
         return;
      }

      // Initialize price levels
      double price_step = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double min_price = ticks[0].bid;
      double max_price = ticks[0].bid;
      for(int i = 1; i < copied; i++)
      {
         min_price = MathMin(min_price, ticks[i].bid);
         max_price = MathMax(max_price, ticks[i].bid);
      }
      int price_levels = (int)((max_price - min_price) / price_step) + 1;

      ArrayResize(m_profile, price_levels);
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = 0;
         m_profile[i].buy_volume = 0;
         m_profile[i].sell_volume = 0;
         m_profile[i].isPOC = false;
         m_profile[i].isVAH = false;
         m_profile[i].isVAL = false;
         m_profile[i].isThin = false;
      }
      m_total_volume = 0;

      // Populate volume profile with tick data
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = min_price + i * price_step;
      }

      for(int i = 0; i < copied; i++)
      {
         double price = ticks[i].bid;
         int index = (int)((price - min_price) / price_step);
         if(index >= 0 && index < price_levels)
         {
            long volume = ticks[i].volume;
            m_total_volume += volume;
            // Approximate buy/sell using tick flags (AvaTrade may not always provide clear flags)
            if(ticks[i].flags & TICK_FLAG_BUY)
               m_profile[index].buy_volume += volume;
            else if(ticks[i].flags & TICK_FLAG_SELL)
               m_profile[index].sell_volume += volume;
            else
            {
               // If flags are unclear, split volume evenly (fallback)
               m_profile[index].buy_volume += volume / 2;
               m_profile[index].sell_volume += volume / 2;
            }
         }
      }

      // Calculate POC
      long max_volume = 0;
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume > max_volume)
         {
            max_volume = total_volume;
            m_poc_price = m_profile[i].price;
            m_profile[i].isPOC = true;
         }
      }

      // Identify Thin Profiles
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume < max_volume * ThinProfileThreshold)
            m_profile[i].isThin = true;
      }

      // Calculate Value Area (VAH/VAL)
      double target_volume = m_total_volume * (ValueAreaPercentage / 100.0);
      long current_volume = max_volume;
      int poc_index = (int)((m_poc_price - min_price) / price_step);
      int up_index = poc_index;
      int down_index = poc_index;

      while(current_volume < target_volume && (up_index < price_levels - 1 || down_index > 0))
      {
         long up_volume = (up_index + 1 < price_levels) ? (m_profile[up_index + 1].buy_volume + m_profile[up_index + 1].sell_volume) : 0;
         long down_volume = (down_index - 1 >= 0) ? (m_profile[down_index - 1].buy_volume + m_profile[down_index - 1].sell_volume) : 0;

         if(up_volume >= down_volume && up_index + 1 < price_levels)
         {
            current_volume += up_volume;
            up_index++;
         }
         else if(down_index - 1 >= 0)
         {
            current_volume += down_volume;
            down_index--;
         }
      }

      m_vah_price = m_profile[up_index].price;
      m_val_price = m_profile[down_index].price;
      m_profile[up_index].isVAH = true;
      m_profile[down_index].isVAL = true;
   }

   void CalculateSecondProfile()
   {
      // Fallback to 1-second aggregation
      MqlTick ticks[];
      ResetLastError();
      int copied = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, m_start_time * 1000, (m_end_time - m_start_time) * 1000);
      if(copied <= 0)
      {
         Print("No tick data for 1-second aggregation: ", GetLastError(), ". Falling back to M1 bars.");
         m_use_seconds = false;
         CalculateM1Profile();
         return;
      }

      // Aggregate ticks into 1-second buckets
      ArrayResize(m_second_data, 0);
      datetime current_second = 0;
      double sum_price = 0;
      long sum_buy_volume = 0;
      long sum_sell_volume = 0;
      int count = 0;

      for(int i = 0; i < copied; i++)
      {
         datetime second = ticks[i].time - (ticks[i].time % 1);
         if(second != current_second && current_second != 0)
         {
            ArrayResize(m_second_data, ArraySize(m_second_data) + 1);
            m_second_data[ArraySize(m_second_data) - 1].time = current_second;
            m_second_data[ArraySize(m_second_data) - 1].price = sum_price / count;
            m_second_data[ArraySize(m_second_data) - 1].buy_volume = sum_buy_volume;
            m_second_data[ArraySize(m_second_data) - 1].sell_volume = sum_sell_volume;
            sum_price = 0;
            sum_buy_volume = 0;
            sum_sell_volume = 0;
            count = 0;
         }
         current_second = second;
         sum_price += ticks[i].bid;
         long volume = ticks[i].volume;
         if(ticks[i].flags & TICK_FLAG_BUY)
            sum_buy_volume += volume;
         else if(ticks[i].flags & TICK_FLAG_SELL)
            sum_sell_volume += volume;
         else
         {
            sum_buy_volume += volume / 2;
            sum_sell_volume += volume / 2;
         }
         count++;
      }

      if(count > 0)
      {
         ArrayResize(m_second_data, ArraySize(m_second_data) + 1);
         m_second_data[ArraySize(m_second_data) - 1].time = current_second;
         m_second_data[ArraySize(m_second_data) - 1].price = sum_price / count;
         m_second_data[ArraySize(m_second_data) - 1].buy_volume = sum_buy_volume;
         m_second_data[ArraySize(m_second_data) - 1].sell_volume = sum_sell_volume;
      }

      // Initialize price levels
      double price_step = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double min_price = m_second_data[0].price;
      double max_price = m_second_data[0].price;
      for(int i = 1; i < ArraySize(m_second_data); i++)
      {
         min_price = MathMin(min_price, m_second_data[i].price);
         max_price = MathMax(max_price, m_second_data[i].price);
      }
      int price_levels = (int)((max_price - min_price) / price_step) + 1;

      ArrayResize(m_profile, price_levels);
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = 0;
         m_profile[i].buy_volume = 0;
         m_profile[i].sell_volume = 0;
         m_profile[i].isPOC = false;
         m_profile[i].isVAH = false;
         m_profile[i].isVAL = false;
         m_profile[i].isThin = false;
      }
      m_total_volume = 0;

      // Populate volume profile with 1-second data
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = min_price + i * price_step;
      }

      for(int i = 0; i < ArraySize(m_second_data); i++)
      {
         double price = m_second_data[i].price;
         int index = (int)((price - min_price) / price_step);
         if(index >= 0 && index < price_levels)
         {
            m_profile[index].buy_volume += m_second_data[i].buy_volume;
            m_profile[index].sell_volume += m_second_data[i].sell_volume;
            m_total_volume += m_second_data[i].buy_volume + m_second_data[i].sell_volume;
         }
      }

      // Calculate POC and VAH/VAL
      long max_volume = 0;
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume > max_volume)
         {
            max_volume = total_volume;
            m_poc_price = m_profile[i].price;
            m_profile[i].isPOC = true;
         }
      }

      // Identify Thin Profiles
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume < max_volume * ThinProfileThreshold)
            m_profile[i].isThin = true;
      }

      double target_volume = m_total_volume * (ValueAreaPercentage / 100.0);
      long current_volume = max_volume;
      int poc_index = (int)((m_poc_price - min_price) / price_step);
      int up_index = poc_index;
      int down_index = poc_index;

      while(current_volume < target_volume && (up_index < price_levels - 1 || down_index > 0))
      {
         long up_volume = (up_index + 1 < price_levels) ? (m_profile[up_index + 1].buy_volume + m_profile[up_index + 1].sell_volume) : 0;
         long down_volume = (down_index - 1 >= 0) ? (m_profile[down_index - 1].buy_volume + m_profile[down_index - 1].sell_volume) : 0;

         if(up_volume >= down_volume && up_index + 1 < price_levels)
         {
            current_volume += up_volume;
            up_index++;
         }
         else if(down_index - 1 >= 0)
         {
            current_volume += down_volume;
            down_index--;
         }
      }

      m_vah_price = m_profile[up_index].price;
      m_val_price = m_profile[down_index].price;
      m_profile[up_index].isVAH = true;
      m_profile[down_index].isVAL = true;
   }

   void CalculateM1Profile()
   {
      // Fallback to M1 bars (last resort)
      MqlRates rates[];
      long volumes[];
      ResetLastError();
      int copied = CopyRates(m_symbol, PERIOD_M1, m_start_time, m_end_time, rates);
      if(copied <= 0) { Alert("Error copying M1 rates: ", GetLastError()); return; }
      CopyTickVolume(m_symbol, PERIOD_M1, m_start_time, m_end_time, volumes);

      // Initialize price levels
      double price_step = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double min_price = rates[0].low;
      double max_price = rates[0].high;
      for(int i = 1; i < copied; i++)
      {
         min_price = MathMin(min_price, rates[i].low);
         max_price = MathMax(max_price, rates[i].high);
      }
      int price_levels = (int)((max_price - min_price) / price_step) + 1;

      ArrayResize(m_profile, price_levels);
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = 0;
         m_profile[i].buy_volume = 0;
         m_profile[i].sell_volume = 0;
         m_profile[i].isPOC = false;
         m_profile[i].isVAH = false;
         m_profile[i].isVAL = false;
         m_profile[i].isThin = false;
      }
      m_total_volume = 0;

      // Populate volume profile with M1 data (no buy/sell distinction available)
      for(int i = 0; i < price_levels; i++)
      {
         m_profile[i].price = min_price + i * price_step;
      }

      for(int i = 0; i < copied; i++)
      {
         double price = rates[i].close;
         int index = (int)((price - min_price) / price_step);
         if(index >= 0 && index < price_levels)
         {
            m_profile[index].buy_volume += volumes[i] / 2;
            m_profile[index].sell_volume += volumes[i] / 2;
            m_total_volume += volumes[i];
         }
      }

      // Calculate POC and VAH/VAL
      long max_volume = 0;
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume > max_volume)
         {
            max_volume = total_volume;
            m_poc_price = m_profile[i].price;
            m_profile[i].isPOC = true;
         }
      }

      // Identify Thin Profiles
      for(int i = 0; i < price_levels; i++)
      {
         long total_volume = m_profile[i].buy_volume + m_profile[i].sell_volume;
         if(total_volume < max_volume * ThinProfileThreshold)
            m_profile[i].isThin = true;
      }

      double target_volume = m_total_volume * (ValueAreaPercentage / 100.0);
      long current_volume = max_volume;
      int poc_index = (int)((m_poc_price - min_price) / price_step);
      int up_index = poc_index;
      int down_index = poc_index;

      while(current_volume < target_volume && (up_index < price_levels - 1 || down_index > 0))
      {
         long up_volume = (up_index + 1 < price_levels) ? (m_profile[up_index + 1].buy_volume + m_profile[up_index + 1].sell_volume) : 0;
         long down_volume = (down_index - 1 >= 0) ? (m_profile[down_index - 1].buy_volume + m_profile[down_index - 1].sell_volume) : 0;

         if(up_volume >= down_volume && up_index + 1 < price_levels)
         {
            current_volume += up_volume;
            up_index++;
         }
         else if(down_index - 1 >= 0)
         {
            current_volume += down_volume;
            down_index--;
         }
      }

      m_vah_price = m_profile[up_index].price;
      m_val_price = m_profile[down_index].price;
      m_profile[up_index].isVAH = true;
      m_profile[down_index].isVAL = true;
   }

   void RenderProfile(ENUM_BASE_CORNER position, color poc_color, color vahval_color, color buy_histogram_color, color sell_histogram_color, color thin_profile_color, color shading_color)
   {
      if(!m_enabled) { ObjectsDeleteAll(0, m_prefix); return; }

      double max_volume = 0;
      for(int i = 0; i < ArraySize(m_profile); i++)
         max_volume = MathMax(max_volume, m_profile[i].buy_volume + m_profile[i].sell_volume);

      // Render Buy/Sell Histograms
      for(int i = 0; i < ArraySize(m_profile); i++)
      {
         if(m_profile[i].buy_volume + m_profile[i].sell_volume == 0) continue;

         // Buy Histogram
         if(ShowBuySellVolumes && m_profile[i].buy_volume > 0)
         {
            string buy_obj_name = m_prefix + "BuyHist_" + IntegerToString(i);
            double width = (m_profile[i].buy_volume / max_volume) * HistogramWidth;
            ObjectCreate(0, buy_obj_name, OBJ_RECTANGLE, 0, m_start_time, m_profile[i].price, m_start_time + width * 60, m_profile[i].price + SymbolInfoDouble(m_symbol, SYMBOL_POINT));
            ObjectSetInteger(0, buy_obj_name, OBJPROP_COLOR, m_profile[i].isThin ? thin_profile_color : buy_histogram_color);
            ObjectSetInteger(0, buy_obj_name, OBJPROP_FILL, true);
            ObjectSetInteger(0, buy_obj_name, OBJPROP_BACK, true);
            ObjectSetInteger(0, buy_obj_name, OBJPROP_ZORDER, 0);
         }

         // Sell Histogram
         if(ShowBuySellVolumes && m_profile[i].sell_volume > 0)
         {
            string sell_obj_name = m_prefix + "SellHist_" + IntegerToString(i);
            double width = (m_profile[i].sell_volume / max_volume) * HistogramWidth;
            ObjectCreate(0, sell_obj_name, OBJ_RECTANGLE, 0, m_start_time, m_profile[i].price, m_start_time - width * 60, m_profile[i].price + SymbolInfoDouble(m_symbol, SYMBOL_POINT));
            ObjectSetInteger(0, sell_obj_name, OBJPROP_COLOR, m_profile[i].isThin ? thin_profile_color : sell_histogram_color);
            ObjectSetInteger(0, sell_obj_name, OBJPROP_FILL, true);
            ObjectSetInteger(0, sell_obj_name, OBJPROP_BACK, true);
            ObjectSetInteger(0, sell_obj_name, OBJPROP_ZORDER, 0);
         }

         // Combined Histogram (if buy/sell not shown)
         if(!ShowBuySellVolumes && (m_profile[i].buy_volume + m_profile[i].sell_volume) > 0)
         {
            string obj_name = m_prefix + "Hist_" + IntegerToString(i);
            double width = ((m_profile[i].buy_volume + m_profile[i].sell_volume) / max_volume) * HistogramWidth;
            ObjectCreate(0, obj_name, OBJ_RECTANGLE, 0, m_start_time, m_profile[i].price, m_start_time + width * 60, m_profile[i].price + SymbolInfoDouble(m_symbol, SYMBOL_POINT));
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, m_profile[i].isThin ? thin_profile_color : buy_histogram_color);
            ObjectSetInteger(0, obj_name, OBJPROP_FILL, true);
            ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
            ObjectSetInteger(0, obj_name, OBJPROP_ZORDER, 0);
         }
      }

      // Render Shading (Value Area)
      string shade_name = m_prefix + "Shading";
      ObjectCreate(0, shade_name, OBJ_RECTANGLE, 0, m_start_time, m_val_price, m_end_time, m_vah_price);
      ObjectSetInteger(0, shade_name, OBJPROP_COLOR, shading_color);
      ObjectSetInteger(0, shade_name, OBJPROP_FILL, true);
      ObjectSetInteger(0, shade_name, OBJPROP_BACK, true);
      ObjectSetInteger(0, shade_name, OBJPROP_ZORDER, -1);
      ObjectSetInteger(0, shade_name, OBJPROP_BGCOLOR, ColorToARGB(shading_color, Transparency));

      // Render POC
      string poc_name = m_prefix + "POC";
      ObjectCreate(0, poc_name, OBJ_HLINE, 0, m_start_time, m_poc_price);
      ObjectSetInteger(0, poc_name, OBJPROP_COLOR, poc_color);
      ObjectSetInteger(0, poc_name, OBJPROP_WIDTH, 2);
      if(ExtendLines) ObjectSetInteger(0, poc_name, OBJPROP_RAY_RIGHT, true);

      // Render VAH/VAL
      string vah_name = m_prefix + "VAH";
      ObjectCreate(0, vah_name, OBJ_HLINE, 0, m_start_time, m_vah_price);
      ObjectSetInteger(0, vah_name, OBJPROP_COLOR, vahval_color);
      ObjectSetInteger(0, vah_name, OBJPROP_WIDTH, 1);
      if(ExtendLines) ObjectSetInteger(0, vah_name, OBJPROP_RAY_RIGHT, true);

      string val_name = m_prefix + "VAL";
      ObjectCreate(0, val_name, OBJ_HLINE, 0, m_start_time, m_val_price);
      ObjectSetInteger(0, val_name, OBJPROP_COLOR, vahval_color);
      ObjectSetInteger(0, val_name, OBJPROP_WIDTH, 1);
      if(ExtendLines) ObjectSetInteger(0, val_name, OBJPROP_RAY_RIGHT, true);
   }

   void DetectFailedAuction()
   {
      if(!m_enabled || !EnableFailedAuction) return;

      MqlTick ticks[];
      ResetLastError();
      int copied = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, m_end_time * 1000, (TimeCurrent() - m_end_time) * 1000);
      if(copied <= 0) return;

      for(int i = 1; i < copied; i++)
      {
         if(ticks[i].bid > m_vah_price && ticks[i-1].bid < m_vah_price)
         {
            string obj_name = m_prefix + "FA_Above_" + IntegerToString(i);
            ObjectCreate(0, obj_name, OBJ_ARROW_DOWN, 0, ticks[i].time, ticks[i].bid);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, FailedAuctionAboveColor);
            ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_TOP);
         }
         if(ticks[i].bid < m_val_price && ticks[i-1].bid > m_val_price)
         {
            string obj_name = m_prefix + "FA_Below_" + IntegerToString(i);
            ObjectCreate(0, obj_name, OBJ_ARROW_UP, 0, ticks[i].time, ticks[i].bid);
            ObjectSetInteger(0, obj_name, OBJPROP_COLOR, FailedAuctionBelowColor);
            ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
         }
      }
   }
};

// Global Variables
CVolumeProfile *DailyProfile;
CVolumeProfile *WeeklyProfile;
CVolumeProfile *SessionProfile;
CVolumeProfile *FlexibleProfile;

// Initialization
int OnInit()
{
   // Validate Inputs
   if(ValueAreaPercentage < 60.0 || ValueAreaPercentage > 80.0)
   {
      Alert("Value Area Percentage must be between 60 and 80");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(FlexibleStartTime >= FlexibleEndTime && EnableFlexibleProfile)
   {
      Alert("Flexible Profile: Start time must be before end time");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(ThinProfileThreshold < 0.0 || ThinProfileThreshold > 1.0)
   {
      Alert("Thin Profile Threshold must be between 0 and 1");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // Initialize Profiles
   datetime now = TimeCurrent();
   datetime day_start = now - (now % 86400);
   datetime week_start = now - (now % (86400 * 7));
   datetime session_start = StringToTime(TimeToString(now, TIME_DATE) + " " + SessionStartTime);
   datetime session_end = StringToTime(TimeToString(now, TIME_DATE) + " " + SessionEndTime);

   DailyProfile = new CVolumeProfile(_Symbol, day_start, now, "Daily_");
   WeeklyProfile = new CVolumeProfile(_Symbol, week_start, now, "Weekly_");
   SessionProfile = new CVolumeProfile(_Symbol, session_start, session_end, "Session_");
   FlexibleProfile = new CVolumeProfile(_Symbol, FlexibleStartTime, FlexibleEndTime, "Flexible_");

   DailyProfile.Enable(EnableDailyProfile);
   WeeklyProfile.Enable(EnableWeeklyProfile);
   SessionProfile.Enable(EnableSessionProfile);
   FlexibleProfile.Enable(EnableFlexibleProfile);

   return(INIT_SUCCEEDED);
}

// Deinitialization
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "Daily_");
   ObjectsDeleteAll(0, "Weekly_");
   ObjectsDeleteAll(0, "Session_");
   ObjectsDeleteAll(0, "Flexible_");
   delete DailyProfile;
   delete WeeklyProfile;
   delete SessionProfile;
   delete FlexibleProfile;
}

// Calculation
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(prev_calculated == 0)
   {
      DailyProfile.CalculateProfile();
      WeeklyProfile.CalculateProfile();
      SessionProfile.CalculateProfile();
      FlexibleProfile.CalculateProfile();
   }
   else
   {
      // Update only new ticks
      DailyProfile.CalculateProfile();
      WeeklyProfile.CalculateProfile();
      SessionProfile.CalculateProfile();
      FlexibleProfile.CalculateProfile();
   }

   // Render Profiles
   DailyProfile.RenderProfile(ProfilePosition, POCColor, VAHVALColor, BuyHistogramColor, SellHistogramColor, ThinProfileColor, DailyShadingColor);
   WeeklyProfile.RenderProfile(ProfilePosition, POCColor, VAHVALColor, BuyHistogramColor, SellHistogramColor, ThinProfileColor, WeeklyShadingColor);
   SessionProfile.RenderProfile(ProfilePosition, POCColor, VAHVALColor, BuyHistogramColor, SellHistogramColor, ThinProfileColor, SessionShadingColor);
   FlexibleProfile.RenderProfile(ProfilePosition, POCColor, VAHVALColor, BuyHistogramColor, SellHistogramColor, ThinProfileColor, FlexibleShadingColor);

   // Detect Failed Auctions
   if(EnableFailedAuction)
   {
      DailyProfile.DetectFailedAuction();
      WeeklyProfile.DetectFailedAuction();
      SessionProfile.DetectFailedAuction();
      FlexibleProfile.DetectFailedAuction();
   }

   return(rates_total);
}

// Chart Event Handler
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle interactive repositioning or other events if needed
}