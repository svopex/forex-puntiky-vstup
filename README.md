# Puntiky Quick Entry — rychlý vstup do pozice pro MetaTrader 5

Expert Advisor pro MT5 (RoboForex, XAUUSD), který zadá obchod na **dvě
kliknutí**: tlačítko `BUY` nebo `SELL` v panelu a klik do grafu na místo vstupu.
Podle polohy kliknutí vůči aktuální ceně vznikne buď **STOP příkaz**, nebo
**MARKET příkaz**, vždy rovnou se **stop lossem a profit targetem** a s objemem
dopočítaným z **rizika v procentech zůstatku účtu** (výchozí 1 %).

Expert sám nikdy nic neobchoduje — dělá jen to, co se mu klikne.

## Jak se používá

1. Přetáhni experta `PuntikyQuickEntry` na graf **XAUUSD** (symbol se dá změnit
   v nastavení i ve formuláři, musí ale odpovídat grafu).
2. V panelu vlevo nahoře je formulář předvyplněný z nastavení experta:
   `Symbol`, `SL (body)`, `PT (body)`, `Riziko (%)`. Kteroukoli hodnotu lze
   před obchodem přepsat (Enter nebo odchod z pole ji potvrdí; nesmysl se vrátí
   na poslední platnou hodnotu a důvod se ukáže v panelu).
   Pod polem `Riziko (%)` je řada tlačítek s předvolbami (`0.5%  1%  1.5%  2%
   2.5%`, nastavitelné vstupem `InpRiskPresets`) — klik nastaví riziko a zapíše
   ho do pole, zvýrazněné je tlačítko odpovídající aktuální hodnotě (po startu
   tedy `InpRiskPercent`, výchozí 1 %). Ručně zapsaná hodnota mimo předvolby
   nezvýrazní žádné.
3. Stiskni `BUY` nebo `SELL`. Tlačítko se změní na `ZRUŠIT BUY` / `ZRUŠIT SELL`
   a za myší začne jezdit **linka vstupu** spolu s linkami SL a PT a popiskem,
   který říká přesně, co klik udělá — včetně objemu.
4. Klikni do grafu na místo vstupu:

   | Směr | Klik | Výsledek |
   |---|---|---|
   | BUY  | nad Ask (dál než stop-level brokera) | `BUY STOP` na kliknuté ceně |
   | BUY  | na Ask nebo pod ním | `BUY` za trh (aktuální Ask) |
   | SELL | pod Bid (dál než stop-level brokera) | `SELL STOP` na kliknuté ceně |
   | SELL | na Bid nebo nad ním | `SELL` za trh (aktuální Bid) |

   Linka STOP příkazu je **čárkovaná**, linka MARKET vstupu **plná** (drží se
   aktuální ceny). Kliknutí v pásmu mezi trhem a stop-levelem brokera se
   odmítne (šedá linka, důvod v popisku) a výběr zůstává aktivní.
5. Po odeslání příkazu výběr končí a panel na řádku `poslední:` ukáže ticket,
   cenu a objem; detaily včetně SL a PT jsou v Expert logu.

Výběr se ruší klávesou **Esc** nebo opětovným stiskem téhož tlačítka. Stisk
druhého tlačítka během výběru jen přepne směr.

Pod BUY / SELL je řada tří tlačítek zavírání (vždy jen obchody s magic number
experta, cizí pozice a příkazy nechává; bez potvrzování):

| Tlačítko | Co udělá |
|---|---|
| `ZRUŠIT STOP` | zruší **všechny** čekající STOP příkazy experta, otevřené pozice nechá |
| `ZAVŘÍT 1` | zavře **jednu** pozici experta za trh — při více pozicích (hedging) tu **nejstarší** (FIFO) |
| `ZAVŘÍT VŠE` | zavře všechny pozice experta a zruší všechny jeho STOP příkazy |

Tlačítko, pro které na trhu nic není, je šedé a důvod má v bublině; počty jsou
na stavovém řádku `příkazy … pozice …`. Výsledek se zapíše na řádek `»` i do
Expert logu.

SL a PT se měří **od vstupní ceny** v bodech (`_Point` symbolu — u XAUUSD se
dvěma desetinnými místy je 300 bodů = 3,00 USD). Panel na řádku `SL … PT …`
vždy ukazuje přepočet na cenu.

## Objem z rizika

Objem se počítá tak, aby ztráta při zásahu SL odpovídala zadanému procentu
**zůstatku** účtu:

```
lot = zůstatek × riziko / 100 / (vzdálenost SL / tick size × tick value ztrátové strany)
```

Výsledek se zaokrouhlí **dolů** na krok objemu symbolu. Když na zadané riziko
nestačí ani nejmenší povolený lot, obchod se nezadá (riziko nesmí tiše přetéct
přes limit) a panel řekne, kolik procent by minimální lot znamenal. Před
odesláním se ještě ověří volná marže.

Řádek `objem:` v panelu ukazuje aktuální výsledek pro hodnoty ve formuláři,
takže je vidět ještě před stiskem tlačítka.

### Dorovnání SL/PT po vyplnění

STOP příkaz na účtu s Market execution se plní za trh a MARKET příkaz může mít
skluz — SL a PT nastavené od požadované ceny by pak neseděly s rizikem. Expert
proto po vyplnění (`OnTradeTransaction`) posune SL a PT tak, aby měly od
**skutečné plnicí ceny** stejnou vzdálenost, jakou měly od ceny příkazu. Vypíná
se vstupem `InpAlignStopsToFill`.

## Nastavení experta

| Vstup | Výchozí | Význam |
|---|---|---|
| `InpSymbol` | `XAUUSD` | Symbol — předvyplní se do formuláře, musí odpovídat grafu |
| `InpStopLossPoints` | `300` | Stop loss v bodech — předvyplní se do formuláře |
| `InpTakeProfitPoints` | `300` | Profit target v bodech (0 = bez PT) — předvyplní se do formuláře |
| `InpRiskPercent` | `1.0` | Riziko na obchod v % zůstatku — předvyplní se do formuláře a zvýrazní odpovídající tlačítko |
| `InpRiskPresets` | `0.5;1;1.5;2;2.5` | Předvolby rizika pro tlačítka (%, oddělené `;`, nejvýše 8) |
| `InpSlippage` | `20` | Maximální skluz MARKET příkazu (body) |
| `InpExpirationMinutes` | `0` | Platnost STOP příkazu v minutách (0 = do zrušení) |
| `InpAlignStopsToFill` | `true` | Po vyplnění dorovnat SL/PT na skutečnou plnicí cenu |
| `InpMagic` | `20260828` | Magic number příkazů experta |
| `InpPanelX`, `InpPanelY` | `12`, `22` | Poloha panelu v pixelech při 96 DPI (škáluje se s DPI monitoru) |
| `InpPanelOneClickShift` | `70` | Posun panelu dolů, když je zapnuté okno One Click Trading MT5 (px při 96 DPI) |
| `InpPanelFontSize` | `10` | Velikost písma panelu — celý panel včetně tlačítek se s ním zvětšuje |
| `InpColor*` | | Barvy textu panelu a linek vstupu BUY / SELL, SL a PT |

Hodnoty formuláře **přežijí změnu timeframe** (objekty v grafu zůstávají);
změna parametrů experta, rekompilace nebo odebrání z grafu formulář vrátí na
hodnoty ze vstupů.

## Panel

```
VSTUP XAUUSD  Ask 2345.10  Bid 2345.00
Symbol      [XAUUSD  ]
SL (body)   [300     ]
PT (body)   [300     ]
Riziko (%)  [1.00    ]
[0.5%] [ 1% ] [1.5%] [ 2% ] [2.5%]     ← vybrané zvýrazněno modře
[     BUY     ] [    SELL     ]
[ZRUŠIT STOP] [ ZAVŘÍT 1 ] [ZAVŘÍT VŠE]
stav: připraven - stiskni BUY nebo SELL
objem 0.33 lot = 99.00 USD (0.99 %)
SL 300 b = 3.00   PT 300 b = 3.00
příkazy 0  pozice 0  zůstatek 10000.00
» BUY MARKET #740748081 4459.66 0.08 lot
```

Řádek `stav:` říká, proč se případně nedá obchodovat (symbol formuláře
neodpovídá grafu, vypnutý Algo Trading, účet bez povolení…) — ve stejné situaci
tlačítka zešednou a důvod mají v bublině.

## Nasazení

Terminál musí být alespoň jednou spuštěný (aby existoval datový adresář).
Ve Windows spusť z kořene repozitáře:

```
scripts\deploy.cmd
```

nebo přímo

```
powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1 [-Broker "RoboForex"] [-NoCompile]
```

Skript:

1. najde instalaci terminálu podle názvu brokera v `C:\Program Files`
   a její datový adresář v `%APPDATA%\MetaQuotes\Terminal` (přes `origin.txt`),
2. zkopíruje `MQL5\Experts\PuntikyQuickEntry\*.mq5` do
   `<data>\MQL5\Experts\PuntikyQuickEntry\`,
3. zkompiluje zdroj přes `MetaEditor64.exe /compile` a vypíše chyby, varování
   a výsledek kompilace.

Po kompilaci se expert objeví v Navigátoru terminálu (Experts →
PuntikyQuickEntry); stačí ho přetáhnout na graf a v dialogu povolit
**Allow Algo Trading**. V terminálu musí být zapnutý Algo Trading (tlačítko
v liště).

### Po novém nasazení — která verze v grafu běží?

Běžící terminál experta po kompilaci obvykle sám znovu načte (v žurnálu
`expert … removed` / `loaded successfully`), ale **ne vždy** — např. když expert
zrovna obchoduje, reload se přeskočí a v grafu dál běží stará verze. Změna
symbolu nebo timeframe grafu to nespraví (jen reinicializuje tutéž instanci
v paměti).

Kontrola: v Expert logu má být po startu řádek
`PQE: rychlý vstup spuštěn … build <datum a čas kompilace>`; stejný čas je
v bublině titulku panelu. Když čas neodpovídá poslednímu nasazení, odeber
experta ze **všech** grafů a přidej ho znovu (nebo restartuj terminál).
Deploy skript na to při běžícím terminálu upozorní.

## Struktura repozitáře

```
MQL5/Experts/PuntikyQuickEntry/PuntikyQuickEntry.mq5   zdroj experta (jediný soubor)
scripts/deploy.ps1                                      nasazení + kompilace
scripts/deploy.cmd                                      obálka pro stroje se zakázaným PowerShellem
docs/zadani.md                                          původní zadání
```

## Poznámky a omezení

- Expert obchoduje **symbol grafu**, na kterém běží; pole `Symbol` ve formuláři
  je pojistka — když neodpovídá grafu, tlačítka nefungují a panel to hlásí.
- Ceny kliknutí se zarovnávají na krok kotace symbolu.
- Nevyplněné STOP příkazy expert sám neruší (leda přes `InpExpirationMinutes`);
  ruší se v terminálu jako kterýkoli jiný příkaz.
- Panel je navržen pro tmavé pozadí grafu. Rozměry se přepočítávají podle DPI
  monitoru (`TERMINAL_SCREEN_DPI`) a velikosti písma — MT5 totiž písmo objektů
  s DPI zvětšuje, ale souřadnice a rozměry objektů ne, a bez přepočtu se při
  škálování Windows (např. 200 % ve VM) texty v panelu překrývají.
- Testovací prostředí: RoboForex MT5, XAUUSD.
