# Производственный план (Production Plan) — План реализации

> Статус: исторический план первой версии. Актуальная инструкция по развёртыванию и актуальный список методов находятся в `docs/setup-instructions.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HTML-представление для altAwin, позволяющее группировать заказы (Orders) в производственные партии (сменные задания) через drag-and-drop интерфейс.

**Architecture:** JS ↔ altAwin мост через `Host.executeMethod(name, params) → Promise`. Клиентские методы (SCRIPTMETHODS) на Pascal/Delphi выполняют запросы к Firebird и возвращают JSON. Номер партии хранится в UserField `batch_number` документа IdocOrder (тип VAR_STR). Всё в одном HTML-файле (embedded CSS + JS), без внешних зависимостей.

**Tech Stack:** HTML5/CSS3/Vanilla JS (CEF), Pascal (FastScript) для клиентских методов, Firebird SQL

---

## Контекст БД

### Ключевые таблицы и поля

| Таблица | PK | Назначение |
|---|---|---|
| `ORDERS` | `ID` | Заказы. `ORDERNO`, `DATEORDER`, `AGREEMENTNO` (номер договора), `ORDERSTATUS`, `ORDERSTATEID`, `CUSTOMERID`, `TOTALPRICE`, `RCOMMENT`, `PRODDATE`, `FACTORYNUM` |
| `ORDERSTATES` | `ORDERSTATEID` | Состояния. `NAME`, `CODE`. Значения: 1=Создан, 4=В производство, 9-15=Участки, 17=Готово |
| `CONTRAGENTS` | `CONTRAGID` | Контрагенты. `NAME` — имя клиента. Связь: `ORDERS.CUSTOMERID = CONTRAGENTS.CONTRAGID` |
| `USERFIELDS` | `USERFIELDID` | Определения доп. полей. `DOCTYPE`='IdocOrder', `FIELDNAME`, `VARTYPE` |
| `ORDERS_UF_VALUES` | `ID` | Значения доп. полей. `ORDERID`, `USERFIELDID`, `VAR_STR`/`VAR_INT`/... |
| `SCRIPTMETHODS` | `ID` | Клиентские методы. `NAME` = идентификатор для `Host.executeMethod`, `SCRIPT` = Pascal код |
| `HTML_VIEWS` | `ID` | HTML-представления. `SOURCEHTML` = HTML код, `TITLE` |

### Существующие UserFields для IdocOrder
68 полей уже существуют (executor_region, price_dop, write_down_raskroi/vayma/schlif/grunt/mol/sbor/upak, и др.). Новое поле `batch_number` добавляется вручную.

### Формат цен
`TOTALPRICE` — NUMERIC(18,4) в Firebird. Значения в рублях (1329643 = 1 329 643 ₽).

### JS ↔ altAwin мост (подтверждено пользователем)
```javascript
Host.executeMethod('methodName', { param1: 'value1' })
  .then(function(result) { /* result — объект */ })
  .catch(function(err) { alert(err); });
```

---

## Структура файлов проекта

```
VK_html_production_plan/
├── client-methods/
│   ├── getProductionOrders.pas    — загрузка заказов с партиями
│   ├── assignOrderBatch.pas       — назначение партии заказу
│   └── openOrder.pas              — открытие документа заказа
├── html/
│   └── production-plan.html       — HTML-представление (всё в одном файле)
├── docs/
│   ├── setup-instructions.md      — инструкция по настройке в altAwin
│   └── superpowers/plans/
│       └── 2026-03-19-production-plan.md  — этот план
```

---

## Предварительные требования (ручная настройка в altAwin)

Перед началом разработки пользователь должен вручную:

1. **Создать UserField `batch_number`** для IdocOrder:
   - Настройки → Дополнительные поля → IdocOrder
   - Идентификатор поля: `batch_number`
   - Заголовок: `Номер партии`
   - Тип значения: `VAR_STR` (строка)
   - Видимость: `3` (grid + form)
   - **Запомнить USERFIELDID** — он нужен в скриптах клиентских методов

2. **Записать USERFIELDID** нового поля (узнать из altAwin или SQL):
   ```sql
   SELECT USERFIELDID FROM USERFIELDS
   WHERE DOCTYPE = 'IdocOrder' AND FIELDNAME = 'batch_number' AND DELETED = 0
   ```

---

## Task 1: Клиентский метод `getProductionOrders`

**Назначение:** Загружает последние 30 заказов с номерами договоров, включая состояние, клиента и текущий номер партии.

**Files:**
- Create: `client-methods/getProductionOrders.pas`

**Куда в altAwin:** Настройки → Клиентские методы → Новый метод
- Идентификатор (NAME): `getProductionOrders`
- Наименование (TITLE): `Загрузка заказов для производственного плана`
- Серверный: Нет

- [ ] **Step 1: Создать файл Pascal-скрипта**

```pascal
// client-methods/getProductionOrders.pas
// Клиентский метод: getProductionOrders
// Параметры (Args): нет обязательных
// Возвращает: Result['data'] = JSON-строка с массивом заказов
//
// ВАЖНО: Замените @BATCH_UF_ID на реальный USERFIELDID поля batch_number!

var
  Query: Variant;
  json, s: string;
  isFirst: Boolean;
begin
  json := '[';
  isFirst := True;

  Query := Session.CreateQuery(
    'SELECT FIRST 30 ' +
    '  o.ID, ' +
    '  o.ORDERNO, ' +
    '  CAST(o.DATEORDER AS DATE) as DATEORDER, ' +
    '  o.AGREEMENTNO, ' +
    '  o.ORDERSTATUS, ' +
    '  os.NAME as STATENAME, ' +
    '  ca.NAME as CUSTOMERNAME, ' +
    '  o.RCOMMENT, ' +
    '  o.TOTALPRICE, ' +
    '  CAST(o.PRODDATE AS DATE) as PRODDATE, ' +
    '  o.FACTORYNUM, ' +
    '  uf.VAR_STR as BATCH_NUMBER ' +
    'FROM ORDERS o ' +
    'LEFT JOIN ORDERSTATES os ON os.ORDERSTATEID = o.ORDERSTATEID ' +
    'LEFT JOIN CONTRAGENTS ca ON ca.CONTRAGID = o.CUSTOMERID ' +
    'LEFT JOIN ORDERS_UF_VALUES uf ON uf.ORDERID = o.ID AND uf.USERFIELDID = @BATCH_UF_ID ' +
    'WHERE o.DELETED = 0 ' +
    '  AND o.AGREEMENTNO IS NOT NULL ' +
    '  AND TRIM(o.AGREEMENTNO) <> '''' ' +
    'ORDER BY o.DATEORDER DESC'
  );
  Query.Open;

  while not Query.Eof do
  begin
    if not isFirst then
      json := json + ',';

    // Экранируем строки для JSON
    s := '{';
    s := s + '"id":' + IntToStr(Query.FieldByName('ID').AsInteger);
    s := s + ',"orderNo":"' + StringReplace(Query.FieldByName('ORDERNO').AsString, '"', '\"', [rfReplaceAll]) + '"';
    s := s + ',"dateOrder":"' + Query.FieldByName('DATEORDER').AsString + '"';
    s := s + ',"agreementNo":"' + StringReplace(Query.FieldByName('AGREEMENTNO').AsString, '"', '\"', [rfReplaceAll]) + '"';
    s := s + ',"orderStatus":' + IntToStr(Query.FieldByName('ORDERSTATUS').AsInteger);
    s := s + ',"stateName":"' + StringReplace(Query.FieldByName('STATENAME').AsString, '"', '\"', [rfReplaceAll]) + '"';
    s := s + ',"customerName":"' + StringReplace(Query.FieldByName('CUSTOMERNAME').AsString, '"', '\"', [rfReplaceAll]) + '"';
    s := s + ',"comment":"' + StringReplace(Query.FieldByName('RCOMMENT').AsString, '"', '\"', [rfReplaceAll]) + '"';
    s := s + ',"totalPrice":' + Query.FieldByName('TOTALPRICE').AsString;
    s := s + ',"prodDate":"' + Query.FieldByName('PRODDATE').AsString + '"';
    s := s + ',"factoryNum":"' + Query.FieldByName('FACTORYNUM').AsString + '"';
    s := s + ',"batchNumber":"' + Query.FieldByName('BATCH_NUMBER').AsString + '"';
    s := s + '}';

    json := json + s;
    isFirst := False;
    Query.Next;
  end;

  json := json + ']';
  Result['data'] := json;
end;
```

> **Примечание:** Если `Session.CreateQuery` не работает, попробуйте:
> - `Session.OpenSQL('SELECT ...')` — возвращает DataSet
> - `CreateSQLQuery('SELECT ...')` — альтернативный синтаксис
> - Проверьте в дереве объектов скриптов (F1 в редакторе скрипта)

- [ ] **Step 2: Сохранить файл**
- [ ] **Step 3: Перенести в altAwin и протестировать**

Тест из HTML (временный):
```javascript
Host.executeMethod('getProductionOrders', {})
  .then(function(r) {
    console.log('Orders:', r.data);
    alert('Загружено: ' + JSON.parse(r.data).length + ' заказов');
  })
  .catch(function(e) { alert('Ошибка: ' + e); });
```

---

## Task 2: Клиентский метод `assignOrderBatch`

**Назначение:** Назначает или снимает номер партии для заказа (пишет в UserField `batch_number`).

**Files:**
- Create: `client-methods/assignOrderBatch.pas`

**Куда в altAwin:** Настройки → Клиентские методы → Новый метод
- Идентификатор (NAME): `assignOrderBatch`
- Наименование (TITLE): `Назначение партии заказу`
- Серверный: Нет

- [ ] **Step 1: Создать файл Pascal-скрипта**

```pascal
// client-methods/assignOrderBatch.pas
// Клиентский метод: assignOrderBatch
// Параметры (Args):
//   orderId    : Integer — ID заказа
//   batchNumber: String  — номер партии ("" для снятия)
// Возвращает: Result['success'] = 'true'/'false'
//
// ВАЖНО: Замените @BATCH_UF_ID на реальный USERFIELDID поля batch_number!

var
  orderId: Integer;
  batchNumber: string;
  existsQuery: Variant;
  recordExists: Boolean;
begin
  orderId := Args['orderId'];
  batchNumber := Args['batchNumber'];

  // Проверяем, существует ли уже запись для этого заказа + userfield
  existsQuery := Session.CreateQuery(
    'SELECT ID FROM ORDERS_UF_VALUES ' +
    'WHERE ORDERID = ' + IntToStr(orderId) + ' ' +
    'AND USERFIELDID = @BATCH_UF_ID'
  );
  existsQuery.Open;
  recordExists := not existsQuery.Eof;

  if batchNumber = '' then
  begin
    // Снимаем партию — удаляем запись если есть
    if recordExists then
      Session.ExecSQL(
        'DELETE FROM ORDERS_UF_VALUES ' +
        'WHERE ORDERID = ' + IntToStr(orderId) + ' ' +
        'AND USERFIELDID = @BATCH_UF_ID'
      );
  end
  else
  begin
    if recordExists then
    begin
      // Обновляем существующую запись
      Session.ExecSQL(
        'UPDATE ORDERS_UF_VALUES SET VAR_STR = ''' + batchNumber + ''' ' +
        'WHERE ORDERID = ' + IntToStr(orderId) + ' ' +
        'AND USERFIELDID = @BATCH_UF_ID'
      );
    end
    else
    begin
      // Создаём новую запись
      Session.ExecSQL(
        'INSERT INTO ORDERS_UF_VALUES (ORDERID, USERFIELDID, VAR_STR) ' +
        'VALUES (' + IntToStr(orderId) + ', @BATCH_UF_ID, ''' + batchNumber + ''')'
      );
    end;
  end;

  Result['success'] := 'true';
end;
```

> **Альтернативный подход через API документов** (если прямой SQL не работает или нужны триггеры/события):
> ```pascal
> var
>   Order: IdocOrder;
> begin
>   Order := OpenDocument(IdocOrder, Args['orderId']);
>   if Order <> nil then
>   begin
>     Order.UserFields['batch_number'] := Args['batchNumber'];
>     Order.Save;
>     Result['success'] := 'true';
>   end
>   else
>     Result['success'] := 'false';
> end;
> ```

- [ ] **Step 2: Сохранить файл**
- [ ] **Step 3: Перенести в altAwin и протестировать**

Тест:
```javascript
Host.executeMethod('assignOrderBatch', { orderId: 5648, batchNumber: '1' })
  .then(function(r) { alert('Успех: ' + r.success); })
  .catch(function(e) { alert('Ошибка: ' + e); });
```

---

## Task 3: Клиентский метод `openOrder`

**Назначение:** Открывает документ заказа в altAwin по ID.

**Files:**
- Create: `client-methods/openOrder.pas`

**Куда в altAwin:** Настройки → Клиентские методы → Новый метод
- Идентификатор (NAME): `openOrder`
- Наименование (TITLE): `Открытие заказа`
- Серверный: Нет

- [ ] **Step 1: Создать файл Pascal-скрипта**

```pascal
// client-methods/openOrder.pas
// Клиентский метод: openOrder
// Параметры (Args):
//   orderId: Integer — ID заказа
// Возвращает: Result['success']

var
  Order: IdocOrder;
begin
  Order := OpenDocument(IdocOrder, Args['orderId']);
  if Order <> nil then
  begin
    Order.ShowModal;
    Result['success'] := 'true';
  end
  else
    Result['success'] := 'false';
end;
```

- [ ] **Step 2: Сохранить файл**
- [ ] **Step 3: Перенести в altAwin и протестировать**

Тест:
```javascript
Host.executeMethod('openOrder', { orderId: 5648 })
  .then(function(r) { alert('Открыт: ' + r.success); })
  .catch(function(e) { alert('Ошибка: ' + e); });
```

---

## Task 4: HTML-представление — полный UI

**Назначение:** Основной интерфейс — таблица заказов с группировкой по партиям и drag-and-drop.

**Files:**
- Create: `html/production-plan.html`

**Куда в altAwin:** HTML-представления → Новое → вкладка "Источник" → вставить весь HTML

### UI-структура

```
┌─────────────────────────────────────────────────────┐
│ Производственный план              [+ Добавить партию] │
├─────────────────────────────────────────────────────┤
│ ▼ Нераспределённые заказы (N)                       │
│ ┌───┬─────────┬──────────┬────────┬───────┬───────┐ │
│ │ # │ Заказ   │ Дата     │Клиент  │Статус │ Сумма │ │
│ ├───┼─────────┼──────────┼────────┼───────┼───────┤ │
│ │   │ draggable rows...                           │ │
│ └───┴─────────┴──────────┴────────┴───────┴───────┘ │
│                                                     │
│ ▼ Партия 1 (M заказов)                  [✕ Удалить]│
│ ┌───┬─────────┬──────────┬────────┬───────┬───────┐ │
│ │   │ draggable rows...                           │ │
│ └───┴─────────┴──────────┴────────┴───────┴───────┘ │
│                                                     │
│ ▼ Партия 2 (K заказов)                  [✕ Удалить]│
│ ...                                                 │
└─────────────────────────────────────────────────────┘
```

### Функционал

1. **Автозагрузка** — при открытии вызывает `getProductionOrders`, группирует по `batchNumber`
2. **Добавить партию** — создаёт новую секцию с инкрементальным номером
3. **Drag-and-drop** — перетаскивание строк заказов между секциями (HTML5 DnD API)
4. **Сохранение** — при drop вызывает `assignOrderBatch` для обновления UserField
5. **Двойной клик** — открывает заказ в altAwin через `openOrder`
6. **Удалить партию** — перемещает все заказы обратно в "Нераспределённые"

- [ ] **Step 1: Создать HTML файл**

Полный код — `html/production-plan.html` (см. Task 4 Step 1 ниже)

- [ ] **Step 2: Перенести в altAwin**

1. Открыть Настройки → HTML-представления
2. Создать новое представление
3. Название: "Производственный план"
4. Раздел: "Производство"
5. Вкладка "Источник" → вставить содержимое `html/production-plan.html`
6. Сохранить

- [ ] **Step 3: Тестировать в altAwin**

Проверить:
- Заказы загружаются при открытии
- Кнопка "Добавить партию" создаёт новую секцию
- Перетаскивание строк работает между секциями
- При перетаскивании batch_number обновляется (проверить в карточке заказа)
- Двойной клик открывает заказ

---

## Task 5: Инструкция по настройке

**Files:**
- Create: `docs/setup-instructions.md`

- [ ] **Step 1: Создать инструкцию**

Содержит пошаговую инструкцию для настройки всех компонентов в altAwin.

---

## Порядок развёртывания

1. Создать UserField `batch_number` (вручную в altAwin)
2. Узнать и записать USERFIELDID нового поля
3. Подставить USERFIELDID вместо `@BATCH_UF_ID` во всех .pas файлах
4. Создать клиентский метод `getProductionOrders` (Task 1)
5. Создать клиентский метод `assignOrderBatch` (Task 2)
6. Создать клиентский метод `openOrder` (Task 3)
7. Протестировать каждый метод простым HTML с кнопкой
8. Создать HTML-представление (Task 4)
9. Комплексное тестирование

## Риски и допущения

1. **API скриптов:** Точный синтаксис работы с БД из Pascal-скриптов (`Session.CreateQuery`, `Session.OpenSQL`, `Session.ExecSQL`) может отличаться. Проверить в дереве объектов скриптов altAwin.
2. **Возврат данных:** Предполагается, что `Result['data'] := jsonString` корректно передаётся в JS через `Host.executeMethod`. Если нет — попробовать `Result.Add('data', jsonString)`.
3. **TOTALPRICE:** Значения в рублях напрямую (1329643 = 1 329 643 ₽). Если отображение некорректно — возможно нужно делить на 10000.
4. **Права доступа:** Клиентские методы с прямым SQL (`Session.ExecSQL`) требуют соответствующих прав пользователя в altAwin.
5. **ID поля batch_number:** `@BATCH_UF_ID` — placeholder, заменяется на реальный USERFIELDID после создания поля.

## Будущие доработки (вне текущего scope)

- Дополнительные UserFields (дата партии, ответственный, приоритет)
- Фильтрация заказов по датам, статусам
- Печать/экспорт сменного задания
- Подсчёт итогов по партии (сумма, количество изделий)
- Сохранение состояния партий между сессиями
- Цветовая индикация статусов заказов
