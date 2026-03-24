// Клиентский метод: getBatches
// Параметры:
//   batchType (integer, Входной)  — 1=столярка, 2=малярка
//   data      (string,  Выходной) — JSON-массив партий
//
// Возвращает список партий текущего режима в формате:
//   [{ id, batchNumber, sortOrder, dateStart, dateEnd }, ...]

var
  records: IcmDictionaryList;
  srcRec, outRec: IcmDictionary;
  i: Integer;
  json: string;
begin
  records := QueryRecordList(
    'SELECT ID, BATCHNUMBER, SORTORDER, CAST(DATE_START AS DATE) AS DATE_START, CAST(DATE_END AS DATE) AS DATE_END ' +
    'FROM VK_PROD_BATCHES ' +
    'WHERE BATCHTYPE = :bt ' +
    'ORDER BY SORTORDER, ID',
    MakeDictionary(['bt', batchType]),
    ''
  );

  json := '[';
  for i := 0 to records.Count - 1 do
  begin
    srcRec := records.Items[i];

    outRec := CreateDictionary;
    outRec.Add('id',          srcRec['ID']);
    outRec.Add('batchNumber', VarToStr(srcRec['BATCHNUMBER']));
    outRec.Add('sortOrder',   srcRec['SORTORDER']);
    outRec.Add('dateStart',   VarToStr(srcRec['DATE_START']));
    outRec.Add('dateEnd',     VarToStr(srcRec['DATE_END']));

    if i > 0 then json := json + ',';
    json := json + JSONEncode(outRec);
  end;
  json := json + ']';

  data := json;
end;
