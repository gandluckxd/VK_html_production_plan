// Клиентский метод: reorderBatches
// Параметры:
//   batchType   (integer, Входной)  — 1=столярка, 2=малярка
//   batchesStr  (string,  Входной)  — legacy: имена партий через |
//   success     (string,  Выходной)
//
// Дополнительно поддерживается JSON через входной параметр batchesJson:
//   [{"batchNumber":"..."}, ...]
// Если JSON не передан/невалиден, используется legacy batchesStr.

function SetBatchOrder(token: string; so: Integer): Boolean;
begin
  Result := False;
  if token = '' then Exit;

  ExecSQL(
    'UPDATE VK_PROD_BATCHES SET SORTORDER = :so WHERE BATCHTYPE = :bt AND BATCHNUMBER = :bn',
    MakeDictionary(['so', so, 'bt', batchType, 'bn', token]),
    ''
  );
  Result := True;
end;

function ApplyOrderFromJson(jsonText: string): Boolean;
var
  items: IcmDictionaryList;
  item: IcmDictionary;
  i, sortOrder: Integer;
  token: string;
begin
  Result := False;
  if jsonText = '' then Exit;

  try
    items := IcmDictionaryList(JSONDecode(jsonText));
    sortOrder := 0;
    for i := 0 to items.Count - 1 do
    begin
      item := items.Items[i];
      token := '';
      if item.Exists('batchNumber') then
        token := VarToStr(item['batchNumber']);
      if SetBatchOrder(token, sortOrder) then
        sortOrder := sortOrder + 1;
    end;
    Result := True;
  except
    Result := False;
  end;
end;

var
  remaining, token, jsonPayload: string;
  sepPos, sortOrder: Integer;
begin
  jsonPayload := VarToStr(batchesJson);

  if ApplyOrderFromJson(jsonPayload) then
  begin
    success := 'true';
    Exit;
  end;

  // Legacy режим: строка через "|"
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
      if SetBatchOrder(token, sortOrder) then
        sortOrder := sortOrder + 1;
    end;
  end;
  success := 'true';
end;
