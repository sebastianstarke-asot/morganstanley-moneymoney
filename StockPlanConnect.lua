WebBanking{version     = 1.00,
           url         = "https://stockplanconnect.morganstanley.com/",
           services    = {"Morgan Stanley StockPlan"},
           description = string.format(MM.localizeText("Get portfolio of %s"), "Morgan Stanley")}


local connection = nil
local headers = nil
local html = nil
local cookies = nil
local fingerprint = nil


function SupportsBank (protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == "Morgan Stanley StockPlan"
end


function InitializeSession (protocol, bankCode, username, username2, password, username3)
  -- Create connection object.
  connection = Connection()
  connection.language = "en-us"

  -- Load login page.
  html = HTML(connection:get(url))

  -- Prepare HTTP headers.
  headers = {}
  headers["Accept"] = "application/json, text/plain, */*"
  headers["Referer"] = connection:getBaseURL()

  -- Request XSRF token.
  print("Requesting XSRF token.")
  local json = JSON(connection:request("POST", "/app-bin/cesreg/spc/envUrl/getEnvironmentUrl", "{}", "application/json", headers)):dictionary()

  -- Extract XSRF token from cookies and set it in HTTP header.
  headers["X-XSRF-TOKEN"] = string.match(connection:getCookies(), "XSRF%-TOKEN=([^;]+)")

  -- Generate device fingerprint.
  fingerprint = "version=2" ..
                      "&pm_fpua=" .. string.lower(connection.useragent) .. "|" .. string.sub(connection.useragent, 9) .. "|MacIntel&pm_fpsc=24|1366|768|745" ..
                      "&pm_fpsw=&pm_fptz=2&pm_fpln=lang=en-us|syslang=|userlang=&pm_fpjv=1&pm_fpco=1&pm_fpasw=&pm_fpan=Netscape&pm_fpacn=Mozilla" ..
                      "&pm_fpol=true&pm_fposp=&pm_fpup=&pm_fpsaw=1366&pm_fpspd=24&pm_fpsbd=&pm_fpsdx=&pm_fpsdy=&pm_fpslx=&pm_fpsly=&pm_fpsfse=&pm_fpsui="
  fingerprint = string.gsub(string.gsub(string.gsub(string.gsub(MM.urlencode(fingerprint), "%+", "%%20"), "-", "%%2D"), "%.", "%%2E"), "_", "%%5F")

  -- Submit login form.
  print("Submitting login form.")
  local postContent = JSON():set{
    username = username,
    password = password,
    devicePrint = fingerprint,
    deviceTokenFSO = "",
    lang = "EN",
    spSSOFlow = false
  }:json()
  local content = connection:request("POST", "/app-bin/cesreg/spc/login/validateLogin", postContent, "application/json", headers)

  cookies = connection:getCookies()
  -- The server sends garbage in front of the JSON response.
  content = string.gsub(content, ".-{", "{")

  -- Evaluate response.
  local json = JSON(content):dictionary()
  if json["errorIds"] and json["errorIds"][1] == "500166" then
    return LoginFailed
  elseif not json["success"] then
    return MM.localizeText("The server of your bank responded with an internal error. Please try again later.")
  elseif json["redirectUrl"] then
    print("Following redirect.")
    html = HTML(connection:get(json["redirectUrl"]))
  end
end


function ListAccounts (knownAccounts)
  -- Return array of accounts. Hardcoded for now, TODO: make this dynamic in the future
  local account = {
    name = "Amazon Stockplan",
    owner = "Amazon Stockplan Owner",
    accountNumber = "MS-xxxxxx-xx",
    bankCode = "N/A",
    currency = "EUR",
    type = AccountTypePortfolio,
    portfolio = true
  }
  return {account}
end

function RefreshAccount (account, since)
  -- Return balance and array of transactions.
  headers = {}
  headers["Accept"] = "application/json, text/plain, */*"

  --start saml authentication flow

  --step 1: kick off solium and generate inputs to SAML call
  print("Kicking off SAML flow")
  local step1 = "https://stockplanconnect.morganstanley.com/app-bin/spc/ba/sps/soliumSamlService/SoliumSAMLPost?format=json"
  local step1Content = JSON():set{
    company_id = "1HH", --static for amazon
    device_info = fingerprint,
  }:json()

  local samlData = connection:request("POST", step1, step1Content, "application/json", headers)
  -- The server sends garbage in front of the JSON response we need to cut
  samlData = string.sub(samlData, 7)
  local json = JSON(samlData):dictionary()

--step 2: SAML call and follow redirects to obtain apiKey = session key
  local step2 = "https://sso.solium.com/sp/ACS.saml2"
  headers[":authority:"] = "sso.solium.com"
  headers[":method:"] = "POST"
  headers[":path:"] = "/sp/ACS.saml2"
  headers[":scheme:"] = "https"
  headers["Cookies"] = connection:getCookies()
  headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9"
  headers["Referer"] = connection:getBaseURL()

  --use the samlResponse that step 1 generated
  local step2Content = "SAMLResponse="..MM.urlencode(json["samlResponse"])
  local content = connection:request("POST", step2, step2Content, "application/x-www-form-urlencoded; charset=UTF-8", headers)
  print("SAML response received")

  --extract apiIndex and employeeID from the HTML response (the server rendered this in there)
  local apiIndex = string.find(content, "apiKey: ")
  local apiKey=string.sub(content, apiIndex+9, apiIndex+44)
  local employeeIdIndex = string.find(content, "employeePK: ")
  local employeeID = tonumber(string.sub(content, employeeIdIndex+13, employeeIdIndex+13+10))
  print("Using APIKey: " .. apiKey .. " and employeeID " .. employeeID)

  --step 3: obtain tokens from token request, which yields an authorization token we can use for follow up calls
  local tokenContentRequest = JSON():set{
    authType = "SWPTPAPI_TOKEN",
    sessionToken = apiKey,
    employeeId = employeeID,
    locale = "en-US"
  }:json()

  local tokenContent = connection:request("POST", "https://stockplan.morganstanley.com/rest/participant/v2/auth/tokens", tokenContentRequest, "application/json", headers)
  local tokenJSON = JSON(tokenContent):dictionary()
  local accessToken = tokenJSON["accessToken"]
  print("Token received. Using accessToken " .. accessToken)

  -- step 4: get portfolio values
  headers = {}
  headers["Accept"] = "*/*"
  headers["Referer"] = connection:getBaseURL()
  headers["authorization"] = accessToken
  headers["employeeId"] = employeeID

  local portfolioContentRequest = JSON():set{
    operationName = "",
    variables = {},
    query = "{  portfolio {    portfolioType    availableValue {      ...money    }    unavailableValue {      ...money    }    inProgressValue {      ...money    }    totalValue {      ...money    }    totalAvailableQuantity    totalUnavailableQuantity    savingsPlans {      savingsPlanId      savingsPlanName      availableIncludesRestricted      availableValue {        ...money      }      unavailableValue {        ...money      }      totalValue {        ...money      }      availableQuantity      unavailableQuantity      totalQuantity    }    awards {      awardId      awardName      awardNamePlural      isCashAward      isSaye      availableValue {        ...awardsTotalValues      }      unavailableValue {        ...awardsTotalValues      }      totalValue {        ...awardsTotalValues      }      availableQuantity      unavailableQuantity      totalQuantity      dictionary {        ...dictionaryEntry      }    }    securities {      stockBaseTypeName      stockBaseType      availableValue {        ...money      }      unavailableValue {        ...money      }      totalValue {        ...money      }      availableQuantity      unavailableQuantity      totalQuantity    }    retailAccounts {      holdingsType      accountNumber      accountType      category      accountState      relayState      shareHoldings {        symbol        quantity        exchange        marketValue {          ...money        }      }      totalMarketValue {        ...money      }    }  }}fragment awardsTotalValues on AwardsTotalValues {  totalValue {    ...money  }  cashValue {    ...money  }}fragment money on JsonMoney {  amount  currency}fragment dictionaryEntry on DictionaryEntry {  key  value}"
  }:json()

  local portfolioContent = connection:request("POST", "https://stockplan.morganstanley.com/graphql", portfolioContentRequest, "application/json", headers)
  local portfolioJSON = JSON(portfolioContent):dictionary()

  local amountString = portfolioJSON["data"]["portfolio"]["availableValue"]["amount"]
  local amount = tonumber(amountString)
  local quantity = tonumber(portfolioJSON["data"]["portfolio"]["totalAvailableQuantity"])
  local price = amount / quantity

  local amazon = {}
  amazon.name="Amazon"
  amazon.securityNumber="906866"
  amazon.isin = "US0231351067"
  amazon.quantity=quantity
  amazon.price=price
  amazon.amount=amount
  amazon.currencyOfPrice = "EUR"
  amazon.purchasePrice = 0
  amazon.currencyOfPurchasePrice = "EUR"

  local secs = {}
  table.insert(secs, amazon)
  print("Update succesful.")
  return {securities=secs}
end

function EndSession ()
  headers = {}
  headers["Accept"] = "*/*"
  headers["Referer"] = "https://stockplan.morganstanley.com/solium/servlet/ui/dashboard"
  headers["Sec-Fetch-Dest"] = "document"
  headers["Sec-Fetch-Mode"] = "navigate"
  headers["Sec-Fetch-Site"] = "same-origin"
  headers["Sec-Fetch-User"] = "?1"
  headers["Upgrade-Insecure-Requests"] = "1"

  connection = Connection()

  connection:request("GET","https://stockplan.morganstanley.com/solium/servlet/userLogout.do?requested_lang=en_US",nil, "", headers)
  print("Logout succesful")
end
