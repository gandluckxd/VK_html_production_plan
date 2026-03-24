// Клиентский метод: getProductionOrders
// Параметры: data (string, Выходной)
//
// Возвращает список заказов для производственного плана с полями:
//   id, orderNo, dateOrder, agreementNo, orderStatus, stateName,
//   customerName, comment, totalPrice, prodDate, factoryNum,
//   carpBatch, paintBatch,
//   manager (фамилия владельца документа),
//   qtyIzd (шт, UF 48), areaIzd (кв.м, UF 49), lengthPogon (погонаж, UF 122),
//   woodTypes (породы дерева из PACKINFO через GetConstructionInfo),
//   colors (цвета из ORDERS_UNITS.INCOLORID/OUTCOLORID)
//
// Настройка UF ID для carpBatch/paintBatch берётся из VK_PROD_SETTINGS
// (ID=1, поля CARP_UF_ID/PAINT_UF_ID). Если таблица не создана — fallback 170/171.

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

// Получение породы дерева из PACKINFO
function GetWoodBreed(packInfo: Variant): string;
var
  constr: IcsConstruction;
  prod: IcsProduct;
  iP, iParam: Integer;
  nParam: string;
begin
  Result := '';
  try
    constr := GetConstructionInfo(packInfo);
    for iP := 0 to constr.Products.Count - 1 do
    begin
      prod := constr.Products[iP];
      for iParam := 0 to prod.UserParams.Count - 1 do
      begin
        nParam := VarToStr(prod.UserParams[iParam].Name);
        if nParam = 'Порода_дерева' then
        begin
          Result := VarToStr(prod.UserParams[iParam].Value);
          Exit;
        end;
      end;
    end;
  except
  end;
end;

function AppendCsv(existing, item: string): string;
begin
  if item = '' then
    Result := existing
  else if existing = '' then
    Result := item
  else
    Result := existing + ', ' + item;
end;

var
  records, unitRecs: IcmDictionaryList;
  srcRec, unitRec, outRec: IcmDictionary;
  woodByOrder, colorByOrder: IcmDictionary;
  seenWood, seenColor: IcmDictionary;
  i: Integer;
  json: string;
  orderIdsCsv, orderKey: string;
  woodVal, colorIn, colorOut, listVal, markKey: string;
  carpUfId, paintUfId: Integer;
begin
  carpUfId := GetBatchUfId(1);
  paintUfId := GetBatchUfId(2);

  // Основной запрос: заказы + менеджер + UF-поля
  records := QueryRecordList(
    'SELECT FIRST 500 ' +
    '  o.ID, o.ORDERNO, CAST(o.DATEORDER AS DATE) as DATEORDER, ' +
    '  o.AGREEMENTNO, o.ORDERSTATUS, o.ORDERSTATEID, ' +
    '  COALESCE(os.NAME, '''') as STATENAME, ' +
    '  COALESCE(os.RECINDEX, -1) as STATE_RECINDEX, ' +
    '  o.CUSTOMERID, ' +
    '  COALESCE(ca.NAME, '''') as CUSTOMERNAME, ' +
    '  COALESCE(o.RCOMMENT, '''') as RCOMMENT, ' +
    '  COALESCE(o.TOTALPRICE, 0) as TOTALPRICE, ' +
    '  o.PRODDATE, ' +
    '  COALESCE(o.FACTORYNUM, 0) as FACTORYNUM, ' +
    '  COALESCE(uf_carp.VAR_STR, '''') as CARP_BATCH, ' +
    '  COALESCE(uf_paint.VAR_STR, '''') as PAINT_BATCH, ' +
    '  COALESCE(p.PERSONLASTNAME, '''') as MANAGER, ' +
    '  COALESCE(uf_qty.VAR_FLT, 0) as QTY_IZD, ' +
    '  COALESCE(uf_area.VAR_FLT, 0) as AREA_IZD, ' +
    '  COALESCE(uf_pogon.VAR_FLT, 0) as LENGTH_POGON ' +
    'FROM ORDERS o ' +
    'LEFT JOIN ORDERSTATES os ON os.ORDERSTATEID = o.ORDERSTATEID ' +
    'LEFT JOIN CONTRAGENTS ca ON ca.CONTRAGID = o.CUSTOMERID ' +
    'LEFT JOIN EMPLOYEE e ON e.EMPID = o.OWNERID ' +
    'LEFT JOIN PERSONS p ON p.PERSONID = e.PERSONID ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_carp  ON uf_carp.ORDERID  = o.ID AND uf_carp.USERFIELDID  = ' + IntToStr(carpUfId) + ' ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_paint ON uf_paint.ORDERID = o.ID AND uf_paint.USERFIELDID = ' + IntToStr(paintUfId) + ' ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_qty   ON uf_qty.ORDERID   = o.ID AND uf_qty.USERFIELDID   = 48 ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_area  ON uf_area.ORDERID  = o.ID AND uf_area.USERFIELDID  = 49 ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_pogon ON uf_pogon.ORDERID = o.ID AND uf_pogon.USERFIELDID = 122 ' +
    'WHERE o.DELETED = 0 AND o.AGREEMENTNO IS NOT NULL AND TRIM(o.AGREEMENTNO) <> '''' ' +
    'ORDER BY o.DATEORDER DESC',
    MakeDictionary([]),
    ''
  );

  // Подготовка агрегатов по изделиям заказа (без N+1 запросов)
  woodByOrder := CreateDictionary;
  colorByOrder := CreateDictionary;
  seenWood := CreateDictionary;
  seenColor := CreateDictionary;

  orderIdsCsv := '';
  for i := 0 to records.Count - 1 do
  begin
    if i > 0 then orderIdsCsv := orderIdsCsv + ',';
    orderIdsCsv := orderIdsCsv + VarToStr(records.Items[i]['ID']);
  end;

  if orderIdsCsv <> '' then
  begin
    unitRecs := QueryRecordList(
      'SELECT ou.ORDERID, ou.PACKINFO, ' +
      '  COALESCE(cin.TITLE, '''') as IN_COLOR, ' +
      '  COALESCE(cout.TITLE, '''') as OUT_COLOR ' +
      'FROM ORDERS_UNITS ou ' +
      'LEFT JOIN COLORS cin  ON cin.COLORID  = ou.INCOLORID ' +
      'LEFT JOIN COLORS cout ON cout.COLORID = ou.OUTCOLORID ' +
      'WHERE ou.ORDERID IN (' + orderIdsCsv + ') AND ou.ISPART = 0',
      MakeDictionary([]),
      ''
    );

    for i := 0 to unitRecs.Count - 1 do
    begin
      unitRec := unitRecs.Items[i];
      orderKey := VarToStr(unitRec['ORDERID']);

      woodVal := GetWoodBreed(unitRec['PACKINFO']);
      if woodVal <> '' then
      begin
        markKey := orderKey + '|' + woodVal;
        if not seenWood.Exists(markKey) then
        begin
          seenWood.Add(markKey, 1);
          if woodByOrder.Exists(orderKey) then
            listVal := VarToStr(woodByOrder[orderKey])
          else
            listVal := '';
          listVal := AppendCsv(listVal, woodVal);
          woodByOrder.Add(orderKey, listVal);
        end;
      end;

      colorIn := VarToStr(unitRec['IN_COLOR']);
      if colorIn <> '' then
      begin
        markKey := orderKey + '|' + colorIn;
        if not seenColor.Exists(markKey) then
        begin
          seenColor.Add(markKey, 1);
          if colorByOrder.Exists(orderKey) then
            listVal := VarToStr(colorByOrder[orderKey])
          else
            listVal := '';
          listVal := AppendCsv(listVal, colorIn);
          colorByOrder.Add(orderKey, listVal);
        end;
      end;

      colorOut := VarToStr(unitRec['OUT_COLOR']);
      if colorOut <> '' then
      begin
        markKey := orderKey + '|' + colorOut;
        if not seenColor.Exists(markKey) then
        begin
          seenColor.Add(markKey, 1);
          if colorByOrder.Exists(orderKey) then
            listVal := VarToStr(colorByOrder[orderKey])
          else
            listVal := '';
          listVal := AppendCsv(listVal, colorOut);
          colorByOrder.Add(orderKey, listVal);
        end;
      end;
    end;
  end;

  json := '[';
  for i := 0 to records.Count - 1 do
  begin
    srcRec := records.Items[i];
    orderKey := VarToStr(srcRec['ID']);

    outRec := CreateDictionary;
    outRec.Add('id',           srcRec['ID']);
    outRec.Add('orderNo',      srcRec['ORDERNO']);
    outRec.Add('dateOrder',    VarToStr(srcRec['DATEORDER']));
    outRec.Add('agreementNo',  VarToStr(srcRec['AGREEMENTNO']));
    outRec.Add('orderStatus',  srcRec['ORDERSTATUS']);
    outRec.Add('orderStateId', srcRec['ORDERSTATEID']);
    outRec.Add('stateRecIdx',  srcRec['STATE_RECINDEX']);
    outRec.Add('stateName',    srcRec['STATENAME']);
    outRec.Add('customerId',   srcRec['CUSTOMERID']);
    outRec.Add('customerName', srcRec['CUSTOMERNAME']);
    outRec.Add('comment',      srcRec['RCOMMENT']);
    outRec.Add('totalPrice',   srcRec['TOTALPRICE']);
    outRec.Add('prodDate',     VarToStr(srcRec['PRODDATE']));
    outRec.Add('factoryNum',   srcRec['FACTORYNUM']);
    outRec.Add('carpBatch',    srcRec['CARP_BATCH']);
    outRec.Add('paintBatch',   srcRec['PAINT_BATCH']);
    outRec.Add('manager',      srcRec['MANAGER']);
    outRec.Add('qtyIzd',       srcRec['QTY_IZD']);
    outRec.Add('areaIzd',      srcRec['AREA_IZD']);
    outRec.Add('lengthPogon',  srcRec['LENGTH_POGON']);

    if woodByOrder.Exists(orderKey) then
      outRec.Add('woodTypes', VarToStr(woodByOrder[orderKey]))
    else
      outRec.Add('woodTypes', '');

    if colorByOrder.Exists(orderKey) then
      outRec.Add('colors', VarToStr(colorByOrder[orderKey]))
    else
      outRec.Add('colors', '');

    if i > 0 then json := json + ',';
    json := json + JSONEncode(outRec);
  end;
  json := json + ']';

  data := json;
end;
