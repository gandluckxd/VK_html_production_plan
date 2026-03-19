// Клиентский метод: assignOrderBatch
// Параметры:
//   orderId     (integer, Входной)  — ID заказа
//   batchNumber (string,  Входной)  — номер партии ("" = снять)
//   batchType   (integer, Входной)  — 1=столярка (UF 170), 2=малярка (UF 171)
//   success     (string,  Выходной)

var
  ufId: Integer;
begin
  ufId := 170;
  if VarToStr(batchType) <> '1' then ufId := 171;

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
