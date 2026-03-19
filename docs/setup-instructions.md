# Инструкция по настройке в altAwin

## 1. Создать UserField `batch_number`

1. Откройте altAwin → Настройки → Пользовательские поля (UserFields)
2. Найдите раздел для документа **IdocOrder**
3. Создайте новое поле:
   - **Идентификатор поля (FIELDNAME):** `batch_number`
   - **Заголовок (FIELDCAPTION):** `Номер партии`
   - **Тип значения (VARTYPE):** `VAR_STR` (строка)
   - **Видимость (VISIBILITY):** `3` (grid + form)
   - **Значение обязательно:** Нет
4. Сохраните

## 2. Узнать USERFIELDID

Выполните SQL-запрос:
```sql
SELECT USERFIELDID FROM USERFIELDS
WHERE DOCTYPE = 'IdocOrder' AND FIELDNAME = 'batch_number' AND DELETED = 0
```

Запомните число (например, `170`). Оно нужно на шаге 3.

## 3. Подставить USERFIELDID в скрипты

Во всех файлах `.pas` в папке `client-methods/` замените `@BATCH_UF_ID` на реальное число.

Например, если USERFIELDID = 170:

- `AND uf.USERFIELDID = @BATCH_UF_ID` → `AND uf.USERFIELDID = 170`
- `AND USERFIELDID = @BATCH_UF_ID` → `AND USERFIELDID = 170`
- `VALUES (..., @BATCH_UF_ID, ...)` → `VALUES (..., 170, ...)`

## 4. Создать клиентские методы

Для каждого файла в `client-methods/`:

### 4.1. getProductionOrders
1. Настройки → Клиентские методы → Создать новый
2. **Идентификатор (NAME):** `getProductionOrders`
3. **Наименование (TITLE):** `Загрузка заказов для производственного плана`
4. **Серверный:** Нет
5. Вставьте содержимое `client-methods/getProductionOrders.pas` в поле скрипта
6. Сохраните

### 4.2. assignOrderBatch
1. Создать новый клиентский метод
2. **Идентификатор (NAME):** `assignOrderBatch`
3. **Наименование (TITLE):** `Назначение партии заказу`
4. **Серверный:** Нет
5. Вставьте содержимое `client-methods/assignOrderBatch.pas`
6. Сохраните

### 4.3. openOrder
1. Создать новый клиентский метод
2. **Идентификатор (NAME):** `openOrder`
3. **Наименование (TITLE):** `Открытие заказа`
4. **Серверный:** Нет
5. Вставьте содержимое `client-methods/openOrder.pas`
6. Сохраните

## 5. Тестирование методов (по отдельности)

Создайте временное HTML-представление для тестов:

```html
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<h3>Тест клиентских методов</h3>
<button onclick="testGet()">Тест getProductionOrders</button>
<button onclick="testAssign()">Тест assignOrderBatch</button>
<button onclick="testOpen()">Тест openOrder</button>
<pre id="log" style="background:#f0f0f0;padding:10px;margin-top:10px;white-space:pre-wrap;font-size:12px;max-height:400px;overflow:auto"></pre>
<script>
function log(s) { document.getElementById('log').textContent += s + '\n'; }

function testGet() {
  log('--- getProductionOrders ---');
  Host.executeMethod('getProductionOrders', {})
    .then(function(r) {
      var data = JSON.parse(r.data);
      log('Загружено ' + data.length + ' заказов');
      data.forEach(function(o) { log('  ' + o.orderNo + ' | ' + o.batchNumber); });
    })
    .catch(function(e) { log('ОШИБКА: ' + e); });
}

function testAssign() {
  // Замените 5648 на реальный ID заказа из вашей БД
  log('--- assignOrderBatch (orderId=5648, batch=1) ---');
  Host.executeMethod('assignOrderBatch', { orderId: 5648, batchNumber: '1' })
    .then(function(r) { log('Результат: ' + JSON.stringify(r)); })
    .catch(function(e) { log('ОШИБКА: ' + e); });
}

function testOpen() {
  log('--- openOrder (orderId=5648) ---');
  Host.executeMethod('openOrder', { orderId: 5648 })
    .then(function(r) { log('Результат: ' + JSON.stringify(r)); })
    .catch(function(e) { log('ОШИБКА: ' + e); });
}
</script>
</body>
</html>
```

## 6. Создать основное HTML-представление

1. Настройки → HTML-представления → Создать новое
2. **Название:** `Производственный план`
3. **Раздел:** `Производство`
4. Вкладка **"Источник"** → вставьте содержимое `html/production-plan.html`
5. Сохраните

## 7. Проверки

- [ ] При открытии представления загружаются заказы с номерами договоров
- [ ] Отображаются нераспределённые заказы
- [ ] Кнопка "Добавить партию" создаёт новую секцию
- [ ] Перетаскивание заказа в партию работает
- [ ] После перетаскивания в карточке заказа видно поле "Номер партии" с правильным значением
- [ ] Двойной клик (клик по ссылке заказа) открывает документ в altAwin
- [ ] Удаление партии перемещает заказы в "Нераспределённые"
- [ ] Кнопка "Обновить" перезагружает данные

## Устранение неполадок

| Проблема | Решение |
|---|---|
| `Host is not defined` | Представление открыто не в altAwin |
| Заказы не загружаются | Проверьте скрипт `getProductionOrders` — может отличаться API (`Session.CreateQuery` vs `Session.OpenSQL`) |
| `undefined` вместо данных | Проверьте `Result['data']` — если не работает, попробуйте `Result.Add('data', json)` |
| Пустой список | Проверьте что есть заказы с заполненным полем AGREEMENTNO |
| Ошибка при перетаскивании | Проверьте скрипт `assignOrderBatch` и правильность `@BATCH_UF_ID` |
| TOTALPRICE отображается неверно | Возможно нужно делить на 10000 — исправьте в `formatPrice()` |
