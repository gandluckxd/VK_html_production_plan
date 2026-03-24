# Инструкция по настройке в altAwin

Документ синхронизирован с текущей реализацией из `client-methods/*.pas` и `html/production-plan.html`.

## 1. Подготовить UserFields для партий

Текущий код работает с **двумя** строковыми UserField у `IdocOrder`:
- столярка (режим `batchType=1`)
- малярка (режим `batchType=2`)

Пример SQL для проверки:
```sql
SELECT USERFIELDID, FIELDNAME, FIELDCAPTION, VARTYPE
FROM USERFIELDS
WHERE DOCTYPE = 'IdocOrder' AND DELETED = 0
ORDER BY USERFIELDID
```

## 2. Создать объекты БД для партий

Выполните SQL-скрипт:
- `docs/sql/production-plan-schema.sql`

Скрипт создаёт:
- таблицу `VK_PROD_BATCHES`
- генератор `GEN_VK_PROD_BATCHES_ID`
- индекс `IDX_VK_PROD_BATCHES_TYPE_SORT`
- таблицу `VK_PROD_SETTINGS` с централизованной настройкой UF ID

После выполнения скрипта проверьте/обновите UF ID в настройках:
```sql
UPDATE VK_PROD_SETTINGS
SET CARP_UF_ID = 170, PAINT_UF_ID = 171
WHERE ID = 1
```

Подставьте ваши реальные ID вместо `170/171`, если они отличаются.

## 3. Создать клиентские методы

Для каждого файла в `client-methods/` создайте метод в altAwin:
- Настройки → Клиентские методы → Создать новый
- Серверный: `Нет`
- Скрипт: содержимое соответствующего `.pas`

### Список методов и параметров

1. `getProductionOrders`
   - `data` (string, выходной)
2. `getBatches`
   - `batchType` (integer, входной)
   - `data` (string, выходной)
3. `addBatch`
   - `batchType` (integer, входной)
   - `batchNumber` (string, входной)
   - `dateStart` (string, входной)
   - `dateEnd` (string, входной)
   - `success` (string, выходной)
4. `editBatch`
   - `batchType` (integer, входной)
   - `oldBatchNumber` (string, входной)
   - `newBatchNumber` (string, входной)
   - `dateStart` (string, входной)
   - `dateEnd` (string, входной)
   - `success` (string, выходной)
5. `deleteBatch`
   - `batchType` (integer, входной)
   - `batchNumber` (string, входной)
   - `success` (string, выходной)
6. `reorderBatches`
   - `batchType` (integer, входной)
   - `batchesStr` (string, входной, legacy-формат через `|`)
   - `batchesJson` (string, входной, JSON-массив `[{batchNumber}]`)
   - `success` (string, выходной)
7. `assignOrderBatch`
   - `orderId` (integer, входной)
   - `batchNumber` (string, входной)
   - `batchType` (integer, входной)
   - `success` (string, выходной)
8. `openOrder`
   - `orderId` (integer, входной)

## 4. Создать HTML-представление

1. Настройки → HTML-представления → Создать новое
2. Название: `Производственный план`
3. Раздел: `Производство`
4. Вкладка "Источник" → вставьте содержимое `html/production-plan.html`
5. Сохраните

## 5. Быстрый smoke-test

1. Откройте представление, убедитесь что загрузились заказы и партии.
2. Переключите режим `Столярка/Малярка`, проверьте, что партии различаются по режиму.
3. Создайте новую партию и задайте даты.
4. Перетащите заказ в партию и обратно.
5. Измените название партии и убедитесь, что у заказов обновился номер партии.
6. Перетащите партию для изменения порядка.
7. Удалите партию и убедитесь, что её заказы стали нераспределёнными.
8. Откройте заказ кликом по номеру.

## 6. Типовые проблемы

| Проблема | Что проверить |
|---|---|
| `Method getBatches not found` | Создан ли метод `getBatches` из `client-methods/getBatches.pas` |
| Ошибка `Table unknown VK_PROD_BATCHES` | Выполнен ли `docs/sql/production-plan-schema.sql` |
| Ошибка `Table unknown VK_PROD_SETTINGS` | Выполнен ли `docs/sql/production-plan-schema.sql` полностью |
| Заказ не переносится в нужном режиме | Корректны ли `CARP_UF_ID/PAINT_UF_ID` в `VK_PROD_SETTINGS` |
| Пустой список заказов | Есть ли данные в `ORDERS` с `AGREEMENTNO` и `DELETED = 0` |
| `Host is not defined` | Представление открыто вне altAwin |
