// Клиентский метод: openCustomer
// Идентификатор (NAME): openCustomer
// Наименование (TITLE): Открытие клиента
// Серверный: Нет
//
// Параметры:
//   customerId: Integer — ID контрагента (CUSTOMERID)
//   success: string — признак успешного открытия

var
  Customer: IdocCustomer;
begin
  Customer := OpenDocument(IdocCustomer, customerId);
  if Customer <> nil then
  begin
    Customer.ShowModal;
    success := 'true';
  end
  else
    success := 'false';
end;
