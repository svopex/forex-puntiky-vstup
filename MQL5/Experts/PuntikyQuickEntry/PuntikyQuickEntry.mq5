//+------------------------------------------------------------------+
//|                                            PuntikyQuickEntry.mq5 |
//|                                                                  |
//|  Rychly vstup do pozice na dve kliknuti:                         |
//|   1. tlacitko BUY nebo SELL v panelu                             |
//|   2. za mysi jede linka s nahledem vstupu, SL a PT               |
//|   3. klik do grafu prikaz zada                                   |
//|                                                                  |
//|  Klik na "spravne" strane trhu (BUY nad Ask, SELL pod Bid) zada  |
//|  BUY STOP / SELL STOP na kliknute cene. Klik na druhe strane     |
//|  trhu posle MARKET prikaz za aktualni cenu.                      |
//|  SL a PT se nastavi hned s prikazem. Objem se dopocita z rizika  |
//|  (% zustatku uctu) a vzdalenosti SL.                             |
//|  Symbol, SL, PT a riziko se predvyplni ze vstupu do formulare    |
//|  v grafu, kde se daji pred kazdym obchodem prepsat.              |
//+------------------------------------------------------------------+
#property copyright "Puntiky"
#property version   "1.10"
#property description "Rychlý vstup: tlačítko BUY/SELL + klik do grafu = STOP nebo MARKET příkaz se SL a PT"

#include <Trade\Trade.mqh>

//--- Obchod
input group "=== Obchod ==="
input string InpSymbol             = "XAUUSD";  // Symbol (předvyplní se do formuláře, musí odpovídat grafu)
input int    InpStopLossPoints     = 300;       // Stop loss (body, předvyplní se do formuláře)
input int    InpTakeProfitPoints   = 300;       // Profit target (body, 0 = bez PT, předvyplní se)
input double InpRiskPercent        = 1.0;       // Riziko na obchod (% zůstatku, předvyplní se)
input string InpRiskPresets        = "0.5;1;1.5;2;2.5"; // Předvolby rizika pro tlačítka (%, oddělené ;)
input int    InpSlippage           = 20;        // Maximální skluz MARKET příkazu (body)
input int    InpExpirationMinutes  = 0;         // Platnost STOP příkazu (minuty, 0 = do zrušení)
input bool   InpAlignStopsToFill   = true;      // Po vyplnění dorovnat SL/PT na skutečnou plnicí cenu
input long   InpMagic              = 20260828;  // Magic number

//--- Panel a nahled v grafu
input group "=== Panel a graf ==="
input int    InpPanelX             = 12;        // Panel - odsazení X (px při 96 DPI, škáluje se)
input int    InpPanelY             = 22;        // Panel - odsazení Y (px při 96 DPI, škáluje se)
input int    InpPanelOneClickShift = 70;        // Posun panelu pod okno One Click Trading (px při 96 DPI)
input int    InpPanelFontSize      = 10;        // Panel - velikost písma (panel se s ním zvětšuje)
input color  InpColorText          = clrWhite;       // Barva textu panelu
input color  InpColorBuy           = clrLimeGreen;   // Barva linky vstupu BUY
input color  InpColorSell          = clrTomato;      // Barva linky vstupu SELL
input color  InpColorSL            = clrOrangeRed;   // Barva linky SL
input color  InpColorTP            = clrDeepSkyBlue; // Barva linky PT

//--- Pojmenovane konstanty misto magickych cisel v kodu
#define PQE_PREFIX           "PQE_"      // prefix vsech objektu experta v grafu
#define PQE_FONT             "Consolas"  // neproporcionalni pismo panelu
#define PQE_BASE_FONT        10.0        // velikost pisma, pro kterou jsou rozmery nize
#define PQE_BASE_DPI         96.0        // DPI, pro ktere jsou rozmery nize

// Rozmery panelu v pixelech pri 96 DPI a pismu 10. MT5 pismo objektu
// zvetsuje podle DPI monitoru sam, ale souradnice a rozmery objektu ne -
// vsechny rozmery se proto za behu nasobi meritkem (viz Px / Dpi).
#define PQE_PANEL_W          324         // sirka panelu (2 tlacitka po 148 px + mezery)
#define PQE_PANEL_PAD        10          // vnitrni okraj panelu
#define PQE_CHAR_W           7.4         // sirka znaku pisma Consolas 10 pri 96 DPI (px)
#define PQE_ROW_H            26          // vyska radku formulare
#define PQE_EDIT_H           22          // vyska editacniho pole
#define PQE_EDIT_W           130         // sirka editacniho pole
#define PQE_LABEL_W          110         // sirka popisku pole
#define PQE_BTN_H            36          // vyska tlacitek
#define PQE_BTN_GAP          8           // mezera kolem tlacitek
#define PQE_BTN_FONT_PLUS    3           // o kolik je pismo BUY / SELL vetsi nez pismo panelu
#define PQE_BTN_FONT_PLUS_SMALL 1        // totez pro uzsi tlacitka zavirani
#define PQE_STATUS_H         20          // vyska stavoveho radku
#define PQE_STATUS_LINES     5           // pocet stavovych radku
#define PQE_RISK_BTN_H       24          // vyska tlacitek predvoleb rizika
#define PQE_RISK_BTN_GAP     6           // mezera mezi tlacitky predvoleb rizika
#define PQE_MAX_RISK_PRESETS 8           // nejvyse tolik predvoleb rizika
#define PQE_RISK_EPS         0.005       // tolerance shody rizika s predvolbou (%)

// Priorita objektu pro prijem kliknuti (OBJPROP_ZORDER). Linka nahledu jede
// pod kurzorem pres celou sirku grafu a bez priority by sebrala klik
// tlacitku, ktere lezi pod ni.
#define PQE_ZORDER_PANEL     5           // pozadi panelu
#define PQE_ZORDER_CONTROL   10          // tlacitka a editacni pole
#define PQE_CLICK_GUARD_MS   300         // klik do grafu tesne po stisku tlacitka se ignoruje (ms)
#define PQE_MAX_SENT         64          // pamet odeslanych prikazu (dorovnani SL/PT po vyplneni)
#define PQE_LOTSTEP_EPS      1e-9        // tolerance deleni objemu krokem
#define PQE_MAX_CHARS        63          // MT5 zobrazi z textu objektu jen prvnich 63 znaku
#define PQE_KEY_ESCAPE       27          // kod klavesy Esc

// Barvy panelu - panel je navrzen pro tmave pozadi grafu
#define PQE_COLOR_PANEL_BG   C'22,24,32'    // pozadi panelu
#define PQE_COLOR_PANEL_BRD  C'90,90,110'   // ramecek panelu
#define PQE_COLOR_EDIT_BG    C'44,46,58'    // pozadi editacnich poli
#define PQE_COLOR_BTN_BUY    C'0,110,0'     // tlacitko BUY
#define PQE_COLOR_BTN_SELL   C'150,0,0'     // tlacitko SELL
#define PQE_COLOR_BTN_CANCEL C'120,80,0'    // tlacitko ZRUSIT (probiha vyber mista vstupu)
#define PQE_COLOR_BTN_CANCEL_ORD C'120,80,0' // tlacitko ZRUSIT STOP (lezi cekajici prikaz)
#define PQE_COLOR_BTN_CLOSE_ONE  C'150,50,0' // tlacitko ZAVRIT 1 (je otevrena pozice)
#define PQE_COLOR_BTN_CLOSE  C'175,60,0'    // tlacitko ZAVRIT VSE (na trhu je pozice nebo prikaz)
#define PQE_COLOR_BTN_OFF    C'48,48,48'    // tlacitko bez funkce (chyba formulare, zakazany obchod)
#define PQE_COLOR_BTN_RISK_ON  C'30,110,200' // vybrana predvolba rizika
#define PQE_COLOR_BTN_RISK_OFF C'60,62,74'   // ostatni predvolby rizika
#define PQE_COLOR_OFF        clrGray        // linka nahledu, kdyz klik nelze provest

// Jmena objektu v grafu
#define PQE_OBJ_BG           (PQE_PREFIX + "BG")
#define PQE_OBJ_TITLE        (PQE_PREFIX + "TITLE")
#define PQE_OBJ_EDIT_SYMBOL  (PQE_PREFIX + "EDIT_SYMBOL")
#define PQE_OBJ_EDIT_SL      (PQE_PREFIX + "EDIT_SL")
#define PQE_OBJ_EDIT_TP      (PQE_PREFIX + "EDIT_TP")
#define PQE_OBJ_EDIT_RISK    (PQE_PREFIX + "EDIT_RISK")
#define PQE_OBJ_BTN_BUY      (PQE_PREFIX + "BTN_BUY")
#define PQE_OBJ_BTN_SELL     (PQE_PREFIX + "BTN_SELL")
#define PQE_OBJ_BTN_CANCEL_ORDERS (PQE_PREFIX + "BTN_CANCEL_ORDERS")
#define PQE_OBJ_BTN_CLOSE_ONE     (PQE_PREFIX + "BTN_CLOSE_ONE")
#define PQE_OBJ_BTN_CLOSE_ALL     (PQE_PREFIX + "BTN_CLOSE_ALL")
#define PQE_OBJ_BTN_RISK          (PQE_PREFIX + "BTN_RISK_")     // + poradi predvolby
#define PQE_OBJ_STATUS       (PQE_PREFIX + "STATUS_")    // + poradi radku
#define PQE_OBJ_PV_ENTRY     (PQE_PREFIX + "PV_ENTRY")
#define PQE_OBJ_PV_SL        (PQE_PREFIX + "PV_SL")
#define PQE_OBJ_PV_TP        (PQE_PREFIX + "PV_TP")
#define PQE_OBJ_PV_LABEL     (PQE_PREFIX + "PV_LABEL")

//--- Stav vyberu mista vstupu
enum ENUM_PQE_ARM
  {
   PQE_ARM_NONE = 0,   // nic se nevybira
   PQE_ARM_BUY  = 1,   // vybira se misto pro BUY
   PQE_ARM_SELL = 2    // vybira se misto pro SELL
  };

//--- Zpusob vstupu podle polohy kliknuti vuci trhu
enum ENUM_PQE_MODE
  {
   PQE_MODE_STOP,      // STOP prikaz na kliknute cene
   PQE_MODE_MARKET,    // MARKET prikaz za aktualni cenu
   PQE_MODE_TOO_CLOSE  // uvnitr stop-levelu brokera, nelze zadat
  };

//--- Co ma tlacitko zavirani udelat
enum ENUM_PQE_CLOSE
  {
   PQE_CLOSE_ORDERS,   // zrusit vsechny cekajici STOP prikazy (pozice nechat)
   PQE_CLOSE_ONE,      // zavrit jednu (nejstarsi) pozici
   PQE_CLOSE_ALL       // zavrit vsechny pozice a zrusit vsechny prikazy
  };

//--- Navrh vstupu spocteny z kliknute (nebo najete) ceny
struct SEntryPlan
  {
   bool              isBuy;     // smer obchodu
   ENUM_PQE_MODE     mode;      // STOP / MARKET / prilis blizko
   double            entry;     // vstupni cena (u MARKET aktualni Ask/Bid)
   double            sl;        // stop loss (0 = nespocten)
   double            tp;        // profit target (0 = bez PT)
   double            lots;      // objem
   bool              valid;     // lze zadat
   string            reason;    // proc nelze zadat (kdyz valid = false)
  };

//--- Pamet odeslanych prikazu: vzdalenosti SL/PT pro dorovnani po vyplneni
struct SSentOrder
  {
   ulong             ticket;    // ticket prikazu
   double            slDist;    // vzdalenost SL od vstupu (cena)
   double            tpDist;    // vzdalenost PT od vstupu (cena, 0 = bez PT)
  };

//--- Globalni stav
CTrade        g_trade;                        // obchodni rozhrani
ENUM_PQE_ARM  g_armed       = PQE_ARM_NONE;   // probihajici vyber mista vstupu
uint          g_armedAt     = 0;              // cas aktivace vyberu (GetTickCount)
string        g_lastEvent   = "";             // posledni akce pro panel a log
string        g_symbol      = "";             // hodnoty formulare (posledni platne)
int           g_slPoints    = 0;
int           g_tpPoints    = 0;
double        g_riskPercent = 0.0;
SSentOrder    g_sent[PQE_MAX_SENT];           // kruhova pamet odeslanych prikazu
int           g_sentNext    = 0;              // dalsi volny slot v pameti
int           g_mouseX      = -1;             // posledni poloha mysi (obnova nahledu po ticku)
int           g_mouseY      = -1;
double        g_dpiScale    = 1.0;            // meritko DPI monitoru (1.0 = 96 DPI)
double        g_layoutScale = 1.0;            // meritko rozmeru panelu (DPI x velikost pisma)
double        g_riskPresets[];                // predvolby rizika pro tlacitka (%)

//+------------------------------------------------------------------+
//| Inicializace experta                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Nesmyslne vstupy se odmitnou hned pri startu, ne az pri obchodu
   if(InpStopLossPoints <= 0 || InpTakeProfitPoints < 0 || InpRiskPercent <= 0.0 ||
      InpSlippage < 0 || InpExpirationMinutes < 0 || InpPanelFontSize < 6)
     {
      Print("PQE: neplatné vstupy - SL > 0, PT >= 0, riziko > 0, skluz >= 0, platnost >= 0, písmo >= 6.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);

   //--- Souradnice objektu jsou ve fyzickych pixelech, pismo se ale s DPI
   //--- monitoru zvetsuje samo - rozmery panelu se prepocitaji podle DPI
   //--- a zvolene velikosti pisma, jinak se pri skalovani Windows texty
   //--- prekryvaji
   g_dpiScale    = MathMax(0.5, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / PQE_BASE_DPI);
   g_layoutScale = g_dpiScale * InpPanelFontSize / PQE_BASE_FONT;

   ParseRiskPresets();

   for(int i = 0; i < PQE_MAX_SENT; i++)
      g_sent[i].ticket = 0;

   InitFormValues();
   UpdatePanel();

   //--- Nahled vstupu jede za mysi, proto se zapnou udalosti pohybu mysi
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   EventSetTimer(1);
   ChartRedraw();

   // Cas kompilace v logu: terminal po externi kompilaci experta ne vzdy
   // znovu nacte a v grafu pak bezi stara verze - podle razitka se to pozna
   PrintFormat("PQE: rychlý vstup spuštěn na %s - SL %d b, PT %d b, riziko %.2f %%, magic %I64d, build %s",
               _Symbol, g_slPoints, g_tpPoints, g_riskPercent, InpMagic, BuildStamp());
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Ukonceni experta                                                 |
//|  reason - duvod ukonceni (REASON_*)                              |
//| Zmena timeframe objekty v grafu nemaze a hodnoty formulare se    |
//| maji zachovat; ve vsech ostatnich pripadech (odebrani experta,   |
//| rekompilace, zmena parametru) panel z grafu zmizi.               |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);

   g_armed = PQE_ARM_NONE;
   DeletePreview();

   if(reason != REASON_CHARTCHANGE)
      ObjectsDeleteAll(0, PQE_PREFIX);

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Novy tick - u MARKET nahledu se linka vstupu drzi aktualni ceny  |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(g_armed != PQE_ARM_NONE)
      UpdatePreview();
  }

//+------------------------------------------------------------------+
//| Casovac - obnova panelu (zustatek, objem, pocty prikazu)         |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Udalosti grafu: tlacitka, editace poli, pohyb mysi, klik, Esc.   |
//|  id     - typ udalosti (CHARTEVENT_*)                            |
//|  lparam - u mysi souradnice X, u klavesy kod klavesy             |
//|  dparam - u mysi souradnice Y                                    |
//|  sparam - jmeno objektu (klik, konec editace)                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam,
                  const string &sparam)
  {
   switch(id)
     {
      case CHARTEVENT_OBJECT_CLICK:
         if(sparam == PQE_OBJ_BTN_BUY || sparam == PQE_OBJ_BTN_SELL)
           {
            // MT5 necha tlacitko "zamacknute", vraci se rucne
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            OnDirectionButton(sparam == PQE_OBJ_BTN_BUY);
           }
         else
            if(sparam == PQE_OBJ_BTN_CANCEL_ORDERS || sparam == PQE_OBJ_BTN_CLOSE_ONE ||
               sparam == PQE_OBJ_BTN_CLOSE_ALL)
              {
               ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
               OnCloseButton(sparam == PQE_OBJ_BTN_CANCEL_ORDERS ? PQE_CLOSE_ORDERS
                             : sparam == PQE_OBJ_BTN_CLOSE_ONE  ? PQE_CLOSE_ONE
                             : PQE_CLOSE_ALL);
              }
            else
               if(StringFind(sparam, PQE_OBJ_BTN_RISK) == 0)
                 {
                  // Poradi predvolby je za prefixem jmena objektu
                  ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
                  OnRiskButton((int)StringToInteger(StringSubstr(sparam, StringLen(PQE_OBJ_BTN_RISK))));
                 }
               else
            // Linka nahledu jede presne pod kurzorem, takze klik do grafu
            // muze prijit jako klik na ni - bere se stejne jako klik do grafu
            if(g_armed != PQE_ARM_NONE && StringFind(sparam, PQE_PREFIX + "PV_") == 0)
               HandleChartClick((int)lparam, (int)dparam);
         break;

      case CHARTEVENT_CLICK:
         if(g_armed != PQE_ARM_NONE)
            HandleChartClick((int)lparam, (int)dparam);
         break;

      case CHARTEVENT_MOUSE_MOVE:
         g_mouseX = (int)lparam;
         g_mouseY = (int)dparam;
         if(g_armed != PQE_ARM_NONE)
            UpdatePreview();
         break;

      case CHARTEVENT_OBJECT_ENDEDIT:
         if(StringFind(sparam, PQE_PREFIX + "EDIT_") == 0)
            OnFieldEdited(sparam);
         break;

      case CHARTEVENT_KEYDOWN:
         if(lparam == PQE_KEY_ESCAPE && g_armed != PQE_ARM_NONE)
           {
            Disarm("výběr zrušen (Esc)");
            UpdatePanel();
            ChartRedraw();
           }
         break;
     }
  }

//+------------------------------------------------------------------+
//| Vyplneni prikazu: SL a PT se dorovnaji na skutecnou plnici cenu. |
//| STOP prikaz na Market execution se plni za trh a MARKET prikaz   |
//| muze mit skluz - SL/PT pocitane od pozadovane ceny by pak nesly  |
//| presne s rizikem. Vzdalenosti se berou z pameti odeslanych       |
//| prikazu, po restartu experta z historie prikazu.                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpAlignStopsToFill || trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   //--- Jen vstupni obchody teto strategie na tomto symbolu
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
      return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol)
      return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_IN)
      return;
   const long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL)
      return;

   const bool   isBuy  = (dealType == DEAL_TYPE_BUY);
   const ulong  order  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   const ulong  posId  = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   const double fill   = HistoryDealGetDouble(trans.deal, DEAL_PRICE);

   double slDist = 0.0, tpDist = 0.0;
   if(!FindSent(order, slDist, tpDist))
     {
      // Prikaz z doby pred restartem experta - vzdalenosti z historie prikazu
      if(!HistoryOrderSelect(order))
         return;
      const double oPrice = HistoryOrderGetDouble(order, ORDER_PRICE_OPEN);
      const double oSL    = HistoryOrderGetDouble(order, ORDER_SL);
      const double oTP    = HistoryOrderGetDouble(order, ORDER_TP);
      slDist = (oSL > 0.0) ? MathAbs(oPrice - oSL) : 0.0;
      tpDist = (oTP > 0.0) ? MathAbs(oTP - oPrice) : 0.0;
     }
   if(slDist <= 0.0 && tpDist <= 0.0)
      return;

   const double newSL = (slDist > 0.0) ? NormalizePrice(isBuy ? fill - slDist : fill + slDist) : 0.0;
   const double newTP = (tpDist > 0.0) ? NormalizePrice(isBuy ? fill + tpDist : fill - tpDist) : 0.0;

   if(!PositionSelectByTicket(posId))
      return;
   const double curSL = PositionGetDouble(POSITION_SL);
   const double curTP = PositionGetDouble(POSITION_TP);

   //--- Bez skluzu neni co dorovnavat
   if(SamePrice(curSL, newSL) && SamePrice(curTP, newTP))
      return;

   if(g_trade.PositionModify(posId, newSL, newTP))
      g_lastEvent = StringFormat("#%I64u SL/PT dorovnány na %s",
                                 posId, DoubleToString(fill, _Digits));
   else
      g_lastEvent = StringFormat("#%I64u SL/PT nedorovnány (%d)",
                                 posId, g_trade.ResultRetcode());
   Print("PQE: ", g_lastEvent);
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Formular                                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Vychozi hodnoty formulare.                                       |
//| Bere se ze vstupu experta; kdyz uz pole v grafu existuji (zmena  |
//| timeframe objekty nemaze), maji prednost hodnoty v nich, aby     |
//| prepnuti timeframe nevratilo uzivateli jeho upravy.              |
//+------------------------------------------------------------------+
void InitFormValues()
  {
   g_symbol      = InpSymbol;
   StringTrimLeft(g_symbol);
   StringTrimRight(g_symbol);
   g_slPoints    = InpStopLossPoints;
   g_tpPoints    = InpTakeProfitPoints;
   g_riskPercent = InpRiskPercent;

   string names[4];
   names[0] = PQE_OBJ_EDIT_SYMBOL;
   names[1] = PQE_OBJ_EDIT_SL;
   names[2] = PQE_OBJ_EDIT_TP;
   names[3] = PQE_OBJ_EDIT_RISK;

   for(int i = 0; i < 4; i++)
     {
      if(ObjectFind(0, names[i]) < 0)
         continue;
      string err;
      ApplyField(names[i], ObjectGetString(0, names[i], OBJPROP_TEXT), err);
     }
  }

//+------------------------------------------------------------------+
//| Prevede text pole na cislo.                                      |
//|  text  - obsah pole (uz orezany, s teckou misto carky)           |
//|  value - out: prevedena hodnota                                  |
//| StringToDouble vraci pro nesmysl tise 0, proto se format hlida   |
//| zvlast: cislice, nejvyse jedna desetinna tecka, volitelne minus. |
//| Vraci false, kdyz text neni cislo.                               |
//+------------------------------------------------------------------+
bool ParseNumber(const string text, double &value)
  {
   value = 0.0;
   const int len = StringLen(text);
   if(len == 0)
      return(false);

   int dots = 0, digits = 0;
   for(int i = 0; i < len; i++)
     {
      const ushort ch = StringGetCharacter(text, i);
      if(ch >= '0' && ch <= '9')
         digits++;
      else
         if(ch == '.')
            dots++;
         else
            if(ch == '-' && i == 0)
               continue;
            else
               return(false);
     }
   if(digits == 0 || dots > 1)
      return(false);

   value = StringToDouble(text);
   return(true);
  }

//+------------------------------------------------------------------+
//| Prevezme hodnotu jednoho pole formulare do globalniho stavu.     |
//|  name  - jmeno objektu pole                                      |
//|  text  - text zadany uzivatelem                                  |
//|  error - out: duvod odmitnuti (prazdne = prijato)                |
//| Vraci true, kdyz je hodnota platna a byla prevzata.              |
//+------------------------------------------------------------------+
bool ApplyField(const string name, string text, string &error)
  {
   error = "";
   StringTrimLeft(text);
   StringTrimRight(text);
   StringReplace(text, ",", ".");   // ceska desetinna carka

   if(name == PQE_OBJ_EDIT_SYMBOL)
     {
      if(text == "")
        {
         error = "symbol nesmí být prázdný";
         return(false);
        }
      // Nazvy symbolu v MT5 rozlisuji velikost pismen (napr. XAUUSD.m),
      // proto se text nechava tak, jak ho uzivatel zadal
      g_symbol = text;
      return(true);
     }

   double value = 0.0;
   if(!ParseNumber(text, value))
     {
      error = "'" + text + "' není číslo";
      return(false);
     }

   if(name == PQE_OBJ_EDIT_SL)
     {
      if(value < 1.0)
        {
         error = "SL musí být aspoň 1 bod";
         return(false);
        }
      g_slPoints = (int)MathRound(value);
      return(true);
     }
   if(name == PQE_OBJ_EDIT_TP)
     {
      if(value < 0.0)
        {
         error = "PT nesmí být záporný";
         return(false);
        }
      g_tpPoints = (int)MathRound(value);
      return(true);
     }
   if(name == PQE_OBJ_EDIT_RISK)
     {
      if(value <= 0.0 || value > 100.0)
        {
         error = "riziko musí být v rozsahu 0..100 %";
         return(false);
        }
      g_riskPercent = value;
      return(true);
     }

   error = "neznámé pole";
   return(false);
  }

//+------------------------------------------------------------------+
//| Text posledni platne hodnoty pole (pro vraceni po chybe).        |
//|  name - jmeno objektu pole                                       |
//+------------------------------------------------------------------+
string FieldValueText(const string name)
  {
   if(name == PQE_OBJ_EDIT_SYMBOL) return(g_symbol);
   if(name == PQE_OBJ_EDIT_SL)     return(IntegerToString(g_slPoints));
   if(name == PQE_OBJ_EDIT_TP)     return(IntegerToString(g_tpPoints));
   if(name == PQE_OBJ_EDIT_RISK)   return(DoubleToString(g_riskPercent, 2));
   return("");
  }

//+------------------------------------------------------------------+
//| Popisek pole pro hlasky v panelu.                                |
//|  name - jmeno objektu pole                                       |
//+------------------------------------------------------------------+
string FieldLabel(const string name)
  {
   if(name == PQE_OBJ_EDIT_SYMBOL) return("symbol");
   if(name == PQE_OBJ_EDIT_SL)     return("SL");
   if(name == PQE_OBJ_EDIT_TP)     return("PT");
   if(name == PQE_OBJ_EDIT_RISK)   return("riziko");
   return("pole");
  }

//+------------------------------------------------------------------+
//| Uzivatel dokoncil editaci pole (Enter nebo odchod z pole).       |
//|  name - jmeno objektu pole                                       |
//| Neplatna hodnota se vrati na posledni platnou, aby formular      |
//| nikdy nedrzel nesmysl, a duvod se ukaze v panelu.                |
//+------------------------------------------------------------------+
void OnFieldEdited(const string name)
  {
   string err;
   if(!ApplyField(name, ObjectGetString(0, name, OBJPROP_TEXT), err))
     {
      ObjectSetString(0, name, OBJPROP_TEXT, FieldValueText(name));
      g_lastEvent = "neplatná hodnota: " + err;
     }
   else
      g_lastEvent = "formulář: " + FieldLabel(name) + " = " + FieldValueText(name);

   UpdatePanel();
   if(g_armed != PQE_ARM_NONE)
      UpdatePreview();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Nacte predvolby rizika ze vstupu InpRiskPresets.                 |
//| Hodnoty v procentech oddelene strednikem (desetinna carka i      |
//| znak % se toleruji). Neplatne polozky se preskoci; kdyz nezbyde  |
//| zadna, pouzije se vychozi rada 0.5; 1; 1.5; 2; 2.5.              |
//+------------------------------------------------------------------+
void ParseRiskPresets()
  {
   ArrayResize(g_riskPresets, 0);

   string parts[];
   const int n = StringSplit(InpRiskPresets, ';', parts);
   for(int i = 0; i < n && ArraySize(g_riskPresets) < PQE_MAX_RISK_PRESETS; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      StringReplace(s, ",", ".");
      StringReplace(s, "%", "");

      double v = 0.0;
      if(!ParseNumber(s, v) || v <= 0.0 || v > 100.0)
        {
         if(s != "")
            Print("PQE: předvolba rizika '", parts[i], "' není platná, přeskočena.");
         continue;
        }
      const int k = ArraySize(g_riskPresets);
      ArrayResize(g_riskPresets, k + 1);
      g_riskPresets[k] = v;
     }

   if(ArraySize(g_riskPresets) == 0)
     {
      Print("PQE: InpRiskPresets neobsahuje platnou hodnotu, použije se 0.5;1;1.5;2;2.5.");
      ArrayResize(g_riskPresets, 5);
      g_riskPresets[0] = 0.5;
      g_riskPresets[1] = 1.0;
      g_riskPresets[2] = 1.5;
      g_riskPresets[3] = 2.0;
      g_riskPresets[4] = 2.5;
     }
  }

//--- Procento jako kratky text tlacitka: 1%, 0.5%, 1.25%
string FormatPercent(const double value)
  {
   if(MathAbs(value - MathRound(value)) < PQE_RISK_EPS)
      return(StringFormat("%.0f%%", value));
   if(MathAbs(value * 10.0 - MathRound(value * 10.0)) < PQE_RISK_EPS)
      return(StringFormat("%.1f%%", value));
   return(StringFormat("%.2f%%", value));
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka s predvolbou rizika.                              |
//|  index - poradi predvolby                                        |
//| Hodnota se zapise i do pole Riziko, aby formular a tlacitka      |
//| ukazovaly totez; zvyrazneni prekresli UpdatePanel.               |
//+------------------------------------------------------------------+
void OnRiskButton(const int index)
  {
   if(index < 0 || index >= ArraySize(g_riskPresets))
      return;

   g_riskPercent = g_riskPresets[index];
   ObjectSetString(0, PQE_OBJ_EDIT_RISK, OBJPROP_TEXT, DoubleToString(g_riskPercent, 2));
   g_lastEvent = "riziko " + FormatPercent(g_riskPercent);

   UpdatePanel();
   if(g_armed != PQE_ARM_NONE)
      UpdatePreview();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Znovu nacte vsechna pole z objektu v grafu.                      |
//| Vola se pred aktivaci vyberu - uzivatel mohl do pole napsat      |
//| hodnotu a rovnou kliknout na tlacitko bez potvrzeni Enterem.     |
//| Vraci false a duvod, kdyz je nektere pole neplatne.              |
//+------------------------------------------------------------------+
bool ReloadForm(string &error)
  {
   string names[4];
   names[0] = PQE_OBJ_EDIT_SYMBOL;
   names[1] = PQE_OBJ_EDIT_SL;
   names[2] = PQE_OBJ_EDIT_TP;
   names[3] = PQE_OBJ_EDIT_RISK;

   for(int i = 0; i < 4; i++)
     {
      if(ObjectFind(0, names[i]) < 0)
         continue;
      string err;
      if(!ApplyField(names[i], ObjectGetString(0, names[i], OBJPROP_TEXT), err))
        {
         ObjectSetString(0, names[i], OBJPROP_TEXT, FieldValueText(names[i]));
         error = FieldLabel(names[i]) + ": " + err;
         return(false);
        }
     }
   error = "";
   return(true);
  }

//+------------------------------------------------------------------+
//| Chyba formulare branici obchodu (prazdne = formular v poradku).  |
//| Klik do grafu dava cenu tohoto grafu, proto musi symbol ve       |
//| formulari odpovidat symbolu grafu - jinak by se obchodovalo      |
//| na cizi cene. Nesoulad je pojistka proti expertovi na spatnem    |
//| grafu.                                                           |
//+------------------------------------------------------------------+
string FormError()
  {
   // Porovnani bez ohledu na velikost pismen - preklep "xauusd" nema
   // zablokovat obchod, skutecny nesoulad (jiny trh) ano
   if(StringCompare(g_symbol, _Symbol, false) != 0)
      return("symbol " + g_symbol + " ≠ graf " + _Symbol);
   if(g_slPoints <= 0)
      return("SL musí být aspoň 1 bod");
   if(g_riskPercent <= 0.0)
      return("riziko musí být > 0");
   return("");
  }

//+------------------------------------------------------------------+
//| Obchodovani                                                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Je obchodovani povoleno (terminal, expert, ucet, symbol)?        |
//|  reason - out: duvod zakazu                                      |
//+------------------------------------------------------------------+
bool TradingAllowed(string &reason)
  {
   reason = "";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      reason = "Algo Trading je v terminálu vypnutý";
   else
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
         reason = "expert nemá povoleno obchodovat";
      else
         if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
            reason = "účet nemá povoleno obchodovat";
         else
            if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
               reason = "účet nemá povoleno obchodovat experty";
            else
              {
               const long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
               if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY)
                  reason = "symbol nelze obchodovat (jen zavírání)";
              }
   return(reason == "");
  }

//--- Stop level brokera prevedeny na cenu
double StopsLevelPrice()
  {
   return((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point);
  }

//--- Shoda dvou cen na uroven jednoho bodu (double se presne neporovnava)
bool SamePrice(const double a, const double b)
  {
   return(MathAbs(a - b) < _Point / 2.0);
  }

//+------------------------------------------------------------------+
//| Zarovna cenu na krok kotace symbolu a pocet desetinnych mist.    |
//|  price - libovolna cena (napr. z polohy mysi)                    |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
  {
   const double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick > 0.0)
      price = MathRound(price / tick) * tick;
   return(NormalizeDouble(price, _Digits));
  }

//--- Pocet desetinnych mist objemu podle kroku objemu symbolu
int VolumeDigits()
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   int digits = 0;
   while(step > 0.0 && step < 0.999999 && digits < 8)
     {
      step *= 10.0;
      digits++;
     }
   return(digits);
  }

//--- Objem jako text s poctem mist podle symbolu
string FormatLots(const double lots)
  {
   return(DoubleToString(lots, VolumeDigits()));
  }

//+------------------------------------------------------------------+
//| Ztrata na 1 lot pri zasazeni SL v mene uctu.                     |
//|  slDistance - vzdalenost SL v cene                               |
//| Pocita se ztratova strana ticku - u nesymetrickych nastroju se   |
//| od TICK_VALUE lisi a riziko by vyslo mimo. Vraci 0 bez dat.      |
//+------------------------------------------------------------------+
double LossPerLot(const double slDistance)
  {
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   const double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0 || slDistance <= 0.0)
      return(0.0);
   return(slDistance / tickSize * tickValue);
  }

//+------------------------------------------------------------------+
//| Vypocet objemu z rizika.                                         |
//|  slDistance - vzdalenost SL v cene                               |
//|  reason     - out: duvod, proc objem nelze pouzit                |
//| Objem se dopocita tak, aby ztrata na SL odpovidala zadanemu      |
//| procentu zustatku, a zaokrouhli se DOLU na krok objemu. Kdyz na  |
//| riziko nestaci ani nejmensi dovoleny lot, vraci 0 - riziko nesmi |
//| tise pretect pres zadany limit.                                  |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, string &reason)
  {
   reason = "";

   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   const double lossPerLot = LossPerLot(slDistance);

   if(balance <= 0.0 || lossPerLot <= 0.0)
     {
      reason = "chybí data pro výpočet rizika";
      return(0.0);
     }

   double lot = (balance * g_riskPercent / 100.0) / lossPerLot;

   //--- Zaokrouhleni dolu na krok objemu. Tolerance srovnava chybu
   //--- plovouci carky: 0.29 / 0.01 vyjde 28.999999999999996.
   if(lotStep > 0.0)
      lot = MathFloor(lot / lotStep + PQE_LOTSTEP_EPS) * lotStep;

   if(lot < minLot)
     {
      reason = StringFormat("min. lot %s = %.2f %% > %.2f %%",
                            FormatLots(minLot), minLot * lossPerLot / balance * 100.0,
                            g_riskPercent);
      return(0.0);
     }

   lot = MathMin(lot, maxLot);
   return(NormalizeDouble(lot, VolumeDigits()));
  }

//+------------------------------------------------------------------+
//| Sestavi navrh vstupu z ceny pod kurzorem.                        |
//|  isBuy - smer, price - cena pod kurzorem, plan - out: navrh      |
//| BUY nad Ask (+ stop level) = BUY STOP na kliknute cene,          |
//| BUY na Ask nebo pod nim = BUY za trh. Pro SELL zrcadlove k Bid.  |
//| Pasmo mezi trhem a stop levelem broker pro STOP nepovoli a jako  |
//| trzni vstup by prekvapilo - tam se klik odmitne.                 |
//| SL a PT se meri od vstupni ceny, objem z rizika a vzdalenosti SL.|
//+------------------------------------------------------------------+
void BuildPlan(const bool isBuy, double price, SEntryPlan &plan)
  {
   plan.isBuy  = isBuy;
   plan.mode   = PQE_MODE_TOO_CLOSE;
   plan.entry  = 0.0;
   plan.sl     = 0.0;
   plan.tp     = 0.0;
   plan.lots   = 0.0;
   plan.valid  = false;
   plan.reason = "";

   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double stops = StopsLevelPrice();
   if(ask <= 0.0 || bid <= 0.0)
     {
      plan.reason = "chybí cena trhu";
      return;
     }

   price = NormalizePrice(price);
   plan.entry = price;

   //--- Urceni zpusobu vstupu podle polohy vuci trhu
   if(isBuy)
     {
      if(price > ask + stops)
         plan.mode = PQE_MODE_STOP;
      else
         if(price <= ask)
           {
            plan.mode  = PQE_MODE_MARKET;
            plan.entry = ask;
           }
     }
   else
     {
      if(price < bid - stops)
         plan.mode = PQE_MODE_STOP;
      else
         if(price >= bid)
           {
            plan.mode  = PQE_MODE_MARKET;
            plan.entry = bid;
           }
     }

   const double slDist = g_slPoints * _Point;
   const double tpDist = g_tpPoints * _Point;
   plan.sl = NormalizePrice(isBuy ? plan.entry - slDist : plan.entry + slDist);
   plan.tp = (tpDist > 0.0) ? NormalizePrice(isBuy ? plan.entry + tpDist : plan.entry - tpDist) : 0.0;

   if(plan.mode == PQE_MODE_TOO_CLOSE)
     {
      plan.reason = StringFormat("moc blízko trhu (stop-level %.0f b)", stops / _Point);
      return;
     }

   //--- SL a PT musi respektovat stop level brokera
   if(slDist < stops)
     {
      plan.reason = StringFormat("SL < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }
   if(tpDist > 0.0 && tpDist < stops)
     {
      plan.reason = StringFormat("PT < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }

   string lotReason;
   plan.lots = CalcLot(slDist, lotReason);
   if(plan.lots <= 0.0)
     {
      plan.reason = lotReason;
      return;
     }

   //--- Marze se overi predem - "nedostatek penez" od serveru by prisel
   //--- az po kliknuti a bez cisel
   double margin = 0.0;
   if(OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol, plan.lots, plan.entry, margin))
     {
      const double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > free)
        {
         plan.reason = StringFormat("marže: třeba %.2f, volné %.2f", margin, free);
         return;
        }
     }

   plan.valid = true;
  }

//+------------------------------------------------------------------+
//| Zapamatuje si vzdalenosti SL/PT odeslaneho prikazu.              |
//|  ticket - ticket prikazu, slDist / tpDist - vzdalenosti v cene   |
//+------------------------------------------------------------------+
void RememberSent(const ulong ticket, const double slDist, const double tpDist)
  {
   if(ticket == 0)
      return;
   g_sent[g_sentNext].ticket = ticket;
   g_sent[g_sentNext].slDist = slDist;
   g_sent[g_sentNext].tpDist = tpDist;
   g_sentNext = (g_sentNext + 1) % PQE_MAX_SENT;
  }

//+------------------------------------------------------------------+
//| Najde vzdalenosti SL/PT drive odeslaneho prikazu.                |
//|  ticket - ticket prikazu, slDist / tpDist - out: vzdalenosti     |
//| Vraci false, kdyz prikaz v pameti neni (napr. po restartu).      |
//+------------------------------------------------------------------+
bool FindSent(const ulong ticket, double &slDist, double &tpDist)
  {
   for(int i = 0; i < PQE_MAX_SENT; i++)
     {
      if(g_sent[i].ticket != ticket || ticket == 0)
         continue;
      slDist = g_sent[i].slDist;
      tpDist = g_sent[i].tpDist;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Odesle prikaz podle navrhu (STOP nebo MARKET).                   |
//|  plan - platny navrh vstupu                                      |
//| Vysledek se zapise do panelu i do logu. Vraci true pri uspechu.  |
//+------------------------------------------------------------------+
bool ExecutePlan(SEntryPlan &plan)
  {
   const string dir    = plan.isBuy ? "BUY" : "SELL";
   const bool   market = (plan.mode == PQE_MODE_MARKET);
   bool ok = false;

   if(market)
     {
      // Cena 0 = CTrade pouzije aktualni Ask/Bid v okamziku odeslani
      ok = plan.isBuy
           ? g_trade.Buy(plan.lots, _Symbol, 0.0, plan.sl, plan.tp, "PQE BUY")
           : g_trade.Sell(plan.lots, _Symbol, 0.0, plan.sl, plan.tp, "PQE SELL");
     }
   else
     {
      // Platnost do casu jen tam, kde ji symbol podporuje - jinak GTC
      ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC;
      datetime expiration = 0;
      if(InpExpirationMinutes > 0)
        {
         const long expModes = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
         if((expModes & SYMBOL_EXPIRATION_SPECIFIED) != 0)
           {
            typeTime   = ORDER_TIME_SPECIFIED;
            expiration = TimeCurrent() + InpExpirationMinutes * 60;
           }
         else
            Print("PQE: symbol nepodporuje platnost příkazu do času, příkaz je do zrušení.");
        }

      ok = plan.isBuy
           ? g_trade.BuyStop(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                             typeTime, expiration, "PQE BUYSTOP")
           : g_trade.SellStop(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                              typeTime, expiration, "PQE SELLSTOP");
     }

   if(!RequestAccepted(ok))
     {
      g_lastEvent = StringFormat("%s selhal: %d %s", dir, g_trade.ResultRetcode(),
                                 g_trade.ResultRetcodeDescription());
      Print("PQE: ", g_lastEvent);
      return(false);
     }

   const ulong  ticket = g_trade.ResultOrder();
   const double price  = (market && g_trade.ResultPrice() > 0.0) ? g_trade.ResultPrice() : plan.entry;

   // Vzdalenosti pro dorovnani SL/PT po vyplneni
   const double slDist = g_slPoints * _Point;
   const double tpDist = g_tpPoints * _Point;
   RememberSent(ticket, slDist, tpDist);

   // Kratky tvar - radek panelu ma omezenou sirku
   g_lastEvent = StringFormat("%s %s #%I64u %s %s lot",
                              dir, market ? "MARKET" : "STOP", ticket,
                              DoubleToString(price, _Digits), FormatLots(plan.lots));
   PrintFormat("PQE: %s %s #%I64u @ %s  SL %s  PT %s  %s lot  (riziko %.2f %%)",
               dir, market ? "MARKET" : "STOP", ticket,
               DoubleToString(price, _Digits), DoubleToString(plan.sl, _Digits),
               plan.tp > 0.0 ? DoubleToString(plan.tp, _Digits) : "-",
               FormatLots(plan.lots), g_riskPercent);
   return(true);
  }

//--- Patri prave vybrany prikaz expertovi? (symbol + magic)
bool IsOurOrder()
  {
   return(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagic);
  }

//--- Patri prave vybrana pozice expertovi? (symbol + magic)
bool IsOurPosition()
  {
   return(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic);
  }

//--- Pocet cekajicich prikazu experta na tomto symbolu
int CountOurOrders()
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderGetTicket(i) != 0 && IsOurOrder())
         n++;
   return(n);
  }

//--- Pocet otevrenych pozic experta na tomto symbolu
int CountOurPositions()
  {
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) != 0 && IsOurPosition())
         n++;
   return(n);
  }

//+------------------------------------------------------------------+
//| Prijal server posledni pozadavek?                                |
//|  sent - navratova hodnota metody CTrade                          |
//| CTrade vraci true uz za odeslani, proto se kontroluje i retcode. |
//+------------------------------------------------------------------+
bool RequestAccepted(const bool sent)
  {
   const uint rc = g_trade.ResultRetcode();
   return(sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_PLACED ||
                   rc == TRADE_RETCODE_DONE_PARTIAL));
  }

//+------------------------------------------------------------------+
//| Ticket nejstarsi otevrene pozice experta (0 = zadna).            |
//| Pri vice pozicich (hedging) se za "jednu" bere nejdrive otevrena |
//| - pozice se tak zaviraji v poradi, v jakem vznikly (FIFO).       |
//+------------------------------------------------------------------+
ulong OldestOurPosition()
  {
   ulong oldest     = 0;
   long  oldestTime = LONG_MAX;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      const long t = PositionGetInteger(POSITION_TIME_MSC);
      if(t < oldestTime || (t == oldestTime && ticket < oldest))
        {
         oldestTime = t;
         oldest     = ticket;
        }
     }
   return(oldest);
  }

//+------------------------------------------------------------------+
//| Zavre pozice experta za trh.                                     |
//|  onlyOldest - true = jen nejstarsi pozici, false = vsechny       |
//|  failed     - in/out: pocet neuspesnych pokusu                   |
//| Vraci pocet zavrenych pozic, neuspechy jdou do logu.             |
//+------------------------------------------------------------------+
int ClosePositions(const bool onlyOldest, int &failed)
  {
   const ulong oldest = onlyOldest ? OldestOurPosition() : 0;
   if(onlyOldest && oldest == 0)
      return(0);

   int closed = 0;
   //--- Od konce - seznam se zaviranim zkracuje
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      if(onlyOldest && ticket != oldest)
         continue;
      if(RequestAccepted(g_trade.PositionClose(ticket)))
         closed++;
      else
        {
         failed++;
         PrintFormat("PQE: pozici #%I64u se nepodařilo zavřít, retcode %d (%s)",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
        }
     }
   return(closed);
  }

//+------------------------------------------------------------------+
//| Zrusi vsechny cekajici prikazy experta.                          |
//|  failed - in/out: pocet neuspesnych pokusu                       |
//| Vraci pocet zrusenych prikazu. Prikaz ve freeze zone brokera     |
//| zrusit nejde (TRADE_RETCODE_FROZEN) - zapise se do logu.         |
//+------------------------------------------------------------------+
int CancelOrders(int &failed)
  {
   int deleted = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder())
         continue;
      if(RequestAccepted(g_trade.OrderDelete(ticket)))
         deleted++;
      else
        {
         failed++;
         PrintFormat("PQE: příkaz #%I64u se nepodařilo zrušit, retcode %d (%s)",
                     ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
        }
     }
   return(deleted);
  }

//+------------------------------------------------------------------+
//| Stisk jednoho z tlacitek zavirani.                               |
//|  kind - co zavrit                                                |
//| ZRUSIT STOP rusi jen cekajici prikazy, ZAVRIT 1 zavre jednu      |
//| pozici, ZAVRIT VSE zavre pozice i zrusi prikazy. Vzdy jen        |
//| obchody experta (magic), cizi se nechavaji. Bez potvrzovani.     |
//+------------------------------------------------------------------+
void OnCloseButton(const ENUM_PQE_CLOSE kind)
  {
   string reason;
   if(!TradingAllowed(reason))
      g_lastEvent = "zavřít nelze: " + reason;
   else
     {
      int closed = 0, deleted = 0, failed = 0;
      if(kind == PQE_CLOSE_ONE || kind == PQE_CLOSE_ALL)
         closed = ClosePositions(kind == PQE_CLOSE_ONE, failed);
      if(kind == PQE_CLOSE_ORDERS || kind == PQE_CLOSE_ALL)
         deleted = CancelOrders(failed);

      if(closed + deleted + failed == 0)
         g_lastEvent = (kind == PQE_CLOSE_ORDERS) ? "žádný STOP příkaz ke zrušení"
                       : (kind == PQE_CLOSE_ONE) ? "žádná pozice k zavření"
                       : "nic k zavření";
      else
         g_lastEvent = StringFormat("zavřeno: pozice %d, příkazy %d%s", closed, deleted,
                                    failed > 0 ? StringFormat(", %d selhalo", failed) : "");
     }
   Print("PQE: ", g_lastEvent);

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Vyber mista vstupu                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Stisk tlacitka BUY / SELL.                                       |
//|  isBuy - ktere tlacitko                                          |
//| Tlacitko se chova stridave: stisk zahaji vyber mista vstupu,     |
//| dalsi stisk tehoz tlacitka vyber zrusi; stisk druheho tlacitka   |
//| prepne smer.                                                     |
//+------------------------------------------------------------------+
void OnDirectionButton(const bool isBuy)
  {
   const ENUM_PQE_ARM dir = isBuy ? PQE_ARM_BUY : PQE_ARM_SELL;
   const string dirText = isBuy ? "BUY" : "SELL";

   if(g_armed == dir)
      Disarm("výběr " + dirText + " zrušen");
   else
     {
      string err;
      if(!ReloadForm(err) || (err = FormError()) != "" || !TradingAllowed(err))
        {
         Disarm("");
         g_lastEvent = dirText + ": " + err;
         Print("PQE: ", g_lastEvent);
        }
      else
        {
         g_armed     = dir;
         g_armedAt   = GetTickCount();
         g_lastEvent = dirText + ": klikni do grafu, kam dát vstup";
         UpdatePreview();
        }
     }

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Ukonci vyber mista vstupu a uklidi nahled.                       |
//|  message - text do panelu (prazdny = nechat posledni)            |
//+------------------------------------------------------------------+
void Disarm(const string message)
  {
   g_armed = PQE_ARM_NONE;
   DeletePreview();
   if(message != "")
      g_lastEvent = message;
  }

//+------------------------------------------------------------------+
//| Klik do grafu behem vyberu mista vstupu.                         |
//|  x, y - souradnice kliknuti v pixelech                           |
//| Klik do panelu a klik tesne po stisku tlacitka (stejne kliknuti  |
//| muze prijit jeste jako udalost grafu) se ignoruji. Neproveditelny|
//| klik jen ohlasi duvod a vyber zustava aktivni, po odeslani       |
//| prikazu (i neuspesnem) vyber konci.                              |
//+------------------------------------------------------------------+
void HandleChartClick(const int x, const int y)
  {
   if(GetTickCount() - g_armedAt < PQE_CLICK_GUARD_MS)
      return;
   if(IsInsidePanel(x, y))
      return;

   int      sub   = 0;
   datetime time  = 0;
   double   price = 0.0;
   if(!ChartXYToTimePrice(0, x, y, sub, time, price) || sub != 0)
      return;

   SEntryPlan plan;
   BuildPlan(g_armed == PQE_ARM_BUY, price, plan);
   if(!plan.valid)
     {
      // Radek panelu se oreze, plne zneni duvodu jde do logu
      g_lastEvent = (plan.isBuy ? "BUY" : "SELL") + ": " + plan.reason;
      Print("PQE: ", g_lastEvent);
      UpdatePanel();
      ChartRedraw();
      return;
     }

   ExecutePlan(plan);
   Disarm("");
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Prekresli nahled vstupu podle polohy mysi.                       |
//| Linka vstupu (carkovana = STOP, plna = MARKET, seda = nelze),    |
//| linky SL a PT a popisek u kurzoru s tim, co klik udela.          |
//+------------------------------------------------------------------+
void UpdatePreview()
  {
   if(g_armed == PQE_ARM_NONE || g_mouseX < 0)
      return;

   //--- Nad panelem se nahled schova: tam se vstup zadat neda a linka
   //--- vedena pod kurzorem by lezela pres tlacitka (ZRUSIT BUY by
   //--- klik nedostalo)
   int      sub   = 0;
   datetime time  = 0;
   double   price = 0.0;
   if(IsInsidePanel(g_mouseX, g_mouseY) ||
      !ChartXYToTimePrice(0, g_mouseX, g_mouseY, sub, time, price) || sub != 0)
     {
      DeletePreview();
      ChartRedraw();
      return;
     }

   SEntryPlan plan;
   BuildPlan(g_armed == PQE_ARM_BUY, price, plan);

   const string dir      = plan.isBuy ? "BUY" : "SELL";
   const color  dirColor = plan.isBuy ? InpColorBuy : InpColorSell;
   const color  lineClr  = plan.valid ? dirColor : PQE_COLOR_OFF;

   DrawHLine(PQE_OBJ_PV_ENTRY, plan.entry, lineClr,
             (plan.mode == PQE_MODE_MARKET) ? STYLE_SOLID : STYLE_DASH, 2);

   if(plan.sl > 0.0)
      DrawHLine(PQE_OBJ_PV_SL, plan.sl, InpColorSL, STYLE_DOT, 1);
   else
      ObjectDelete(0, PQE_OBJ_PV_SL);

   if(plan.tp > 0.0)
      DrawHLine(PQE_OBJ_PV_TP, plan.tp, InpColorTP, STYLE_DOT, 1);
   else
      ObjectDelete(0, PQE_OBJ_PV_TP);

   string text;
   if(!plan.valid)
      text = dir + ": " + plan.reason;
   else
      text = StringFormat("%s %s @ %s  SL %s  PT %s  %s lot",
                          dir, (plan.mode == PQE_MODE_MARKET) ? "MARKET" : "STOP",
                          DoubleToString(plan.entry, _Digits),
                          DoubleToString(plan.sl, _Digits),
                          plan.tp > 0.0 ? DoubleToString(plan.tp, _Digits) : "-",
                          FormatLots(plan.lots));

   DrawLabel(PQE_OBJ_PV_LABEL, g_mouseX + Dpi(16), g_mouseY + Dpi(18), Fit(text), lineClr);
   ChartRedraw();
  }

//--- Odstrani vsechny objekty nahledu vstupu
void DeletePreview()
  {
   ObjectDelete(0, PQE_OBJ_PV_ENTRY);
   ObjectDelete(0, PQE_OBJ_PV_SL);
   ObjectDelete(0, PQE_OBJ_PV_TP);
   ObjectDelete(0, PQE_OBJ_PV_LABEL);
  }

//+------------------------------------------------------------------+
//| Panel                                                            |
//+------------------------------------------------------------------+

//--- Rozmer panelu prepocteny podle DPI a velikosti pisma (px)
int Px(const double base)
  {
   return((int)MathRound(base * g_layoutScale));
  }

//--- Vzdalenost prepoctena jen podle DPI (poloha panelu, odsazeni popisku)
int Dpi(const double base)
  {
   return((int)MathRound(base * g_dpiScale));
  }

//--- Levy okraj panelu
int PanelLeft()
  {
   return(Dpi(InpPanelX));
  }

//--- Horni okraj panelu; pod zapnutym One Click Trading se panel posune
int PanelTop()
  {
   int y = Dpi(InpPanelY);
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))
      y += Dpi(InpPanelOneClickShift);
   return(y);
  }

//--- Celkova vyska panelu: titulek, 4 pole, predvolby rizika, dva radky
//--- tlacitek, stavove radky
int PanelHeight()
  {
   return(Px(PQE_PANEL_PAD) + Px(PQE_ROW_H) * 5 +
          Px(PQE_RISK_BTN_H) + Px(PQE_BTN_GAP) +
          (Px(PQE_BTN_H) + Px(PQE_BTN_GAP)) * 2 +
          PQE_STATUS_LINES * Px(PQE_STATUS_H) + Px(PQE_PANEL_PAD));
  }

//--- Lezi bod (v pixelech) uvnitr panelu?
bool IsInsidePanel(const int x, const int y)
  {
   const int left = PanelLeft();
   const int top  = PanelTop();
   return(x >= left && x <= left + Px(PQE_PANEL_W) &&
          y >= top && y <= top + PanelHeight());
  }

//--- Razitko buildu = datum a cas kompilace (__DATETIME__ je typu datetime)
string BuildStamp()
  {
   return(TimeToString(__DATETIME__, TIME_DATE | TIME_MINUTES));
  }

//--- Kolik znaku se vejde na radek panelu (sirka i pismo se skaluji stejne)
int PanelMaxChars()
  {
   return((int)MathFloor((PQE_PANEL_W - 2 * PQE_PANEL_PAD) / PQE_CHAR_W));
  }

//+------------------------------------------------------------------+
//| Orizne text na zadany pocet znaku.                               |
//|  text     - text, maxChars - limit (vychozi = co MT5 zobrazi)    |
//| Radky panelu se rezou na sirku panelu, aby z nej nevycnivaly;    |
//| plne zneni delsich hlasek je v Expert logu.                      |
//+------------------------------------------------------------------+
string Fit(const string text, const int maxChars = PQE_MAX_CHARS)
  {
   if(StringLen(text) <= maxChars)
      return(text);
   return(StringSubstr(text, 0, maxChars));
  }

//+------------------------------------------------------------------+
//| Vykresli / obnovi cely panel: pozadi, formular, tlacitka, stav.  |
//| Vola se kazdou sekundu a po kazde akci; kreslici funkce nastavuji|
//| jen to, co se zmenilo, aby se graf zbytecne neprekresloval.      |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   const int left  = PanelLeft();
   const int top   = PanelTop();
   const int pad   = Px(PQE_PANEL_PAD);
   const int rowH  = Px(PQE_ROW_H);
   const int btnH  = Px(PQE_BTN_H);
   const int gap   = Px(PQE_BTN_GAP);
   const int width = Px(PQE_PANEL_W);
   int y = top + pad;

   DrawRect(PQE_OBJ_BG, left, top, width, PanelHeight());

   //--- Titulek s aktualni cenou
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DrawLabel(PQE_OBJ_TITLE, left + pad, y + Px(3),
             Fit(StringFormat("VSTUP %s  Ask %s  Bid %s", _Symbol,
                              DoubleToString(ask, _Digits), DoubleToString(bid, _Digits)),
                 PanelMaxChars()),
             InpColorText);
   // Bublina titulku prozradi, ktery build v grafu opravdu bezi
   ObjectSetString(0, PQE_OBJ_TITLE, OBJPROP_TOOLTIP,
                   "Puntiky Quick Entry - build " + BuildStamp());
   y += rowH;

   //--- Formular: popisek + editacni pole na kazdem radku
   DrawFormRow(PQE_OBJ_EDIT_SYMBOL, "Symbol",     y, g_symbol,
               "Symbol obchodu - musí odpovídat symbolu grafu");
   y += rowH;
   DrawFormRow(PQE_OBJ_EDIT_SL,     "SL (body)",  y, IntegerToString(g_slPoints),
               "Stop loss v bodech od vstupní ceny");
   y += rowH;
   DrawFormRow(PQE_OBJ_EDIT_TP,     "PT (body)",  y, IntegerToString(g_tpPoints),
               "Profit target v bodech od vstupní ceny (0 = bez PT)");
   y += rowH;
   DrawFormRow(PQE_OBJ_EDIT_RISK,   "Riziko (%)", y, DoubleToString(g_riskPercent, 2),
               "Riziko na obchod v procentech zůstatku účtu");
   y += rowH;

   //--- Predvolby rizika (vybrana je zvyraznena)
   DrawRiskButtons(left + pad, y, width - 2 * pad);
   y += Px(PQE_RISK_BTN_H) + gap;

   //--- Tlacitka BUY / SELL vedle sebe
   const int btnW = (width - 2 * pad - gap) / 2;
   DrawDirectionButton(PQE_OBJ_BTN_BUY,  true,  left + pad, y, btnW);
   DrawDirectionButton(PQE_OBJ_BTN_SELL, false, left + pad + btnW + gap, y, btnW);
   y += btnH + gap;

   //--- Rada tlacitek zavirani: ZRUSIT STOP / ZAVRIT 1 / ZAVRIT VSE
   DrawCloseButtons(left + pad, y, width - 2 * pad);
   y += btnH + gap;

   //--- Stavove radky
   string lines[PQE_STATUS_LINES];
   BuildStatusLines(lines);
   for(int i = 0; i < PQE_STATUS_LINES; i++)
     {
      DrawLabel(PQE_OBJ_STATUS + IntegerToString(i), left + pad, y,
                Fit(lines[i], PanelMaxChars()), InpColorText);
      y += Px(PQE_STATUS_H);
     }
  }

//+------------------------------------------------------------------+
//| Sestavi texty stavovych radku panelu.                            |
//|  lines - out: pole radku (PQE_STATUS_LINES polozek)              |
//+------------------------------------------------------------------+
void BuildStatusLines(string &lines[])
  {
   //--- Stav: co se prave deje, nebo proc nejde obchodovat
   string reason;
   if(g_armed != PQE_ARM_NONE)
      lines[0] = "stav: " + (g_armed == PQE_ARM_BUY ? "BUY" : "SELL") + " - klikni do grafu (Esc ruší)";
   else
      if(FormError() != "")
         lines[0] = "stav: " + FormError();
      else
         if(!TradingAllowed(reason))
            lines[0] = "stav: " + reason;
         else
            lines[0] = "stav: připraven - stiskni BUY nebo SELL";

   //--- Objem z rizika pro aktualni SL a zustatek (texty jsou kratke,
   //--- radek panelu ma jen PanelMaxChars znaku)
   const double slDist = g_slPoints * _Point;
   string lotReason;
   const double lots = CalcLot(slDist, lotReason);
   if(lots > 0.0)
     {
      const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      const double risk    = lots * LossPerLot(slDist);
      lines[1] = StringFormat("objem %s lot = %.2f %s (%.2f %%)",
                              FormatLots(lots), risk, AccountInfoString(ACCOUNT_CURRENCY),
                              balance > 0.0 ? risk / balance * 100.0 : 0.0);
     }
   else
      lines[1] = "objem: " + lotReason;

   //--- Vzdalenosti SL a PT prevedene na cenu
   lines[2] = StringFormat("SL %d b = %s   PT %s",
                           g_slPoints, DoubleToString(slDist, _Digits),
                           g_tpPoints > 0
                           ? StringFormat("%d b = %s", g_tpPoints, DoubleToString(g_tpPoints * _Point, _Digits))
                           : "bez PT");

   //--- Co uz na trhu lezi
   lines[3] = StringFormat("příkazy %d  pozice %d  zůstatek %.2f",
                           CountOurOrders(), CountOurPositions(),
                           AccountInfoDouble(ACCOUNT_BALANCE));

   lines[4] = "» " + g_lastEvent;
  }

//+------------------------------------------------------------------+
//| Vykresli radek formulare: popisek vlevo, editacni pole vpravo.   |
//|  name    - jmeno editacniho pole                                 |
//|  label   - popisek pole                                          |
//|  y       - horni okraj radku v pixelech                          |
//|  initial - vychozi text pole (jen pri vzniku, uzivateli se       |
//|            rozepsany text neprepisuje)                           |
//|  tooltip - bublina pole                                          |
//+------------------------------------------------------------------+
void DrawFormRow(const string name, const string label, const int y,
                 const string initial, const string tooltip)
  {
   const int left = PanelLeft() + Px(PQE_PANEL_PAD);
   DrawLabel(name + "_LBL", left, y + Px(3), label, InpColorText);
   DrawEdit(name, left + Px(PQE_LABEL_W), y, Px(PQE_EDIT_W), Px(PQE_EDIT_H), initial, tooltip);
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko BUY / SELL a nastavi mu podobu podle stavu.    |
//| Behem vyberu se tlacitko zmeni na ZRUSIT, pri chybe formulare    |
//| nebo zakazanem obchodovani zesedne a duvod da do bubliny.        |
//|  name - jmeno objektu, isBuy - smer                              |
//|  x, y - poloha, w - sirka v pixelech                             |
//+------------------------------------------------------------------+
void DrawDirectionButton(const string name, const bool isBuy, const int x, const int y, const int w)
  {
   const string dir   = isBuy ? "BUY" : "SELL";
   const ENUM_PQE_ARM armDir = isBuy ? PQE_ARM_BUY : PQE_ARM_SELL;

   string text    = dir;
   string tooltip = "";
   color  bg      = isBuy ? PQE_COLOR_BTN_BUY : PQE_COLOR_BTN_SELL;
   string reason  = FormError();

   if(g_armed == armDir)
     {
      text    = "ZRUŠIT " + dir;
      bg      = PQE_COLOR_BTN_CANCEL;
      tooltip = "Zruší výběr místa vstupu.";
     }
   else
      if(reason != "" || !TradingAllowed(reason))
        {
         bg      = PQE_COLOR_BTN_OFF;
         tooltip = "Nelze obchodovat: " + reason;
        }
      else
         tooltip = isBuy
                   ? "Klik nad Ask = BUY STOP, klik na Ask nebo pod ním = BUY za trh."
                   : "Klik pod Bid = SELL STOP, klik na Bid nebo nad ním = SELL za trh.";

   DrawButton(name, x, y, w, Px(PQE_BTN_H), text, bg, tooltip, PQE_BTN_FONT_PLUS);
  }

//+------------------------------------------------------------------+
//| Vykresli radu tlacitek zavirani a nastavi jim podobu podle trhu: |
//|  ZRUSIT STOP - zrusi vsechny cekajici STOP prikazy (pozice necha)|
//|  ZAVRIT 1    - zavre jednu (nejstarsi) pozici za trh             |
//|  ZAVRIT VSE  - zavre vsechny pozice a zrusi vsechny prikazy      |
//| Tlacitko, pro ktere na trhu nic neni, zesedne a duvod ma v       |
//| bubline. Pocty jsou i na stavovem radku "prikazy / pozice".      |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//+------------------------------------------------------------------+
void DrawCloseButtons(const int x, const int y, const int w)
  {
   const int orders    = CountOurOrders();
   const int positions = CountOurPositions();
   const int gap       = Px(PQE_BTN_GAP);
   const int btnW      = (w - 2 * gap) / 3;
   const int btnH      = Px(PQE_BTN_H);

   DrawButton(PQE_OBJ_BTN_CANCEL_ORDERS, x, y, btnW, btnH, "ZRUŠIT STOP",
              orders > 0 ? PQE_COLOR_BTN_CANCEL_ORD : PQE_COLOR_BTN_OFF,
              orders > 0
              ? StringFormat("Zruší všechny čekající STOP příkazy experta (%d), pozice nechá.", orders)
              : "Žádný čekající STOP příkaz experta.",
              PQE_BTN_FONT_PLUS_SMALL);

   DrawButton(PQE_OBJ_BTN_CLOSE_ONE, x + btnW + gap, y, btnW, btnH, "ZAVŘÍT 1",
              positions > 0 ? PQE_COLOR_BTN_CLOSE_ONE : PQE_COLOR_BTN_OFF,
              positions > 0
              ? StringFormat("Zavře jednu (nejstarší) pozici experta za trh, otevřeno: %d.", positions)
              : "Žádná otevřená pozice experta.",
              PQE_BTN_FONT_PLUS_SMALL);

   // Posledni tlacitko dostane zbytek sirky, aby rada koncila zarovnane
   DrawButton(PQE_OBJ_BTN_CLOSE_ALL, x + 2 * (btnW + gap), y, w - 2 * (btnW + gap), btnH, "ZAVŘÍT VŠE",
              orders + positions > 0 ? PQE_COLOR_BTN_CLOSE : PQE_COLOR_BTN_OFF,
              orders + positions > 0
              ? StringFormat("Zavře všechny pozice experta (%d) a zruší jeho STOP příkazy (%d).", positions, orders)
              : "Expert nemá na trhu pozici ani příkaz.",
              PQE_BTN_FONT_PLUS_SMALL);
  }

//+------------------------------------------------------------------+
//| Vykresli radu tlacitek s predvolbami rizika.                     |
//| Zvyraznene je to, ktere odpovida aktualni hodnote rizika - tedy  |
//| po startu hodnote ze vstupu InpRiskPercent; rucne zapsana        |
//| hodnota bez odpovidajici predvolby nezvyrazni zadne.             |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//+------------------------------------------------------------------+
void DrawRiskButtons(const int x, const int y, const int w)
  {
   const int count = ArraySize(g_riskPresets);
   if(count == 0)
      return;

   const int gap  = Px(PQE_RISK_BTN_GAP);
   const int btnW = (w - (count - 1) * gap) / count;
   const int btnH = Px(PQE_RISK_BTN_H);

   for(int i = 0; i < count; i++)
     {
      const bool selected = (MathAbs(g_riskPresets[i] - g_riskPercent) < PQE_RISK_EPS);
      const int  bx = x + i * (btnW + gap);
      // Posledni tlacitko dostane zbytek sirky, aby rada koncila zarovnane
      const int  bw = (i == count - 1) ? (w - i * (btnW + gap)) : btnW;

      DrawButton(PQE_OBJ_BTN_RISK + IntegerToString(i), bx, y, bw, btnH,
                 FormatPercent(g_riskPresets[i]),
                 selected ? PQE_COLOR_BTN_RISK_ON : PQE_COLOR_BTN_RISK_OFF,
                 StringFormat("Nastaví riziko %.2f %% zůstatku na obchod.", g_riskPresets[i]),
                 0);
     }
  }

//+------------------------------------------------------------------+
//| Kreslici pomocnici                                               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Obdelnik pozadi panelu.                                          |
//|  name - jmeno objektu, x, y - poloha, w, h - rozmery (px)        |
//+------------------------------------------------------------------+
void DrawRect(const string name, const int x, const int y, const int w, const int h)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PQE_COLOR_PANEL_BG);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, PQE_COLOR_PANEL_BRD);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, PQE_ZORDER_PANEL);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

//+------------------------------------------------------------------+
//| Textovy popisek ukotveny k levemu hornimu rohu grafu.            |
//|  name - jmeno objektu, x, y - poloha (px), text, clr - barva     |
//| Text a barva se nastavuji jen pri zmene - popisky se obnovuji    |
//| kazdou sekundu a kazdy ObjectSet* je volani do terminalu.        |
//+------------------------------------------------------------------+
void DrawLabel(const string name, const int x, const int y, const string text, const color clr)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, PQE_FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   if((color)ObjectGetInteger(0, name, OBJPROP_COLOR) != clr)
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

//+------------------------------------------------------------------+
//| Editacni pole formulare.                                         |
//|  name    - jmeno objektu, x, y - poloha, w, h - rozmery (px)     |
//|  initial - text pri vzniku pole, tooltip - bublina               |
//+------------------------------------------------------------------+
void DrawEdit(const string name, const int x, const int y, const int w, const int h,
              const string initial, const string tooltip)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, PQE_FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorText);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, PQE_COLOR_EDIT_BG);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, PQE_COLOR_PANEL_BRD);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_LEFT);
      ObjectSetInteger(0, name, OBJPROP_READONLY, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, PQE_ZORDER_CONTROL);
      ObjectSetString(0, name, OBJPROP_TEXT, initial);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
  }

//+------------------------------------------------------------------+
//| Tlacitko ukotvene k levemu hornimu rohu grafu.                   |
//|  name    - jmeno objektu, x, y - poloha, w, h - rozmery (px)     |
//|  text    - popisek, bg - barva pozadi, tooltip - bublina         |
//|  fontPlus - o kolik je pismo vetsi nez pismo panelu              |
//| Text, barva a bublina se nastavuji jen pri zmene. Tlacitko ma    |
//| prednost pri kliknuti pred linkou nahledu, ktera pres nej muze   |
//| vest.                                                            |
//+------------------------------------------------------------------+
void DrawButton(const string name, const int x, const int y, const int w, const int h,
                const string text, const color bg, const string tooltip, const int fontPlus)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, PQE_FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpPanelFontSize + fontPlus);
      ObjectSetInteger(0, name, OBJPROP_COLOR, InpColorText);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, InpColorText);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, PQE_ZORDER_CONTROL);
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   if((color)ObjectGetInteger(0, name, OBJPROP_BGCOLOR) != bg)
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   if(ObjectGetString(0, name, OBJPROP_TOOLTIP) != tooltip)
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
//| Vodorovna linka nahledu (vstup, SL, PT).                         |
//|  name - jmeno objektu, price - cena, clr - barva                 |
//|  style - styl cary, width - tloustka                             |
//+------------------------------------------------------------------+
void DrawHLine(const string name, const double price, const color clr,
               const ENUM_LINE_STYLE style, const int width)
  {
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
     }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
  }
//+------------------------------------------------------------------+
