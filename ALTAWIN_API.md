# altAwin FastScript API — правила и функции

## Параметры клиентских методов (SCRIPTMETHODS)

- Параметры объявляются во вкладке **"Параметры"** редактора метода (или в таблице `SCRIPTMETHODSPARAMS`)
- Типы параметра: `0` = Входной, `1` = Выходной, `2` = Входной/Выходной
- В скрипте переменные доступны **напрямую по имени** (не через Args):
  ```pascal
  // Входной параметр orderId — читаем напрямую
  ExecSQL('... WHERE ID = :id', MakeDictionary(['id', orderId]), '');

  // Выходной параметр data — присваиваем напрямую
  data := 'результат';
  ```
- `Args` = nil, если параметры не объявлены через UI/SCRIPTMETHODSPARAMS

---

## QueryRecordList

```pascal
QueryRecordList(SQL: string; Params: IcmDictionary; Connection: string = ''): IcmDictionaryList
```

- **Нельзя** передавать `nil` в Params — нужно `MakeDictionary([])`
- Пример без параметров:
  ```pascal
  records := QueryRecordList('SELECT * FROM ORDERS', MakeDictionary([]), '');
  ```
- Пример с параметрами:
  ```pascal
  records := QueryRecordList(
    'SELECT * FROM ORDERS WHERE ID = :id',
    MakeDictionary(['id', orderId]),
    ''
  );
  ```

---

## IcmDictionary

Создание: `CreateDictionary: IcmDictionary`

| Метод/свойство | Описание |
|---|---|
| `D['key']` | Чтение значения (index property Value) |
| `D.Add('key', value)` | Добавить/изменить значение |
| `D.Exists('key')` | Проверить наличие ключа |
| `D.Remove('key')` | Удалить ключ |
| `D.Clone` | Создать копию |
| `D.Count` | Количество ключей |
| `D.Name[i]` | Имя ключа по индексу |
| `D.Clear` | Очистить |

---

## IcmDictionaryList

Создание: `CreateDictionaryList: IcmDictionaryList`

| Метод/свойство | Описание |
|---|---|
| `L.Items[i]` | Получить IcmDictionary по индексу |
| `L.Count` | Количество элементов |
| `L.Add(item)` | Добавить IcmDictionary |
| `L.Delete(i)` | Удалить по индексу |
| `L.Clear` | Очистить |

---

## JSON-функции

```pascal
JSONEncode(var Value): string
```
Возвращает JSON-представление значения (IcmDictionary → объект, строка → строка).

```pascal
JSONDecode(Value: string)
```
Парсит JSON. Для получения словаря: `D := IcmDictionary(JSONDecode(s))`.

```pascal
TidyJSON(const Value: string): string
```
Форматирует JSON-строку (pretty print).

Пример — сборка JSON-массива из QueryRecordList:
```pascal
json := '[';
for i := 0 to records.Count - 1 do
begin
  srcRec := records.Items[i];
  outRec := CreateDictionary;
  outRec.Add('id',    srcRec['ID']);
  outRec.Add('name',  srcRec['NAME']);
  if i > 0 then json := json + ',';
  json := json + JSONEncode(outRec);
end;
json := json + ']';
data := json;
```

---

## MakeDictionary

```pascal
MakeDictionary(arr: array): IcmDictionary
```
Создаёт словарь из плоского массива пар ключ-значение:
```pascal
MakeDictionary(['key1', val1, 'key2', val2])
MakeDictionary([])  // пустой словарь
```

---

## ExecSQL / QueryValue

```pascal
ExecSQL(SQL: string; Params: IcmDictionary; Connection: string)
QueryValue(SQL: string; Params: IcmDictionary; Connection: string): Variant
```

Пример:
```pascal
// Проверка существования
existingId := QueryValue(
  'SELECT ID FROM TABLE WHERE ID = :id',
  MakeDictionary(['id', someId]),
  ''
);
if not VarIsNull(existingId) then ...

// INSERT/UPDATE/DELETE
ExecSQL(
  'UPDATE TABLE SET VAL = :val WHERE ID = :id',
  MakeDictionary(['val', batchNumber, 'id', orderId]),
  ''
);
```

---

## Строковые функции

```pascal
ReplaceStr(AText, AFromText, AToText: string): string
```
Замена всех вхождений (аналог StringReplace с rfReplaceAll).
`StringReplace` в FastScript принимает только 3 параметра (без флагов).

---

## Открытие документов

```pascal
Order := OpenDocument(IdocOrder, orderId);
if Order <> nil then
begin
  Order.ShowModal;  // модально (блокирует HTML)
  // или: Framework.GetService(IpubObjectsUIService).ShowDocument(Order);
end;
```

---

## Host.executeMethod (JS → Pascal)

```javascript
Host.executeMethod('methodName', { param1: val1, param2: val2 })
  .then(function(result) {
    // result.outParam — значение выходного параметра
  })
  .catch(function(err) { alert(err); });
```

- Имена параметров в JS объекте должны совпадать с NAME в SCRIPTMETHODSPARAMS
- Выходные параметры доступны в result по имени

---

## Таблицы настроек (mcp-firebird-vk)

| Таблица | Описание |
|---|---|
| `SCRIPTMETHODS` | Клиентские методы (SCRIPT, NAME, ISSERVER) |
| `SCRIPTMETHODSPARAMS` | Параметры методов (METHODID, NAME, DATATYPE, PARAMTYPE) |
| `HTML_VIEWS` | HTML-представления (SOURCEHTML BLOB) |
| `HTML_VIEWS_RESOURCES` | Ресурсы HTML (JS/CSS файлы) |
| `USERFIELDS` | Пользовательские поля документов |
| `LIBRARIES` | Библиотеки скриптов |
