//+------------------------------------------------------------------+
//|                                            PuntikyQuickEntry.mq5 |
//|                                                                  |
//|  Rychly vstup do pozice na dve kliknuti:                         |
//|   1. tlacitko BUY / SELL nebo BUYSTOP / SELLSTOP v panelu        |
//|   2. za mysi jede linka s nahledem vstupu, SL a PT               |
//|   3. klik do grafu prikaz zada                                   |
//|                                                                  |
//|  Klik na "spravne" strane trhu (BUY nad Ask, SELL pod Bid) zada  |
//|  BUY STOP / SELL STOP na kliknute cene. Klik na druhe strane     |
//|  trhu zada u BUY / SELL BUY LIMIT / SELL LIMIT na kliknute cene  |
//|  (MARKET jen tesne u trhu, kde by broker LIMIT odmitl), u        |
//|  BUYSTOP / SELLSTOP posle MARKET prikaz za aktualni cenu.        |
//|  SL a PT se nastavi hned s prikazem. Objem se dopocita z rizika  |
//|  (% zustatku uctu) a vzdalenosti SL.                             |
//|  Obchoduje se symbol grafu. SL, PT a riziko se predvyplni ze     |
//|  vstupu do formulare v grafu, kde se daji pred obchodem prepsat. |
//+------------------------------------------------------------------+
#property copyright "Puntiky"
#property version   "1.20"
#property description "Rychlý vstup: tlačítko BUY/SELL (STOP, LIMIT nebo MARKET) či BUYSTOP/SELLSTOP (jen STOP nebo MARKET) + klik do grafu = příkaz se SL a PT"

#include <Trade\Trade.mqh>

//--- Obchod
input group "=== Obchod ==="
input int    InpStopLossPoints     = 300;       // Stop loss (body, předvyplní se do formuláře)
input int    InpTakeProfitPoints   = 300;       // Profit target (body, 0 = bez PT, předvyplní se)
input double InpRiskPercent        = 1.0;       // Riziko na obchod (% zůstatku, předvyplní se)
input string InpRiskPresets        = "0.5;1;1.5;2;2.5"; // Předvolby rizika pro tlačítka (%, oddělené ;)
input int    InpSlippage           = 20;        // Maximální skluz MARKET příkazu (body)
input int    InpExpirationMinutes  = 0;         // Platnost čekajícího příkazu STOP/LIMIT (minuty, 0 = do zrušení)
input bool   InpAlignStopsToFill   = true;      // Po vyplnění dorovnat SL/PT na skutečnou plnicí cenu
input long   InpMagic              = 20260828;  // Magic number

//--- Panel a nahled v grafu
input group "=== Panel a graf ==="
input int    InpPanelX             = 12;        // Panel - odsazení X (px při 96 DPI, škáluje se)
input int    InpPanelY             = 22;        // Panel - odsazení Y (px při 96 DPI, škáluje se)
input int    InpPanelOneClickShift = 60;        // Posun panelu pod okno One Click Trading (px při 96 DPI)
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
#define PQE_BTN_FONT_PLUS_SMALL 1        // totez pro tlacitka BUYSTOP / SELLSTOP a tlacitka zavirani
#define PQE_STATUS_H         20          // vyska stavoveho radku
#define PQE_STATUS_LINES     5           // pocet stavovych radku
#define PQE_RISK_BTN_H       24          // vyska tlacitek predvoleb rizika
#define PQE_RISK_BTN_GAP     6           // mezera mezi tlacitky predvoleb rizika
#define PQE_MAX_RISK_PRESETS 8           // nejvyse tolik predvoleb rizika
#define PQE_RISK_EPS         0.005       // tolerance shody rizika s predvolbou (%)
#define PQE_MAX_POINTS       1000000     // horni mez SL / PT v bodech (chrani prevod na int)
#define PQE_MAX_RISK_PCT     100.0       // horni mez rizika na obchod (% zustatku)
#define PQE_FORM_FIELDS      3           // pocet editacnich poli formulare (SL, PT, riziko)
#define PQE_CLOSE_SHARE_CANCEL 0.42      // podil sirky rady zavirani pro ZRUSIT PRIKAZY (nejdelsi popisek)
#define PQE_CLOSE_SHARE_ONE    0.26      // podil sirky rady zavirani pro ZAVRIT 1 (nejkratsi popisek)

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
#define PQE_COLOR_BTN_STOP_BUY  C'0,80,0'    // tlacitko BUYSTOP (tmavsi odstin BUY)
#define PQE_COLOR_BTN_STOP_SELL C'110,0,0'   // tlacitko SELLSTOP (tmavsi odstin SELL)
#define PQE_COLOR_BTN_CANCEL C'120,80,0'    // tlacitko ZRUSIT (probiha vyber mista vstupu)
#define PQE_COLOR_BTN_CANCEL_ORD C'120,80,0' // tlacitko ZRUSIT PRIKAZY (lezi cekajici prikaz)
#define PQE_COLOR_BTN_CLOSE_ONE  C'150,50,0' // tlacitko ZAVRIT 1 (je otevrena pozice)
#define PQE_COLOR_BTN_CLOSE  C'175,60,0'    // tlacitko ZAVRIT VSE (na trhu je pozice nebo prikaz)
#define PQE_COLOR_BTN_OFF    C'48,48,48'    // tlacitko bez funkce (chyba formulare, zakazany obchod)
#define PQE_COLOR_BTN_RISK_ON  C'30,110,200' // vybrana predvolba rizika
#define PQE_COLOR_BTN_RISK_OFF C'60,62,74'   // ostatni predvolby rizika
#define PQE_COLOR_OFF        clrGray        // linka nahledu, kdyz klik nelze provest

// Jmena objektu v grafu
#define PQE_OBJ_BG           (PQE_PREFIX + "BG")
#define PQE_OBJ_TITLE        (PQE_PREFIX + "TITLE")
#define PQE_OBJ_EDIT_SL      (PQE_PREFIX + "EDIT_SL")
#define PQE_OBJ_EDIT_TP      (PQE_PREFIX + "EDIT_TP")
#define PQE_OBJ_EDIT_RISK    (PQE_PREFIX + "EDIT_RISK")
#define PQE_OBJ_BTN_BUY      (PQE_PREFIX + "BTN_BUY")
#define PQE_OBJ_BTN_SELL     (PQE_PREFIX + "BTN_SELL")
#define PQE_OBJ_BTN_STOP_BUY  (PQE_PREFIX + "BTN_STOP_BUY")
#define PQE_OBJ_BTN_STOP_SELL (PQE_PREFIX + "BTN_STOP_SELL")
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
   PQE_ARM_NONE      = 0,   // nic se nevybira
   PQE_ARM_BUY       = 1,   // vybira se misto pro BUY (STOP nad trhem, LIMIT pod nim, MARKET tesne u trhu)
   PQE_ARM_SELL      = 2,   // vybira se misto pro SELL (STOP pod trhem, LIMIT nad nim, MARKET tesne u trhu)
   PQE_ARM_STOP_BUY  = 3,   // vybira se misto pro BUYSTOP (STOP nad trhem, MARKET pod nim, bez LIMIT)
   PQE_ARM_STOP_SELL = 4    // vybira se misto pro SELLSTOP (STOP pod trhem, MARKET nad nim, bez LIMIT)
  };

//--- Zpusob vstupu podle polohy kliknuti vuci trhu
enum ENUM_PQE_MODE
  {
   PQE_MODE_STOP,      // STOP prikaz na kliknute cene
   PQE_MODE_MARKET,    // MARKET prikaz za aktualni cenu
   PQE_MODE_LIMIT,     // LIMIT prikaz na kliknute cene (jen BUY / SELL, BUYSTOP / SELLSTOP ho nezadava)
   PQE_MODE_TOO_CLOSE  // uvnitr stop-levelu brokera, nelze zadat
  };

//--- Co ma tlacitko zavirani udelat
enum ENUM_PQE_CLOSE
  {
   PQE_CLOSE_ORDERS,   // zrusit vsechny cekajici prikazy STOP i LIMIT (pozice nechat)
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

//--- Stav trhu a formulare spocteny jednou za prekresleni panelu.
//--- Panel se obnovuje kazdou sekundu a kazdy dotaz do terminalu (pocty
//--- prikazu, povoleni obchodu) neco stoji - drive si je stavove radky
//--- i jednotliva tlacitka zjistovaly kazde zvlast.
struct SPanelState
  {
   int               orders;       // pocet cekajicich prikazu experta
   int               positions;    // pocet otevrenych pozic experta
   string            formError;    // chyba formulare ("" = v poradku)
   bool              canTrade;     // lze otevrit novy obchod
   string            tradeReason;  // duvod zakazu otevirani
   bool              canClose;     // lze zavirat pozice a rusit prikazy
   string            closeReason;  // duvod zakazu zavirani
   double            balance;      // zustatek uctu
   double            slDist;       // vzdalenost SL v cene podle formulare
   double            lots;         // objem z rizika (0 = nelze spocitat)
   string            lotReason;    // duvod, proc objem nelze pouzit
  };

//--- Svisle rozvrzeni panelu. Pocita se na jednom miste, aby pozadi,
//--- obsah a IsInsidePanel vzdy sedely - drive se celkova vyska scitala
//--- zvlast a musela se rucne udrzovat v souladu s vykreslovanim.
struct SPanelLayout
  {
   int               left;         // levy okraj panelu
   int               top;          // horni okraj panelu
   int               width;        // sirka panelu
   int               height;       // celkova vyska panelu
   int               pad;          // vnitrni okraj
   int               gap;          // mezera mezi tlacitky
   int               btnH;         // vyska tlacitek
   int               statusH;      // vyska stavoveho radku
   int               yTitle;       // titulek s cenou
   int               yFields[PQE_FORM_FIELDS]; // radky formulare (SL, PT, riziko)
   int               yRisk;        // rada predvoleb rizika
   int               yBuySell;     // tlacitka BUY / SELL
   int               yStops;       // tlacitka BUYSTOP / SELLSTOP
   int               yClose;       // rada tlacitek zavirani
   int               yStatus;      // prvni stavovy radek
  };

//--- Globalni stav
CTrade        g_trade;                        // obchodni rozhrani
ENUM_PQE_ARM  g_armed       = PQE_ARM_NONE;   // probihajici vyber mista vstupu
uint          g_armedAt     = 0;              // cas aktivace vyberu (GetTickCount)
string        g_lastEvent   = "";             // posledni akce pro panel a log
int           g_slPoints    = 0;              // hodnoty formulare (posledni platne)
int           g_tpPoints    = 0;
double        g_riskPercent = 0.0;
SSentOrder    g_sent[PQE_MAX_SENT];           // kruhova pamet odeslanych prikazu
int           g_sentNext    = 0;              // dalsi volny slot v pameti
int           g_mouseX      = -1;             // posledni poloha mysi (obnova nahledu po ticku)
int           g_mouseY      = -1;
double        g_dpiScale    = 1.0;            // meritko DPI monitoru (1.0 = 96 DPI)
double        g_layoutScale = 1.0;            // meritko rozmeru panelu (DPI x velikost pisma)
double        g_riskPresets[];                // predvolby rizika pro tlacitka (%)

//--- Naposledy vykresleny nahled vstupu. Slouzi k tomu, aby se graf
//--- neprekresloval, kdyz se nahled nezmenil - OnTick chodi pri zpravach
//--- i mnohokrat za sekundu a ChartRedraw je drahy.
bool          g_pvShown     = false;          // je nahled prave v grafu?
double        g_pvEntry     = 0.0;            // vykreslena cena vstupu
double        g_pvSL        = 0.0;            // vykreslena cena SL
double        g_pvTP        = 0.0;            // vykreslena cena PT
string        g_pvText      = "";             // vykresleny popisek u kurzoru
int           g_pvX         = -1;             // poloha popisku, pro kterou byl nahled vykreslen
int           g_pvY         = -1;

//+------------------------------------------------------------------+
//| Inicializace experta                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Nesmyslne vstupy se odmitnou hned pri startu, ne az pri obchodu.
   //--- Meze jsou stejne jako ve formulari (ApplyField) - jinak by expert
   //--- nastartoval s hodnotou, kterou formular pri kazdem obchodu odmitne,
   //--- a tlacitka by se nedala pouzit, dokud uzivatel hodnotu neprepise.
   if(InpStopLossPoints <= 0 || InpStopLossPoints > PQE_MAX_POINTS ||
      InpTakeProfitPoints < 0 || InpTakeProfitPoints > PQE_MAX_POINTS ||
      InpRiskPercent <= 0.0 || InpRiskPercent > PQE_MAX_RISK_PCT ||
      InpSlippage < 0 || InpExpirationMinutes < 0 || InpPanelFontSize < 6)
     {
      PrintFormat("PQE: neplatné vstupy - SL 1..%d b, PT 0..%d b, riziko 0..%.0f %%, "
                  "skluz >= 0, platnost >= 0, písmo >= 6.",
                  PQE_MAX_POINTS, PQE_MAX_POINTS, PQE_MAX_RISK_PCT);
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
         if(sparam == PQE_OBJ_BTN_BUY || sparam == PQE_OBJ_BTN_SELL ||
            sparam == PQE_OBJ_BTN_STOP_BUY || sparam == PQE_OBJ_BTN_STOP_SELL)
           {
            // MT5 necha tlacitko "zamacknute", vraci se rucne
            ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
            OnDirectionButton(sparam == PQE_OBJ_BTN_BUY || sparam == PQE_OBJ_BTN_STOP_BUY,
                              sparam == PQE_OBJ_BTN_STOP_BUY || sparam == PQE_OBJ_BTN_STOP_SELL);
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
//| Vyplneni prikazu: SL a PT se dorovnaji na skutecnou vstupni cenu.|
//| STOP prikaz na Market execution se plni za trh a MARKET prikaz   |
//| muze mit skluz - SL/PT pocitane od pozadovane ceny by pak nesly  |
//| presne s rizikem. Vzdalenosti se berou z pameti odeslanych       |
//| prikazu, po restartu experta z historie prikazu; meri se od      |
//| prumerne vstupni ceny pozice (POSITION_PRICE_OPEN).              |
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

   if(!PositionSelectByTicket(posId))
      return;
   const double curSL = PositionGetDouble(POSITION_SL);
   const double curTP = PositionGetDouble(POSITION_TP);

   //--- Meri se od prumerne vstupni ceny pozice, ne od ceny jednoho
   //--- obchodu: pri castecnem plneni prijde DEAL_ADD za kazdy dil a
   //--- pri navysovani pozice na netting uctu se vstupy prumeruji -
   //--- stopy podle posledniho dilu by neodpovidaly riziku cele pozice.
   //--- Kdyby pozice cenu jeste nemela, pouzije se cena obchodu.
   const double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   const double base    = (posOpen > 0.0) ? posOpen : fill;

   //--- Chybejici vzdalenost necha stavajici uroven beze zmeny - nula
   //--- predana do PositionModify by SL nebo PT z pozice smazala
   const double newSL = (slDist > 0.0) ? NormalizePrice(isBuy ? base - slDist : base + slDist) : curSL;
   const double newTP = (tpDist > 0.0) ? NormalizePrice(isBuy ? base + tpDist : base - tpDist) : curTP;

   //--- Bez skluzu neni co dorovnavat
   if(SamePrice(curSL, newSL) && SamePrice(curTP, newTP))
      return;

   if(g_trade.PositionModify(posId, newSL, newTP))
      g_lastEvent = StringFormat("#%I64u SL/PT dorovnány na %s",
                                 posId, DoubleToString(base, _Digits));
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

//--- Jmena editacnich poli formulare (v poradi radku panelu)
void FormFieldNames(string &names[])
  {
   ArrayResize(names, PQE_FORM_FIELDS);
   names[0] = PQE_OBJ_EDIT_SL;
   names[1] = PQE_OBJ_EDIT_TP;
   names[2] = PQE_OBJ_EDIT_RISK;
  }

//+------------------------------------------------------------------+
//| Vychozi hodnoty formulare.                                       |
//| Bere se ze vstupu experta; kdyz uz pole v grafu existuji (zmena  |
//| timeframe objekty nemaze), maji prednost hodnoty v nich, aby     |
//| prepnuti timeframe nevratilo uzivateli jeho upravy.              |
//+------------------------------------------------------------------+
void InitFormValues()
  {
   g_slPoints    = InpStopLossPoints;
   g_tpPoints    = InpTakeProfitPoints;
   g_riskPercent = InpRiskPercent;

   string names[];
   FormFieldNames(names);
   for(int i = 0; i < ArraySize(names); i++)
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

   double value = 0.0;
   if(!ParseNumber(text, value))
     {
      error = "'" + text + "' není číslo";
      return(false);
     }

   //--- Horni mez neni jen kosmetika: prevod na int nesmi pretect, jinak
   //--- by se z obrovske hodnoty stalo kladne cislo, ktere by kontrolami
   //--- proslo a panel by ukazoval nesmyslnou cenu SL / PT
   if(name == PQE_OBJ_EDIT_SL)
     {
      if(value < 1.0 || value > PQE_MAX_POINTS)
        {
         error = StringFormat("SL musí být v rozsahu 1..%d bodů", PQE_MAX_POINTS);
         return(false);
        }
      g_slPoints = (int)MathRound(value);
      return(true);
     }
   if(name == PQE_OBJ_EDIT_TP)
     {
      if(value < 0.0 || value > PQE_MAX_POINTS)
        {
         error = StringFormat("PT musí být v rozsahu 0..%d bodů", PQE_MAX_POINTS);
         return(false);
        }
      g_tpPoints = (int)MathRound(value);
      return(true);
     }
   if(name == PQE_OBJ_EDIT_RISK)
     {
      if(value <= 0.0 || value > PQE_MAX_RISK_PCT)
        {
         error = StringFormat("riziko musí být v rozsahu 0..%.0f %%", PQE_MAX_RISK_PCT);
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
      if(!ParseNumber(s, v) || v <= 0.0 || v > PQE_MAX_RISK_PCT)
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
   string names[];
   FormFieldNames(names);
   for(int i = 0; i < ArraySize(names); i++)
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
//| Symbol se nekontroluje - obchoduje se vzdy symbol grafu.         |
//+------------------------------------------------------------------+
string FormError()
  {
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
//| Povoluje prostredi obchodovat? (terminal, expert, ucet)          |
//|  reason - out: duvod zakazu                                      |
//| Rezim symbolu se resi zvlast - lisi se pro otevirani a zavirani. |
//+------------------------------------------------------------------+
bool TradingEnvAllowed(string &reason)
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
   return(reason == "");
  }

//+------------------------------------------------------------------+
//| Lze otevrit novy obchod? (prostredi + symbol plne obchodovatelny)|
//|  reason - out: duvod zakazu                                      |
//+------------------------------------------------------------------+
bool TradingAllowed(string &reason)
  {
   if(!TradingEnvAllowed(reason))
      return(false);

   const long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      reason = "symbol nelze obchodovat";
   else
      if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
         reason = "symbol je jen na zavírání";
   return(reason == "");
  }

//+------------------------------------------------------------------+
//| Lze zavirat pozice a rusit prikazy?                              |
//|  reason - out: duvod zakazu                                      |
//| Rezim SYMBOL_TRADE_MODE_CLOSEONLY zavirani naopak povoluje - je  |
//| to jedine, co v nem broker dovoli, a expert ho tedy nesmi brat   |
//| jako zakaz. Zakazane je zavirani jen u zcela vypnuteho symbolu.  |
//+------------------------------------------------------------------+
bool ClosingAllowed(string &reason)
  {
   if(!TradingEnvAllowed(reason))
      return(false);

   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      reason = "symbol nelze obchodovat";
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

   //--- Orez na maximum symbolu. VOLUME_MAX nemusi byt nasobkem kroku
   //--- objemu, proto se po orezu zaokrouhluje znovu dolu - jinak by
   //--- server prikaz odmitl s TRADE_RETCODE_INVALID_VOLUME.
   if(maxLot > 0.0 && lot > maxLot)
     {
      lot = maxLot;
      if(lotStep > 0.0)
         lot = MathFloor(lot / lotStep + PQE_LOTSTEP_EPS) * lotStep;
     }

   //--- Kontrola minima az po orezu: u nesmyslne nastaveneho symbolu
   //--- (VOLUME_MAX < VOLUME_MIN) by jinak prosel objem pod minimem
   if(lot < minLot)
     {
      reason = StringFormat("min. lot %s = %.2f %% > %.2f %%",
                            FormatLots(minLot), minLot * lossPerLot / balance * 100.0,
                            g_riskPercent);
      return(0.0);
     }

   return(NormalizeDouble(lot, VolumeDigits()));
  }

//--- Nazev zpusobu vstupu pro panel, nahled a log
string ModeName(const ENUM_PQE_MODE mode)
  {
   switch(mode)
     {
      case PQE_MODE_STOP:   return("STOP");
      case PQE_MODE_MARKET: return("MARKET");
      case PQE_MODE_LIMIT:  return("LIMIT");
      default:              return("?");
     }
  }

//+------------------------------------------------------------------+
//| Sestavi navrh vstupu z ceny pod kurzorem.                        |
//|  isBuy - smer, stopOnly - varianta BUYSTOP / SELLSTOP            |
//|  price - cena pod kurzorem, plan - out: navrh                    |
//| BUY nad Ask (+ stop level) = BUY STOP na kliknute cene. Pod Ask  |
//| dal nez stop level = BUY LIMIT na kliknute cene, na Ask nebo     |
//| tesne pod nim (broker by LIMIT odmitl) = BUY za trh. Pro SELL    |
//| zrcadlove k Bid. Varianta BUYSTOP / SELLSTOP LIMIT nezadava:     |
//| vsude pod Ask (SELL: nad Bid) vstupuje za trh.                   |
//| Pasmo mezi trhem a stop levelem broker pro STOP nepovoli a jako  |
//| trzni vstup by prekvapilo - tam se klik odmitne.                 |
//| SL a PT se meri od vstupni ceny, objem z rizika a vzdalenosti SL.|
//+------------------------------------------------------------------+
void BuildPlan(const bool isBuy, const bool stopOnly, double price, SEntryPlan &plan)
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

   //--- Urceni zpusobu vstupu podle polohy vuci trhu. U BUY / SELL ma
   //--- LIMIT prednost pred MARKET vsude, kde ho broker prijme (dal od
   //--- trhu nez stop level); MARKET tak zbyva jen tesne u trhu.
   //--- BUYSTOP / SELLSTOP LIMIT nezadava a vstupuje tam za trh.
   if(isBuy)
     {
      if(price > ask + stops)
         plan.mode = PQE_MODE_STOP;
      else
         if(!stopOnly && price < ask - stops)
            plan.mode = PQE_MODE_LIMIT;
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
         if(!stopOnly && price > bid + stops)
            plan.mode = PQE_MODE_LIMIT;
         else
            if(price >= bid)
              {
               plan.mode  = PQE_MODE_MARKET;
               plan.entry = bid;
              }
     }

   //--- U MARKET se vstup prepsal na Ask/Bid - i ten se zarovna, aby
   //--- vzdalenosti nize vychazely ze stejne mrizky jako SL a PT
   plan.entry = NormalizePrice(plan.entry);

   const double slDist = g_slPoints * _Point;
   const double tpDist = g_tpPoints * _Point;
   plan.sl = NormalizePrice(isBuy ? plan.entry - slDist : plan.entry + slDist);
   plan.tp = (tpDist > 0.0) ? NormalizePrice(isBuy ? plan.entry + tpDist : plan.entry - tpDist) : 0.0;

   //--- Skutecne vzdalenosti po zarovnani na krok kotace. Kdyz je krok
   //--- kotace vetsi nez bod (napr. indexove CFD s krokem 0.25 a bodem
   //--- 0.01), lisi se od nominalnich hodnot z formulare - a rozhoduje
   //--- ta skutecna, protoze ta se posila na server.
   const double slReal = MathAbs(plan.entry - plan.sl);
   const double tpReal = (plan.tp > 0.0) ? MathAbs(plan.tp - plan.entry) : 0.0;

   if(plan.mode == PQE_MODE_TOO_CLOSE)
     {
      plan.reason = StringFormat("moc blízko trhu (stop-level %.0f b)", stops / _Point);
      return;
     }

   //--- SL a PT musi respektovat stop level brokera
   if(slReal < stops)
     {
      plan.reason = StringFormat("SL < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }
   if(tpReal > 0.0 && tpReal < stops)
     {
      plan.reason = StringFormat("PT < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }

   //--- Objem se pocita ze skutecne vzdalenosti SL, ne z nominalni -
   //--- jinak by realna ztrata na SL neodpovidala zadanemu procentu
   string lotReason;
   plan.lots = CalcLot(slReal, lotReason);
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
//| Odesle prikaz podle navrhu (STOP, LIMIT nebo MARKET).            |
//|  plan - platny navrh vstupu                                      |
//| Vysledek se zapise do panelu i do logu. Vraci true pri uspechu.  |
//+------------------------------------------------------------------+
bool ExecutePlan(SEntryPlan &plan)
  {
   const string dir      = plan.isBuy ? "BUY" : "SELL";
   const string modeName = ModeName(plan.mode);
   const bool   market   = (plan.mode == PQE_MODE_MARKET);
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

      // STOP i LIMIT jsou cekajici prikazy na kliknute cene, lisi se jen typem
      if(plan.mode == PQE_MODE_STOP)
         ok = plan.isBuy
              ? g_trade.BuyStop(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                                typeTime, expiration, "PQE BUYSTOP")
              : g_trade.SellStop(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                                 typeTime, expiration, "PQE SELLSTOP");
      else
         ok = plan.isBuy
              ? g_trade.BuyLimit(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                                 typeTime, expiration, "PQE BUYLIMIT")
              : g_trade.SellLimit(plan.lots, plan.entry, _Symbol, plan.sl, plan.tp,
                                  typeTime, expiration, "PQE SELLLIMIT");
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

   // Vzdalenosti pro dorovnani SL/PT po vyplneni. Berou se z navrhu, ne
   // z formulare - navrh uz ma ceny zarovnane na krok kotace a dorovnani
   // musi vychazet ze stejnych hodnot, jake se poslaly na server.
   const double slDist = MathAbs(plan.entry - plan.sl);
   const double tpDist = (plan.tp > 0.0) ? MathAbs(plan.tp - plan.entry) : 0.0;
   RememberSent(ticket, slDist, tpDist);

   // Kratky tvar - radek panelu ma omezenou sirku
   g_lastEvent = StringFormat("%s %s #%I64u %s %s lot",
                              dir, modeName, ticket,
                              DoubleToString(price, _Digits), FormatLots(plan.lots));
   PrintFormat("PQE: %s %s #%I64u @ %s  SL %s  PT %s  %s lot  (riziko %.2f %%)",
               dir, modeName, ticket,
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
   //--- Jedina pozice: ticket uz je z OldestOurPosition znamy, cely
   //--- seznam pozic se proto neprochazi podruhe
   if(onlyOldest)
     {
      const ulong oldest = OldestOurPosition();
      if(oldest == 0)
         return(0);
      return(CloseOnePosition(oldest, failed) ? 1 : 0);
     }

   int closed = 0;
   //--- Od konce - seznam se zaviranim zkracuje
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      if(CloseOnePosition(ticket, failed))
         closed++;
     }
   return(closed);
  }

//+------------------------------------------------------------------+
//| Zavre jednu pozici za trh.                                       |
//|  ticket - ticket pozice, failed - in/out: pocet neuspechu        |
//| Vraci true pri uspechu, neuspech jde do logu.                    |
//+------------------------------------------------------------------+
bool CloseOnePosition(const ulong ticket, int &failed)
  {
   if(RequestAccepted(g_trade.PositionClose(ticket)))
      return(true);

   failed++;
   PrintFormat("PQE: pozici #%I64u se nepodařilo zavřít, retcode %d (%s)",
               ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
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
//| ZRUSIT PRIKAZY rusi jen cekajici prikazy (STOP i LIMIT), ZAVRIT 1|
//| zavre jednu pozici, ZAVRIT VSE zavre pozice i zrusi prikazy. Vzdy|
//| jen obchody experta (magic), cizi se nechavaji. Bez potvrzovani. |
//+------------------------------------------------------------------+
void OnCloseButton(const ENUM_PQE_CLOSE kind)
  {
   string reason;
   //--- Zavirani ma vlastni kontrolu: v rezimu "jen zavirani" je otevirani
   //--- zakazane, ale zavrit pozici je prave to jedine, co jeste jde
   if(!ClosingAllowed(reason))
      g_lastEvent = "zavřít nelze: " + reason;
   else
     {
      int closed = 0, deleted = 0, failed = 0;
      if(kind == PQE_CLOSE_ONE || kind == PQE_CLOSE_ALL)
         closed = ClosePositions(kind == PQE_CLOSE_ONE, failed);
      if(kind == PQE_CLOSE_ORDERS || kind == PQE_CLOSE_ALL)
         deleted = CancelOrders(failed);

      if(closed + deleted + failed == 0)
         g_lastEvent = (kind == PQE_CLOSE_ORDERS) ? "žádný čekající příkaz ke zrušení"
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

//--- Smer vyberu: true = BUY (BUY i BUYSTOP)
bool ArmIsBuy(const ENUM_PQE_ARM arm)
  {
   return(arm == PQE_ARM_BUY || arm == PQE_ARM_STOP_BUY);
  }

//--- Varianta BUYSTOP / SELLSTOP (jen STOP nebo MARKET, bez LIMIT)
bool ArmIsStopOnly(const ENUM_PQE_ARM arm)
  {
   return(arm == PQE_ARM_STOP_BUY || arm == PQE_ARM_STOP_SELL);
  }

//--- Stav vyberu pro dany smer a variantu tlacitka
ENUM_PQE_ARM ArmOf(const bool isBuy, const bool stopOnly)
  {
   if(stopOnly)
      return(isBuy ? PQE_ARM_STOP_BUY : PQE_ARM_STOP_SELL);
   return(isBuy ? PQE_ARM_BUY : PQE_ARM_SELL);
  }

//--- Nazev tlacitka / vyberu: BUY, SELL, BUYSTOP, SELLSTOP
string ArmName(const ENUM_PQE_ARM arm)
  {
   const string dir = ArmIsBuy(arm) ? "BUY" : "SELL";
   return(ArmIsStopOnly(arm) ? dir + "STOP" : dir);
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka BUY / SELL / BUYSTOP / SELLSTOP.                  |
//|  isBuy - smer, stopOnly - varianta BUYSTOP / SELLSTOP            |
//| Tlacitko se chova stridave: stisk zahaji vyber mista vstupu,     |
//| dalsi stisk tehoz tlacitka vyber zrusi; stisk jineho tlacitka    |
//| prepne smer nebo variantu.                                       |
//+------------------------------------------------------------------+
void OnDirectionButton(const bool isBuy, const bool stopOnly)
  {
   const ENUM_PQE_ARM dir = ArmOf(isBuy, stopOnly);
   const string dirText = ArmName(dir);

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
         // Kratky tvar, aby se i "SELLSTOP: ..." vesel na radek panelu
         g_lastEvent = dirText + ": klikni na místo vstupu";
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

   //--- Od stisku tlacitka mohla uplynout dlouha doba a podminky se mohly
   //--- zmenit (vypnuty Algo Trading, odebrane povoleni). Kontrola se
   //--- proto opakuje tesne pred odeslanim - jinak by misto srozumitelne
   //--- hlasky prisel jen holy retcode od serveru.
   string err = FormError();
   if(err != "" || !TradingAllowed(err))
     {
      const string message = ArmName(g_armed) + ": " + err;
      Disarm("");
      g_lastEvent = message;
      Print("PQE: ", g_lastEvent);
      UpdatePanel();
      ChartRedraw();
      return;
     }

   SEntryPlan plan;
   BuildPlan(ArmIsBuy(g_armed), ArmIsStopOnly(g_armed), price, plan);
   if(!plan.valid)
     {
      // Radek panelu se oreze, plne zneni duvodu jde do logu
      g_lastEvent = ArmName(g_armed) + ": " + plan.reason;
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
//| Linka vstupu (carkovana = STOP, cerchovana = LIMIT, plna =       |
//| MARKET, seda = nelze), linky SL a PT a popisek u kurzoru s tim,  |
//| co klik udela.                                                   |
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
      //--- Mazat a prekreslovat jen tehdy, kdyz nahled opravdu v grafu je -
      //--- pri kurzoru nad panelem sem jinak chodi kazdy tick nadarmo
      if(g_pvShown)
        {
         DeletePreview();
         ChartRedraw();
        }
      return;
     }

   SEntryPlan plan;
   BuildPlan(ArmIsBuy(g_armed), ArmIsStopOnly(g_armed), price, plan);

   const string dir      = plan.isBuy ? "BUY" : "SELL";
   const color  dirColor = plan.isBuy ? InpColorBuy : InpColorSell;
   const color  lineClr  = plan.valid ? dirColor : PQE_COLOR_OFF;

   string text;
   if(!plan.valid)
      text = dir + ": " + plan.reason;
   else
      text = StringFormat("%s %s @ %s  SL %s  PT %s  %s lot",
                          dir, ModeName(plan.mode),
                          DoubleToString(plan.entry, _Digits),
                          DoubleToString(plan.sl, _Digits),
                          plan.tp > 0.0 ? DoubleToString(plan.tp, _Digits) : "-",
                          FormatLots(plan.lots));

   //--- Nezmeneny nahled se nekresli znovu. OnTick chodi pri zpravach
   //--- i mnohokrat za sekundu a prekresleni celeho grafu je drahe;
   //--- popisek sleduje kurzor, takze do shody patri i jeho poloha.
   if(g_pvShown && text == g_pvText && g_mouseX == g_pvX && g_mouseY == g_pvY &&
      SamePrice(plan.entry, g_pvEntry) && SamePrice(plan.sl, g_pvSL) &&
      SamePrice(plan.tp, g_pvTP))
      return;

   //--- Styl linky rika, jaky prikaz klik zada: plna = MARKET,
   //--- carkovana = STOP, cerchovana = LIMIT
   const ENUM_LINE_STYLE style = (plan.mode == PQE_MODE_MARKET) ? STYLE_SOLID
                                 : (plan.mode == PQE_MODE_LIMIT) ? STYLE_DASHDOT
                                 : STYLE_DASH;
   DrawHLine(PQE_OBJ_PV_ENTRY, plan.entry, lineClr, style, 2);

   if(plan.sl > 0.0)
      DrawHLine(PQE_OBJ_PV_SL, plan.sl, InpColorSL, STYLE_DOT, 1);
   else
      ObjectDelete(0, PQE_OBJ_PV_SL);

   if(plan.tp > 0.0)
      DrawHLine(PQE_OBJ_PV_TP, plan.tp, InpColorTP, STYLE_DOT, 1);
   else
      ObjectDelete(0, PQE_OBJ_PV_TP);

   DrawLabel(PQE_OBJ_PV_LABEL, g_mouseX + Dpi(16), g_mouseY + Dpi(18), Fit(text), lineClr);

   //--- Vykresleny stav pro porovnani pri dalsim volani
   g_pvShown = true;
   g_pvEntry = plan.entry;
   g_pvSL    = plan.sl;
   g_pvTP    = plan.tp;
   g_pvText  = text;
   g_pvX     = g_mouseX;
   g_pvY     = g_mouseY;

   ChartRedraw();
  }

//--- Odstrani vsechny objekty nahledu vstupu
void DeletePreview()
  {
   ObjectDelete(0, PQE_OBJ_PV_ENTRY);
   ObjectDelete(0, PQE_OBJ_PV_SL);
   ObjectDelete(0, PQE_OBJ_PV_TP);
   ObjectDelete(0, PQE_OBJ_PV_LABEL);

   //--- Pamet vykresleneho nahledu uz neplati
   g_pvShown = false;
   g_pvText  = "";
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

//+------------------------------------------------------------------+
//| Spocte rozvrzeni panelu: polohu vsech radku i celkovou vysku.    |
//|  lo - out: rozvrzeni                                             |
//| Poradi shora: titulek, tri pole formulare, predvolby rizika, tri |
//| rady tlacitek (BUY / SELL, BUYSTOP / SELLSTOP, zavirani) a       |
//| stavove radky. Vyska vznika soucasne s polohami, takze pozadi    |
//| panelu i IsInsidePanel vzdy odpovidaji tomu, co je vykreslene -  |
//| pri pridani radku uz neni co udrzovat na dvou mistech.           |
//| Pod zapnutym One Click Trading se cely panel posune nize.        |
//+------------------------------------------------------------------+
void BuildLayout(SPanelLayout &lo)
  {
   lo.left = Dpi(InpPanelX);
   lo.top  = Dpi(InpPanelY);
   if(ChartGetInteger(0, CHART_SHOW_ONE_CLICK))
      lo.top += Dpi(InpPanelOneClickShift);

   lo.width   = Px(PQE_PANEL_W);
   lo.pad     = Px(PQE_PANEL_PAD);
   lo.gap     = Px(PQE_BTN_GAP);
   lo.btnH    = Px(PQE_BTN_H);
   lo.statusH = Px(PQE_STATUS_H);

   const int rowH = Px(PQE_ROW_H);
   int y = lo.top + lo.pad;

   lo.yTitle = y;
   y += rowH;
   for(int i = 0; i < PQE_FORM_FIELDS; i++)
     {
      lo.yFields[i] = y;
      y += rowH;
     }
   lo.yRisk = y;
   y += Px(PQE_RISK_BTN_H) + lo.gap;
   lo.yBuySell = y;
   y += lo.btnH + lo.gap;
   lo.yStops = y;
   y += lo.btnH + lo.gap;
   lo.yClose = y;
   y += lo.btnH + lo.gap;
   lo.yStatus = y;
   y += PQE_STATUS_LINES * lo.statusH;

   lo.height = y + lo.pad - lo.top;
  }

//--- Lezi bod (v pixelech) uvnitr panelu?
bool IsInsidePanel(const int x, const int y)
  {
   SPanelLayout lo;
   BuildLayout(lo);
   return(x >= lo.left && x <= lo.left + lo.width &&
          y >= lo.top  && y <= lo.top + lo.height);
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
   SPanelLayout lo;
   BuildLayout(lo);

   //--- Stav trhu a formulare se zjisti jednou a sdileji ho stavove
   //--- radky i vsechna tlacitka
   SPanelState st;
   BuildPanelState(st);

   const int x     = lo.left + lo.pad;        // levy okraj obsahu panelu
   const int inner = lo.width - 2 * lo.pad;   // sirka obsahu panelu

   DrawRect(PQE_OBJ_BG, lo.left, lo.top, lo.width, lo.height);

   //--- Titulek s aktualni cenou
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   DrawLabel(PQE_OBJ_TITLE, x, lo.yTitle + Px(3),
             Fit(StringFormat("VSTUP %s  Ask %s  Bid %s", _Symbol,
                              DoubleToString(ask, _Digits), DoubleToString(bid, _Digits)),
                 PanelMaxChars()),
             InpColorText);
   // Bublina titulku prozradi, ktery build v grafu opravdu bezi
   SetObjText(PQE_OBJ_TITLE, OBJPROP_TOOLTIP,
              "Puntiky Quick Entry - build " + BuildStamp());

   //--- Formular: popisek + editacni pole na kazdem radku (symbol se
   //--- bere z grafu a je v titulku)
   DrawFormRow(PQE_OBJ_EDIT_SL,   "SL (body)",  x, lo.yFields[0],
               IntegerToString(g_slPoints),
               "Stop loss v bodech od vstupní ceny");
   DrawFormRow(PQE_OBJ_EDIT_TP,   "PT (body)",  x, lo.yFields[1],
               IntegerToString(g_tpPoints),
               "Profit target v bodech od vstupní ceny (0 = bez PT)");
   DrawFormRow(PQE_OBJ_EDIT_RISK, "Riziko (%)", x, lo.yFields[2],
               DoubleToString(g_riskPercent, 2),
               "Riziko na obchod v procentech zůstatku účtu");

   //--- Predvolby rizika (vybrana je zvyraznena)
   DrawRiskButtons(x, lo.yRisk, inner);

   //--- Hlavni tlacitka BUY / SELL vedle sebe (STOP, LIMIT nebo MARKET)
   const int btnW = (inner - lo.gap) / 2;
   DrawDirectionButton(PQE_OBJ_BTN_BUY,  true,  false, x, lo.yBuySell, btnW, lo.btnH, st);
   DrawDirectionButton(PQE_OBJ_BTN_SELL, false, false, x + btnW + lo.gap, lo.yBuySell,
                       btnW, lo.btnH, st);

   //--- Pod nimi BUYSTOP / SELLSTOP (jen STOP nebo MARKET), stejne siroka
   DrawDirectionButton(PQE_OBJ_BTN_STOP_BUY,  true,  true, x, lo.yStops, btnW, lo.btnH, st);
   DrawDirectionButton(PQE_OBJ_BTN_STOP_SELL, false, true, x + btnW + lo.gap, lo.yStops,
                       btnW, lo.btnH, st);

   //--- Rada tlacitek zavirani: ZRUSIT PRIKAZY / ZAVRIT 1 / ZAVRIT VSE
   DrawCloseButtons(x, lo.yClose, inner, lo.btnH, st);

   //--- Stavove radky
   string lines[PQE_STATUS_LINES];
   BuildStatusLines(lines, st);
   int y = lo.yStatus;
   for(int i = 0; i < PQE_STATUS_LINES; i++)
     {
      DrawLabel(PQE_OBJ_STATUS + IntegerToString(i), x, y,
                Fit(lines[i], PanelMaxChars()), InpColorText);
      y += lo.statusH;
     }
  }

//+------------------------------------------------------------------+
//| Zjisti vse, co panel pri prekresleni potrebuje.                  |
//|  st - out: stav trhu a formulare                                 |
//| Pocty prikazu a pozic, povoleni obchodu i objem z rizika se ctou |
//| jednou za prekresleni. Drive si je stavove radky a kazde tlacitko|
//| zjistovaly zvlast, takze se cely seznam prikazu i pozic prochazel|
//| nekolikrat za sekundu.                                           |
//+------------------------------------------------------------------+
void BuildPanelState(SPanelState &st)
  {
   st.orders    = CountOurOrders();
   st.positions = CountOurPositions();
   st.formError = FormError();
   st.canTrade  = TradingAllowed(st.tradeReason);
   st.canClose  = ClosingAllowed(st.closeReason);
   st.balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   st.slDist    = g_slPoints * _Point;
   st.lots      = CalcLot(st.slDist, st.lotReason);
  }

//+------------------------------------------------------------------+
//| Sestavi texty stavovych radku panelu.                            |
//|  lines - out: pole radku (PQE_STATUS_LINES polozek)              |
//|  st    - stav spocteny pro toto prekresleni                      |
//+------------------------------------------------------------------+
void BuildStatusLines(string &lines[], const SPanelState &st)
  {
   //--- Stav: co se prave deje, nebo proc nejde obchodovat
   // Kratky tvar - i "stav: SELLSTOP - ..." se musi vejit na radek panelu
   if(g_armed != PQE_ARM_NONE)
      lines[0] = "stav: " + ArmName(g_armed) + " - klikni do grafu (Esc)";
   else
      if(st.formError != "")
         lines[0] = "stav: " + st.formError;
      else
         if(!st.canTrade)
            lines[0] = "stav: " + st.tradeReason;
         else
            lines[0] = "stav: připraven - stiskni BUY nebo SELL";

   //--- Objem z rizika pro aktualni SL a zustatek (texty jsou kratke,
   //--- radek panelu ma jen PanelMaxChars znaku)
   if(st.lots > 0.0)
     {
      const double risk = st.lots * LossPerLot(st.slDist);
      lines[1] = StringFormat("objem %s lot = %.2f %s (%.2f %%)",
                              FormatLots(st.lots), risk, AccountInfoString(ACCOUNT_CURRENCY),
                              st.balance > 0.0 ? risk / st.balance * 100.0 : 0.0);
     }
   else
      lines[1] = "objem: " + st.lotReason;

   //--- Vzdalenosti SL a PT prevedene na cenu
   lines[2] = StringFormat("SL %d b = %s   PT %s",
                           g_slPoints, DoubleToString(st.slDist, _Digits),
                           g_tpPoints > 0
                           ? StringFormat("%d b = %s", g_tpPoints, DoubleToString(g_tpPoints * _Point, _Digits))
                           : "bez PT");

   //--- Co uz na trhu lezi
   lines[3] = StringFormat("příkazy %d  pozice %d  zůstatek %.2f",
                           st.orders, st.positions, st.balance);

   lines[4] = "» " + g_lastEvent;
  }

//+------------------------------------------------------------------+
//| Vykresli radek formulare: popisek vlevo, editacni pole vpravo.   |
//|  name    - jmeno editacniho pole                                 |
//|  label   - popisek pole                                          |
//|  x, y    - levy horni roh radku v pixelech                       |
//|  initial - vychozi text pole (jen pri vzniku, uzivateli se       |
//|            rozepsany text neprepisuje)                           |
//|  tooltip - bublina pole                                          |
//+------------------------------------------------------------------+
void DrawFormRow(const string name, const string label, const int x, const int y,
                 const string initial, const string tooltip)
  {
   DrawLabel(name + "_LBL", x, y + Px(3), label, InpColorText);
   DrawEdit(name, x + Px(PQE_LABEL_W), y, Px(PQE_EDIT_W), Px(PQE_EDIT_H), initial, tooltip);
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko BUY / SELL / BUYSTOP / SELLSTOP a nastavi      |
//| mu podobu podle stavu. Behem vyberu se tlacitko zmeni na ZRUSIT, |
//| pri chybe formulare nebo zakazanem obchodovani zesedne a duvod   |
//| da do bubliny. Tlacitka BUYSTOP / SELLSTOP maji mensi pismo,     |
//| aby se vesel i text "ZRUSIT SELLSTOP".                           |
//|  name - jmeno objektu, isBuy - smer                              |
//|  stopOnly - varianta BUYSTOP / SELLSTOP                          |
//|  x, y - poloha, w, h - rozmery v pixelech                        |
//|  st - stav spocteny pro toto prekresleni                         |
//+------------------------------------------------------------------+
void DrawDirectionButton(const string name, const bool isBuy, const bool stopOnly,
                         const int x, const int y, const int w, const int h,
                         const SPanelState &st)
  {
   const ENUM_PQE_ARM armDir = ArmOf(isBuy, stopOnly);
   const string dir   = ArmName(armDir);

   string text    = dir;
   string tooltip = "";
   color  bg      = stopOnly ? (isBuy ? PQE_COLOR_BTN_STOP_BUY : PQE_COLOR_BTN_STOP_SELL)
                             : (isBuy ? PQE_COLOR_BTN_BUY : PQE_COLOR_BTN_SELL);

   if(g_armed == armDir)
     {
      text    = "ZRUŠIT " + dir;
      bg      = PQE_COLOR_BTN_CANCEL;
      tooltip = "Zruší výběr místa vstupu.";
     }
   else
      if(st.formError != "" || !st.canTrade)
        {
         bg      = PQE_COLOR_BTN_OFF;
         tooltip = "Nelze obchodovat: " +
                   (st.formError != "" ? st.formError : st.tradeReason);
        }
      else
         if(stopOnly)
            tooltip = isBuy
                      ? "Klik nad Ask = BUY STOP, klik na Ask nebo pod ním = BUY za trh (LIMIT nezadává)."
                      : "Klik pod Bid = SELL STOP, klik na Bid nebo nad ním = SELL za trh (LIMIT nezadává).";
         else
            tooltip = isBuy
                      ? "Klik nad Ask = BUY STOP, klik pod Ask = BUY LIMIT, klik těsně pod Ask (do stop-levelu) = BUY za trh."
                      : "Klik pod Bid = SELL STOP, klik nad Bid = SELL LIMIT, klik těsně nad Bid (do stop-levelu) = SELL za trh.";

   DrawButton(name, x, y, w, h, text, bg, tooltip,
              stopOnly ? PQE_BTN_FONT_PLUS_SMALL : PQE_BTN_FONT_PLUS);
  }

//+------------------------------------------------------------------+
//| Vykresli radu tlacitek zavirani a nastavi jim podobu podle trhu: |
//|  ZRUSIT PRIKAZY - zrusi vsechny cekajici prikazy STOP i LIMIT    |
//|                   (pozice necha)                                 |
//|  ZAVRIT 1       - zavre jednu (nejstarsi) pozici za trh          |
//|  ZAVRIT VSE     - zavre vsechny pozice a zrusi vsechny prikazy   |
//| Tlacitko, pro ktere na trhu nic neni nebo ktere nelze pouzit,    |
//| zesedne a duvod ma v bubline. Pocty jsou i na stavovem radku     |
//| "prikazy / pozice". Sirky tlacitek jsou podle delky popisku, aby |
//| se vesel i nejdelsi "ZRUSIT PRIKAZY".                            |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//|  btnH - vyska tlacitek                                           |
//|  st   - stav spocteny pro toto prekresleni                       |
//+------------------------------------------------------------------+
void DrawCloseButtons(const int x, const int y, const int w, const int btnH,
                      const SPanelState &st)
  {
   const int gap = Px(PQE_BTN_GAP);

   //--- Rozdeleni sirky: nejdelsi popisek dostane nejvic, posledni
   //--- tlacitko zbytek, aby rada koncila zarovnane
   const int inner   = w - 2 * gap;
   const int cancelW = (int)MathRound(inner * PQE_CLOSE_SHARE_CANCEL);
   const int oneW    = (int)MathRound(inner * PQE_CLOSE_SHARE_ONE);
   const int allW    = inner - cancelW - oneW;

   //--- Kdyz zavirat nejde vubec, zesednou vsechna tri tlacitka a duvod
   //--- je v bubline - drive vypadala aktivne a klik jen tise nic neudelal
   const string blocked = st.canClose ? "" : "Nelze zavírat: " + st.closeReason;

   string tip = blocked;
   if(tip == "")
      tip = st.orders > 0
            ? StringFormat("Zruší všechny čekající příkazy experta (STOP i LIMIT, celkem %d), pozice nechá.", st.orders)
            : "Žádný čekající příkaz experta.";
   DrawButton(PQE_OBJ_BTN_CANCEL_ORDERS, x, y, cancelW, btnH, "ZRUŠIT PŘÍKAZY",
              (st.canClose && st.orders > 0) ? PQE_COLOR_BTN_CANCEL_ORD : PQE_COLOR_BTN_OFF,
              tip, PQE_BTN_FONT_PLUS_SMALL);

   tip = blocked;
   if(tip == "")
      tip = st.positions > 0
            ? StringFormat("Zavře jednu (nejstarší) pozici experta za trh, otevřeno: %d.", st.positions)
            : "Žádná otevřená pozice experta.";
   DrawButton(PQE_OBJ_BTN_CLOSE_ONE, x + cancelW + gap, y, oneW, btnH, "ZAVŘÍT 1",
              (st.canClose && st.positions > 0) ? PQE_COLOR_BTN_CLOSE_ONE : PQE_COLOR_BTN_OFF,
              tip, PQE_BTN_FONT_PLUS_SMALL);

   tip = blocked;
   if(tip == "")
      tip = (st.orders + st.positions) > 0
            ? StringFormat("Zavře všechny pozice experta (%d) a zruší jeho čekající příkazy (%d).", st.positions, st.orders)
            : "Expert nemá na trhu pozici ani příkaz.";
   DrawButton(PQE_OBJ_BTN_CLOSE_ALL, x + cancelW + gap + oneW + gap, y, allW, btnH, "ZAVŘÍT VŠE",
              (st.canClose && (st.orders + st.positions) > 0) ? PQE_COLOR_BTN_CLOSE : PQE_COLOR_BTN_OFF,
              tip, PQE_BTN_FONT_PLUS_SMALL);
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
//| Zapis vlastnosti objektu jen pri zmene.                          |
//|  name - jmeno objektu, prop - vlastnost, value - hodnota         |
//| Panel se prekresluje kazdou sekundu a kazdy ObjectSet* je volani |
//| do terminalu. U OBJ_EDIT navic zbytecny zapis muze zahodit text, |
//| ktery uzivatel prave pise.                                       |
//+------------------------------------------------------------------+
void SetObjLong(const string name, const ENUM_OBJECT_PROPERTY_INTEGER prop, const long value)
  {
   if(ObjectGetInteger(0, name, prop) != value)
      ObjectSetInteger(0, name, prop, value);
  }

//--- Textova vlastnost objektu, zapis jen pri zmene
void SetObjText(const string name, const ENUM_OBJECT_PROPERTY_STRING prop, const string value)
  {
   if(ObjectGetString(0, name, prop) != value)
      ObjectSetString(0, name, prop, value);
  }

//--- Poloha a rozmery objektu (px), zapis jen pri zmene
void SetObjGeometry(const string name, const int x, const int y, const int w, const int h)
  {
   SetObjLong(name, OBJPROP_XDISTANCE, x);
   SetObjLong(name, OBJPROP_YDISTANCE, y);
   SetObjLong(name, OBJPROP_XSIZE, w);
   SetObjLong(name, OBJPROP_YSIZE, h);
  }

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
   SetObjGeometry(name, x, y, w, h);
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
      //--- Bez vlastni bubliny by terminal ukazoval interni jmeno objektu;
      //--- "\n" ji vypne (titulek si pozdeji nastavi vlastni text)
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
     }
   SetObjLong(name, OBJPROP_XDISTANCE, x);
   SetObjLong(name, OBJPROP_YDISTANCE, y);
   SetObjText(name, OBJPROP_TEXT, text);
   SetObjLong(name, OBJPROP_COLOR, (long)clr);
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
   SetObjGeometry(name, x, y, w, h);
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
   SetObjGeometry(name, x, y, w, h);
   SetObjText(name, OBJPROP_TEXT, text);
   SetObjLong(name, OBJPROP_BGCOLOR, (long)bg);
   SetObjText(name, OBJPROP_TOOLTIP, tooltip);
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
      //--- Linka jede za kurzorem, takze mys je nad ni porad a terminal
      //--- by u ni stale ukazoval bublinu "jmeno + cena". Hodnota "\n"
      //--- automatickou bublinu vypina.
      ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
     }
   //--- Nahled jede za mysi a prekresluje se casto - zapisuje se jen to,
   //--- co se opravdu zmenilo
   if(ObjectGetDouble(0, name, OBJPROP_PRICE) != price)
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   SetObjLong(name, OBJPROP_COLOR, (long)clr);
   SetObjLong(name, OBJPROP_STYLE, (long)style);
   SetObjLong(name, OBJPROP_WIDTH, width);
  }
//+------------------------------------------------------------------+
