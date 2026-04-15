// Клиентский метод: getProductionOrders
// Параметры: data (string, Выходной)
//
// Возвращает список заказов для производственного плана с полями:
//   id, orderNo, dateOrder, agreementNo, orderStatus, stateName,
//   customerName, comment, totalPrice, prodDate, factoryNum,
//   carpBatch, paintBatch,
//   manager (фамилия владельца документа),
//   qtyIzd (шт, UF 48), areaIzd (кв.м, UF 49), lengthPogon (погонаж, UF 122),
//   brusEnough (доп.поле по коду brus_enough),
//   spArrivalDate (ожидаемая дата прихода СП из заказа изделий "Стеклопакет"),
//   woodTypes (породы дерева из PACKINFO через GetConstructionInfo),
//   colors (цвета из ORDERS_UNITS.INCOLORID/OUTCOLORID),
//   shprosse (уникальные профили шпросс с типом соединения: кресты/не кресты),
//   notes (блок "Примечания" с важными особенностями заказа),
//   laborTotal (итоговая трудоёмкость заказа),
//   laborExplain (JSON-строка с детальной калькуляцией по изделиям)
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

function GetOrderUfIdByCode(fieldCode: string): Integer;
var
  cfgVal: Variant;
begin
  Result := 0;
  try
    cfgVal := QueryValue(
      'SELECT FIRST 1 USERFIELDID ' +
      'FROM USERFIELDS ' +
      'WHERE DOCTYPE = ''IdocOrder'' AND DELETED = 0 AND FIELDNAME = ''' + fieldCode + '''',
      MakeDictionary([]),
      ''
    );
    if (not VarIsNull(cfgVal)) and (VarToStr(cfgVal) <> '') then
      Result := cfgVal;
  except
    // fallback 0 = поле не найдено
  end;
end;

function GetProductTypeIdByName(typeName: string; fallbackId: Integer): Integer;
var
  cfgVal: Variant;
begin
  Result := fallbackId;
  try
    cfgVal := QueryValue(
      'SELECT FIRST 1 ID FROM PRODUCTTYPES WHERE DELETED = 0 AND NAME = ''' + typeName + '''',
      MakeDictionary([]),
      ''
    );
    if (not VarIsNull(cfgVal)) and (VarToStr(cfgVal) <> '') then
      Result := cfgVal;
  except
    // fallback уже задан выше
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

function NormalizeMark(value: string): string;
begin
  Result := UpperCase(Trim(value));
  Result := ReplaceStr(Result, ' ', '');
  Result := ReplaceStr(Result, '_', '');
  Result := ReplaceStr(Result, '-', '');
  Result := ReplaceStr(Result, '/', '');
  Result := ReplaceStr(Result, ',', '');
  Result := ReplaceStr(Result, '.', '');
  Result := ReplaceStr(Result, '(', '');
  Result := ReplaceStr(Result, ')', '');
  Result := ReplaceStr(Result, '''', '');
  Result := ReplaceStr(Result, '"', '');
end;

procedure AddUniqueToCsv(var list: string; seen: IcmDictionary; prefix, item: string);
var
  mark: string;
begin
  item := Trim(item);
  if item = '' then Exit;
  mark := prefix + '|' + NormalizeMark(item);
  if seen.Exists(mark) then Exit;
  seen.Add(mark, 1);
  list := AppendCsv(list, item);
end;

procedure AddOrderListUnique(listByOrder, seenByOrder: IcmDictionary; orderKey, item: string);
var
  mark, listVal: string;
begin
  item := Trim(item);
  if item = '' then Exit;
  mark := orderKey + '|' + NormalizeMark(item);
  if seenByOrder.Exists(mark) then Exit;
  seenByOrder.Add(mark, 1);
  if listByOrder.Exists(orderKey) then listVal := VarToStr(listByOrder[orderKey]) else listVal := '';
  listByOrder.Add(orderKey, AppendCsv(listVal, item));
end;

procedure AddCsvItemsToOrder(listByOrder, seenByOrder: IcmDictionary; orderKey, csv: string);
var
  p: Integer;
  s, item: string;
begin
  s := Trim(csv);
  while s <> '' do
  begin
    p := Pos(',', s);
    if p > 0 then
    begin
      item := Trim(Copy(s, 1, p - 1));
      s := Trim(Copy(s, p + 1, Length(s)));
    end
    else
    begin
      item := Trim(s);
      s := '';
    end;
    AddOrderListUnique(listByOrder, seenByOrder, orderKey, item);
  end;
end;

procedure SetOrderFlag(flags: IcmDictionary; orderKey: string);
begin
  flags.Add(orderKey, 1);
end;

procedure IncOrderCounter(counters: IcmDictionary; orderKey: string; delta: Integer);
var
  curr: Variant;
begin
  if counters.Exists(orderKey) then curr := counters[orderKey] else curr := 0;
  counters.Add(orderKey, curr + delta);
end;

function VarToIntSafe(v: Variant): Integer;
begin
  Result := 0;
  try
    Result := Round(v);
  except
    try
      Result := StrToInt(Trim(VarToStr(v)));
    except
      Result := 0;
    end;
  end;
end;

function VarToFloatSafe(v: Variant): Double;
begin
  Result := 0;
  try
    Result := v;
  except
    try
      Result := StrToFloat(Trim(VarToStr(v)));
    except
      Result := 0;
    end;
  end;
end;

function GetOrderCounter(counters: IcmDictionary; orderKey: string): Integer;
begin
  Result := 0;
  if counters.Exists(orderKey) then
    Result := VarToIntSafe(counters[orderKey]);
end;

function BuildUnitDisplayName(itemName, unitProductName: string; unitId: Integer): string;
begin
  itemName := Trim(itemName);
  unitProductName := Trim(unitProductName);
  if (itemName <> '') and (unitProductName <> '') then
    Result := itemName + ' (' + unitProductName + ')'
  else if itemName <> '' then
    Result := itemName
  else if unitProductName <> '' then
    Result := unitProductName
  else
    Result := 'Unit #' + IntToStr(unitId);
end;

function GetFalseCrossQty(falseObj: IcsFalse): Integer;
begin
  Result := 0;
  try
    Result := VarToIntSafe(falseObj.QtyFalshCon);
  except
    Result := 0;
  end;
end;

function IsMsPlisseSystem(systemName: string): Integer;
var
  u: string;
begin
  u := UpperCase(systemName);
  if (Pos('SHARKNET', u) > 0) or (Pos('SKF', u) > 0) or (Pos('ROLL', u) > 0) or
     (Pos('BLOKBLY', u) > 0) or (Pos('РОЛЛ', u) > 0) then
    Result := 1
  else
    Result := 0;
end;

function IsWarmSpacerFormula(formulaName: string): Integer;
var
  u: string;
begin
  u := UpperCase(formulaName);
  if (Pos('WARM', u) > 0) or (Pos('TGI', u) > 0) or (Pos('CH', u) > 0) then
    Result := 1
  else
    Result := 0;
end;

function IsDigitChar(ch: string): Integer;
begin
  if (ch >= '0') and (ch <= '9') then Result := 1 else Result := 0;
end;

function ExtractRalLikeCodes(sourceText: string): string;
var
  i: Integer;
  token: string;
  seen: IcmDictionary;
begin
  Result := '';
  seen := CreateDictionary;
  for i := 1 to Length(sourceText) - 3 do
  begin
    if (IsDigitChar(Copy(sourceText, i, 1)) = 1) and
       (IsDigitChar(Copy(sourceText, i + 1, 1)) = 1) and
       (IsDigitChar(Copy(sourceText, i + 2, 1)) = 1) and
       (IsDigitChar(Copy(sourceText, i + 3, 1)) = 1) then
    begin
      token := Copy(sourceText, i, 4);
      if (Copy(token, 1, 1) >= '6') and (Copy(token, 1, 1) <= '9') then
        AddUniqueToCsv(Result, seen, 'RAL', token);
      end;
  end;
end;

procedure HandleNoteUserParam(
  userParamName, userParamValue: string;
  var woodTypes: string;
  seen: IcmDictionary;
  var isDaProduct: Integer;
  var daColorCandidate, raskColorCandidate: string;
  var hasBrosh, hasMammut, hasHidden, hasDriveInProduct: Integer
);
var
  userParamNameNorm, userParamValueNorm, userParamValueUpper: string;
begin
  userParamName := Trim(userParamName);
  userParamValue := Trim(userParamValue);
  userParamNameNorm := NormalizeMark(userParamName);
  userParamValueNorm := NormalizeMark(userParamValue);
  userParamValueUpper := UpperCase(userParamValue);

  if userParamNameNorm = 'ПОРОДАДЕРЕВА' then
    AddUniqueToCsv(woodTypes, seen, 'WOOD', userParamValue);

  if userParamNameNorm = 'НАРУЖНЫЕПРОФИЛИ' then
    if Pos('HOLZPLUS', userParamValueNorm) > 0 then
      isDaProduct := 1;

  // Цвет Д/А берём только из пользовательского параметра "Цвет_наружных_профилей"
  if userParamNameNorm = 'ЦВЕТНАРУЖНЫХПРОФИЛЕЙ' then
    daColorCandidate := userParamValue;

  if userParamNameNorm = 'ЦВЕТРАСКЛАДКИRAL' then
    raskColorCandidate := userParamValue;

  if Pos('СТАРЕНИ', userParamNameNorm) > 0 then
    if Pos('ДА', userParamValueUpper) > 0 then
      hasBrosh := 1;

  if (userParamNameNorm = 'ПЕТЛИОКОННЫЕ') or
     (userParamNameNorm = 'ПЕТЛИДВЕРНЫЕ') or
     (userParamNameNorm = 'ПЕТЛИНАСТВОРКУ') then
  begin
    if Pos('MULTIMAMMUT', userParamValueNorm) > 0 then
      hasMammut := 1;
    if (Pos('СКРЫТ', userParamValueUpper) > 0) or
       (Pos('MULTIPOWER', userParamValueNorm) > 0) then
      hasHidden := 1;
  end;

  if userParamNameNorm = 'ПРИВОД' then
    if Pos('ЭЛЕКТРОПРИВОД', userParamValueUpper) > 0 then
      hasDriveInProduct := 1;
end;

// Анализ PACKINFO в один проход:
// - дерево, шпроссы, раскладка, закалка
// - Д/А (с цветом из пользовательского параметра), раскладка
// - итальянские ручки, броширование
// - мс-плиссе (цвет + количество)
// - Multi Mammut, скрытые петли, электропривод
function AnalyzePackInfo(packInfo: Variant): IcmDictionary;
var
  constr: IcsConstruction;
  prod: IcsProduct;
  filling: IcsFilling;
  leaf: IcsLeaf;
  mosNet: IcsMosquitoNet;
  iP: Integer;
  iParam: Integer;
  fillIdx: Integer;
  iB: Integer;
  iLeaf: Integer;
  iGlass: Integer;
  iMos: Integer;
  iSand: Integer;
  iSandParam: Integer;
  userParamValueUpper, handleName, sysName, colorName: string;
  beam, raskProfile: string;
  seen: IcmDictionary;
  woodTypes, shprossProfiles: string;
  daColors, raskladkaColors, msColors: string;
  hasTempered, daFlag, hasRaskladka, hasItalian, hasBrosh, hasMammut, hasHidden: Integer;
  hasCrossShpross: Integer;
  driveCnt, msCnt: Integer;
  isDaProduct, hasDriveInProduct: Integer;
  daColorCandidate, raskColorCandidate: string;
  shprossType: string;
  crossQty: Integer;
begin
  Result := CreateDictionary;
  woodTypes := '';
  shprossProfiles := '';
  daColors := '';
  raskladkaColors := '';
  msColors := '';
  hasTempered := 0;
  daFlag := 0;
  hasRaskladka := 0;
  hasItalian := 0;
  hasBrosh := 0;
  hasMammut := 0;
  hasHidden := 0;
  hasCrossShpross := 0;
  driveCnt := 0;
  msCnt := 0;
  seen := CreateDictionary;

  try
    constr := GetConstructionInfo(packInfo);
    for iP := 0 to constr.Products.Count - 1 do
    begin
      prod := constr.Products[iP];

      // Флаги/значения на уровне изделия
      isDaProduct := 0;
      hasDriveInProduct := 0;
      daColorCandidate := '';
      raskColorCandidate := '';

      // Стекло и закалка
      for iGlass := 0 to prod.Glasses.Count - 1 do
      begin
        userParamValueUpper := UpperCase(VarToStr(prod.Glasses[iGlass].Formula.Name));
        if (Pos('ZK', userParamValueUpper) > 0) or (Pos('ЗАК', userParamValueUpper) > 0) then
          hasTempered := 1;

        for iParam := 0 to prod.Glasses[iGlass].UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(prod.Glasses[iGlass].UserParams[iParam].Name),
            VarToStr(prod.Glasses[iGlass].UserParams[iParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );
      end;

      // Параметры изделия (включая вложенные user params)
      for iParam := 0 to prod.UserParams.Count - 1 do
        HandleNoteUserParam(
          VarToStr(prod.UserParams[iParam].Name),
          VarToStr(prod.UserParams[iParam].Value),
          woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
          hasBrosh, hasMammut, hasHidden, hasDriveInProduct
        );

      if not VarIsClear(prod.Frame) then
        for iParam := 0 to prod.Frame.UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(prod.Frame.UserParams[iParam].Name),
            VarToStr(prod.Frame.UserParams[iParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );

      for iSand := 0 to prod.Sandwiches.Count - 1 do
        for iSandParam := 0 to prod.Sandwiches[iSand].UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(prod.Sandwiches[iSand].UserParams[iSandParam].Name),
            VarToStr(prod.Sandwiches[iSand].UserParams[iSandParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );

      // Итальянские ручки
      for iLeaf := 0 to prod.Leafs.Count - 1 do
      begin
        leaf := prod.Leafs[iLeaf];

        for iParam := 0 to leaf.UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(leaf.UserParams[iParam].Name),
            VarToStr(leaf.UserParams[iParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );

        if not VarIsClear(leaf.Handle) then
        begin
          handleName := VarToStr(leaf.Handle.TypeName);
          if Pos('"', handleName) > 0 then
            hasItalian := 1;
        end;
      end;

      // МС-плиссе
      for iMos := 0 to prod.MosquitoNets.Count - 1 do
      begin
        mosNet := prod.MosquitoNets[iMos];
        for iParam := 0 to mosNet.UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(mosNet.UserParams[iParam].Name),
            VarToStr(mosNet.UserParams[iParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );

        sysName := VarToStr(mosNet.MosquitoNetSystem.Name);
        if IsMsPlisseSystem(sysName) = 1 then
        begin
          msCnt := msCnt + 1;
          // Цвет берём именно из покрытия рамки
          colorName := VarToStr(mosNet.FrameCoating.ColorName);
          AddUniqueToCsv(msColors, seen, 'MS_COLOR', colorName);
        end;
      end;

      // Шпроссы и раскладка
      for fillIdx := 0 to prod.Fillings.Count - 1 do
      begin
        filling := prod.Fillings[fillIdx];

        for iParam := 0 to filling.UserParams.Count - 1 do
          HandleNoteUserParam(
            VarToStr(filling.UserParams[iParam].Name),
            VarToStr(filling.UserParams[iParam].Value),
            woodTypes, seen, isDaProduct, daColorCandidate, raskColorCandidate,
            hasBrosh, hasMammut, hasHidden, hasDriveInProduct
          );

        if not VarIsClear(filling.Glass) then
          if not VarIsClear(filling.Glass.Shprosse) then
          begin
            hasRaskladka := 1;
            for iB := 0 to filling.Glass.Shprosse.Beams.Count - 1 do
            begin
              raskProfile := VarToStr(filling.Glass.Shprosse.Beams[iB].MrkProfil);
              AddUniqueToCsv(raskladkaColors, seen, 'RASK_PROFILE', raskProfile);
            end;
          end;

        if not VarIsClear(filling.InnerFalse) then
        begin
          crossQty := GetFalseCrossQty(filling.InnerFalse);
          if crossQty > 0 then
          begin
            shprossType := 'кресты';
            hasCrossShpross := 1;
          end
          else
            shprossType := 'не кресты';
          for iB := 0 to filling.InnerFalse.Beams.Count - 1 do
          begin
            beam := VarToStr(filling.InnerFalse.Beams[iB].MrkProfil);
            if Trim(beam) <> '' then
              AddUniqueToCsv(shprossProfiles, seen, 'SHPROSS', beam + ' (' + shprossType + ')');
          end;
        end;
        if not VarIsClear(filling.OuterFalse) then
        begin
          crossQty := GetFalseCrossQty(filling.OuterFalse);
          if crossQty > 0 then
          begin
            shprossType := 'кресты';
            hasCrossShpross := 1;
          end
          else
            shprossType := 'не кресты';
          for iB := 0 to filling.OuterFalse.Beams.Count - 1 do
          begin
            beam := VarToStr(filling.OuterFalse.Beams[iB].MrkProfil);
            if Trim(beam) <> '' then
              AddUniqueToCsv(shprossProfiles, seen, 'SHPROSS', beam + ' (' + shprossType + ')');
          end;
        end;
      end;

      if isDaProduct = 1 then
      begin
        daFlag := 1;
        AddUniqueToCsv(daColors, seen, 'DA_COLOR', daColorCandidate);
      end;

      if hasDriveInProduct = 1 then
        driveCnt := driveCnt + 1;
    end;
  except
  end;

  Result.Add('woodTypes', woodTypes);
  Result.Add('shpross', shprossProfiles);
  Result.Add('hasTempered', hasTempered);
  Result.Add('daFlag', daFlag);
  Result.Add('daColors', daColors);
  Result.Add('hasRaskladka', hasRaskladka);
  Result.Add('raskladkaColors', raskladkaColors);
  Result.Add('hasItalian', hasItalian);
  Result.Add('hasBrosh', hasBrosh);
  Result.Add('msCnt', msCnt);
  Result.Add('msColors', msColors);
  Result.Add('hasMammut', hasMammut);
  Result.Add('hasHidden', hasHidden);
  Result.Add('driveCnt', driveCnt);
  Result.Add('hasCrossShpross', hasCrossShpross);
end;

var
  records, unitRecs, warmRecs, itemTypeRecs, laborRecs: IcmDictionaryList;
  srcRec, unitRec, outRec, noteRec, laborRec, laborRowRec, laborExplainRec: IcmDictionary;
  woodByOrder, colorByOrder, shprossByOrder: IcmDictionary;
  seenWood, seenColor, seenShpross: IcmDictionary;
  noteTemperedByOrder, noteDaByOrder, noteRaskByOrder: IcmDictionary;
  noteItalianByOrder, noteBroshByOrder, noteWarmByOrder: IcmDictionary;
  noteMammutByOrder, noteHiddenByOrder: IcmDictionary;
  noteDaColorsByOrder, noteRaskColorsByOrder, noteWarmColorsByOrder, noteMsColorsByOrder: IcmDictionary;
  notePskCntByOrder, noteHsCntByOrder, noteFoldCntByOrder: IcmDictionary;
  noteDriveCntByOrder, noteMsCntByOrder: IcmDictionary;
  seenDaColors, seenRaskColors, seenWarmColors, seenMsColors: IcmDictionary;
  i, j: Integer;
  cnt, unitId, inColorId, outColorId: Integer;
  itemQty: Integer;
  json: string;
  orderIdsCsv, orderKey: string;
  woodVal, colorIn, colorOut, rowsJson, itemsJson, laborExplainJson: string;
  itemName, unitProductName, unitName: string;
  shprossVal, notesVal, warmFormula, warmColors, itemTypeCode: string;
  areaIzd, qtyIzd, avgAreaPerItem, lengthPogon, laborByPogon, laborByUnits, laborTotal: Double;
  unitAreaM2, baseLabor, k07, kTwoSide, kCross, k2, kTotal, unitLabor: Double;
  carpUfId, paintUfId, brusEnoughUfId, glassProductTypeId: Integer;
begin
  carpUfId := GetBatchUfId(1);
  paintUfId := GetBatchUfId(2);
  brusEnoughUfId := GetOrderUfIdByCode('brus_enough');
  glassProductTypeId := GetProductTypeIdByName('Стеклопакет', 2);

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
    '  COALESCE(uf_pogon.VAR_FLT, 0) as LENGTH_POGON, ' +
    '  COALESCE(uf_ptime.VAR_INT, 0) as PROD_TIME, ' +
    '  COALESCE(CAST(uf_supply.VAR_BIN AS VARCHAR(2000)), '''') as SUPPLY_COMMENT, ' +
    '  COALESCE(uf_brus.VAR_STR, '''') as BRUS_ENOUGH, ' +
    '  (SELECT MIN(fo.DUEDATE) ' +
    '     FROM FACTORY_ORDERS_UF_VALUES fov ' +
    '     JOIN FACTORY_ORDERS fo ON fo.ID = fov.FACTORYORDERID AND fo.DELETED = 0 AND fo.PRODUCTTYPEID = ' + IntToStr(glassProductTypeId) + ' ' +
    '    WHERE fov.USERFIELDID = 178 AND TRIM(fov.VAR_GUID) = TRIM(o.GUID)) as SP_ARRIVAL_DATE, ' +
    '  (SELECT EXTRACT(YEAR  FROM MIN(op2.DATEPAYMENT)) FROM PAYMENTRELAT pr2 JOIN ORDERPAYMENT op2 ON op2.ORDERPAYMENTID = pr2.ORDERPAYMENTID WHERE pr2.ORDERID = o.ID AND op2.DELETED = 0) as PAY_YEAR, ' +
    '  (SELECT EXTRACT(MONTH FROM MIN(op2.DATEPAYMENT)) FROM PAYMENTRELAT pr2 JOIN ORDERPAYMENT op2 ON op2.ORDERPAYMENTID = pr2.ORDERPAYMENTID WHERE pr2.ORDERID = o.ID AND op2.DELETED = 0) as PAY_MONTH, ' +
    '  (SELECT EXTRACT(DAY   FROM MIN(op2.DATEPAYMENT)) FROM PAYMENTRELAT pr2 JOIN ORDERPAYMENT op2 ON op2.ORDERPAYMENTID = pr2.ORDERPAYMENTID WHERE pr2.ORDERID = o.ID AND op2.DELETED = 0) as PAY_DAY ' +
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
    'LEFT JOIN ORDERS_UF_VALUES uf_ptime ON uf_ptime.ORDERID = o.ID AND uf_ptime.USERFIELDID = 77 ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_supply ON uf_supply.ORDERID = o.ID AND uf_supply.USERFIELDID = 174 ' +
    'LEFT JOIN ORDERS_UF_VALUES uf_brus ON uf_brus.ORDERID = o.ID AND uf_brus.USERFIELDID = ' + IntToStr(brusEnoughUfId) + ' ' +
    'WHERE o.DELETED = 0 ' +
    'AND (' +
    '  EXISTS (SELECT 1 FROM ORDERS_UF_VALUES atp WHERE atp.ORDERID = o.ID AND atp.USERFIELDID = 173 AND atp.VAR_STR = ''Да'') ' +
    '  OR EXISTS (SELECT 1 FROM PAYMENTRELAT pr JOIN ORDERPAYMENT op ON op.ORDERPAYMENTID = pr.ORDERPAYMENTID WHERE pr.ORDERID = o.ID AND op.DATEPAYMENT >= ''2026-03-01'' AND op.DELETED = 0) ' +
    '  OR EXISTS (SELECT 1 FROM ORDERS_UF_VALUES bp WHERE bp.ORDERID = o.ID AND bp.USERFIELDID IN (' + IntToStr(carpUfId) + ',' + IntToStr(paintUfId) + ') AND bp.VAR_STR IS NOT NULL AND TRIM(bp.VAR_STR) <> '''') ' +
    ') ' +
    'ORDER BY o.DATEORDER DESC',
    MakeDictionary([]),
    ''
  );

  // Подготовка агрегатов по изделиям заказа (без N+1 запросов)
  woodByOrder    := CreateDictionary;
  colorByOrder   := CreateDictionary;
  shprossByOrder := CreateDictionary;
  seenWood  := CreateDictionary;
  seenColor := CreateDictionary;
  seenShpross := CreateDictionary;

  noteTemperedByOrder := CreateDictionary;
  noteDaByOrder := CreateDictionary;
  noteRaskByOrder := CreateDictionary;
  noteItalianByOrder := CreateDictionary;
  noteBroshByOrder := CreateDictionary;
  noteWarmByOrder := CreateDictionary;
  noteMammutByOrder := CreateDictionary;
  noteHiddenByOrder := CreateDictionary;

  noteDaColorsByOrder := CreateDictionary;
  noteRaskColorsByOrder := CreateDictionary;
  noteWarmColorsByOrder := CreateDictionary;
  noteMsColorsByOrder := CreateDictionary;

  notePskCntByOrder := CreateDictionary;
  noteHsCntByOrder := CreateDictionary;
  noteFoldCntByOrder := CreateDictionary;
  noteDriveCntByOrder := CreateDictionary;
  noteMsCntByOrder := CreateDictionary;

  seenDaColors := CreateDictionary;
  seenRaskColors := CreateDictionary;
  seenWarmColors := CreateDictionary;
  seenMsColors := CreateDictionary;

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
      '  COALESCE(oi.QTY, 1) AS ITEM_QTY, ' +
      '  COALESCE(cin.TITLE, '''') as IN_COLOR, ' +
      '  COALESCE(cout.TITLE, '''') as OUT_COLOR ' +
      'FROM ORDERS_UNITS ou ' +
      'LEFT JOIN ORDERS_ITEMS oi ON oi.ID = ou.ORDERITEMID ' +
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
      itemQty := VarToIntSafe(unitRec['ITEM_QTY']);
      if itemQty < 1 then itemQty := 1;

      noteRec := AnalyzePackInfo(unitRec['PACKINFO']);

      woodVal := VarToStr(noteRec['woodTypes']);
      if woodVal <> '' then
        AddCsvItemsToOrder(woodByOrder, seenWood, orderKey, woodVal);

      colorIn := VarToStr(unitRec['IN_COLOR']);
      AddOrderListUnique(colorByOrder, seenColor, orderKey, colorIn);

      colorOut := VarToStr(unitRec['OUT_COLOR']);
      AddOrderListUnique(colorByOrder, seenColor, orderKey, colorOut);

      shprossVal := VarToStr(noteRec['shpross']);
      AddCsvItemsToOrder(shprossByOrder, seenShpross, orderKey, shprossVal);

      if VarToIntSafe(noteRec['hasTempered']) > 0 then SetOrderFlag(noteTemperedByOrder, orderKey);
      if VarToIntSafe(noteRec['daFlag']) > 0 then SetOrderFlag(noteDaByOrder, orderKey);
      if VarToIntSafe(noteRec['hasRaskladka']) > 0 then SetOrderFlag(noteRaskByOrder, orderKey);
      if VarToIntSafe(noteRec['hasItalian']) > 0 then SetOrderFlag(noteItalianByOrder, orderKey);
      if VarToIntSafe(noteRec['hasBrosh']) > 0 then SetOrderFlag(noteBroshByOrder, orderKey);
      if VarToIntSafe(noteRec['hasMammut']) > 0 then SetOrderFlag(noteMammutByOrder, orderKey);
      if VarToIntSafe(noteRec['hasHidden']) > 0 then SetOrderFlag(noteHiddenByOrder, orderKey);

      AddCsvItemsToOrder(noteDaColorsByOrder, seenDaColors, orderKey, VarToStr(noteRec['daColors']));
      AddCsvItemsToOrder(noteRaskColorsByOrder, seenRaskColors, orderKey, VarToStr(noteRec['raskladkaColors']));
      AddCsvItemsToOrder(noteMsColorsByOrder, seenMsColors, orderKey, VarToStr(noteRec['msColors']));

      cnt := VarToIntSafe(noteRec['driveCnt']);
      if cnt > 0 then IncOrderCounter(noteDriveCntByOrder, orderKey, cnt * itemQty);
      cnt := VarToIntSafe(noteRec['msCnt']);
      if cnt > 0 then IncOrderCounter(noteMsCntByOrder, orderKey, cnt * itemQty);
    end;

    // Тёплая рамка: анализ формулы стеклопакета (любая дистанционная рамка не AL)
    warmRecs := QueryRecordList(
      'SELECT ou.ORDERID, COALESCE(gp.FORMULANAME, '''') AS FORMULANAME ' +
      'FROM ORDERS_UNITS ou ' +
      'JOIN GPACKETTYPES gp ON gp.GPTYPEID = ou.GPTYPEID ' +
      'WHERE ou.ORDERID IN (' + orderIdsCsv + ') ' +
      '  AND ou.PRODUCTTYPEID = 2 ' +
      '  AND ou.GPTYPEID IS NOT NULL',
      MakeDictionary([]),
      ''
    );

    for i := 0 to warmRecs.Count - 1 do
    begin
      orderKey := VarToStr(warmRecs.Items[i]['ORDERID']);
      warmFormula := VarToStr(warmRecs.Items[i]['FORMULANAME']);
      if IsWarmSpacerFormula(warmFormula) = 1 then
      begin
        SetOrderFlag(noteWarmByOrder, orderKey);
        warmColors := ExtractRalLikeCodes(warmFormula);
        AddCsvItemsToOrder(noteWarmColorsByOrder, seenWarmColors, orderKey, warmColors);
      end;
    end;

    // PSK / HS / гармошка: строго по коду вида изделия
    itemTypeRecs := QueryRecordList(
      'SELECT ou.ORDERID, UPPER(COALESCE(it.CODE, '''')) AS ITEM_CODE, ' +
      '  SUM(CASE WHEN COALESCE(oi.QTY, 0) > 0 THEN oi.QTY ELSE 1 END) AS CNT ' +
      'FROM ORDERS_UNITS ou ' +
      'LEFT JOIN ORDERS_ITEMS oi ON oi.ID = ou.ORDERITEMID ' +
      'JOIN ITEMTYPES it ON it.ITEMTYPEID = ou.ITEMTYPEID ' +
      'WHERE ou.ORDERID IN (' + orderIdsCsv + ') ' +
      '  AND ou.ISPART = 0 ' +
      '  AND UPPER(COALESCE(it.CODE, '''')) IN (''SLIDINGPORTAL'', ''PORTAL'', ''PORTALFOLD'') ' +
      'GROUP BY ou.ORDERID, UPPER(COALESCE(it.CODE, ''''))',
      MakeDictionary([]),
      ''
    );

    for i := 0 to itemTypeRecs.Count - 1 do
    begin
      orderKey := VarToStr(itemTypeRecs.Items[i]['ORDERID']);
      itemTypeCode := Trim(VarToStr(itemTypeRecs.Items[i]['ITEM_CODE']));
      cnt := VarToIntSafe(itemTypeRecs.Items[i]['CNT']);
      if cnt > 0 then
      begin
        if itemTypeCode = 'SLIDINGPORTAL' then
          IncOrderCounter(notePskCntByOrder, orderKey, cnt)
        else if itemTypeCode = 'PORTAL' then
          IncOrderCounter(noteHsCntByOrder, orderKey, cnt)
        else if itemTypeCode = 'PORTALFOLD' then
          IncOrderCounter(noteFoldCntByOrder, orderKey, cnt);
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
    outRec.Add('comment',         srcRec['RCOMMENT']);
    outRec.Add('commentSupply',   VarToStr(srcRec['SUPPLY_COMMENT']));
    outRec.Add('brusEnough',      VarToStr(srcRec['BRUS_ENOUGH']));
    outRec.Add('spArrivalDate',   VarToStr(srcRec['SP_ARRIVAL_DATE']));
    outRec.Add('totalPrice',   srcRec['TOTALPRICE']);
    outRec.Add('prodDate',     VarToStr(srcRec['PRODDATE']));
    outRec.Add('factoryNum',   srcRec['FACTORYNUM']);
    outRec.Add('carpBatch',    srcRec['CARP_BATCH']);
    outRec.Add('paintBatch',   srcRec['PAINT_BATCH']);
    outRec.Add('manager',           srcRec['MANAGER']);
    outRec.Add('prodTime',  srcRec['PROD_TIME']);
    outRec.Add('payYear',   srcRec['PAY_YEAR']);
    outRec.Add('payMonth',  srcRec['PAY_MONTH']);
    outRec.Add('payDay',    srcRec['PAY_DAY']);
    outRec.Add('qtyIzd',            srcRec['QTY_IZD']);
    outRec.Add('areaIzd',      srcRec['AREA_IZD']);
    outRec.Add('lengthPogon',  srcRec['LENGTH_POGON']);

    areaIzd := VarToFloatSafe(srcRec['AREA_IZD']);
    qtyIzd := VarToFloatSafe(srcRec['QTY_IZD']);
    if qtyIzd > 0 then
      avgAreaPerItem := areaIzd / qtyIzd
    else
      avgAreaPerItem := 0;

    lengthPogon := VarToFloatSafe(srcRec['LENGTH_POGON']);
    laborByPogon := lengthPogon * 0.02;
    laborByUnits := 0;

    rowsJson := '';
    laborRecs := QueryRecordList(
      'SELECT ou.ID AS UNIT_ID, ' +
      '  COALESCE(ou.AREA, 0) AS UNIT_AREA, ' +
      '  ou.INCOLORID, ou.OUTCOLORID, ' +
      '  COALESCE(oi.QTY, 1) AS ITEM_QTY, ' +
      '  COALESCE(oi.NAME, '''') AS ITEM_NAME, ' +
      '  COALESCE(ou.PRODUCTNAME, '''') AS UNIT_PRODUCTNAME ' +
      'FROM ORDERS_UNITS ou ' +
      'LEFT JOIN ORDERS_ITEMS oi ON oi.ID = ou.ORDERITEMID ' +
      'WHERE ou.ORDERID = :orderId ' +
      '  AND ou.TYPEID = 0 ' +
      'ORDER BY ou.ID',
      MakeDictionary(['orderId', srcRec['ID']]),
      ''
    );

    for j := 0 to laborRecs.Count - 1 do
    begin
      laborRec := laborRecs.Items[j];
      unitId := VarToIntSafe(laborRec['UNIT_ID']);

      itemQty := VarToIntSafe(laborRec['ITEM_QTY']);
      if itemQty < 1 then itemQty := 1;

      unitAreaM2 := VarToFloatSafe(laborRec['UNIT_AREA']) / 1000000;
      baseLabor := unitAreaM2 * 0.25 * itemQty;

      if avgAreaPerItem >= 3 then
        k07 := 0.7
      else
        k07 := 0;

      kTwoSide := 0;
      if (not VarIsNull(laborRec['INCOLORID'])) and (not VarIsNull(laborRec['OUTCOLORID'])) then
      begin
        inColorId := VarToIntSafe(laborRec['INCOLORID']);
        outColorId := VarToIntSafe(laborRec['OUTCOLORID']);
        if inColorId <> outColorId then
          kTwoSide := 2;
      end;

      noteRec := AnalyzePackInfo(
        QueryValue(
          'SELECT PACKINFO FROM ORDERS_UNITS WHERE ID = :unitId',
          MakeDictionary(['unitId', unitId]),
          ''
        )
      );
      if VarToIntSafe(noteRec['hasCrossShpross']) > 0 then
        kCross := 2
      else
        kCross := 0;

      k2 := kTwoSide;
      if kCross > k2 then k2 := kCross;

      kTotal := 1 + k07 + k2;
      unitLabor := baseLabor * kTotal;
      laborByUnits := laborByUnits + unitLabor;

      itemName := VarToStr(laborRec['ITEM_NAME']);
      unitProductName := VarToStr(laborRec['UNIT_PRODUCTNAME']);
      unitName := BuildUnitDisplayName(itemName, unitProductName, unitId);

      laborRowRec := CreateDictionary;
      laborRowRec.Add('name', unitName);
      laborRowRec.Add('qty', itemQty);
      laborRowRec.Add('areaM2', unitAreaM2);
      laborRowRec.Add('k07', k07);
      laborRowRec.Add('kTwoSide', kTwoSide);
      laborRowRec.Add('kCross', kCross);
      laborRowRec.Add('labor', unitLabor);
      if rowsJson <> '' then rowsJson := rowsJson + ',';
      rowsJson := rowsJson + JSONEncode(laborRowRec);
    end;

    laborTotal := laborByUnits + laborByPogon;

    outRec.Add('laborByUnits', laborByUnits);
    outRec.Add('laborByPogon', laborByPogon);
    outRec.Add('avgAreaPerItem', avgAreaPerItem);

    if rowsJson <> '' then
      itemsJson := '[' + rowsJson + ']'
    else
      itemsJson := '[]';

    laborTotal := laborTotal / 8;
    outRec.Add('laborTotal', laborTotal);

    laborExplainRec := CreateDictionary;
    laborExplainRec.Add('orderId', srcRec['ID']);
    laborExplainRec.Add('orderNo', VarToStr(srcRec['ORDERNO']));
    laborExplainRec.Add('areaIzd', areaIzd);
    laborExplainRec.Add('qtyIzd', qtyIzd);
    laborExplainRec.Add('avgAreaPerItem', avgAreaPerItem);
    laborExplainRec.Add('lengthPogon', lengthPogon);
    laborExplainRec.Add('laborByUnits', laborByUnits);
    laborExplainRec.Add('laborByPogon', laborByPogon);
    laborExplainRec.Add('laborTotal', laborTotal);
    laborExplainJson := JSONEncode(laborExplainRec);
    outRec.Add('laborExplain', laborExplainJson);
    outRec.Add('laborItems', itemsJson);

    if woodByOrder.Exists(orderKey) then
      outRec.Add('woodTypes', VarToStr(woodByOrder[orderKey]))
    else
      outRec.Add('woodTypes', '');

    if colorByOrder.Exists(orderKey) then
      outRec.Add('colors', VarToStr(colorByOrder[orderKey]))
    else
      outRec.Add('colors', '');

    if shprossByOrder.Exists(orderKey) then
      outRec.Add('shprosse', VarToStr(shprossByOrder[orderKey]))
    else
      outRec.Add('shprosse', '');

    notesVal := '';
    if noteTemperedByOrder.Exists(orderKey) then
      notesVal := AppendCsv(notesVal, 'закалка');

    if noteDaByOrder.Exists(orderKey) then
    begin
      if noteDaColorsByOrder.Exists(orderKey) and (Trim(VarToStr(noteDaColorsByOrder[orderKey])) <> '') then
        notesVal := AppendCsv(notesVal, 'Д/А (' + VarToStr(noteDaColorsByOrder[orderKey]) + ')')
      else
        notesVal := AppendCsv(notesVal, 'Д/А');
    end;

    if noteRaskByOrder.Exists(orderKey) then
    begin
      if noteRaskColorsByOrder.Exists(orderKey) and (Trim(VarToStr(noteRaskColorsByOrder[orderKey])) <> '') then
        notesVal := AppendCsv(notesVal, 'раскладка (' + VarToStr(noteRaskColorsByOrder[orderKey]) + ')')
      else
        notesVal := AppendCsv(notesVal, 'раскладка');
    end;

    cnt := GetOrderCounter(notePskCntByOrder, orderKey);
    if cnt > 0 then
      notesVal := AppendCsv(notesVal, 'PSK (' + IntToStr(cnt) + ' шт.)');

    cnt := GetOrderCounter(noteHsCntByOrder, orderKey);
    if cnt > 0 then
      notesVal := AppendCsv(notesVal, 'HS (' + IntToStr(cnt) + ' шт.)');

    cnt := GetOrderCounter(noteFoldCntByOrder, orderKey);
    if cnt > 0 then
      notesVal := AppendCsv(notesVal, 'гармошка (' + IntToStr(cnt) + ' шт.)');

    if noteItalianByOrder.Exists(orderKey) then
      notesVal := AppendCsv(notesVal, 'итальянские ручки');

    if noteBroshByOrder.Exists(orderKey) then
      notesVal := AppendCsv(notesVal, 'броширование');

    if noteWarmByOrder.Exists(orderKey) then
    begin
      if noteWarmColorsByOrder.Exists(orderKey) and (Trim(VarToStr(noteWarmColorsByOrder[orderKey])) <> '') then
        notesVal := AppendCsv(notesVal, 'теплая рамка (' + VarToStr(noteWarmColorsByOrder[orderKey]) + ')')
      else
        notesVal := AppendCsv(notesVal, 'теплая рамка');
    end;

    cnt := GetOrderCounter(noteMsCntByOrder, orderKey);
    if cnt > 0 then
    begin
      if noteMsColorsByOrder.Exists(orderKey) and (Trim(VarToStr(noteMsColorsByOrder[orderKey])) <> '') then
        notesVal := AppendCsv(notesVal, 'мс-плиссе (' + VarToStr(noteMsColorsByOrder[orderKey]) + ') ' + IntToStr(cnt) + ' шт.')
      else
        notesVal := AppendCsv(notesVal, 'мс-плиссе ' + IntToStr(cnt) + ' шт.');
    end;

    if noteMammutByOrder.Exists(orderKey) then
      notesVal := AppendCsv(notesVal, 'Multi Mammut');

    if noteHiddenByOrder.Exists(orderKey) then
      notesVal := AppendCsv(notesVal, 'скрытые петли');

    cnt := GetOrderCounter(noteDriveCntByOrder, orderKey);
    if cnt > 0 then
      notesVal := AppendCsv(notesVal, 'электропривод (' + IntToStr(cnt) + ' шт.)');

    outRec.Add('notes', notesVal);

    if i > 0 then json := json + ',';
    json := json + JSONEncode(outRec);
  end;
  json := json + ']';

  data := json;
end;
