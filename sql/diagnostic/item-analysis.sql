-- Analiza pozycji (produktow) w zamowieniu
-- Podmien: [ID] = CustomerOrderId
SELECT
    oip.EAN,
    oip.Quantity AS Ilosc,
    CAST(oip.UnitSalesPriceNet AS DECIMAL(8,2)) AS CenaSprzedazy,
    CAST(oip.UnitPurchasePriceNet AS DECIMAL(8,2)) AS CenaZakupu,
    CAST(oip.ItemProfit AS DECIMAL(8,2)) AS ProfitPozycji,
    CAST(oip.OrderCostMinusShippingChargeForUnit AS DECIMAL(8,2)) AS KosztyPosrednieJedn,
    CAST(oip.ShippingChargePlnNettoForUnit AS DECIMAL(8,2)) AS KosztWysylkiJedn,
    CASE
        WHEN oip.UnitPurchasePriceNet >= oip.UnitSalesPriceNet THEN 'CENA_ZAKUPU_ZA_WYSOKA'
        WHEN oip.OrderCostMinusShippingChargeForUnit > (oip.UnitSalesPriceNet - oip.UnitPurchasePriceNet) THEN 'KOSZTY_POSREDNIE'
        WHEN oip.ShippingChargePlnNettoForUnit > (oip.UnitSalesPriceNet - oip.UnitPurchasePriceNet) THEN 'KOSZTY_WYSYLKI'
        ELSE 'KOMBINACJA'
    END AS GlownaPrzyczyna,
    -- Historia cen
    CAST(oip.UnitPurchasePriceNet_OfferTime AS DECIMAL(8,2)) AS CenaZakupuWMomencieOferty,
    CAST((oip.UnitPurchasePriceNet - ISNULL(oip.UnitPurchasePriceNet_OfferTime, oip.UnitPurchasePriceNet)) AS DECIMAL(8,2)) AS ZmianaCenyZakupu
FROM BIData.opi.OrderItemProfit oip (NOLOCK)
WHERE oip.CustomerOrderId = [ID]
ORDER BY oip.ItemProfit ASC;
