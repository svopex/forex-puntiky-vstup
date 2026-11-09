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
//|  BUY MARKET / SELL MARKET vstoupi za trh hned, bez kliku do      |
//|  grafu. Spodni rada tlacitek zavre zadane procento puvodniho     |
//|  objemu pozice, kdyz je otevrena prave jedna pozice experta.     |
//|  Tlacitko "nastav" u SL zmeri SL a PT v grafu: 1. klik = vychozi |
//|  bod, 2. klik = konec; vzdalenost se zapise do SL i PT.          |
//|  Tlacitka rozdeleni pod rizikem urci, kolik pozic vstup otevre:  |
//|  pozice k ma PT = k x PT, SL je vsem spolecny a riziko se mezi   |
//|  pozice deli podle zvoleneho pomeru (100 %, 50/50, 50/40/10,     |
//|  40/35/25 - prvni podil patri nejblizsimu PT).                   |
//|  Dve rady pod castecnym zavrenim posouvaji o maly / stredni /    |
//|  velky krok nahoru (1. rada) nebo dolu (2. rada) bud SL vsech    |
//|  pozic a prikazu experta, nebo cele cekajici prikazy; rezim SL / |
//|  PO se prepina prvnimi tlacitky rad.                             |
//|  SJEDNOTIT SL / SJEDNOTIT PO srovna ruzne SL (zvlast BUY a SELL) |
//|  nebo ceny cekajicich prikazu (zvlast kazdy typ) na jejich       |
//|  prumernou uroven.                                               |
//+------------------------------------------------------------------+
// Verze experta - zvysuje se pred kazdym nasazenim (viz README, Verzovani)
#define EA_VERSION "1.91"

#property copyright "Puntiky"
#property version   EA_VERSION
#property description "Rychlý vstup: BUY/SELL (STOP, LIMIT nebo MARKET) či BUYSTOP/SELLSTOP + klik do grafu, nebo BUY/SELL MARKET hned; 1-3 pozice s PT, 2xPT, 3xPT a rozdělením rizika; částečné zavření pozice; posun a sjednocení SL a čekajících příkazů"

// Vychozi predvolby tlacitek - pouzije je vstup i nahradni rada, kdyz
// vstup neobsahuje zadnou platnou hodnotu
#define PQE_DEFAULT_RISK_PRESETS  "0.5;1;1.5;2;2.5;3"
#define PQE_DEFAULT_CLOSE_PRESETS "100;50;25;15"

#include <Trade\Trade.mqh>

//--- Obchod
input group "=== Obchod ==="
input int    InpStopLossPoints     = 300;               // Stop loss (body, předvyplní se do formuláře)
input int    InpTakeProfitPoints   = 300;               // Profit target (body, 0 = bez PT, předvyplní se)
input double InpRiskPercent        = 1.0;               // Riziko na obchod (% zůstatku, předvyplní se)
input string InpRiskPresets        = PQE_DEFAULT_RISK_PRESETS;  // Předvolby rizika pro tlačítka (%, oddělené ;)
input string InpClosePresets       = PQE_DEFAULT_CLOSE_PRESETS; // Částečné zavření jediné pozice (% původního objemu, oddělené ;)
input int    InpSlippage           = 20;                // Maximální skluz MARKET příkazu (body)
input int    InpExpirationMinutes  = 0;                 // Platnost čekajícího příkazu STOP/LIMIT (minuty, 0 = do zrušení)
input bool   InpAlignStopsToFill   = true;              // Po vyplnění dorovnat SL/PT na skutečnou plnicí cenu
input long   InpMagic              = 202608281524;      // Magic number

//--- Posun SL a cekajicich prikazu tlacitky v panelu
input group "=== Posun SL / příkazů ==="
input int    InpMoveMinPoints      = 10;                // Posun - malý krok na doladění (body)
input int    InpMoveMidPoints      = 50;                // Posun - střední krok (body)
input int    InpMoveMaxPoints      = 200;               // Posun - velký krok (body)

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
#define PQE_MEASURE_W        52          // sirka tlacitka "nastav" mezi popiskem a polem SL
#define PQE_MEASURE_GAP      6           // mezera mezi tlacitkem "nastav" a editacnim polem
#define PQE_BTN_H            36          // vyska tlacitek
#define PQE_BTN_GAP          8           // mezera kolem tlacitek
#define PQE_BTN_FONT_PLUS    3           // o kolik je pismo BUY / SELL vetsi nez pismo panelu
#define PQE_BTN_FONT_PLUS_SMALL 1        // totez pro tlacitka BUYSTOP / SELLSTOP, MARKET a zavirani
#define PQE_STATUS_H         20          // vyska stavoveho radku
#define PQE_STATUS_LINES     5           // pocet stavovych radku
#define PQE_RISK_BTN_H       24          // vyska tlacitek predvoleb rizika
#define PQE_RISK_BTN_GAP     6           // mezera mezi tlacitky predvoleb rizika
#define PQE_MAX_RISK_PRESETS 8           // nejvyse tolik predvoleb rizika
#define PQE_MAX_CLOSE_PRESETS 4          // nejvyse tolik tlacitek castecneho zavreni (popisky jsou delsi)
#define PQE_MAX_POSITIONS    3           // nejvyse tolik pozic na jeden vstup
#define PQE_SPLIT_PRESETS    4           // tlacitka rozdeleni rizika (100%, 50/50, 50/40/10, 40/35/25)
#define PQE_MOVE_STEPS       3           // kroky posunu v rade (maly, stredni, velky)
#define PQE_SL_GROUPS        2           // skupiny sjednoceni SL: nakupy, prodeje
#define PQE_PENDING_TYPES    4           // skupiny sjednoceni prikazu: BUY/SELL LIMIT, BUY/SELL STOP
#define PQE_RISK_EPS         0.005       // tolerance shody rizika s predvolbou (%)
#define PQE_MAX_POINTS       1000000     // horni mez SL / PT v bodech (chrani prevod na int)
#define PQE_MAX_RISK_PCT     100.0       // horni mez rizika na obchod (% zustatku)
#define PQE_MAX_CLOSE_PCT    100.0       // horni mez castecneho zavreni (% puvodniho objemu)
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
#define PQE_MAX_VOL_CACHE    64          // pamet puvodnich objemu pozic (castecne zavreni)
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
#define PQE_COLOR_BTN_MKT_BUY   C'0,140,90'  // tlacitko BUY MARKET (do tyrkysova, aby se nepletlo s BUY)
#define PQE_COLOR_BTN_MKT_SELL  C'175,0,70'  // tlacitko SELL MARKET (do purpurova, aby se nepletlo se SELL)
#define PQE_COLOR_BTN_PARTIAL   C'130,70,0'  // tlacitka castecneho zavreni (je otevrena prave jedna pozice)
#define PQE_COLOR_BTN_MOVE_UP   C'30,90,60'  // posun nahoru
#define PQE_COLOR_BTN_MOVE_DOWN C'110,45,45' // posun dolu
#define PQE_COLOR_BTN_CONSOLIDATE C'90,60,130' // sjednoceni SL / cekajicich prikazu
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
#define PQE_OBJ_BTN_MKT_BUY   (PQE_PREFIX + "BTN_MKT_BUY")
#define PQE_OBJ_BTN_MKT_SELL  (PQE_PREFIX + "BTN_MKT_SELL")
#define PQE_OBJ_BTN_CANCEL_ORDERS (PQE_PREFIX + "BTN_CANCEL_ORDERS")
#define PQE_OBJ_BTN_CLOSE_ONE     (PQE_PREFIX + "BTN_CLOSE_ONE")
#define PQE_OBJ_BTN_CLOSE_ALL     (PQE_PREFIX + "BTN_CLOSE_ALL")
#define PQE_OBJ_BTN_RISK          (PQE_PREFIX + "BTN_RISK_")     // + poradi predvolby
#define PQE_OBJ_BTN_PARTIAL       (PQE_PREFIX + "BTN_PART_")     // + poradi predvolby zavreni
#define PQE_OBJ_BTN_SPLIT         (PQE_PREFIX + "BTN_SPLIT_")    // + poradi tlacitka rozdeleni rizika (0 = 100 %)
#define PQE_OBJ_BTN_MOVE_SL       (PQE_PREFIX + "BTN_MVMODE_SL") // rezim posunu: SL
#define PQE_OBJ_BTN_MOVE_PO       (PQE_PREFIX + "BTN_MVMODE_PO") // rezim posunu: cekajici prikazy
#define PQE_OBJ_BTN_MOVE_UP       (PQE_PREFIX + "BTN_MVUP_")     // + krok posunu nahoru (0 = maly)
#define PQE_OBJ_BTN_MOVE_DOWN     (PQE_PREFIX + "BTN_MVDN_")     // + krok posunu dolu (0 = maly)
#define PQE_OBJ_BTN_CONS_SL       (PQE_PREFIX + "BTN_CONS_SL")   // sjednotit SL na prumer
#define PQE_OBJ_BTN_CONS_PO       (PQE_PREFIX + "BTN_CONS_PO")   // sjednotit ceny cekajicich prikazu na prumer
#define PQE_OBJ_BTN_MEASURE       (PQE_PREFIX + "BTN_MEASURE")   // "nastav" - mereni SL/PT v grafu
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

//--- Stav mereni SL/PT v grafu (tlacitko "nastav")
enum ENUM_PQE_MEASURE
  {
   PQE_MEASURE_NONE = 0,   // nic se nemeri
   PQE_MEASURE_FROM = 1,   // ceka se na 1. klik (vychozi bod)
   PQE_MEASURE_TO   = 2    // ceka se na 2. klik (konec vzdalenosti)
  };

//--- Zpusob vstupu podle polohy kliknuti vuci trhu
enum ENUM_PQE_MODE
  {
   PQE_MODE_STOP,      // STOP prikaz na kliknute cene
   PQE_MODE_MARKET,    // MARKET prikaz za aktualni cenu
   PQE_MODE_LIMIT,     // LIMIT prikaz na kliknute cene (jen BUY / SELL, BUYSTOP / SELLSTOP ho nezadava)
   PQE_MODE_TOO_CLOSE  // uvnitr stop-levelu brokera, nelze zadat
  };

//--- Jake prikazy tlacitko vstupu zadava
enum ENUM_PQE_ENTRY
  {
   PQE_ENTRY_ANY,       // BUY / SELL: STOP, LIMIT nebo MARKET podle kliknute ceny
   PQE_ENTRY_NO_LIMIT,  // BUYSTOP / SELLSTOP: STOP nebo MARKET, LIMIT nikdy
   PQE_ENTRY_MARKET     // BUY / SELL MARKET: vzdy za trh, bez kliku do grafu
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
   double            tp;        // profit target 1. pozice (0 = bez PT); pozice k ma k-nasobnou vzdalenost
   int               count;     // pocet pozic, ktere vstup otevre
   double            lots[PQE_MAX_POSITIONS]; // objem kazde pozice (podle jejiho podilu rizika)
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

//--- Pamet puvodnich objemu pozic (InitialVolume). Historie obchodu se
//--- cte znovu jen pri zmene objemu pozice - panel se pta kazdou sekundu.
struct SVolumeCache
  {
   long              posId;     // identifikator pozice (0 = prazdny slot, skutecne id je vzdy kladne)
   double            current;   // objem pozice v dobe vypoctu
   double            initial;   // spocteny puvodni objem
  };

//--- Otevrena pozice experta pro castecne zavreni
struct SPositionVolume
  {
   ulong             ticket;    // ticket pozice
   double            initial;   // puvodni (celkovy) objem
   double            current;   // aktualni objem
  };

//--- Stav trhu a formulare spocteny jednou za prekresleni panelu.
//--- Panel se obnovuje kazdou sekundu a kazdy dotaz do terminalu (pocty
//--- prikazu, povoleni obchodu) neco stoji - drive si je stavove radky
//--- i jednotliva tlacitka zjistovaly kazde zvlast.
struct SPanelState
  {
   int               orders;       // pocet cekajicich prikazu experta
   int               positions;    // pocet otevrenych pozic experta
   SPositionVolume   posVolumes[]; // ty pozice s objemy (castecne zavreni)
   string            formError;    // chyba formulare ("" = v poradku)
   bool              canTrade;     // lze otevrit novy obchod
   string            tradeReason;  // duvod zakazu otevirani
   bool              canClose;     // lze zavirat pozice a rusit prikazy
   string            closeReason;  // duvod zakazu zavirani
   double            balance;      // zustatek uctu
   double            slDist;       // vzdalenost SL v cene podle formulare
   int               count;        // pocet pozic vstupu podle zvoleneho rozdeleni rizika
   bool              lotsOk;       // objemy pozic lze pouzit
   double            lots[PQE_MAX_POSITIONS]; // objemy pozic vstupu z rizika
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
   int               ySplit;       // rada tlacitek rozdeleni rizika mezi pozice
   int               yBuySell;     // tlacitka BUY / SELL
   int               yStops;       // tlacitka BUYSTOP / SELLSTOP
   int               yMarket;      // tlacitka BUY MARKET / SELL MARKET
   int               yClose;       // rada tlacitek zavirani
   int               yPartial;     // rada tlacitek castecneho zavreni
   int               yMoveUp;      // rada posunu SL / prikazu nahoru
   int               yMoveDown;    // rada posunu SL / prikazu dolu
   int               yConsolidate; // rada SJEDNOTIT SL / SJEDNOTIT PO
   int               yStatus;      // prvni stavovy radek
  };

//--- Globalni stav
CTrade        g_trade;                        // obchodni rozhrani
ENUM_PQE_ARM  g_armed       = PQE_ARM_NONE;   // probihajici vyber mista vstupu
uint          g_armedAt     = 0;              // cas aktivace vyberu nebo mereni (GetTickCount)
ENUM_PQE_MEASURE g_measure  = PQE_MEASURE_NONE; // probihajici mereni SL/PT v grafu
double        g_measureFrom = 0.0;            // cena 1. kliku mereni
string        g_lastEvent   = "";             // posledni akce pro panel a log
int           g_slPoints    = 0;              // hodnoty formulare (posledni platne)
int           g_tpPoints    = 0;
double        g_riskPercent = 0.0;
int           g_splitIndex  = 0;              // zvolene rozdeleni rizika (radek g_splitShares, 0 = 100 %)

//--- Rozdeleni rizika vstupu mezi pozice (% rizika, 0 = pozice se neotevira).
//--- Pozice k ma PT = k x PT: prvni podil patri nejblizsimu PT, posledni
//--- nejvzdalenejsimu. Kazdy radek je jedno tlacitko v panelu.
const double  g_splitShares[PQE_SPLIT_PRESETS][PQE_MAX_POSITIONS] =
  {
     {100.0,  0.0,  0.0},
     { 50.0, 50.0,  0.0},
     { 50.0, 40.0, 10.0},
     { 40.0, 35.0, 25.0}
  };
bool          g_moveOrders  = false;          // co tlacitka posunu hybou: false = SL, true = cele cekajici prikazy
SSentOrder   g_sent[PQE_MAX_SENT];           // kruhova pamet odeslanych prikazu
int           g_sentNext    = 0;              // dalsi volny slot v pameti
int           g_mouseX      = -1;             // posledni poloha mysi (obnova nahledu po ticku)
int           g_mouseY      = -1;
double        g_dpiScale    = 1.0;            // meritko DPI monitoru (1.0 = 96 DPI)
double        g_layoutScale = 1.0;            // meritko rozmeru panelu (DPI x velikost pisma)
double        g_riskPresets[];                // predvolby rizika pro tlacitka (%)
double        g_closePresets[];               // predvolby castecneho zavreni (% puvodniho objemu)

SVolumeCache  g_volCache[PQE_MAX_VOL_CACHE]; // kruhova pamet puvodnich objemu pozic
int           g_volCacheNext = 0;             // dalsi volny slot v pameti

//--- Naposledy vykresleny nahled vstupu. Slouzi k tomu, aby se graf
//--- neprekresloval, kdyz se nahled nezmenil - OnTick chodi pri zpravach
//--- i mnohokrat za sekundu a ChartRedraw je drahy.
bool          g_pvShown     = false;          // je nahled prave v grafu?
double        g_pvEntry     = 0.0;            // vykreslena cena vstupu
double        g_pvSL        = 0.0;            // vykreslena cena SL
double        g_pvTP        = 0.0;            // vykreslena cena PT
int           g_pvTpLines   = 0;              // pocet vykreslenych linek PT (jedna na pozici)
string       g_pvText      = "";             // vykresleny popisek u kurzoru
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
      InpSlippage < 0 || InpExpirationMinutes < 0 || InpPanelFontSize < 6 ||
      !MoveStepsValid())
     {
      PrintFormat("PQE: neplatné vstupy - SL 1..%d b, PT 0..%d b, riziko 0..%.0f %%, "
                  "skluz >= 0, platnost >= 0, písmo >= 6, kroky posunu 1..%d b.",
                  PQE_MAX_POINTS, PQE_MAX_POINTS, PQE_MAX_RISK_PCT, PQE_MAX_POINTS);
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

   ParsePresets(InpRiskPresets, PQE_DEFAULT_RISK_PRESETS, "InpRiskPresets",
                PQE_MAX_RISK_PCT, PQE_MAX_RISK_PRESETS, g_riskPresets);
   ParsePresets(InpClosePresets, PQE_DEFAULT_CLOSE_PRESETS, "InpClosePresets",
                PQE_MAX_CLOSE_PCT, PQE_MAX_CLOSE_PRESETS, g_closePresets);

   for(int i = 0; i < PQE_MAX_SENT; i++)
      g_sent[i].ticket = 0;

   //--- Vic pozic na vstup jen na hedging uctu. Zmena uctu znovu vola
   //--- OnInit, invariant tak plati po celou dobu behu a navrh vstupu
   //--- ani panel ho uz kontrolovat nemusi.
   if(CountBlockReason(SplitCount(g_splitIndex)) != "")
      g_splitIndex = 0;

   InitFormValues();
   UpdatePanel();

   //--- Nahled vstupu jede za mysi, proto se zapnou udalosti pohybu mysi
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   EventSetTimer(1);
   ChartRedraw();

   // Cas kompilace v logu: terminal po externi kompilaci experta ne vzdy
   // znovu nacte a v grafu pak bezi stara verze - podle razitka se to pozna
   PrintFormat("PQE: rychlý vstup v%s spuštěn na %s - SL %d b, PT %d b, riziko %.2f %%, magic %I64d, build %s",
               EA_VERSION, _Symbol, g_slPoints, g_tpPoints, g_riskPercent, InpMagic, BuildStamp());
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

   Disarm("");

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
         // Linka nahledu jede presne pod kurzorem, takze klik do grafu
         // muze prijit jako klik na ni - bere se stejne jako klik do grafu
         if(StringFind(sparam, PQE_PREFIX + "PV_") == 0)
            OnChartPointClick((int)lparam, (int)dparam);
         else
            if(StringFind(sparam, PQE_PREFIX + "BTN_") == 0)
              {
               // MT5 necha tlacitko "zamacknute", vraci se rucne - jednou pro vsechna
               ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
               OnPanelButton(sparam);
              }
         break;

      case CHARTEVENT_CLICK:
         OnChartPointClick((int)lparam, (int)dparam);
         break;

      case CHARTEVENT_MOUSE_MOVE:
         g_mouseX = (int)lparam;
         g_mouseY = (int)dparam;
         // Mereni a vyber vstupu nikdy nebezi soucasne
         if(g_measure != PQE_MEASURE_NONE)
            UpdateMeasurePreview();
         else
            if(g_armed != PQE_ARM_NONE)
               UpdatePreview();
         break;

      case CHARTEVENT_OBJECT_ENDEDIT:
         if(StringFind(sparam, PQE_PREFIX + "EDIT_") == 0)
            OnFieldEdited(sparam);
         break;

      case CHARTEVENT_KEYDOWN:
         // Esc zrusi to, co prave probiha - mereni SL/PT, nebo vyber vstupu
         if(lparam != PQE_KEY_ESCAPE ||
            (g_measure == PQE_MEASURE_NONE && g_armed == PQE_ARM_NONE))
            break;
         Disarm(g_measure != PQE_MEASURE_NONE ? "měření SL/PT zrušeno (Esc)"
                                              : "výběr zrušen (Esc)");
         UpdatePanel();
         ChartRedraw();
         break;
     }
  }

//+------------------------------------------------------------------+
//| Klik do grafu (nebo na linku nahledu pod kurzorem).              |
//|  x, y - souradnice kliknuti v pixelech                           |
//| Preda kliknutou cenu mereni SL/PT, nebo vyberu mista vstupu -    |
//| podle toho, co prave bezi. Klik do panelu a klik tesne po stisku |
//| tlacitka (stejne kliknuti muze prijit jeste jako udalost grafu)  |
//| se ignoruji pro oba rezimy.                                      |
//+------------------------------------------------------------------+
void OnChartPointClick(const int x, const int y)
  {
   if(g_measure == PQE_MEASURE_NONE && g_armed == PQE_ARM_NONE)
      return;
   if(GetTickCount() - g_armedAt < PQE_CLICK_GUARD_MS)
      return;

   double price = 0.0;
   if(!ChartPointPrice(x, y, price))
      return;

   if(g_measure != PQE_MEASURE_NONE)
      HandleMeasureClick(price);
   else
      HandleChartClick(price);
  }

//+------------------------------------------------------------------+
//| Poradi tlacitka v rade predvoleb podle jmena objektu.            |
//|  name - jmeno objektu, prefix - spolecny zacatek jmen rady       |
//| Vraci -1, kdyz jmeno k rade nepatri.                             |
//+------------------------------------------------------------------+
int PresetIndex(const string name, const string prefix)
  {
   if(StringFind(name, prefix) != 0)
      return(-1);
   return((int)StringToInteger(StringSubstr(name, StringLen(prefix))));
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka panelu - rozdeleni podle jmena objektu.           |
//|  name - jmeno stisknuteho tlacitka                               |
//+------------------------------------------------------------------+
void OnPanelButton(const string name)
  {
   //--- Vstup s vyberem mista v grafu (BUY / SELL / BUYSTOP / SELLSTOP)
   if(name == PQE_OBJ_BTN_BUY || name == PQE_OBJ_BTN_SELL ||
      name == PQE_OBJ_BTN_STOP_BUY || name == PQE_OBJ_BTN_STOP_SELL)
     {
      OnDirectionButton(name == PQE_OBJ_BTN_BUY || name == PQE_OBJ_BTN_STOP_BUY,
                        name == PQE_OBJ_BTN_STOP_BUY || name == PQE_OBJ_BTN_STOP_SELL);
      return;
     }

   //--- Vstup za trh hned, bez vyberu mista v grafu
   if(name == PQE_OBJ_BTN_MKT_BUY || name == PQE_OBJ_BTN_MKT_SELL)
     {
      OnMarketButton(name == PQE_OBJ_BTN_MKT_BUY);
      return;
     }

   //--- Mereni SL/PT v grafu (tlacitko "nastav" u pole SL)
   if(name == PQE_OBJ_BTN_MEASURE)
     {
      OnMeasureButton();
      return;
     }

   //--- Sjednoceni SL nebo cen cekajicich prikazu na prumer
   if(name == PQE_OBJ_BTN_CONS_SL || name == PQE_OBJ_BTN_CONS_PO)
     {
      OnConsolidateButton(name == PQE_OBJ_BTN_CONS_PO);
      return;
     }

   //--- Prepinac rezimu posunu: SL nebo cele cekajici prikazy (PO)
   if(name == PQE_OBJ_BTN_MOVE_SL || name == PQE_OBJ_BTN_MOVE_PO)
     {
      OnMoveModeButton(name == PQE_OBJ_BTN_MOVE_PO);
      return;
     }

   //--- Rada zavirani
   if(name == PQE_OBJ_BTN_CANCEL_ORDERS)  { OnCloseButton(PQE_CLOSE_ORDERS); return; }
   if(name == PQE_OBJ_BTN_CLOSE_ONE)      { OnCloseButton(PQE_CLOSE_ONE);    return; }
   if(name == PQE_OBJ_BTN_CLOSE_ALL)      { OnCloseButton(PQE_CLOSE_ALL);    return; }

   //--- Rady predvoleb: poradi predvolby je za prefixem jmena objektu
   int index = PresetIndex(name, PQE_OBJ_BTN_RISK);
   if(index >= 0)
     {
      OnRiskButton(index);
      return;
     }
   index = PresetIndex(name, PQE_OBJ_BTN_SPLIT);
   if(index >= 0)
     {
      OnSplitButton(index);
      return;
     }
   index = PresetIndex(name, PQE_OBJ_BTN_MOVE_UP);
   if(index >= 0)
     {
      OnMoveButton(true, index);
      return;
     }
   index = PresetIndex(name, PQE_OBJ_BTN_MOVE_DOWN);
   if(index >= 0)
     {
      OnMoveButton(false, index);
      return;
     }
   index = PresetIndex(name, PQE_OBJ_BTN_PARTIAL);
   if(index >= 0)
      OnPartialButton(index);
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

//--- Meze pole SL v bodech - sdili je rucni zapis (ApplyField) i nahled mereni
bool SlPointsInRange(const double points)
  {
   return(points >= 1.0 && points <= PQE_MAX_POINTS);
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
      if(!SlPointsInRange(value))
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

   RefreshPanelAndPreview();
  }

//+------------------------------------------------------------------+
//| Prekresli panel po zmene formulare (pole, riziko, pocet pozic).  |
//| Probihajici vyber vstupu dostane novy nahled - SL, PT i objem    |
//| se mohly zmenit.                                                 |
//+------------------------------------------------------------------+
void RefreshPanelAndPreview()
  {
   UpdatePanel();
   if(g_armed != PQE_ARM_NONE)
      UpdatePreview();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Nacte predvolby tlacitek (riziko, castecne zavreni) ze vstupu.   |
//|  text      - hodnota vstupu: procenta oddelena strednikem        |
//|              (desetinna carka i znak % se toleruji)              |
//|  fallback  - vychozi rada, kdyz ve vstupu neni platna hodnota    |
//|  inputName - jmeno vstupu pro hlasky v logu                      |
//|  maxValue  - horni mez hodnoty (%), stejna jako ve formulari     |
//|  maxCount  - nejvyse tolik predvoleb (tlacitek v rade)           |
//|  presets   - out: nactene hodnoty (%)                            |
//+------------------------------------------------------------------+
void ParsePresets(const string text, const string fallback, const string inputName,
                  const double maxValue, const int maxCount, double &presets[])
  {
   ParsePresetText(text, inputName, maxValue, maxCount, presets);

   //--- Ve vstupu nic platneho - pouzije se vychozi rada
   if(ArraySize(presets) == 0)
     {
      Print("PQE: ", inputName, " neobsahuje platnou hodnotu, použije se ", fallback, ".");
      ParsePresetText(fallback, inputName, maxValue, maxCount, presets);
     }
  }

//+------------------------------------------------------------------+
//| Rozebere text predvoleb do pole (pole se nejdriv vyprazdni).     |
//|  parametry jako u ParsePresets                                   |
//| Neplatne polozky (mimo 0..maxValue) se preskoci s hlaskou v logu.|
//+------------------------------------------------------------------+
void ParsePresetText(const string text, const string inputName, const double maxValue,
                   const int maxCount, double &presets[])
  {
   ArrayResize(presets, 0);

   string parts[];
   const int n = StringSplit(text, ';', parts);
   for(int i = 0; i < n && ArraySize(presets) < maxCount; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      StringReplace(s, ",", ".");
      StringReplace(s, "%", "");

      double v = 0.0;
      if(!ParseNumber(s, v) || v <= 0.0 || v > maxValue)
        {
         if(s != "")
            Print("PQE: ", inputName, ": předvolba '", parts[i], "' není platná, přeskočena.");
         continue;
        }
      const int k = ArraySize(presets);
      ArrayResize(presets, k + 1);
      presets[k] = v;
     }
  }

//--- Procento jako kratky text tlacitka: 1%, 0.5%, 1.25%
string FormatPercent(const double value)
  {
   return(FormatShortNumber(value) + "%");
  }

//--- Cislo s nejmene desetinnymi misty (0 az 2): 1, 0.5, 1.25
string FormatShortNumber(const double value)
  {
   if(MathAbs(value - MathRound(value)) < PQE_RISK_EPS)
      return(DoubleToString(value, 0));
   if(MathAbs(value * 10.0 - MathRound(value * 10.0)) < PQE_RISK_EPS)
      return(DoubleToString(value, 1));
   return(DoubleToString(value, 2));
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

   RefreshPanelAndPreview();
  }

//+------------------------------------------------------------------+
//| Je ucet hedging? Jen tam muze mit expert vic pozic na symbolu -  |
//| netting by vice vstupu sloucil do jedne pozice s jedinym PT a    |
//| castecne zavreni pozice nezna.                                   |
//+------------------------------------------------------------------+
bool IsHedgingAccount()
  {
   return(AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }

//+------------------------------------------------------------------+
//| Proc nelze otevrit dany pocet pozic ("" = lze).                  |
//|  count - pocet pozic na jeden vstup                              |
//| Sdili ho tlacitka rozdeleni rizika, jejich obsluha a OnInit.     |
//+------------------------------------------------------------------+
string CountBlockReason(const int count)
  {
   if(count > 1 && !IsHedgingAccount())
      return("více pozic jen na hedging účtu");
   return("");
  }

//--- Pocet pozic, ktere otevre rozdeleni rizika (nenulove podily)
int SplitCount(const int index)
  {
   int count = 0;
   for(int k = 0; k < PQE_MAX_POSITIONS; k++)
      if(g_splitShares[index][k] > 0.0)
         count++;
   return(count);
  }

//--- Podily rozdeleni v % bez znaku: "100", "50/40/10"
string SplitText(const int index)
  {
   string text = "";
   for(int k = 0; k < SplitCount(index); k++)
      text += (k > 0 ? "/" : "") + FormatShortNumber(g_splitShares[index][k]);
   return(text);
  }

//--- Popisek tlacitka: "100%" u jedne pozice, "50/40/10" u vice (% se nevejde)
string SplitLabel(const int index)
  {
   return(SplitText(index) + (SplitCount(index) == 1 ? "%" : ""));
  }

//+------------------------------------------------------------------+
//| Objemy pozic vstupu podle zvoleneho rozdeleni rizika.            |
//|  slDistance - vzdalenost SL v cene                               |
//|  splitIndex - rozdeleni rizika (radek g_splitShares)             |
//|  lots       - out: objem kazde pozice (pri chybe vsude 0)        |
//|  reason     - out: proc nelze (pozice, na kterou nestaci lot)    |
//| Kazda pozice dostane svuj podil rizika a zaokrouhluje se dolu    |
//| zvlast, celkove riziko tak nikdy nepretece pres pole Riziko.     |
//| Vraci false, kdyz na nekterou pozici nestaci minimalni lot.      |
//+------------------------------------------------------------------+
bool CalcSplitLots(const double slDistance, const int splitIndex, double &lots[], string &reason)
  {
   const int count = SplitCount(splitIndex);
   ArrayInitialize(lots, 0.0);
   for(int k = 0; k < count; k++)
     {
      lots[k] = CalcLot(slDistance, g_riskPercent * g_splitShares[splitIndex][k] / 100.0, reason);
      if(lots[k] <= 0.0)
        {
         // U vice pozic rict, ktera neprosla (typicky ta s nejmensim podilem)
         if(count > 1)
            reason = StringFormat("%d. pozice: %s", k + 1, reason);
         ArrayInitialize(lots, 0.0);
         return(false);
        }
     }
   return(true);   // CalcLot pri uspechu duvod vyprazdnil
  }

//--- Soucet objemu prvnich count pozic
double TotalLots(const double &lots[], const int count)
  {
   double total = 0.0;
   for(int k = 0; k < count; k++)
      total += lots[k];
   return(total);
  }

//--- Objemy pozic jako text: "0.33" nebo "0.05/0.04/0.01"
string FormatSplitLots(const double &lots[], const int count)
  {
   string text = "";
   for(int k = 0; k < count; k++)
      text += (k > 0 ? "/" : "") + FormatLots(lots[k]);
   return(text);
  }

//+------------------------------------------------------------------+
//| Vzdalenosti PT vsech pozic v bodech jako text.                   |
//|  count - pocet pozic                                             |
//| Pozice k ma PT = k x PT z formulare: "300 b" nebo "300/600/900 b"|
//| a bez PT z formulare "bez PT".                                   |
//+------------------------------------------------------------------+
string TpPointsText(const int count)
  {
   if(g_tpPoints <= 0)
      return("bez PT");
   string text = IntegerToString(g_tpPoints);
   for(int k = 2; k <= count; k++)
      text += "/" + IntegerToString(k * g_tpPoints);
   return(text + " b");
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka rozdeleni rizika (100%, 50/50, 50/40/10 ...).     |
//|  index - poradi tlacitka (radek g_splitShares)                   |
//| Vic pozic jde jen na hedging uctu (viz CountBlockReason).        |
//| Rozpracovany vyber vstupu zustava, nahled se jen prekresli.      |
//+------------------------------------------------------------------+
void OnSplitButton(const int index)
  {
   if(index < 0 || index >= PQE_SPLIT_PRESETS)
      return;

   const int    count  = SplitCount(index);
   const string reason = CountBlockReason(count);
   if(reason != "")
      g_lastEvent = SplitLabel(index) + ": " + reason;
   else
     {
      g_splitIndex = index;
      g_lastEvent  = StringFormat("rozdělení %s %%, PT %s", SplitText(index), TpPointsText(count));
     }

   RefreshPanelAndPreview();
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

//+------------------------------------------------------------------+
//| Lze cekajici prikaz zadat na dane cene?                          |
//|  isBuy, isStop - smer a typ (STOP / LIMIT)                       |
//|  price         - cena prikazu                                    |
//|  ask, bid, stops - stav trhu a stop level brokera (cena)         |
//| STOP lezi za trhem, LIMIT pred nim, vzdy dal nez stop level.     |
//| Sdili ho zadani vstupu (BuildPlan) i posun prikazu.              |
//+------------------------------------------------------------------+
bool PendingPriceValid(const bool isBuy, const bool isStop, const double price,
                       const double ask, const double bid, const double stops)
  {
   if(isBuy)
      return(isStop ? price > ask + stops : price < ask - stops);
   return(isStop ? price < bid - stops : price > bid + stops);
  }

//+------------------------------------------------------------------+
//| Lezi SL na ztratove strane reference aspon o stop level?         |
//|  isBuy     - smer obchodu                                        |
//|  reference - vstup prikazu, u pozice cena zavreni (Bid / Ask)    |
//|  sl, stops - stop loss a stop level brokera (cena)               |
//| Sdili ho zadani vstupu (BuildPlan) i posun SL.                   |
//+------------------------------------------------------------------+
bool StopLossValid(const bool isBuy, const double reference, const double sl, const double stops)
  {
   return(isBuy ? sl <= reference - stops : sl >= reference + stops);
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
//| Zaokrouhli objem na krok objemu symbolu.                         |
//|  lot  - objem v lotech                                           |
//|  down - true = dolu (riziko nesmi pretect), false = na nejblizsi |
//| Tolerance srovnava chybu plovouci carky: 0.29 / 0.01 vyjde       |
//| 28.999999999999996 a bez ni by se zaokrouhlilo na 0.28.          |
//+------------------------------------------------------------------+
double RoundToLotStep(const double lot, const bool down)
  {
   const double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep <= 0.0)
      return(lot);
   const double steps = lot / lotStep;
   return((down ? MathFloor(steps + PQE_LOTSTEP_EPS) : MathRound(steps)) * lotStep);
  }

//+------------------------------------------------------------------+
//| Vypocet objemu z rizika.                                         |
//|  slDistance  - vzdalenost SL v cene                              |
//|  riskPercent - riziko jedne pozice (% zustatku)                  |
//|  reason      - out: duvod, proc objem nelze pouzit               |
//| Objem se dopocita tak, aby ztrata na SL odpovidala zadanemu      |
//| procentu zustatku, a zaokrouhli se DOLU na krok objemu. Kdyz na  |
//| riziko nestaci ani nejmensi dovoleny lot, vraci 0 - riziko nesmi |
//| tise pretect pres zadany limit.                                  |
//+------------------------------------------------------------------+
double CalcLot(const double slDistance, const double riskPercent, string &reason)
  {
   reason = "";

   const double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   const double lossPerLot = LossPerLot(slDistance);

   if(balance <= 0.0 || lossPerLot <= 0.0)
     {
      reason = "chybí data pro výpočet rizika";
      return(0.0);
     }

   //--- Zaokrouhleni dolu na krok objemu - riziko nesmi pretect
   double lot = RoundToLotStep((balance * riskPercent / 100.0) / lossPerLot, true);

   //--- Orez na maximum symbolu. VOLUME_MAX nemusi byt nasobkem kroku
   //--- objemu, proto se po orezu zaokrouhluje znovu dolu - jinak by
   //--- server prikaz odmitl s TRADE_RETCODE_INVALID_VOLUME.
   if(maxLot > 0.0 && lot > maxLot)
      lot = RoundToLotStep(maxLot, true);

   //--- Kontrola minima az po orezu: u nesmyslne nastaveneho symbolu
   //--- (VOLUME_MAX < VOLUME_MIN) by jinak prosel objem pod minimem
   if(lot < minLot)
     {
      reason = StringFormat("min. lot %s = %.2f %% > %.2f %%",
                            FormatLots(minLot), minLot * lossPerLot / balance * 100.0,
                            riskPercent);
      return(0.0);
     }

   return(NormalizeDouble(lot, VolumeDigits()));
  }

//--- Ztrata objemu lots na SL ve vzdalenosti slDistance v % zustatku
double RiskPercentOf(const double lots, const double slDistance)
  {
   const double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return(balance > 0.0 ? lots * LossPerLot(slDistance) / balance * 100.0 : 0.0);
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
//|  isBuy - smer, kind - jake prikazy tlacitko zadava               |
//|  price - cena pod kurzorem (u PQE_ENTRY_MARKET se nepouzije)     |
//|  plan  - out: navrh                                              |
//| BUY nad Ask (+ stop level) = BUY STOP na kliknute cene. Pod Ask  |
//| dal nez stop level = BUY LIMIT na kliknute cene, na Ask nebo     |
//| tesne pod nim (broker by LIMIT odmitl) = BUY za trh. Pro SELL    |
//| zrcadlove k Bid. Varianta BUYSTOP / SELLSTOP LIMIT nezadava:     |
//| vsude pod Ask (SELL: nad Bid) vstupuje za trh. BUY / SELL MARKET |
//| vstupuje za trh vzdy, bez ohledu na cenu.                        |
//| Pasmo mezi trhem a stop levelem broker pro STOP nepovoli a jako  |
//| trzni vstup by prekvapilo - tam se klik odmitne.                 |
//| SL a PT se meri od vstupni ceny, objem z rizika a vzdalenosti SL.|
//| Pri vice pozicich (rozdeleni rizika) ma pozice k PT = k x PT, SL |
//| je vsem spolecny a objem kazde pozice se pocita z jejiho podilu. |
//+------------------------------------------------------------------+
void BuildPlan(const bool isBuy, const ENUM_PQE_ENTRY kind, double price, SEntryPlan &plan)
  {
   plan.isBuy  = isBuy;
   plan.mode   = PQE_MODE_TOO_CLOSE;
   plan.entry  = 0.0;
   plan.sl     = 0.0;
   plan.tp     = 0.0;
   plan.count  = SplitCount(g_splitIndex);
   ArrayInitialize(plan.lots, 0.0);
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
   //--- Za trh (MARKET) jen na "druhe" strane trhu nebo presne na nem:
   //--- BUY na Ask a pod nim, SELL na Bid a nad nim.
   const bool stopOnly  = (kind == PQE_ENTRY_NO_LIMIT);
   const bool marketOk  = isBuy ? price <= ask : price >= bid;
   if(kind == PQE_ENTRY_MARKET)
      plan.mode = PQE_MODE_MARKET;
   else
      if(PendingPriceValid(isBuy, true, price, ask, bid, stops))
         plan.mode = PQE_MODE_STOP;
      else
         if(!stopOnly && PendingPriceValid(isBuy, false, price, ask, bid, stops))
            plan.mode = PQE_MODE_LIMIT;
         else
            if(marketOk)
               plan.mode = PQE_MODE_MARKET;
   if(plan.mode == PQE_MODE_MARKET)
      plan.entry = isBuy ? ask : bid;

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
   const double tpReal = (plan.tp > 0.0) ? MathAbs(plan.tp - plan.entry) : 0.0;

   if(plan.mode == PQE_MODE_TOO_CLOSE)
     {
      plan.reason = StringFormat("moc blízko trhu (stop-level %.0f b)", stops / _Point);
      return;
     }

   //--- SL a PT musi respektovat stop level brokera. Kontroluje se PT
   //--- 1. pozice - PT dalsich pozic je od vstupu jeste dal.
   if(!StopLossValid(isBuy, plan.entry, plan.sl, stops))
     {
      plan.reason = StringFormat("SL < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }
   if(tpReal > 0.0 && tpReal < stops)
     {
      plan.reason = StringFormat("PT < stop-level brokera (%.0f b)", stops / _Point);
      return;
     }

   //--- U SELL muze nejvzdalenejsi PT (k x PT) spadnout pod nulu
   if(plan.tp > 0.0 && PlanTakeProfit(plan, plan.count) <= 0.0)
     {
      plan.reason = StringFormat("PT %d. pozice je pod nulou", plan.count);
      return;
     }

   //--- Objem se pocita ze skutecne vzdalenosti SL, ne z nominalni -
   //--- jinak by realna ztrata na SL neodpovidala zadanemu procentu.
   //--- Riziko se deli mezi pozice podle zvoleneho rozdeleni.
   if(!CalcSplitLots(MathAbs(plan.entry - plan.sl), g_splitIndex, plan.lots, plan.reason))
      return;

   //--- Marze se overi predem - "nedostatek penez" od serveru by prisel
   //--- az po kliknuti a bez cisel. Pocita se za vsechny pozice dohromady.
   double margin = 0.0;
   if(OrderCalcMargin(isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, _Symbol,
                      TotalLots(plan.lots, plan.count), plan.entry, margin))
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
//| Cena PT k-te pozice navrhu.                                      |
//|  plan - navrh vstupu, k - poradi pozice (1 = prvni)              |
//| Pozice k ma PT v k-nasobku vzdalenosti PT 1. pozice (ta uz je    |
//| zarovnana na krok kotace). Vraci 0 bez PT.                       |
//+------------------------------------------------------------------+
double PlanTakeProfit(const SEntryPlan &plan, const int k)
  {
   if(plan.tp <= 0.0 || k == 1)
      return(plan.tp);
   const double dist = k * MathAbs(plan.tp - plan.entry);
   return(NormalizePrice(plan.isBuy ? plan.entry + dist : plan.entry - dist));
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

//--- Slot pameti odeslanych prikazu s danym ticketem (-1 = neni v pameti)
int SentSlot(const ulong ticket)
  {
   if(ticket == 0)
      return(-1);
   for(int i = 0; i < PQE_MAX_SENT; i++)
      if(g_sent[i].ticket == ticket)
         return(i);
   return(-1);
  }

//+------------------------------------------------------------------+
//| Prepise vzdalenost SL drive odeslaneho prikazu po posunu SL.     |
//|  ticket - ticket prikazu, slDist - nova vzdalenost SL (cena)     |
//| Jinak by dorovnani po vyplneni vratilo SL na puvodni vzdalenost. |
//| Prikaz mimo pamet (napr. po restartu) se dorovnava podle         |
//| historie prikazu, kde uz je posunuty SL.                         |
//+------------------------------------------------------------------+
void UpdateSentSl(const ulong ticket, const double slDist)
  {
   const int i = SentSlot(ticket);
   if(i >= 0)
      g_sent[i].slDist = slDist;
  }

//+------------------------------------------------------------------+
//| Najde vzdalenosti SL/PT drive odeslaneho prikazu.                |
//|  ticket - ticket prikazu, slDist / tpDist - out: vzdalenosti     |
//| Vraci false, kdyz prikaz v pameti neni (napr. po restartu).      |
//+------------------------------------------------------------------+
bool FindSent(const ulong ticket, double &slDist, double &tpDist)
  {
   const int i = SentSlot(ticket);
   if(i < 0)
      return(false);
   slDist = g_sent[i].slDist;
   tpDist = g_sent[i].tpDist;
   return(true);
  }

//+------------------------------------------------------------------+
//| Platnost prikazu podle InpExpirationMinutes.                     |
//|  pending    - jde o cekajici prikaz (MARKET platnost nema)       |
//|  typeTime, expiration - out: typ platnosti a cas vyprseni        |
//| Platnost do casu jen tam, kde ji symbol podporuje - jinak GTC.   |
//+------------------------------------------------------------------+
void OrderExpiration(const bool pending, ENUM_ORDER_TYPE_TIME &typeTime, datetime &expiration)
  {
   typeTime   = ORDER_TIME_GTC;
   expiration = 0;
   if(!pending || InpExpirationMinutes <= 0)
      return;

   const long expModes = SymbolInfoInteger(_Symbol, SYMBOL_EXPIRATION_MODE);
   if((expModes & SYMBOL_EXPIRATION_SPECIFIED) != 0)
     {
      typeTime   = ORDER_TIME_SPECIFIED;
      expiration = TimeCurrent() + InpExpirationMinutes * 60;
     }
   else
      Print("PQE: symbol nepodporuje platnost příkazu do času, příkaz je do zrušení.");
  }

//+------------------------------------------------------------------+
//| Odesle jeden prikaz navrhu (jednu pozici vstupu).                |
//|  plan    - platny navrh vstupu                                   |
//|  lots    - objem teto pozice                                     |
//|  tp      - PT teto pozice (0 = bez PT)                           |
//|  comment - komentar prikazu                                      |
//|  typeTime, expiration - platnost cekajiciho prikazu              |
//| Vraci navratovou hodnotu metody CTrade (prijeti hlida volajici). |
//+------------------------------------------------------------------+
bool SendPlanOrder(const SEntryPlan &plan, const double lots, const double tp, const string comment,
                   const ENUM_ORDER_TYPE_TIME typeTime, const datetime expiration)
  {
   // Cena 0 = CTrade pouzije aktualni Ask/Bid v okamziku odeslani
   if(plan.mode == PQE_MODE_MARKET)
      return(g_trade.PositionOpen(_Symbol, plan.isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                  lots, 0.0, plan.sl, tp, comment));

   // STOP i LIMIT jsou cekajici prikazy na kliknute cene, lisi se jen typem
   const ENUM_ORDER_TYPE type = (plan.mode == PQE_MODE_STOP)
                                ? (plan.isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP)
                                : (plan.isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
   return(g_trade.OrderOpen(_Symbol, type, lots, 0.0, plan.entry, plan.sl, tp,
                            typeTime, expiration, comment));
  }

//+------------------------------------------------------------------+
//| Odesle prikazy podle navrhu (STOP, LIMIT nebo MARKET).           |
//|  plan - platny navrh vstupu                                      |
//| Pro kazdou pozici vstupu jeden prikaz: stejny SL, objem podle    |
//| podilu rizika, pozice k ma PT = k x PT. Pri prvnim odmitnuti se  |
//| dalsi pozice uz neposilaji (duvod by byl nejspis stejny).        |
//| Vysledek se zapise do panelu i do logu. Vraci true, kdyz prosly  |
//| vsechny pozice.                                                  |
//+------------------------------------------------------------------+
bool ExecutePlan(SEntryPlan &plan)
  {
   const string dir      = plan.isBuy ? "BUY" : "SELL";
   const string modeName = ModeName(plan.mode);
   const bool   market   = (plan.mode == PQE_MODE_MARKET);

   ENUM_ORDER_TYPE_TIME typeTime;
   datetime expiration;
   OrderExpiration(!market, typeTime, expiration);

   // Vzdalenost SL pro dorovnani po vyplneni. Bere se z navrhu, ne
   // z formulare - navrh uz ma ceny zarovnane na krok kotace a dorovnani
   // musi vychazet ze stejnych hodnot, jake se poslaly na server.
   const double slDist = MathAbs(plan.entry - plan.sl);

   //--- Smycka konci pri prvnim odmitnuti, takze k - 1 = pocet otevrenych
   int    k           = 1;
   ulong  firstTicket = 0;
   double firstPrice  = 0.0;
   for(; k <= plan.count; k++)
     {
      //--- Komentar odlisi pozice vstupu: "PQE BUYSTOP 2/3"
      const double tp      = PlanTakeProfit(plan, k);
      const string comment = "PQE " + dir + (market ? "" : modeName) +
                             (plan.count > 1 ? StringFormat(" %d/%d", k, plan.count) : "");
      const double lots    = plan.lots[k - 1];
      if(!RequestAccepted(SendPlanOrder(plan, lots, tp, comment, typeTime, expiration)))
        {
         PrintFormat("PQE: %s %s %d/%d selhal: %d %s", dir, modeName, k, plan.count,
                     g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
         break;
        }

      const ulong  ticket = g_trade.ResultOrder();
      const double price  = (market && g_trade.ResultPrice() > 0.0) ? g_trade.ResultPrice() : plan.entry;
      RememberSent(ticket, slDist, (tp > 0.0) ? MathAbs(tp - plan.entry) : 0.0);

      PrintFormat("PQE: %s %s %d/%d #%I64u @ %s  SL %s  PT %s  %s lot  (riziko %.2f %%)",
                  dir, modeName, k, plan.count, ticket,
                  DoubleToString(price, _Digits), DoubleToString(plan.sl, _Digits),
                  tp > 0.0 ? DoubleToString(tp, _Digits) : "-",
                  FormatLots(lots), RiskPercentOf(lots, slDist));
      if(k == 1)
        {
         firstTicket = ticket;
         firstPrice  = price;
        }
     }
   const int opened = k - 1;

   //--- Kratky tvar - radek panelu ma omezenou sirku; pri oriznuti
   //--- prijde o konec cisla ticketu, ne o objem a cenu. Selhani uz
   //--- je v logu z cyklu.
   if(opened == 0)
      g_lastEvent = StringFormat("%s selhal: %d %s", dir, g_trade.ResultRetcode(),
                                 g_trade.ResultRetcodeDescription());
   else
      if(opened < plan.count)
         g_lastEvent = StringFormat("%s %s: otevřeno jen %d/%d, pak %d", dir, modeName,
                                    opened, plan.count, g_trade.ResultRetcode());
      else
         g_lastEvent = StringFormat("%s %s %s lot @ %s #%I64u", dir, modeName,
                                    FormatSplitLots(plan.lots, plan.count),
                                    DoubleToString(firstPrice, _Digits), firstTicket);
   return(opened == plan.count);
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

//--- Pripona hlasky o zavirani s poctem neuspechu ("" = vse proslo)
string FailedSuffix(const int failed)
  {
   return(failed > 0 ? StringFormat(", %d selhalo", failed) : "");
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
                                    FailedSuffix(failed));
     }
   Print("PQE: ", g_lastEvent);

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka BUY MARKET / SELL MARKET.                         |
//|  isBuy - smer obchodu                                            |
//| Vstoupi za trh hned (Ask / Bid), bez kliku do grafu, se SL, PT   |
//| a objemem z formulare. Probihajici vyber mista vstupu se zrusi - |
//| jinak by po obchodu dal cekal na klik a mohl zadat druhy obchod. |
//+------------------------------------------------------------------+
void OnMarketButton(const bool isBuy)
  {
   const string dirText = isBuy ? "BUY MARKET" : "SELL MARKET";
   // Rozpracovany vyber vstupu nebo mereni SL/PT by po obchodu dal cekal na klik
   Disarm("");

   string err;
   if(!EntryAllowed(err))
     {
      g_lastEvent = dirText + ": " + err;
      Print("PQE: ", g_lastEvent);
     }
   else
     {
      //--- SL, PT, objem i kontrola marze jdou stejnou cestou jako u kliku
      //--- do grafu, jen zpusob vstupu je vzdy MARKET
      SEntryPlan plan;
      BuildPlan(isBuy, PQE_ENTRY_MARKET, 0.0, plan);
      if(plan.valid)
         ExecutePlan(plan);
      else
        {
         g_lastEvent = dirText + ": " + plan.reason;
         Print("PQE: ", g_lastEvent);
        }
     }

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Puvodni (celkovy) objem pozice.                                  |
//|  posId   - identifikator pozice (POSITION_IDENTIFIER)            |
//|  current - aktualni objem pozice                                 |
//| Puvodni objem = soucet vstupnich obchodu pozice. Procenta        |
//| castecneho zavreni se pocitaji vzdy z nej, ne ze zbytku po       |
//| predchozim zavirani - 4x 25 % tak zavre celou pozici. Pri        |
//| navysovani pozice na netting uctu se vstupy sectou. Kdyby        |
//| historie chybela (nebo pozice vznikla otocenim), pouzije se aspon|
//| aktualni objem.                                                  |
//| Panel se pta kazdou sekundu, historie se proto cte znovu jen pri |
//| zmene objemu pozice - puvodni objem se jinak menit nemuze.       |
//+------------------------------------------------------------------+
double InitialVolume(const long posId, const double current)
  {
   //--- Pozice je v pameti a jeji objem se od vypoctu nezmenil
   int slot = -1;
   for(int i = 0; i < PQE_MAX_VOL_CACHE; i++)
      if(g_volCache[i].posId == posId)
        {
         if(g_volCache[i].current == current)
            return(g_volCache[i].initial);
         slot = i;
         break;
        }

   double total = 0.0;
   if(HistorySelectByPosition(posId))
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         const ulong deal = HistoryDealGetTicket(i);
         if(deal != 0 && HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
            total += HistoryDealGetDouble(deal, DEAL_VOLUME);
        }
     }
   const double initial = MathMax(total, current);

   //--- Zapis do pameti: stejna pozice prepise svuj zaznam, nova dostane
   //--- dalsi slot v kruhu (nejstarsi zaznam se zahodi)
   if(slot < 0)
     {
      slot = g_volCacheNext;
      g_volCacheNext = (g_volCacheNext + 1) % PQE_MAX_VOL_CACHE;
     }
   g_volCache[slot].posId   = posId;
   g_volCache[slot].current = current;
   g_volCache[slot].initial = initial;
   return(initial);
  }

//+------------------------------------------------------------------+
//| Vsechny otevrene pozice experta s puvodnim a aktualnim objemem.  |
//|  list - out: pozice experta                                      |
//| Seznam se sestavi predem - ke kazde pozici patri i puvodni objem |
//| z historie. PositionGetTicket pozici v kazde iteraci vybere      |
//| znovu, dotaz do historie tedy pruchod seznamem nenarusi.         |
//| Vraci pocet pozic.                                               |
//+------------------------------------------------------------------+
int OurPositionVolumes(SPositionVolume &list[])
  {
   //--- Pole se zvetsi jednou na nejvetsi mozny pocet a na konci orizne
   int n = 0;
   ArrayResize(list, PositionsTotal());
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      list[n].ticket  = ticket;
      list[n].current = PositionGetDouble(POSITION_VOLUME);
      list[n].initial = InitialVolume(PositionGetInteger(POSITION_IDENTIFIER), list[n].current);
      n++;
     }
   ArrayResize(list, n);
   return(n);
  }

//+------------------------------------------------------------------+
//| Proc castecne zavreni nejde ("" = lze).                          |
//|  canClose, closeReason - povoleni zavirani a jeho duvod          |
//|  positions             - pocet otevrenych pozic experta          |
//| Sdili ho obsluha stisku i kresleni tlacitek, aby hlasky sedely.  |
//+------------------------------------------------------------------+
string PartialBlockReason(const bool canClose, const string closeReason, const int positions)
  {
   if(!canClose)
      return("nelze zavírat - " + closeReason);
   if(positions == 0)
      return("žádná otevřená pozice experta");
   return("");
  }

//+------------------------------------------------------------------+
//| Objem, ktery predvolba castecneho zavreni z pozice zavre.        |
//|  initial - puvodni objem pozice, current - aktualni objem        |
//|  percent - procento puvodniho objemu                             |
//| Vzdy se neco zavre: dil se zaokrouhli na nejblizsi krok objemu,  |
//| ale nejmene na minimalni lot symbolu (u forexu 0.01). Kdyz by po |
//| zavreni zbyl objem pod minimalnim lotem (takovy zbytek server    |
//| neprijme) nebo nic, vraci presne current = zavrit celou pozici.  |
//+------------------------------------------------------------------+
double PartialCloseVolume(const double initial, const double current, const double percent)
  {
   const double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double volume = MathMax(RoundToLotStep(initial * percent / 100.0, false), minLot);

   if(current - volume < minLot - PQE_LOTSTEP_EPS)
      return(current);
   return(NormalizeDouble(volume, VolumeDigits()));
  }

//+------------------------------------------------------------------+
//| Zavre cast pozice (nebo celou pozici) za trh.                    |
//|  ticket  - ticket pozice                                         |
//|  volume  - objem k zavreni z PartialCloseVolume                  |
//|  current - aktualni objem pozice (volume == current = cela)      |
//|  failed  - in/out: pocet neuspechu                               |
//| Cela pozice se zavira jako u ZAVRIT 1 / VSE (hedging i netting). |
//| Cast na hedging uctu castecnym zavrenim; CTrade ho na netting    |
//| uctu neumi - tam pozici zmensi obchod opacnym smerem (bez SL     |
//| a PT, aby se urovne pozice nezmenily). Neuspech jde do logu.     |
//| Vraci true pri prijeti pozadavku serverem.                       |
//+------------------------------------------------------------------+
bool ClosePositionPart(const ulong ticket, const double volume, const double current, int &failed)
  {
   if(volume == current)
      return(CloseOnePosition(ticket, failed));

   bool sent = false;
   if(IsHedgingAccount())
      sent = g_trade.PositionClosePartial(ticket, volume);
   else
      if(PositionSelectByTicket(ticket))
         sent = IsBuyPosition()
                ? g_trade.Sell(volume, _Symbol, 0.0, 0.0, 0.0, "PQE PARTIAL")
                : g_trade.Buy(volume, _Symbol, 0.0, 0.0, 0.0, "PQE PARTIAL");
   if(RequestAccepted(sent))
      return(true);

   failed++;
   PrintFormat("PQE: z pozice #%I64u se nepodařilo zavřít %s lot, retcode %d (%s)",
               ticket, FormatLots(volume), g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka castecneho zavreni (napr. 50 %).                  |
//|  index - poradi predvolby                                        |
//| Z kazde otevrene pozice experta zavre dane procento jejiho       |
//| puvodniho objemu, vzdy aspon minimalni lot (100 % = cele pozice).|
//| Cekajici prikazy necha. Bez potvrzovani, jako ostatni zavirani.  |
//+------------------------------------------------------------------+
void OnPartialButton(const int index)
  {
   if(index < 0 || index >= ArraySize(g_closePresets))
      return;
   const double percent = g_closePresets[index];
   // Kratky tvar jako na tlacitku - radek panelu ma omezenou sirku
   const string label   = "ZAV " + FormatPercent(percent);

   //--- Pozice se zjisti tesne pred odeslanim - od posledniho prekresleni
   //--- panelu se mohly zmenit. Pri zakazanem zavirani se ani necte historie.
   string closeReason;
   SPositionVolume list[];
   const bool canClose = ClosingAllowed(closeReason);
   const int  n        = canClose ? OurPositionVolumes(list) : 0;
   const string reason = PartialBlockReason(canClose, closeReason, n);

   if(reason != "")
      g_lastEvent = label + ": " + reason;
   else
     {
      int    closed = 0, failed = 0;
      double lots   = 0.0;
      for(int k = 0; k < n; k++)
        {
         const double volume = PartialCloseVolume(list[k].initial, list[k].current, percent);
         if(!ClosePositionPart(list[k].ticket, volume, list[k].current, failed))
            continue;
         closed++;
         lots += volume;
         PrintFormat("PQE: %s: #%I64u zavřeno %s lot, zbývá %s", label, list[k].ticket,
                     FormatLots(volume), FormatLots(list[k].current - volume));
        }
      g_lastEvent = StringFormat("%s: pozice %d, %s lot%s", label, closed, FormatLots(lots),
                                 FailedSuffix(failed));
     }
   Print("PQE: ", g_lastEvent);

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Posun SL a cekajicich prikazu                                    |
//+------------------------------------------------------------------+

//--- Velikost kroku posunu v bodech (0 = maly, 1 = stredni, 2 = velky)
int MoveStepPoints(const int step)
  {
   if(step == 0)
      return(InpMoveMinPoints);
   if(step == 1)
      return(InpMoveMidPoints);
   return(InpMoveMaxPoints);
  }

//--- Jsou vsechny kroky posunu ze vstupu v rozsahu 1..PQE_MAX_POINTS?
bool MoveStepsValid()
  {
   for(int step = 0; step < PQE_MOVE_STEPS; step++)
      if(MoveStepPoints(step) <= 0 || MoveStepPoints(step) > PQE_MAX_POINTS)
         return(false);
   return(true);
  }

//--- Popisek tlacitka posunu: "+10" (rada nahoru), "-10" (rada dolu)
string MoveButtonText(const bool up, const int step)
  {
   return((up ? "+" : "-") + IntegerToString(MoveStepPoints(step)));
  }

//--- Je typ cekajiciho prikazu nakupni? (BUY STOP / BUY LIMIT)
bool IsBuyOrderType(const long type)
  {
   return(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT);
  }

//--- Je typ cekajiciho prikazu STOP? (BUY STOP / SELL STOP)
bool IsStopOrderType(const long type)
  {
   return(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP);
  }

//--- Je prave vybrana pozice nakupni?
bool IsBuyPosition()
  {
   return(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
  }

//--- Skupina sjednoceni SL: 0 = nakupy, 1 = prodeje (BUY a SELL zvlast)
int SlGroupIndex(const bool isBuy)
  {
   return(isBuy ? 0 : 1);
  }

//+------------------------------------------------------------------+
//| Zapise do logu odmitnuty posun a zapocita neuspech.              |
//|  failed - in/out: pocet neuspechu                                |
//|  what   - co se posouvalo ("SL pozice", "příkaz" ...)            |
//|  ticket - ticket, price - cena, na kterou posun nesel            |
//+------------------------------------------------------------------+
void RejectMove(int &failed, const string what, const ulong ticket, const double price)
  {
   failed++;
   PrintFormat("PQE: %s #%I64u nelze posunout na %s - špatná strana trhu nebo stop-level",
               what, ticket, DoubleToString(price, _Digits));
  }

//+------------------------------------------------------------------+
//| Zmeni SL vybrane pozice (PositionGetTicket), PT ponecha.         |
//|  ticket - ticket pozice, sl - novy SL                            |
//|  failed - in/out: pocet neuspechu                                |
//| Vraci true pri prijeti pozadavku serverem, neuspech jde do logu. |
//+------------------------------------------------------------------+
bool ModifyPositionSl(const ulong ticket, const double sl, int &failed)
  {
   if(RequestAccepted(g_trade.PositionModify(ticket, sl, PositionGetDouble(POSITION_TP))))
      return(true);

   failed++;
   PrintFormat("PQE: SL pozice #%I64u se nepodařilo posunout, retcode %d (%s)",
               ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
//| Zmeni ceny vybraneho cekajiciho prikazu (OrderGetTicket).        |
//|  ticket - ticket prikazu, price / sl / tp - nove urovne          |
//|  failed - in/out: pocet neuspechu                                |
//| Platnost prikazu (typ a cas vyprseni) se zachova.                |
//| Vraci true pri prijeti pozadavku serverem, neuspech jde do logu. |
//+------------------------------------------------------------------+
bool ModifyOrderLevels(const ulong ticket, const double price, const double sl, const double tp,
                       int &failed)
  {
   const ENUM_ORDER_TYPE_TIME typeTime = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   const datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   if(RequestAccepted(g_trade.OrderModify(ticket, price, sl, tp, typeTime, expiration)))
      return(true);

   failed++;
   PrintFormat("PQE: příkaz #%I64u se nepodařilo upravit, retcode %d (%s)",
               ticket, g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
   return(false);
  }

//+------------------------------------------------------------------+
//| Skupina sjednoceni cekajiciho prikazu podle typu (-1 = jiny typ).|
//| BUY LIMIT = 0, SELL LIMIT = 1, BUY STOP = 2, SELL STOP = 3 - typy|
//| jdou v ENUM_ORDER_TYPE po sobe. Jine typy (STOP LIMIT) expert    |
//| nezadava a sjednoceni je preskoci.                               |
//+------------------------------------------------------------------+
int PendingTypeIndex(const long type)
  {
   const long index = type - ORDER_TYPE_BUY_LIMIT;
   return((index >= 0 && index < PQE_PENDING_TYPES) ? (int)index : -1);
  }

//--- Prumery skupin z nascitanych hodnot (0 = skupina bez obchodu)
void GroupAverages(const double &sum[], const int &cnt[], const int groups, double &targets[])
  {
   ArrayResize(targets, groups);
   for(int k = 0; k < groups; k++)
      targets[k] = (cnt[k] > 0) ? NormalizePrice(sum[k] / cnt[k]) : 0.0;
  }

//+------------------------------------------------------------------+
//| Prumerne SL pozic a cekajicich prikazu experta.                  |
//|  targets - out: prumer SL pro kazdou skupinu (SlGroupIndex)      |
//| BUY a SELL se prumeruji zvlast - spolecny prumer by nedaval      |
//| smysl. Obchody bez SL se nepocitaji (stejny filtr jako upravy).  |
//+------------------------------------------------------------------+
void AverageStopLosses(double &targets[])
  {
   double sum[PQE_SL_GROUPS];
   int    cnt[PQE_SL_GROUPS];
   ArrayInitialize(sum, 0.0);
   ArrayInitialize(cnt, 0);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0 || !IsOurPosition())
         continue;
      const double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
         continue;
      const int k = SlGroupIndex(IsBuyPosition());
      sum[k] += sl;
      cnt[k]++;
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsOurOrder())
         continue;
      const double sl = OrderGetDouble(ORDER_SL);
      if(sl <= 0.0)
         continue;
      const int k = SlGroupIndex(IsBuyOrderType(OrderGetInteger(ORDER_TYPE)));
      sum[k] += sl;
      cnt[k]++;
     }
   GroupAverages(sum, cnt, PQE_SL_GROUPS, targets);
  }

//+------------------------------------------------------------------+
//| Prumerne ceny cekajicich prikazu experta podle typu prikazu.     |
//|  targets - out: prumer pro kazdy typ (PendingTypeIndex)          |
//| Typy se prumeruji zvlast - prumer STOP nad trhem a LIMIT pod     |
//| nim by padl do trhu, kde nejde zadat ani jeden.                  |
//+------------------------------------------------------------------+
void AveragePendingPrices(double &targets[])
  {
   double sum[PQE_PENDING_TYPES];
   int    cnt[PQE_PENDING_TYPES];
   ArrayInitialize(sum, 0.0);
   ArrayInitialize(cnt, 0);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0 || !IsOurOrder())
         continue;
      const int k = PendingTypeIndex(OrderGetInteger(ORDER_TYPE));
      if(k < 0)
         continue;
      sum[k] += OrderGetDouble(ORDER_PRICE_OPEN);
      cnt[k]++;
     }
   GroupAverages(sum, cnt, PQE_PENDING_TYPES, targets);
  }

//+------------------------------------------------------------------+
//| Zmeni SL vsech pozic a cekajicich prikazu experta.               |
//|  delta       - posun v cene (kladny = nahoru); pri sjednoceni 0  |
//|  consolidate - true = SL na prumer sve skupiny (AverageStopLosses)|
//|                misto posunu o delta                              |
//|  failed      - in/out: pocet neuspechu                           |
//| Obchody bez SL a SL, ktere uz na cili jsou, se preskoci. SL musi |
//| zustat na ztratove strane dal nez stop level (StopLossValid) - u |
//| pozice od ceny zavreni (BUY Bid, SELL Ask), u prikazu od jeho    |
//| vstupu. Objem se nemeni, riziko se tedy meni. Vraci pocet zmen.  |
//+------------------------------------------------------------------+
int AdjustStopLosses(const double delta, const bool consolidate, int &failed)
  {
   double targets[];
   if(consolidate)
      AverageStopLosses(targets);

   const double stops = StopsLevelPrice();
   const double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int changed = 0;

   //--- Otevrene pozice
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsOurPosition())
         continue;
      const double sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0.0)
         continue;

      const bool   isBuy = IsBuyPosition();
      const double newSL = consolidate ? targets[SlGroupIndex(isBuy)] : NormalizePrice(sl + delta);
      if(SamePrice(newSL, sl))
         continue;
      if(!StopLossValid(isBuy, isBuy ? bid : ask, newSL, stops))
         RejectMove(failed, "SL pozice", ticket, newSL);
      else
         if(ModifyPositionSl(ticket, newSL, failed))
            changed++;
     }

   //--- Cekajici prikazy: meni se jen SL, vstup a PT zustavaji
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder())
         continue;
      const double sl = OrderGetDouble(ORDER_SL);
      if(sl <= 0.0)
         continue;

      const bool   isBuy = IsBuyOrderType(OrderGetInteger(ORDER_TYPE));
      const double price = OrderGetDouble(ORDER_PRICE_OPEN);
      const double newSL = consolidate ? targets[SlGroupIndex(isBuy)] : NormalizePrice(sl + delta);
      if(SamePrice(newSL, sl))
         continue;
      if(!StopLossValid(isBuy, price, newSL, stops))
         RejectMove(failed, "SL příkazu", ticket, newSL);
      else
         if(ModifyOrderLevels(ticket, price, newSL, OrderGetDouble(ORDER_TP), failed))
           {
            UpdateSentSl(ticket, MathAbs(price - newSL));
            changed++;
           }
     }
   return(changed);
  }

//+------------------------------------------------------------------+
//| Posune cekajici prikazy experta i s jejich SL a PT.              |
//|  delta       - posun v cene (kladny = nahoru); pri sjednoceni 0  |
//|  consolidate - true = cena na prumer sveho typu prikazu          |
//|                (AveragePendingPrices) misto posunu o delta       |
//|  failed      - in/out: pocet neuspechu                           |
//| SL a PT jedou s prikazem, takze vzdalenosti, riziko i objem      |
//| zustavaji (pamet pro dorovnani po vyplneni plati dal). Prikaz se |
//| neprevadi na jiny typ - kdyby se dostal na spatnou stranu trhu   |
//| nebo do stop levelu (PendingPriceValid), nepohne se.             |
//| Vraci pocet posunutych prikazu.                                  |
//+------------------------------------------------------------------+
int AdjustPendingOrders(const double delta, const bool consolidate, int &failed)
  {
   double targets[];
   if(consolidate)
      AveragePendingPrices(targets);

   const double stops = StopsLevelPrice();
   const double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int changed = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      const ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !IsOurOrder())
         continue;

      //--- Sjednoceni pracuje jen s typy, ktere prumeruje (PendingTypeIndex)
      const long type = OrderGetInteger(ORDER_TYPE);
      const int  k    = PendingTypeIndex(type);
      if(consolidate && k < 0)
         continue;
      const double price    = OrderGetDouble(ORDER_PRICE_OPEN);
      const double newPrice = consolidate ? targets[k] : NormalizePrice(price + delta);
      if(SamePrice(newPrice, price))
         continue;

      if(!PendingPriceValid(IsBuyOrderType(type), IsStopOrderType(type), newPrice, ask, bid, stops))
        {
         RejectMove(failed, "příkaz", ticket, newPrice);
         continue;
        }
      // SL a PT se posunou o stejny kus jako vstup; chybejici zustava chybejici
      const double shift = newPrice - price;
      const double sl    = OrderGetDouble(ORDER_SL);
      const double tp    = OrderGetDouble(ORDER_TP);
      if(ModifyOrderLevels(ticket, newPrice,
                           sl > 0.0 ? NormalizePrice(sl + shift) : 0.0,
                           tp > 0.0 ? NormalizePrice(tp + shift) : 0.0, failed))
         changed++;
     }
   return(changed);
  }

//+------------------------------------------------------------------+
//| Proc tlacitka posunu / sjednoceni zesednou ("" = lze).           |
//|  st       - stav spocteny pro toto prekresleni                   |
//|  orders   - true = cekajici prikazy (PO), false = SL             |
//|  minCount - kolik obchodu je treba (posun 1, sjednoceni 2)       |
//| Uprava existujicich obchodu se ridi povolenim zavirani (jde i    |
//| v rezimu "jen zavirani"). Rezim SL pocita pozice i prikazy.      |
//+------------------------------------------------------------------+
string AdjustBlockReason(const SPanelState &st, const bool orders, const int minCount)
  {
   if(!st.canClose)
      return("nelze upravovat - " + st.closeReason);
   const int count = orders ? st.orders : st.orders + st.positions;
   if(count >= minCount)
      return("");
   if(minCount <= 1)
      return(orders ? "žádný čekající příkaz experta" : "žádná pozice ani příkaz experta");
   return(StringFormat("méně než %d %s experta", minCount, orders ? "čekající příkazy" : "obchody"));
  }

//+------------------------------------------------------------------+
//| Provede posun nebo sjednoceni a vysledek zapise do panelu i logu.|
//|  label       - popisek akce pro hlasky ("SL +10", "SJEDNOTIT PO")|
//|  orders      - true = cekajici prikazy, false = SL               |
//|  delta       - posun v cene (pri sjednoceni 0)                   |
//|  consolidate - true = sjednotit na prumer misto posunu           |
//| Predem se hlida jen povoleni uprav - prazdny trh pozna uprava    |
//| sama (nic se nezmeni). Bez potvrzovani, jako zavirani.           |
//+------------------------------------------------------------------+
void RunAdjust(const string label, const bool orders, const double delta, const bool consolidate)
  {
   string reason;
   if(!ClosingAllowed(reason))
      g_lastEvent = label + ": nelze upravovat - " + reason;
   else
     {
      int failed = 0;
      const int changed = orders ? AdjustPendingOrders(delta, consolidate, failed)
                                 : AdjustStopLosses(delta, consolidate, failed);
      g_lastEvent = (changed + failed == 0)
                    ? label + ": nic ke změně"
                    : StringFormat("%s: upraveno %d%s", label, changed, FailedSuffix(failed));
     }
   Print("PQE: ", g_lastEvent);

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Stisk prepinace rezimu posunu (SL / PO).                         |
//|  orders - true = posouvat cele cekajici prikazy, false = SL      |
//+------------------------------------------------------------------+
void OnMoveModeButton(const bool orders)
  {
   g_moveOrders = orders;
   g_lastEvent  = orders ? "posun: čekající příkazy (PO)" : "posun: SL pozic a příkazů";
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka posunu.                                           |
//|  up   - true = 1. rada (nahoru), false = 2. rada (dolu)          |
//|  step - krok posunu (0 = maly, 1 = stredni, 2 = velky)           |
//| Podle rezimu posune SL vsech pozic a prikazu experta, nebo cele  |
//| cekajici prikazy.                                                |
//+------------------------------------------------------------------+
void OnMoveButton(const bool up, const int step)
  {
   if(step < 0 || step >= PQE_MOVE_STEPS)
      return;
   RunAdjust((g_moveOrders ? "PO " : "SL ") + MoveButtonText(up, step), g_moveOrders,
             (up ? 1.0 : -1.0) * MoveStepPoints(step) * _Point, false);
  }

//--- Popisek tlacitka sjednoceni (i pro hlasky v panelu a logu)
string ConsolidateButtonText(const bool orders)
  {
   return(orders ? "SJEDNOTIT PO" : "SJEDNOTIT SL");
  }

//+------------------------------------------------------------------+
//| Stisk tlacitka SJEDNOTIT SL / SJEDNOTIT PO.                      |
//|  orders - true = ceny cekajicich prikazu, false = SL             |
//| SL se srovnaji na prumer zvlast pro BUY a SELL, cekajici prikazy |
//| (i s SL a PT) na prumer zvlast pro kazdy typ prikazu. Co uz na   |
//| prumeru je, se nemeni.                                           |
//+------------------------------------------------------------------+
void OnConsolidateButton(const bool orders)
  {
   RunAdjust(ConsolidateButtonText(orders), orders, 0.0, true);
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

//--- Jake prikazy vyber zadava (pro BuildPlan)
ENUM_PQE_ENTRY ArmEntry(const ENUM_PQE_ARM arm)
  {
   return(ArmIsStopOnly(arm) ? PQE_ENTRY_NO_LIMIT : PQE_ENTRY_ANY);
  }

//+------------------------------------------------------------------+
//| Lze z formulare otevrit novy obchod?                             |
//|  err - out: duvod, proc ne                                       |
//| Pole se nejdriv znovu nactou - uzivatel mohl napsat hodnotu      |
//| a rovnou stisknout tlacitko bez potvrzeni Enterem. Kontroly jsou |
//| stejne jako u zesednuti tlacitek (OpenBlockReason), vcetne       |
//| objemu z rizika - sede tlacitko tak ani nezahaji vyber vstupu.   |
//+------------------------------------------------------------------+
bool EntryAllowed(string &err)
  {
   double lots[PQE_MAX_POSITIONS];
   return(ReloadForm(err) && (err = FormError()) == "" && TradingAllowed(err) &&
          CalcSplitLots(g_slPoints * _Point, g_splitIndex, lots, err));
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
      // Ukonci predchozi vyber i pripadne mereni SL/PT (sdileji klik do grafu)
      Disarm("");
      string err;
      if(!EntryAllowed(err))
        {
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
//| Ukonci vyber mista vstupu i mereni SL/PT a uklidi nahled.        |
//|  message - text do panelu (prazdny = nechat posledni)            |
//| Oba rezimy cekaji na klik do grafu a nesmi bezet soucasne, proto |
//| je ukoncuje jedna funkce - volat ji lze kdykoli, i kdyz nic nebezi.|
//+------------------------------------------------------------------+
void Disarm(const string message)
  {
   g_armed   = PQE_ARM_NONE;
   g_measure = PQE_MEASURE_NONE;
   DeletePreview();
   if(message != "")
      g_lastEvent = message;
  }

//+------------------------------------------------------------------+
//| Klik do grafu behem vyberu mista vstupu.                         |
//|  price - kliknuta cena (filtr kliku dela OnChartPointClick)      |
//| Neproveditelny klik jen ohlasi duvod a vyber zustava aktivni,    |
//| po odeslani prikazu (i neuspesnem) vyber konci.                  |
//+------------------------------------------------------------------+
void HandleChartClick(const double price)
  {
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
   BuildPlan(ArmIsBuy(g_armed), ArmEntry(g_armed), price, plan);
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
   double price = 0.0;
   if(!ChartPointPrice(g_mouseX, g_mouseY, price))
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
   BuildPlan(ArmIsBuy(g_armed), ArmEntry(g_armed), price, plan);

   const string dir      = plan.isBuy ? "BUY" : "SELL";
   const color  dirColor = plan.isBuy ? InpColorBuy : InpColorSell;
   const color  lineClr  = plan.valid ? dirColor : PQE_COLOR_OFF;

   //--- Popisek: objem jde pred ceny, aby ho pri vice pozicich neuriznul
   //--- limit delky textu (PT ukazuje rozsah od 1. do posledni pozice)
   string text;
   if(!plan.valid)
      text = dir + ": " + plan.reason;
   else
     {
      //--- Popisek ma limit 63 znaku: u vice pozic se uvede jen 1. PT
      //--- a pocet dalsich (jejich linky jsou v grafu) a objemy bez "lot"
      string tpText = "-";
      if(plan.tp > 0.0)
         tpText = DoubleToString(plan.tp, _Digits) +
                  (plan.count > 1 ? StringFormat(" +%d", plan.count - 1) : "");
      const string lotsText = FormatSplitLots(plan.lots, plan.count) + (plan.count > 1 ? "" : " lot");
      text = StringFormat("%s %s %s @ %s SL %s PT %s",
                          dir, ModeName(plan.mode), lotsText,
                          DoubleToString(plan.entry, _Digits),
                          DoubleToString(plan.sl, _Digits), tpText);
     }

   //--- Nezmeneny nahled se nekresli znovu. OnTick chodi pri zpravach
   //--- i mnohokrat za sekundu a prekresleni celeho grafu je drahe;
   //--- popisek sleduje kurzor, takze do shody patri i jeho poloha.
   //--- Linka PT je jedna na pozici (u neplatneho navrhu pocet text neobsahuje).
   const int tpLines = (plan.tp > 0.0) ? plan.count : 0;
   if(g_pvShown && text == g_pvText && g_mouseX == g_pvX && g_mouseY == g_pvY &&
      tpLines == g_pvTpLines && SamePrice(plan.entry, g_pvEntry) &&
      SamePrice(plan.sl, g_pvSL) && SamePrice(plan.tp, g_pvTP))
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

   //--- Linka PT pro kazdou pozici vstupu (k x PT). Mazou se jen linky,
   //--- ktere v grafu opravdu jsou - nahled se kresli pri kazdem pohybu
   //--- mysi. DeletePreview pri mazani vsech linek nuluje g_pvTpLines.
   for(int k = 1; k <= tpLines; k++)
      DrawHLine(PreviewTpName(k), PlanTakeProfit(plan, k), InpColorTP, STYLE_DOT, 1);
   for(int k = tpLines + 1; k <= g_pvTpLines; k++)
      ObjectDelete(0, PreviewTpName(k));

   DrawLabel(PQE_OBJ_PV_LABEL, g_mouseX + Dpi(16), g_mouseY + Dpi(18), Fit(text), lineClr);

   //--- Vykresleny stav pro porovnani pri dalsim volani
   g_pvShown = true;
   g_pvEntry = plan.entry;
   g_pvSL    = plan.sl;
   g_pvTP    = plan.tp;
   g_pvTpLines = tpLines;
   g_pvText  = text;
   g_pvX     = g_mouseX;
   g_pvY     = g_mouseY;

   ChartRedraw();
  }

//--- Jmeno linky PT k-te pozice v nahledu: PV_TP, PV_TP2, PV_TP3
string PreviewTpName(const int k)
  {
   return(k == 1 ? PQE_OBJ_PV_TP : PQE_OBJ_PV_TP + IntegerToString(k));
  }

//--- Odstrani vsechny objekty nahledu vstupu
void DeletePreview()
  {
   ObjectDelete(0, PQE_OBJ_PV_ENTRY);
   ObjectDelete(0, PQE_OBJ_PV_SL);
   for(int k = 1; k <= PQE_MAX_POSITIONS; k++)
      ObjectDelete(0, PreviewTpName(k));
   ObjectDelete(0, PQE_OBJ_PV_LABEL);

   //--- Pamet vykresleneho nahledu uz neplati
   g_pvShown   = false;
   g_pvText    = "";
   g_pvTpLines = 0;
  }

//+------------------------------------------------------------------+
//| Cena bodu grafu pod souradnicemi mysi.                           |
//|  x, y  - souradnice v pixelech                                   |
//|  price - out: cena v hlavnim okne grafu                          |
//| Vraci false nad panelem (tam se klik do grafu nebere) a mimo     |
//| hlavni okno grafu (podokna indikatoru maji jinou stupnici).      |
//+------------------------------------------------------------------+
bool ChartPointPrice(const int x, const int y, double &price)
  {
   price = 0.0;
   if(IsInsidePanel(x, y))
      return(false);

   int      sub  = 0;
   datetime time = 0;
   return(ChartXYToTimePrice(0, x, y, sub, time, price) && sub == 0);
  }

//+------------------------------------------------------------------+
//| Mereni SL/PT v grafu                                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Stisk tlacitka "nastav" u pole SL.                               |
//| Tlacitko se chova stridave: stisk zahaji mereni, dalsi stisk ho  |
//| zrusi. Probihajici vyber mista vstupu se zrusi - oba rezimy      |
//| cekaji na klik do grafu a nesmi bezet soucasne. Nahled se zatim  |
//| nekresli - kurzor je nad tlacitkem, tedy nad panelem.            |
//+------------------------------------------------------------------+
void OnMeasureButton()
  {
   if(g_measure != PQE_MEASURE_NONE)
      Disarm("měření SL/PT zrušeno");
   else
     {
      Disarm("");
      g_measure   = PQE_MEASURE_FROM;
      g_armedAt   = GetTickCount();
      g_lastEvent = "SL/PT: klikni na 1. bod v grafu";
     }

   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Zmerena vzdalenost od 1. bodu v celych bodech.                   |
//|  price - cena konce mereni                                       |
//| Vraci double - obri vzdalenost tak nepretece prevodem na int     |
//| a kontrola rozsahu (SlPointsInRange) ji odmitne.                 |
//+------------------------------------------------------------------+
double MeasuredPoints(const double price)
  {
   return(MathRound(MathAbs(price - g_measureFrom) / _Point));
  }

//+------------------------------------------------------------------+
//| Klik do grafu behem mereni SL/PT.                                |
//|  price - kliknuta cena (filtr kliku dela OnChartPointClick)      |
//| 1. klik ulozi vychozi cenu, 2. klik zapise vzdalenost do SL i PT |
//| (PT = SL). Vzdalenost mimo rozsah pole SL jen ohlasi a mereni    |
//| pokracuje.                                                       |
//+------------------------------------------------------------------+
void HandleMeasureClick(const double price)
  {
   //--- 1. klik: vychozi bod mereni - jeho linka se uz nemeni, kresli
   //--- se jednou tady, ne pri kazdem pohybu mysi
   if(g_measure == PQE_MEASURE_FROM)
     {
      g_measureFrom = price;
      g_measure     = PQE_MEASURE_TO;
      g_lastEvent   = "SL/PT: klikni na 2. bod v grafu";
      DrawHLine(PQE_OBJ_PV_ENTRY, g_measureFrom, InpColorText, STYLE_SOLID, 1);
      UpdateMeasurePreview();
      UpdatePanel();
      ChartRedraw();
      return;
     }

   //--- 2. klik: hodnota jde stejnou cestou jako rucni zapis do pole,
   //--- takze plati stejne meze i format. PT ma sirsi rozsah nez SL,
   //--- po prijatem SL proto projde vzdy.
   const string text = DoubleToString(MeasuredPoints(price), 0);
   string err;
   if(!ApplyField(PQE_OBJ_EDIT_SL, text, err))
     {
      g_lastEvent = err;
      UpdatePanel();
      ChartRedraw();
      return;
     }
   ApplyField(PQE_OBJ_EDIT_TP, text, err);
   ObjectSetString(0, PQE_OBJ_EDIT_SL, OBJPROP_TEXT, FieldValueText(PQE_OBJ_EDIT_SL));
   ObjectSetString(0, PQE_OBJ_EDIT_TP, OBJPROP_TEXT, FieldValueText(PQE_OBJ_EDIT_TP));

   Disarm(StringFormat("SL = PT = %d b (změřeno v grafu)", g_slPoints));
   Print("PQE: ", g_lastEvent);
   UpdatePanel();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Prekresli nahled mereni podle polohy mysi.                       |
//| Plna linka = vychozi bod (kresli ji HandleMeasureClick), teckovana|
//| linka jede za kurzorem a popisek u kurzoru ukazuje vzdalenost    |
//| v bodech. Nad panelem se schova jen linka u kurzoru a popisek,   |
//| vychozi bod zustava videt. g_pvShown tu znamena "linka u kurzoru |
//| je v grafu".                                                     |
//+------------------------------------------------------------------+
void UpdateMeasurePreview()
  {
   if(g_measure == PQE_MEASURE_NONE || g_mouseX < 0)
      return;

   double price = 0.0;
   if(!ChartPointPrice(g_mouseX, g_mouseY, price))
     {
      //--- Mazat a prekreslovat jen tehdy, kdyz linka u kurzoru v grafu je
      if(g_pvShown)
        {
         ObjectDelete(0, PQE_OBJ_PV_SL);
         ObjectDelete(0, PQE_OBJ_PV_LABEL);
         g_pvShown = false;
         g_pvText  = "";
         ChartRedraw();
        }
      return;
     }

   //--- Text a barva: pred 1. klikem jen vyzva, pak vzdalenost
   //--- (sede, kdyz je mimo rozsah pole SL)
   string text = "SL/PT: klikni na 1. bod (Esc)";
   color  clr  = InpColorText;
   if(g_measure == PQE_MEASURE_TO)
     {
      const double points = MeasuredPoints(price);
      if(SlPointsInRange(points))
        {
         text = StringFormat("SL = PT = %.0f b = %s", points,
                             DoubleToString(points * _Point, _Digits));
         clr  = InpColorSL;
        }
      else
        {
         text = StringFormat("SL/PT: mimo 1..%d b", PQE_MAX_POINTS);
         clr  = PQE_COLOR_OFF;
        }
     }

   //--- Nezmeneny nahled se nekresli znovu (stejne jako u UpdatePreview)
   if(g_pvShown && text == g_pvText && g_mouseX == g_pvX && g_mouseY == g_pvY &&
      SamePrice(price, g_pvSL))
      return;

   DrawHLine(PQE_OBJ_PV_SL, price, clr, STYLE_DOT, 1);
   DrawLabel(PQE_OBJ_PV_LABEL, g_mouseX + Dpi(16), g_mouseY + Dpi(18), Fit(text), clr);

   //--- Vykresleny stav pro porovnani pri dalsim volani
   g_pvShown = true;
   g_pvSL    = price;
   g_pvText  = text;
   g_pvX     = g_mouseX;
   g_pvY     = g_mouseY;
   ChartRedraw();
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
//| Poradi shora: titulek, tri pole formulare, predvolby rizika,     |
//| rozdeleni rizika, pet                                            |
//| rad tlacitek (BUYSTOP / SELLSTOP, BUY / SELL, BUY / SELL MARKET, |
//| zavirani, castecne zavreni), dve rady posunu SL / prikazu,       |
//| rada sjednoceni SL / prikazu                                     |
//| a stavove radky. Vyska vznika                                    |
//| soucasne s polohami, takze pozadi panelu i IsInsidePanel vzdy    |
//| odpovidaji tomu, co je vykreslene -                              |
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
   lo.ySplit = y;
   y += Px(PQE_RISK_BTN_H) + lo.gap;
   lo.yStops = y;
   y += lo.btnH + lo.gap;
   lo.yBuySell = y;
   y += lo.btnH + lo.gap;
   lo.yMarket = y;
   y += lo.btnH + lo.gap;
   lo.yClose = y;
   y += lo.btnH + lo.gap;
   lo.yPartial = y;
   y += lo.btnH + lo.gap;
   lo.yMoveUp = y;
   y += Px(PQE_RISK_BTN_H) + lo.gap;
   lo.yMoveDown = y;
   y += Px(PQE_RISK_BTN_H) + lo.gap;
   lo.yConsolidate = y;
   y += Px(PQE_RISK_BTN_H) + lo.gap;
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
              "Puntiky Quick Entry v" + EA_VERSION + " - build " + BuildStamp());

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

   //--- Tlacitko "nastav" mezi popiskem a polem SL: mereni SL/PT v grafu.
   //--- Behem mereni se zmeni na "zrušit" (stejne jako BUY na ZRUSIT BUY).
   const bool measuring = (g_measure != PQE_MEASURE_NONE);
   DrawButton(PQE_OBJ_BTN_MEASURE, x + Px(PQE_LABEL_W), lo.yFields[0],
              Px(PQE_MEASURE_W), Px(PQE_EDIT_H),
              measuring ? "zrušit" : "nastav",
              measuring ? PQE_COLOR_BTN_CANCEL : PQE_COLOR_BTN_RISK_OFF,
              measuring ? "Zruší měření SL/PT v grafu."
                        : "Nastaví SL a PT z grafu: 1. klik = výchozí bod, 2. klik = konec (PT = SL).",
              0);

   //--- Predvolby rizika (vybrana je zvyraznena)
   DrawRiskButtons(x, lo.yRisk, inner);

   //--- Rozdeleni rizika mezi pozice vstupu (vybrane je zvyraznene)
   DrawSplitButtons(x, lo.ySplit, inner);

   //--- Tri rady vstupu po dvou tlacitcich: BUYSTOP / SELLSTOP (jen STOP
   //--- nebo MARKET), pod nimi BUY / SELL (STOP, LIMIT nebo MARKET)
   //--- a nakonec BUY MARKET / SELL MARKET (za trh hned, bez kliku do grafu)
   const int btnW = (inner - lo.gap) / 2;
   DrawDirectionButton(PQE_OBJ_BTN_STOP_BUY,  true,  true, x, lo.yStops, btnW, lo.btnH, st);
   DrawDirectionButton(PQE_OBJ_BTN_STOP_SELL, false, true, x + btnW + lo.gap, lo.yStops,
                       btnW, lo.btnH, st);

   DrawDirectionButton(PQE_OBJ_BTN_BUY,  true,  false, x, lo.yBuySell, btnW, lo.btnH, st);
   DrawDirectionButton(PQE_OBJ_BTN_SELL, false, false, x + btnW + lo.gap, lo.yBuySell,
                       btnW, lo.btnH, st);

   DrawMarketButton(PQE_OBJ_BTN_MKT_BUY,  true,  x, lo.yMarket, btnW, lo.btnH, st);
   DrawMarketButton(PQE_OBJ_BTN_MKT_SELL, false, x + btnW + lo.gap, lo.yMarket,
                    btnW, lo.btnH, st);

   //--- Rada tlacitek zavirani: ZRUSIT PRIKAZY / ZAVRIT 1 / ZAVRIT VSE
   DrawCloseButtons(x, lo.yClose, inner, lo.btnH, st);

   //--- Posledni rada: castecne zavreni jedine pozice (100 %, 50 % ...)
   DrawPartialButtons(x, lo.yPartial, inner, lo.btnH, st);

   //--- Dve rady posunu SL / cekajicich prikazu (nahoru, dolu)
   DrawMoveRow(true,  x, lo.yMoveUp,   inner, st);
   DrawMoveRow(false, x, lo.yMoveDown, inner, st);

   //--- Sjednoceni SL / cen cekajicich prikazu na prumer
   DrawConsolidateButtons(x, lo.yConsolidate, inner, st);

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
   // Jeden pruchod pozicemi slouzi poctu i tlacitkum castecneho zavreni
   st.positions = OurPositionVolumes(st.posVolumes);
   st.formError = FormError();
   st.canTrade  = TradingAllowed(st.tradeReason);
   st.canClose  = ClosingAllowed(st.closeReason);
   st.balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   st.slDist    = g_slPoints * _Point;
   // Riziko z formulare se deli mezi pozice podle zvoleneho rozdeleni
   st.count     = SplitCount(g_splitIndex);
   st.lotsOk    = CalcSplitLots(st.slDist, g_splitIndex, st.lots, st.lotReason);
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
   const string blocked = OpenBlockReason(st);
   if(g_measure != PQE_MEASURE_NONE)
      lines[0] = StringFormat("stav: SL/PT - klikni na %d. bod (Esc)",
                              g_measure == PQE_MEASURE_FROM ? 1 : 2);
   else
      if(g_armed != PQE_ARM_NONE)
         lines[0] = "stav: " + ArmName(g_armed) + " - klikni do grafu (Esc)";
      else
         lines[0] = "stav: " + (blocked != "" ? blocked : "připraven - stiskni BUY nebo SELL");

   //--- Objem z rizika pro aktualni SL a zustatek (texty jsou kratke,
   //--- radek panelu ma jen PanelMaxChars znaku). Pri vice pozicich
   //--- objemy vsech pozic a riziko za vsechny dohromady; castka v mene
   //--- se u vice pozic na radek nevejde.
   const int count = st.count;
   if(st.lotsOk)
     {
      const double risk = TotalLots(st.lots, count) * LossPerLot(st.slDist);
      lines[1] = "objem " + FormatSplitLots(st.lots, count) + " lot" +
                 (count == 1 ? StringFormat(" = %.2f %s", risk, AccountInfoString(ACCOUNT_CURRENCY)) : "") +
                 StringFormat(" (%.2f %%)", st.balance > 0.0 ? risk / st.balance * 100.0 : 0.0);
     }
   else
      lines[1] = "objem: " + st.lotReason;

   //--- Vzdalenosti SL a PT prevedene na cenu; pri vice pozicich se
   //--- misto ceny vypisou body PT vsech pozic (na cenu se nevejdou)
   string tpText = TpPointsText(count);
   if(g_tpPoints > 0 && count == 1)
      tpText += " = " + DoubleToString(g_tpPoints * _Point, _Digits);
   lines[2] = StringFormat("SL %d b = %s   PT %s",
                           g_slPoints, DoubleToString(st.slDist, _Digits), tpText);

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
   // Pole vsech radku zacinaji za sloupcem tlacitka "nastav" (je jen na
   // radku SL), aby lezela pod sebou zarovnana
   DrawEdit(name, x + Px(PQE_LABEL_W + PQE_MEASURE_W + PQE_MEASURE_GAP), y,
            Px(PQE_EDIT_W), Px(PQE_EDIT_H), initial, tooltip);
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko BUY / SELL / BUYSTOP / SELLSTOP a nastavi      |
//| mu podobu podle stavu. Behem vyberu se tlacitko zmeni na ZRUSIT, |
//| pri chybe formulare, zakazanem obchodovani nebo objemu, ktery    |
//| nejde spocitat (OpenBlockReason), zesedne a duvod                |
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
   const string dir     = ArmName(armDir);
   const string blocked = OpenBlockReason(st);

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
      if(blocked != "")
        {
         bg      = PQE_COLOR_BTN_OFF;
         tooltip = "Nelze obchodovat: " + blocked;
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
//| Proc nejde otevrit novy obchod ("" = lze).                       |
//|  st - stav spocteny pro toto prekresleni                         |
//| Spolecne poradi kontrol pro stavovy radek a vsechna tlacitka     |
//| vstupu (BUY / SELL, BUYSTOP / SELLSTOP i MARKET). Patri sem i    |
//| objem z rizika (duvod z CalcSplitLots) - kdyz nejde spocitat,    |
//| vstup by se stejne nezadal, tak at tlacitka zesednou predem.     |
//+------------------------------------------------------------------+
string OpenBlockReason(const SPanelState &st)
  {
   if(st.formError != "")
      return(st.formError);
   if(!st.canTrade)
      return(st.tradeReason);
   if(!st.lotsOk)
      return(st.lotReason);
   return("");
  }

//+------------------------------------------------------------------+
//| Poloha a sirka i-teho tlacitka v rade stejne sirokych tlacitek.  |
//|  x, w  - levy okraj a celkova sirka rady, count - pocet tlacitek |
//|  gap   - mezera mezi tlacitky, i - poradi tlacitka               |
//|  bx, bw - out: levy okraj a sirka tlacitka                       |
//| Posledni tlacitko dostane zbytek sirky, aby rada koncila         |
//| zarovnane i pri zaokrouhleni sirky dolu.                         |
//+------------------------------------------------------------------+
void RowCell(const int x, const int w, const int count, const int gap, const int i,
             int &bx, int &bw)
  {
   const int btnW = (w - (count - 1) * gap) / count;
   bx = x + i * (btnW + gap);
   bw = (i == count - 1) ? (w - i * (btnW + gap)) : btnW;
  }

//+------------------------------------------------------------------+
//| Vykresli tlacitko BUY MARKET / SELL MARKET.                      |
//| Pri chybe formulare, zakazanem obchodu nebo objemu, ktery nejde  |
//| spocitat, zesedne a duvod da do bubliny; jinak bublina ukaze,    |
//| s jakym objemem a stopy obchod hned otevre.                      |
//|  name - jmeno objektu, isBuy - smer                              |
//|  x, y - poloha, w, h - rozmery v pixelech                        |
//|  st - stav spocteny pro toto prekresleni                         |
//+------------------------------------------------------------------+
void DrawMarketButton(const string name, const bool isBuy,
                      const int x, const int y, const int w, const int h,
                      const SPanelState &st)
  {
   const string dir = isBuy ? "BUY" : "SELL";

   const string blocked = OpenBlockReason(st);

   string tooltip;
   if(blocked != "")
      tooltip = "Nelze obchodovat: " + blocked;
   else
      tooltip = StringFormat("Hned otevře %s za trh (%s), %s lot, SL %d b, PT %s - bez kliku do grafu.",
                             dir, isBuy ? "Ask" : "Bid", FormatSplitLots(st.lots, st.count),
                             g_slPoints, TpPointsText(st.count));

   const color bg = (blocked != "") ? PQE_COLOR_BTN_OFF
                    : (isBuy ? PQE_COLOR_BTN_MKT_BUY : PQE_COLOR_BTN_MKT_SELL);
   DrawButton(name, x, y, w, h, dir + " MARKET", bg, tooltip, PQE_BTN_FONT_PLUS_SMALL);
  }

//+------------------------------------------------------------------+
//| Vykresli radu tlacitek castecneho zavreni (ZAV 100%, ZAV 50% ...)|
//| Tlacitka zesednou, kdyz expert nema pozici nebo zavirat nejde    |
//| (duvod je v bubline). Bublina aktivniho tlacitka ukaze, kolik    |
//| lotu ze vsech pozic experta dohromady zavre.                     |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//|  btnH - vyska tlacitek                                           |
//|  st   - stav spocteny pro toto prekresleni (vcetne pozic)        |
//+------------------------------------------------------------------+
void DrawPartialButtons(const int x, const int y, const int w, const int btnH,
                        const SPanelState &st)
  {
   const int    count   = ArraySize(g_closePresets);
   const int    gap     = Px(PQE_BTN_GAP);
   const string blocked = PartialBlockReason(st.canClose, st.closeReason, st.positions);

   for(int i = 0; i < count; i++)
     {
      const double percent = g_closePresets[i];
      int bx, bw;
      RowCell(x, w, count, gap, i, bx, bw);

      //--- Kolik lotu predvolba zavre ze vsech pozic dohromady
      double lots = 0.0;
      for(int k = 0; k < st.positions; k++)
         lots += PartialCloseVolume(st.posVolumes[k].initial, st.posVolumes[k].current, percent);

      const string tooltip = (blocked != "")
                             ? "Nelze: " + blocked
                             : StringFormat("Zavře %s původního objemu z každé pozice experta (%d): celkem %s lot.",
                                            FormatPercent(percent), st.positions, FormatLots(lots));

      DrawButton(PQE_OBJ_BTN_PARTIAL + IntegerToString(i), bx, y, bw, btnH,
                 "ZAV " + FormatPercent(percent),
                 (blocked == "") ? PQE_COLOR_BTN_PARTIAL : PQE_COLOR_BTN_OFF, tooltip, 0);
     }
  }

//+------------------------------------------------------------------+
//| Vykresli jednu radu posunu: 1. rada nahoru, 2. rada dolu.        |
//| Prvni tlacitko rady je prepinac rezimu - SL v 1. rade (posun SL  |
//| vsech pozic a prikazu), PO ve 2. rade (posun celych cekajicich   |
//| prikazu); zvoleny rezim je zvyrazneny. Za nim jsou kroky maly /  |
//| stredni / velky. Kroky zesednou, kdyz v danem rezimu neni co     |
//| posunout nebo upravy nejdou (duvod je v bubline).                |
//|  up   - rada nahoru (true) nebo dolu (false)                     |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//|  st   - stav spocteny pro toto prekresleni                       |
//+------------------------------------------------------------------+
void DrawMoveRow(const bool up, const int x, const int y, const int w, const SPanelState &st)
  {
   const int    gap     = Px(PQE_RISK_BTN_GAP);
   const int    btnH    = Px(PQE_RISK_BTN_H);
   const int    cells   = PQE_MOVE_STEPS + 1;   // prepinac + kroky
   const string blocked = AdjustBlockReason(st, g_moveOrders, 1);
   const string target  = g_moveOrders ? "všechny čekající příkazy experta i s SL a PT"
                                       : "SL všech pozic a čekajících příkazů experta";
   int bx, bw;

   //--- Prepinac rezimu: SL v rade nahoru, PO v rade dolu
   RowCell(x, w, cells, gap, 0, bx, bw);
   DrawButton(up ? PQE_OBJ_BTN_MOVE_SL : PQE_OBJ_BTN_MOVE_PO, bx, y, bw, btnH,
              up ? "SL" : "PO",
              (g_moveOrders != up) ? PQE_COLOR_BTN_RISK_ON : PQE_COLOR_BTN_RISK_OFF,
              up ? "Tlačítka posunu budou hýbat SL pozic a čekajících příkazů."
                 : "Tlačítka posunu budou hýbat celými čekajícími příkazy (i s SL a PT).",
              0);

   //--- Kroky posunu
   for(int step = 0; step < PQE_MOVE_STEPS; step++)
     {
      const int points = MoveStepPoints(step);
      RowCell(x, w, cells, gap, step + 1, bx, bw);
      const string tooltip = (blocked != "")
                             ? "Nelze: " + blocked
                             : StringFormat("Posune %s o %d b (%s) %s.", target, points,
                                            DoubleToString(points * _Point, _Digits),
                                            up ? "nahoru" : "dolů");
      DrawButton((up ? PQE_OBJ_BTN_MOVE_UP : PQE_OBJ_BTN_MOVE_DOWN) + IntegerToString(step),
                 bx, y, bw, btnH, MoveButtonText(up, step),
                 (blocked != "") ? PQE_COLOR_BTN_OFF
                 : (up ? PQE_COLOR_BTN_MOVE_UP : PQE_COLOR_BTN_MOVE_DOWN),
                 tooltip, 0);
     }
  }

//+------------------------------------------------------------------+
//| Vykresli radu SJEDNOTIT SL / SJEDNOTIT PO.                       |
//| Tlacitko zesedne, kdyz neni co sjednocovat (mene nez 2 obchody)  |
//| nebo upravy nejdou; duvod je v bubline.                          |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//|  st   - stav spocteny pro toto prekresleni                       |
//+------------------------------------------------------------------+
void DrawConsolidateButtons(const int x, const int y, const int w, const SPanelState &st)
  {
   const int gap  = Px(PQE_RISK_BTN_GAP);
   const int btnH = Px(PQE_RISK_BTN_H);

   for(int i = 0; i < 2; i++)
     {
      const bool   orders  = (i == 1);
      const string blocked = AdjustBlockReason(st, orders, 2);
      int bx, bw;
      RowCell(x, w, 2, gap, i, bx, bw);

      const string tooltip = (blocked != "") ? "Nelze: " + blocked
                             : orders ? "Srovná čekající příkazy experta (i s SL a PT) na průměrnou cenu, zvlášť každý typ příkazu."
                             : "Srovná SL pozic a čekajících příkazů experta na průměrnou úroveň, zvlášť BUY a SELL.";
      DrawButton(orders ? PQE_OBJ_BTN_CONS_PO : PQE_OBJ_BTN_CONS_SL, bx, y, bw, btnH,
                 ConsolidateButtonText(orders),
                 (blocked != "") ? PQE_COLOR_BTN_OFF : PQE_COLOR_BTN_CONSOLIDATE, tooltip, 0);
     }
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
   const int gap   = Px(PQE_RISK_BTN_GAP);
   const int btnH  = Px(PQE_RISK_BTN_H);

   for(int i = 0; i < count; i++)
     {
      const bool selected = (MathAbs(g_riskPresets[i] - g_riskPercent) < PQE_RISK_EPS);
      int bx, bw;
      RowCell(x, w, count, gap, i, bx, bw);

      DrawButton(PQE_OBJ_BTN_RISK + IntegerToString(i), bx, y, bw, btnH,
                 FormatPercent(g_riskPresets[i]),
                 selected ? PQE_COLOR_BTN_RISK_ON : PQE_COLOR_BTN_RISK_OFF,
                 StringFormat("Nastaví riziko %.2f %% zůstatku na obchod.", g_riskPresets[i]),
                 0);
     }
  }

//+------------------------------------------------------------------+
//| Vykresli radu tlacitek rozdeleni rizika (100%, 50/50 ...).       |
//| Zvyraznene je zvolene rozdeleni. Na netting uctu jsou rozdeleni  |
//| na vice pozic seda a duvod maji v bubline (pozice by se sloucily |
//| do jedne).                                                       |
//|  x, y - poloha rady, w - celkova sirka rady v pixelech           |
//+------------------------------------------------------------------+
void DrawSplitButtons(const int x, const int y, const int w)
  {
   const int gap  = Px(PQE_RISK_BTN_GAP);
   const int btnH = Px(PQE_RISK_BTN_H);

   for(int i = 0; i < PQE_SPLIT_PRESETS; i++)
     {
      const int    count   = SplitCount(i);
      const string blocked = CountBlockReason(count);
      int bx, bw;
      RowCell(x, w, PQE_SPLIT_PRESETS, gap, i, bx, bw);

      //--- Bublina rekne, jake PT pozice dostanou a jak se deli riziko
      string tooltip;
      if(blocked != "")
         tooltip = "Nelze: " + blocked + " (netting by pozice sloučil do jedné).";
      else
         tooltip = StringFormat("Pozice: %d, podíly rizika %s %%, PT %s (nejbližší PT má první podíl), SL všem stejný.",
                                count, SplitText(i), TpPointsText(count));

      const color bg = (i == g_splitIndex) ? PQE_COLOR_BTN_RISK_ON
                       : (blocked != "") ? PQE_COLOR_BTN_OFF : PQE_COLOR_BTN_RISK_OFF;
      DrawButton(PQE_OBJ_BTN_SPLIT + IntegerToString(i), bx, y, bw, btnH,
                 SplitLabel(i), bg, tooltip, 0);
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
