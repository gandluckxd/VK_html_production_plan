// Клиентский метод: addBatch
// Параметры:
//   batchType   (integer, Входной)  — 1=столярка, 2=малярка
//   batchNumber (string,  Входной)  — наименование партии
//   dateStart   (string,  Входной)  — дата начала (YYYY-MM-DD или "")
//   dateEnd     (string,  Входной)  — дата окончания (YYYY-MM-DD или "")
//   success     (string,  Выходной)
//
// Примечание: даты встраиваются в SQL как литералы (не параметры),
// т.к. FastScript не умеет передавать строку в DATE-параметр.
// Безопасно — HTML <input type="date"> всегда даёт YYYY-MM-DD или "".

var
  newId: Variant;
  cnt: Variant;
  dsStr, deStr, sqlDS, sqlDE: string;
begin
  cnt := QueryValue(
    'SELECT COUNT(*) FROM VK_PROD_BATCHES WHERE BATCHTYPE = :bt',
    MakeDictionary(['bt', batchType]),
    ''
  );

  newId := QueryValue(
    'SELECT GEN_ID(GEN_VK_PROD_BATCHES_ID, 1) FROM RDB$DATABASE',
    MakeDictionary([]),
    ''
  );

  dsStr := VarToStr(dateStart);
  deStr := VarToStr(dateEnd);

  if dsStr <> '' then sqlDS := '''' + dsStr + '''' else sqlDS := 'NULL';
  if deStr <> '' then sqlDE := '''' + deStr + '''' else sqlDE := 'NULL';

  ExecSQL(
    'INSERT INTO VK_PROD_BATCHES (ID, BATCHNUMBER, BATCHTYPE, SORTORDER, DATE_START, DATE_END) ' +
    'VALUES (:id, :bn, :bt, :so, ' + sqlDS + ', ' + sqlDE + ')',
    MakeDictionary(['id', newId, 'bn', batchNumber, 'bt', batchType, 'so', cnt]),
    ''
  );

  success := 'true';
end;
