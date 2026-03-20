// Клиентский метод: reorderBatches
// Параметры:
//   batchType   (integer, Входной)  — 1=столярка, 2=малярка
//   batchesStr  (string,  Входной)  — имена партий через | в новом порядке
//   success     (string,  Выходной)

var
  remaining, token: string;
  sepPos, sortOrder: Integer;
begin
  remaining := VarToStr(batchesStr);
  sortOrder := 0;
  while remaining <> '' do
  begin
    sepPos := Pos('|', remaining);
    if sepPos > 0 then
    begin
      token := Copy(remaining, 1, sepPos - 1);
      remaining := Copy(remaining, sepPos + 1, Length(remaining));
    end else
    begin
      token := remaining;
      remaining := '';
    end;
    if token <> '' then
    begin
      ExecSQL(
        'UPDATE VK_PROD_BATCHES SET SORTORDER = :so WHERE BATCHTYPE = :bt AND BATCHNUMBER = :bn',
        MakeDictionary(['so', sortOrder, 'bt', batchType, 'bn', token]),
        ''
      );
      sortOrder := sortOrder + 1;
    end;
  end;
  success := 'true';
end;
