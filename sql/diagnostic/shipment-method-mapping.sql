-- Mapowanie EAN na metode wysylki
-- Podmien: [EAN] = EAN produktu
SELECT
    etsm.EAN,
    etsm.ShipmentMethodId,
    sm.ShipmentMethodName AS MetodaWysylki,
    sm.ShipmentMethodFriendlyName AS NazwaPrzyjazna,
    sm.isTrackable AS Sledzalne,
    sm.isConsolidated AS Konsolidowane,
    sm.AllowedRegion AS Region,
    etsm.CreatedOnUtc AS DataMapowania
FROM azymut.dbo.EanToShipmentMethod etsm (NOLOCK)
LEFT JOIN azymut.dbo.ShipmentMethod sm (NOLOCK) ON etsm.ShipmentMethodId = sm.Id
WHERE etsm.EAN = '[EAN]'
ORDER BY etsm.CreatedOnUtc DESC;
