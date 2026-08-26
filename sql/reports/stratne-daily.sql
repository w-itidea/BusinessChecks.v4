-- CHECK: zamowienia stratne z ostatniej doby (zastepuje ~/.claude/cron/stratne_slack.sh)
-- @opis Które zamówienia z ostatniej doby przyniosły stratę i dlaczego — z linkami do panelu.
--
-- Zrodlo: BIData.opi_OrderProfit (mirror w BQ) — bez VPN, bez sqlcmd, bez modelu jezykowego.
-- Klasyfikacja przyczyny jest policzona, nie zgadnieta przez AI: te same progi za kazdym razem,
-- wiec wyniki z roznych dni sa porownywalne.
--
-- Filtry obowiazkowe: OrderStatusId <> 40 (anulowane), IsDoneCalculating = 1 (profit domkniety).
--
-- @link Zamowienie https://panel.fkwt.pl/Order3.aspx?OrderId={}
-- ^ runner dokleja pod tabela klikalne linki do zamowien w panelu (poza code-blockiem,
--   bo w code-blocku linki Slacka sie nie klikaja). Kolumna Zamowienie = CustomerOrderId.

DECLARE dni_wstecz     INT64   DEFAULT 1;
DECLARE prog_straty    NUMERIC DEFAULT 0;    -- Profit_Actual ponizej tej wartosci = strata
DECLARE prog_istotnosci NUMERIC DEFAULT -10; -- ponizej tego pokazujemy nawet bez zdiagnozowanej przyczyny
DECLARE ile_pokazac    INT64   DEFAULT 15;

-- PROG ISTOTNOSCI — dobrany na probce tygodniowej (sql/diagnostic/stratne-inne-rozklad.sql):
-- w kuble "inne / zlozone" 139 z 201 zamowien tracilo < 5 zl, dajac tylko 29% straty kubla.
-- Lista bez progu tonie w szumie. Dlatego pokazujemy zamowienie, gdy MA zdiagnozowana
-- przyczyne (patologia — niezaleznie od kwoty) ALBO strata przekracza prog_istotnosci.

SELECT * FROM (
SELECT
  CustomerOrderId                                        AS Zamowienie,
  IdBookstore                                            AS Rynek,
  CASE ShippingCountryIso2
    WHEN 'DE' THEN 'Niemcy'     WHEN 'FR' THEN 'Francja'    WHEN 'IT' THEN 'Wlochy'
    WHEN 'ES' THEN 'Hiszpania'  WHEN 'NL' THEN 'Holandia'   WHEN 'BE' THEN 'Belgia'
    WHEN 'PL' THEN 'Polska'     WHEN 'SE' THEN 'Szwecja'    WHEN 'AT' THEN 'Austria'
    WHEN 'IE' THEN 'Irlandia'   WHEN 'GB' THEN 'W.Brytania' WHEN 'UK' THEN 'W.Brytania'
    WHEN 'DK' THEN 'Dania'      WHEN 'FI' THEN 'Finlandia'  WHEN 'PT' THEN 'Portugalia'
    WHEN 'LU' THEN 'Luksemburg' WHEN 'CZ' THEN 'Czechy'     WHEN 'MT' THEN 'Malta'
    WHEN 'CY' THEN 'Cypr'       WHEN 'GR' THEN 'Grecja'     WHEN 'HU' THEN 'Wegry'
    WHEN 'RO' THEN 'Rumunia'    WHEN 'SK' THEN 'Slowacja'   WHEN 'SI' THEN 'Slowenia'
    WHEN 'HR' THEN 'Chorwacja'  WHEN 'BG' THEN 'Bulgaria'   WHEN 'EE' THEN 'Estonia'
    WHEN 'LT' THEN 'Litwa'      WHEN 'LV' THEN 'Lotwa'      WHEN 'NO' THEN 'Norwegia'
    WHEN 'CH' THEN 'Szwajcaria'
    ELSE COALESCE(ShippingCountryIso2, '??')
  END                                                    AS Kraj,
  FORMAT_TIMESTAMP('%m-%d %H:%M', OrderCreatedOnUtc)     AS Utworzono,
  NumOfItems                                             AS Szt,
  ROUND(fOrderTotal, 2)                                  AS Wartosc,
  ROUND(Profit_Actual, 2)                                AS Strata,
  ROUND(ProfitMargin, 1)                                 AS Marza_pct,
  CASE
    WHEN fOrderTotal < ProductCost                                     THEN 'sprzedaz ponizej kosztu towaru'
    WHEN ShippingCost > (fOrderTotal - ProductCost)                    THEN 'wysylka zjada marze'
    WHEN SAFE_DIVIDE(MarketplaceCost, NULLIF(fOrderTotal, 0)) > 0.25   THEN 'koszty marketplace > 25%'
    WHEN SAFE_DIVIDE(PaymentCost, NULLIF(fOrderTotal, 0)) > 0.10       THEN 'koszty platnosci > 10%'
    ELSE 'inne / zlozone'
  END                                                    AS Przyczyna
FROM `polish-bookstores-group.BIData.opi_OrderProfit`
WHERE OrderCreatedOnUtc >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL dni_wstecz DAY)
  AND OrderStatusId <> 40
  AND IsDoneCalculating
  AND Profit_Actual < prog_straty
)
WHERE Przyczyna <> 'inne / zlozone' OR Strata <= prog_istotnosci
-- BigQuery nie przyjmuje zmiennej w LIMIT ("expects an integer literal or parameter"),
-- wiec ograniczenie robimy przez QUALIFY — parametr zostaje sterowalny.
QUALIFY ROW_NUMBER() OVER (ORDER BY Strata ASC) <= ile_pokazac
ORDER BY Strata ASC
