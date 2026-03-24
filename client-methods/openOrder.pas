// Клиентский метод: openOrder
// Идентификатор (NAME): openOrder
// Наименование (TITLE): Открытие заказа
// Серверный: Нет
//
// Параметры:
//   orderId: Integer — ID заказа
// Возвращает: Result['success'] = 'true'/'false'
//
// API документация:
//   OpenDocument(DocType: TGUID, Key: Variant): Variant
//   ShowModal — показать модально (блокирует HTML до закрытия)
//   Framework.GetService(IpubObjectsUIService).ShowDocument(Doc) — немодально

var
  Order: IdocOrder;
begin
  Order := OpenDocument(IdocOrder, orderId);
  if Order <> nil then
  begin
    Order.ShowModal;
    Result['success'] := 'true';
  end
  else
    Result['success'] := 'false';
end;

// --- НЕМОДАЛЬНЫЙ ВАРИАНТ ---
// Если ShowModal блокирует HTML-представление и это мешает,
// используйте немодальное открытие:
//
// var
//   Order: IdocOrder;
//   UI: IpubObjectsUIService;
// begin
//   Order := OpenDocument(IdocOrder, orderId);
//   if Order <> nil then
//   begin
//     UI := Framework.GetService(IpubObjectsUIService);
//     UI.ShowDocument(Order);
//     Result['success'] := 'true';
//   end
//   else
//     Result['success'] := 'false';
// end;
