# 📊 MT5 Volume Profile Indicator  

An advanced **institutional-style Volume Profile Indicator** for MetaTrader 5 that helps traders visualize market structure with precision.  
It integrates **POC, VAH/VAL, buy/sell histograms, failed auction detection, and multiple profile modes (Daily, Weekly, Session, Flexible)** — giving you deep insights into order flow and market balance.  

---

## ✨ Features  

- 📅 **Daily / Weekly / Session / Flexible Profiles**  
- 🎯 **POC, VAH, VAL detection** (Point of Control, Value Area High/Low)  
- 📈 **Buy & Sell Volume Histograms** (TradingView-style)  
- 🔍 **Failed Auction Detection** above VAH and below VAL  
- 🖌 **Customizable Colors & Transparency**  
- 📏 **Extendable Lines for POC/VAH/VAL**  
- ⚡ **Tick, Second, and M1 fallback aggregation** for robust profile generation  
- 🪶 **Thin Profile Detection** for identifying low-volume nodes  

---

## 🛠 Installation  

1. Copy the **`VolumeProfile.mq5`** file into your MetaTrader 5 `Indicators` folder:  

   ```bash
   MQL5/Indicators/
   ```

2. Restart MetaTrader 5.
3. Attach the indicator to your chart.
4. Configure input parameters to suit your trading style.

---

## ⚙️ Input Parameters

| Group            | Parameter                               | Description                            |
| ---------------- | --------------------------------------- | -------------------------------------- |
| General Settings | `EnableDailyProfile`                    | Show daily profile                     |
|                  | `EnableWeeklyProfile`                   | Show weekly profile                    |
|                  | `EnableSessionProfile`                  | Custom session-based profile           |
|                  | `EnableFlexibleProfile`                 | Manually define start/end              |
|                  | `ValueAreaPercentage`                   | % for VAH/VAL (default 70%)            |
|                  | `HistogramWidth`                        | Width of volume histogram bars         |
|                  | `EnableFailedAuction`                   | Detect failed auctions                 |
|                  | `ExtendLines`                           | Extend POC/VAH/VAL lines               |
|                  | `ShowBuySellVolumes`                    | Split histogram by buy/sell            |
|                  | `ThinProfileThreshold`                  | Mark thin profile zones                |
| Session Settings | `SessionStartTime` / `SessionEndTime`   | Define custom trading sessions         |
| Flexible Profile | `FlexibleStartTime` / `FlexibleEndTime` | Manually define profile range          |
| Colors           | `POCColor`, `VAHVALColor`, etc.         | Full customization for lines & shading |

---

## 📸 Preview

*(Insert screenshots or GIF of the indicator running on MT5 chart here)*

---

## 🚀 Usage

1. Add the indicator to your chart.
2. Toggle **Daily, Weekly, Session, or Flexible Profiles**.
3. Use **POC/VAH/VAL levels** as reference for high-probability trade locations.
4. Track **thin profiles** for breakout areas.
5. Watch **failed auctions** for reversal signals.

---

## 📌 Example Strategies

* ✅ Use **POC as magnet**: Price often revisits high-volume nodes.
* ✅ Trade **failed auctions**: When price rejects VAH/VAL, it signals potential reversals.
* ✅ Combine with **VWAP, Order Flow, and S/R zones** for institutional-grade confluence.

---

## 🔧 Development Notes

* Written in **MQL5 (MetaTrader 5)**
* Implements **tick-based aggregation**, with fallbacks to **seconds** and **M1 bars**
* Fully object-based rendering for clean performance

---

## 👨‍💻 Author

**Christley Olubela**  
📌 [Twitter/X](https://x.com/xtley001)

---

## 📜 License

This project is licensed under the **MIT License** – free to use and modify.
