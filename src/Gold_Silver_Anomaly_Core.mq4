//+------------------------------------------------------------------+
//|                                    Gold_Silver_Anomaly_Core.mq4  |
//|         Core Logic & Resilience Layer Extract (v7.05 Portfolio)  |
//+------------------------------------------------------------------+
#property copyright "Coding Partner"
#property link      ""
#property version   "7.05"
#property strict

// --- 抜粋パラメータ ---
input double MaxDrawdownPercent = 45.0;      // 許容する最大ドローダウン(資金の何%か)
input string DiscordWebHook     = "";       // Discord Webhook URL

//+------------------------------------------------------------------+
//| 1. 【通信・セキュリティ層】HTTP 400エラー回避型・通知システム
//|   - MQL4特有の末尾NULL文字(\0)を ArrayResize で削る低レイヤ制御
//+------------------------------------------------------------------+
void SendNotify(string message) { 
    if(DiscordWebHook == "") return;

    char postData[], result[]; 
    string headers = "Content-Type: application/json\r\n";
    string resHeaders;
    
    // 特殊文字のエスケープ処理
    StringReplace(message, "\"", "\\\"");
    StringReplace(message, "\n", "\\n");
    string json = "{\"content\": \"" + message + "\"}"; 
    
    // UTF-8バイト配列への変換
    StringToCharArray(json, postData, 0, WHOLE_ARRAY, CP_UTF8); 
    
    // ★重要: 末尾の自動付与NULL文字(\0)を1バイト削り、Discordパーサーの拒絶(HTTP 400)を回避
    ArrayResize(postData, ArraySize(postData) - 1);
    
    int res = WebRequest("POST", DiscordWebHook, headers, 5000, postData, result, resHeaders); 
    
    if(res != 200 && res != 204) {
        Print("[通知システム] Discord送信失敗 [HTTPコード: ", res, "]");
    }
}

//+------------------------------------------------------------------+
//| 2. 【初期化・環境適応層】ブローカー依存を解消するシンボル自動解決
//|   - 異なる命名規則(XAGUSD, SILVER等)に対応する2重ループ総当たり探索
//+------------------------------------------------------------------+
string AutoDetectSilverSymbol(string userSpecifiedInput)
{
   if(userSpecifiedInput != "") {
      string s = userSpecifiedInput;
      int c = StringFind(s, ",");
      if(c > 0) s = StringSubstr(s, 0, c);
      StringTrimLeft(s); StringTrimRight(s);
      return s;
   }

   string currentSym = Symbol();
   string suffix = "";
   if(StringFind(currentSym, "XAUUSD") != -1) suffix = StringSubstr(currentSym, 6);
   else if(StringFind(currentSym, "GOLD") != -1) suffix = StringSubstr(currentSym, 4);
   
   string smartTry1 = "XAGUSD" + suffix;
   if(MarketInfo(smartTry1, MODE_BID) > 0) return smartTry1;

   // 総当たりによるベース名×サフィックス探索
   string baseNames[] = {"XAGUSD", "SILVER", "XAGEUR", "XAG", "Silver"};
   string suffixes[]  = {"", "m", ".m", "pro", ".pro", "_i", ".c", ".s", "ecn", ".ecn", "+"};
   
   for(int i = 0; i < ArraySize(baseNames); i++) {
      for(int j = 0; j < ArraySize(suffixes); j++) {
         string trySym = baseNames[i] + suffixes[j];
         if(MarketInfo(trySym, MODE_BID) > 0) return trySym;
      }
   }
   return "";
}

//+------------------------------------------------------------------+
//| 3. 【リスク管理層】エクイティ・プロテクター（口座破綻防止機構）
//|   - 許容ドローダウン到達時に全ポジションを強制決済し資金を守る
//+------------------------------------------------------------------+
bool CheckEquityProtection(int magicNumber)
{
   if(OrdersTotal() == 0) return false;
   
   double balance = AccountBalance();
   double equity = AccountEquity();
   if(balance <= 0) return false;

   // 現在のドローダウン率をリアルタイム算出
   double currentDD_Percent = ((balance - equity) / balance) * 100.0;

   if(currentDD_Percent >= MaxDrawdownPercent) {
       SendNotify("[MIDAS 資金保護発動] ドローダウンが " + DoubleToString(currentDD_Percent, 2) + "% に達したため、全ポジションを強制損切りしました。");
       
       for(int i = OrdersTotal() - 1; i >= 0; i--) {
          if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) {
             if(OrderSymbol() == Symbol() && OrderMagicNumber() == magicNumber) {
                if(OrderType() == OP_BUY)  OrderClose(OrderTicket(), OrderLots(), Bid, 3, clrRed);
                if(OrderType() == OP_SELL) OrderClose(OrderTicket(), OrderLots(), Ask, 3, clrRed);
             }
          }
       }
       return true; 
   }
   return false;
}
