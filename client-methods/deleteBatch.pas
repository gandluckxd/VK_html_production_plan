// Клиентский метод: deleteBatch
// Параметры:
//   batchType   (integer, Входной)  — 1=столярка, 2=малярка
//   batchNumber (string,  Входной)  — наименование партии
//   success     (string,  Выходной)
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
begin
  ufId := GetBatchUfId(batchType);

  // Снимаем партию со всех заказов в ORDERS_UF_VALUES
  ExecSQL(
    'UPDATE ORDERS_UF_VALUES SET VAR_STR = NULL WHERE USERFIELDID = :ufId AND VAR_STR = :bn',
    MakeDictionary(['ufId', ufId, 'bn', batchNumber]),
    ''
  );

  // Удаляем саму партию
  ExecSQL(
    'DELETE FROM VK_PROD_BATCHES WHERE BATCHTYPE = :bt AND BATCHNUMBER = :bn',
    MakeDictionary(['bt', batchType, 'bn', batchNumber]),
    ''
  );

  success := 'true';
end;
