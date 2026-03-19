// Клиентский метод: getProductionOrders
// Параметры: data (string, Выходной)
// API: records.Items[i], srcRec['FIELD'], CreateDictionary, JSONEncode

var
  records: IcmDictionaryList;
  srcRec, outRec: IcmDictionary;
  i: Integer;
  json: string;
begin
  records := QueryRecordList(
    'SELECT FIRST 30 ' +
    '  o.ID, o.ORDERNO, CAST(o.DATEORDER AS DATE) as DATEORDER, ' +
    '  o.AGREEMENTNO, o.ORDERSTATUS, ' +
    '  COALESCE(os.NAME, '''') as STATENAME, ' +
    '  COALESCE(ca.NAME, '''') as CUSTOMERNAME, ' +
    '  COALESCE(o.RCOMMENT, '''') as RCOMMENT, ' +
    '  COALESCE(o.TOTALPRICE, 0) as TOTALPRICE, ' +
    '  o.PRODDATE, ' +
    '  COALESCE(o.FACTORYNUM, 0) as FACTORYNUM, ' +
    '  COALESCE(uf.VAR_STR, '''') as BATCH_NUMBER ' +
    'FROM ORDERS o ' +
    'LEFT JOIN ORDERSTATES os ON os.ORDERSTATEID = o.ORDERSTATEID ' +
    'LEFT JOIN CONTRAGENTS ca ON ca.CONTRAGID = o.CUSTOMERID ' +
    'LEFT JOIN ORDERS_UF_VALUES uf ON uf.ORDERID = o.ID AND uf.USERFIELDID = 170 ' +
    'WHERE o.DELETED = 0 AND o.AGREEMENTNO IS NOT NULL AND TRIM(o.AGREEMENTNO) <> '''' ' +
    'ORDER BY o.DATEORDER DESC',
    nil, ''
  );

  json := '[';
  for i := 0 to records.Count - 1 do
  begin
    srcRec := records.Items[i];
    outRec := CreateDictionary;
    outRec.Add('id',           srcRec['ID']);
    outRec.Add('orderNo',      srcRec['ORDERNO']);
    outRec.Add('dateOrder',    VarToStr(srcRec['DATEORDER']));
    outRec.Add('agreementNo',  srcRec['AGREEMENTNO']);
    outRec.Add('orderStatus',  srcRec['ORDERSTATUS']);
    outRec.Add('stateName',    srcRec['STATENAME']);
    outRec.Add('customerName', srcRec['CUSTOMERNAME']);
    outRec.Add('comment',      srcRec['RCOMMENT']);
    outRec.Add('totalPrice',   srcRec['TOTALPRICE']);
    outRec.Add('prodDate',     VarToStr(srcRec['PRODDATE']));
    outRec.Add('factoryNum',   srcRec['FACTORYNUM']);
    outRec.Add('batchNumber',  srcRec['BATCH_NUMBER']);
    if i > 0 then json := json + ',';
    json := json + JSONEncode(outRec);
  end;
  json := json + ']';

  data := json;
end;
