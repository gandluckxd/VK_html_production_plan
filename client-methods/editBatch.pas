// Клиентский метод: editBatch
// Параметры:
//   batchType      (integer, Входной)  — 1=столярка, 2=малярка
//   oldBatchNumber (string,  Входной)  — текущее наименование
//   newBatchNumber (string,  Входной)  — новое наименование
//   dateStart      (string,  Входной)  — дата начала (YYYY-MM-DD или "")
//   dateEnd        (string,  Входной)  — дата окончания (YYYY-MM-DD или "")
//   success        (string,  Выходной)
//
// Настройка UF ID берётся из VK_PROD_SETTINGS (ID=1, поля CARP_UF_ID/PAINT_UF_ID).
// Если таблица не создана, используется fallback: 170/171.

function GetBatchUfId(bt: Integer): Integer;
var
  cfgVal: Variant;
begin
  Result := 170;
  if bt <> 1 then Result := 171;

  try
    if bt = 1 then
      cfgVal := QueryValue(
        'SELECT CARP_UF_ID FROM VK_PROD_SETTINGS WHERE ID = 1',
        MakeDictionary([]),
        ''
      )
    else
      cfgVal := QueryValue(
        'SELECT PAINT_UF_ID FROM VK_PROD_SETTINGS WHERE ID = 1',
        MakeDictionary([]),
        ''
      );

    if (not VarIsNull(cfgVal)) and (VarToStr(cfgVal) <> '') then
      Result := cfgVal;
  except
    // fallback уже задан выше
  end;
end;

var
  ufId: Integer;
  dsStr, deStr, sqlDS, sqlDE: string;
begin
  ufId := GetBatchUfId(StrToInt(batchType));

  // Если имя изменилось — переписываем во всех заказах ORDERS_UF_VALUES
  if VarToStr(oldBatchNumber) <> VarToStr(newBatchNumber) then
    ExecSQL(
      'UPDATE ORDERS_UF_VALUES SET VAR_STR = :newBn WHERE USERFIELDID = :ufId AND VAR_STR = :oldBn',
      MakeDictionary(['newBn', newBatchNumber, 'ufId', ufId, 'oldBn', oldBatchNumber]),
      ''
    );

  dsStr := VarToStr(dateStart);
  deStr := VarToStr(dateEnd);
  if dsStr <> '' then sqlDS := '''' + dsStr + '''' else sqlDS := 'NULL';
  if deStr <> '' then sqlDE := '''' + deStr + '''' else sqlDE := 'NULL';

  // Обновляем запись партии
  ExecSQL(
    'UPDATE VK_PROD_BATCHES SET BATCHNUMBER = :newBn, DATE_START = ' + sqlDS + ', DATE_END = ' + sqlDE + ' WHERE BATCHTYPE = :bt AND BATCHNUMBER = :oldBn',
    MakeDictionary(['newBn', newBatchNumber, 'bt', batchType, 'oldBn', oldBatchNumber]),
    ''
  );

  success := 'true';
end;
