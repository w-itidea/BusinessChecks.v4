-- Historia cen produktu (oferty cenowe)
-- Podmien: [EAN] = EAN produktu, [DAYS] = liczba dni wstecz (domyslnie 30)
SELECT TOP 20
    po.CreatedOnUtc AS DataOferty,
    po.BookstoreId AS Marketplace,
    CAST(po.Price AS DECIMAL(8,2)) AS CenaOferty,
    CAST(po.PriceMin AS DECIMAL(8,2)) AS CenaMinimalna,
    po.LastSubmittedOnUtc AS OstatnioWyslana,
    po.LastUpdatedOnUtc AS OstatniaAktualizacja
FROM BIData.ofi.PriceOffer po (NOLOCK)
WHERE po.OurEan = '[EAN]'
    AND po.CreatedOnUtc >= DATEADD(DAY, -[DAYS], GETDATE())
ORDER BY po.CreatedOnUtc DESC;
