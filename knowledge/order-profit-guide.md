# Order Profit - Baza wiedzy

## Architektura systemu

```
CustomerOrder (zamowienie)
    |
opi.Calculate_OrderProfitAll (MASTER procedura)
    |- opi.Calculate_ShippingCost    -> ShippingCost
    |- opi.Calculate_MarketplaceCost -> MarketplaceCost
    |- opi.Calculate_OrderPaymentCost -> PaymentCost
    |- opi.Calculate_ItemProfit      -> OrderItemProfit
    '- OrderProfit (koncowy wynik)
```

## Tabele

### Glowne
| Tabela | Opis |
|--------|------|
| `BIData.opi.OrderProfit` | Profit calego zamowienia |
| `BIData.opi.OrderItemProfit` | Profit per pozycja/produkt |
| `BIData.opi.ShippingCost` | Koszty wysylek (estymacje + rzeczywiste) |
| `BIData.opi.PaymentCost` | Koszty platnosci (PayPal, Paymento) |
| `BIData.opi.MarketplaceCost` | Koszty marketplace (referral, closing fees) |

### Wspomagajace
| Tabela | Opis |
|--------|------|
| `BIData.opi.OrderProfitTag` | Tagi problemow automatycznych |
| `BIData.ofi.PriceOffer` | Historia ofert cenowych produktow |
| `azymut.dbo.EanToShipmentMethod` | Mapowanie EAN na metode wysylki |

### Historyczne (revision)
| Tabela | Opis |
|--------|------|
| `BIData.opi.OrderProfit_Revision` | Historia zmian profitow |
| `BIData.opi.ShippingCost_Revision` | Historia zmian kosztow wysylki |
| `BIData.opi.MarketplaceCost_Revision` | Historia zmian kosztow marketplace |
| `BIData.opi.PaymentCost_Revision` | Historia zmian kosztow platnosci |

## Procedury

### Przeliczanie profitow
```sql
-- Dla pojedynczego zamowienia
EXEC opi.Calculate_OrderProfitAll 123456789;

-- Dla listy zamowien
DECLARE @Ids IdListType;
INSERT INTO @Ids(Id) VALUES(123456789), (123456790);
EXEC opi.Calculate_OrderProfitAll 0, @IdsToProcess = @Ids;
```

### Procedury skladowe
- `opi.Calculate_ShippingCost` - estymacja i rzeczywiste koszty wysylek
- `opi.Calculate_MarketplaceCost` - referral fees, closing fees
- `opi.Calculate_OrderPaymentCost` - PayPal, Paymento fees
- `opi.Calculate_ItemProfit` - profit per pozycja/produkt

## Typowe przyczyny strat

### 1. Cena zakupu >= cena sprzedazy
- Wzrost ceny dostawcy miedzy oferta a zamowieniem
- Blad w kalkulacji ceny sprzedazy
- Problem z kursem walut
- **Diagnoza:** porownaj `UnitPurchasePriceNet_OfferTime` vs `UnitPurchasePriceNet`

### 2. Wysokie koszty posrednie
- Koszty marketplace (referral fees, closing fees) zjadaja marze
- Norma: 13-17% wartosci zamowienia
- **Alarm:** > 20% = krytyczne

### 3. Wysokie koszty wysylki
- Roznica estymacji vs rzeczywistosc > 10% = tag automatyczny
- Przyczyny: fuel surcharge, zmiana taryfy, bledne mapowanie EAN
- **Diagnoza:** porownaj `ShippingCostTotal_EstimatedPreShipments` vs `fShippingCostTotal`

## System tagow automatycznych

Procedury dodaja tagi do `OrderProfitTag` gdy wykryja:
- Roznica estymacji vs rzeczywistych kosztow wysylki > 10%
- Anomalie w kosztach marketplace
- Inne problemy w kalkulacji

Format tagu:
```
Source: opi.UpdateOrderProfitTags
Description: sc.fShippingCostTotal - sc.ShippingCostTotal_EstimatedPreShipments / ... = 64.23% > 10%
```

## Pattern zmian profitu (revision)

Typowa kolejnosc:
1. Pierwsza kalkulacja - profit bazowy
2. Po wysylce - aktualizacja rzeczywistych kosztow wysylki
3. Po fakturze - finalne koszty marketplace
4. Po zwrotach - korekty koncowe

## Panel

Szczegoly zamowienia: `https://panel.fkwt.pl/Orders/OrderProfit/Details?OrderId=[ID]`
