# Stockplan-MoneyMoney

Fetches vested stock amount and value from MorganStanley Stockplan connect for Amazon Employees. 

## Setup

* Download MorganStanley extension StockPlanConnect.lua
* In MoneyMoney app open “Help” Menu and hit “Show database in finder” (https://moneymoney-app.com/extensions/#installation)
* Copy StockPlanConnect.lua in extensions folder
* In MoneyMoney app open “Preferences” > “Extensions” and make sure “StockPlanConnect” show up (to use unsigned extension uncheck “verify digital signatures of extensions” at the bottom)

### MoneyMoney

* Go to Accounts -> Add Account and select "Morgan Stanley StockplanConnect" from the Dropdown
* Enter Username and Password as you use them on the website

## Known Issues and Limitations

* Always assumes EUR as base currency
* Hardcoded for Amazon Accounts on MorganStanley Stockplan Connect