// Клиентский метод: deleteBatch
// Параметры:
//   batchType   (integer, Входной)  — 1=столярка (UF 170), 2=малярка (UF 171)
//   batchNumber (string,  Входной)  — наименование партии
//   success     (string,  Выходной)

var
  ufId: Integer;
begin
  ufId := 170;
  if VarToStr(batchType) <> '1' then ufId := 171;

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
