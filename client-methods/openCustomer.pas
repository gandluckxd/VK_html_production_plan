// Клиентский метод: openCustomer
// Идентификатор (NAME): openCustomer
// Наименование (TITLE): Открытие клиента
// Серверный: Нет
//
// Параметры:
//   customerId: Integer — ID контрагента (CUSTOMERID)
// Возвращает: Result['success'] = 'true'/'false'

var
  Customer: IdocCustomer;
begin
  Customer := OpenDocument(IdocCustomer, customerId);
  if Customer <> nil then
  begin
    Customer.ShowModal;
    Result['success'] := 'true';
  end
  else
    Result['success'] := 'false';
end;
