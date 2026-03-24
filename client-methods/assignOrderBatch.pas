// Клиентский метод: assignOrderBatch
// Параметры:
//   orderId     (integer, Входной)  — ID заказа
//   batchNumber (string,  Входной)  — номер партии ("" = снять)
//   batchType   (integer, Входной)  — 1=столярка, 2=малярка
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
  ufId := GetBatchUfId(StrToInt(batchType));

  // Всегда удаляем старое значение, потом вставляем новое если нужно
  ExecSQL(
    'DELETE FROM ORDERS_UF_VALUES WHERE ORDERID = :oid AND USERFIELDID = :ufId',
    MakeDictionary(['oid', orderId, 'ufId', ufId]),
    ''
  );

  if VarToStr(batchNumber) <> '' then
    ExecSQL(
      'INSERT INTO ORDERS_UF_VALUES (ID, ORDERID, USERFIELDID, VAR_STR) ' +
      'VALUES (GEN_ID(GEN_ORDERS_UF_VALUES, 1), :oid, :ufId, :val)',
      MakeDictionary(['oid', orderId, 'ufId', ufId, 'val', batchNumber]),
      ''
    );

  success := 'true';
end;
