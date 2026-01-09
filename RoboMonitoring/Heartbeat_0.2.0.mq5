//+------------------------------------------------------------------+
//| Robo Monitoring MT - Heartbeat EA                                 |
//| Phase 1: EA Health & Heartbeat Logical Model                      |
//| Author: Krishna                                                   |
//| Version: 0.2.0                                                    |
//+------------------------------------------------------------------+
#property copyright "Robo Monitoring MT"
#property version   "0.2.0"
#property strict

// ==============================
// Inputs
// ==============================
input int    HEARTBEAT_INTERVAL_SEC = 15;   // Heartbeat interval
input bool   PRINT_TO_LOG           = true; // Log heartbeat locally
input bool   ENABLE_HTTP            = true; // Enable HTTP heartbeat
input string HEARTBEAT_URL          = "http://127.0.0.1:8000/heartbeat";
input int    HTTP_TIMEOUT_MS        = 3000; // HTTP timeout

// ==============================
// Global Variables
// ==============================
datetime g_ea_start_time;
ulong    g_heartbeat_count = 0;
datetime g_last_http_error_time = 0;


//+------------------------------------------------------------------+
//| get text description                                             |
//+------------------------------------------------------------------+
string getUninitReasonText(int reasonCode)
  {
   string text="";
//---
   switch(reasonCode)
     {
      case REASON_ACCOUNT:
         text="Account was changed";break;
      case REASON_CHARTCHANGE:
         text="Symbol or timeframe was changed";break;
      case REASON_CHARTCLOSE:
         text="Chart was closed";break;
      case REASON_PARAMETERS:
         text="Input-parameter was changed";break;
      case REASON_RECOMPILE:
         text="Program "+__FILE__+" was recompiled";break;
      case REASON_REMOVE:
         text="Program "+__FILE__+" was removed from chart";break;
      case REASON_TEMPLATE:
         text="New template was applied to chart";break;
      case REASON_CLOSE:
         text="Terminal has been closed";break;
      default:text="Another reason";
     }
//---
   return text;
  }

// ==============================
// Utility Functions
// ==============================

// Return EA uptime in seconds
long GetEAUptimeSeconds()
{
   return (long)(TimeCurrent() - g_ea_start_time);
}

// Safe bool to string
string BoolToStr(bool value)
{
   return value ? "true" : "false";
}

// ==============================
// Heartbeat Payload Builder
// ==============================
string BuildHeartbeatPayload()
{
   string ea_name              = MQLInfoString(MQL_PROGRAM_NAME);
   long   account_login        = AccountInfoInteger(ACCOUNT_LOGIN);
   string broker_server        = AccountInfoString(ACCOUNT_SERVER);
   bool   terminal_connected   = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   // string terminal_name        = TerminalInfoString(TERMINAL_NAME); 
   // string terminal_name        = TerminalInfoString(TERMINAL_INFO_SERVER); 
   long   ping_ms              = TerminalInfoInteger(TERMINAL_PING_LAST);
   // bool   trade_allowed        = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   long   terminal_memory_used = TerminalInfoInteger(TERMINAL_MEMORY_USED);
   long   terminal_memory_total = TerminalInfoInteger(TERMINAL_MEMORY_TOTAL);
   long   ea_uptime_sec        = GetEAUptimeSeconds();
   datetime now                = TimeCurrent();

   // Build JSON-like payload (human readable for MVP)
   string payload;
   payload  = "{";
   payload += "\"ea_name\":\"" + ea_name + "\",";
   payload += "\"account\":" + (string)account_login + ",";
   payload += "\"server\":\"" + broker_server + "\",";
   payload += "\"terminal_connected\":" + BoolToStr(terminal_connected) + ",";
   // payload += "\"terminal_name\":\"" + terminal_name + "\",";
   payload += "\"memory_used_mb\":" + (string)terminal_memory_used + ",";
   payload += "\"memory_total_mb\":" + (string)terminal_memory_total + ",";
   // payload += "\"trade_allowed\":" + BoolToStr(trade_allowed) + ",";
   payload += "\"ping_ms\":" + (string)ping_ms + ",";
   payload += "\"ea_uptime_sec\":" + (string)ea_uptime_sec + ",";
   payload += "\"heartbeat_count\":" + (string)g_heartbeat_count + ",";
   payload += "\"timestamp\":\"" + TimeToString(now, TIME_DATE|TIME_SECONDS) + "\"";
   payload += "}";

   return payload;
}

// ==============================
// HTTP Heartbeat Sender
// ==============================
bool SendHeartbeatHTTP(string payload)
{
   char   post_data[];
   char   result[];
   string headers;
   string status_code = "";

   headers = "Content-Type: application/json\r\n";

   StringToCharArray(payload, post_data);

   ResetLastError();
   int res = WebRequest(
      "POST",
      HEARTBEAT_URL,
      headers,
      HTTP_TIMEOUT_MS,
      post_data,
      result,
      status_code
   );

   if(res == -1)
   {
      int err = GetLastError();
      if(PRINT_TO_LOG)
         Print("[RMMT HTTP ERROR] WebRequest failed. Error=", err);

      g_last_http_error_time = TimeCurrent();
      return false;
   }

   if(status_code != "200")
   {
      if(PRINT_TO_LOG)
         Print("[RMMT HTTP ERROR] HTTP status code=", status_code);

      return false;
   }

   return true;
}

// ==============================
// Heartbeat Logic
// ==============================
void SendHeartbeat()
{
   g_heartbeat_count++;

   string heartbeat_payload = BuildHeartbeatPayload();

   if(PRINT_TO_LOG)
   {
      Print(heartbeat_payload);
      //Print("[RMMT HEARTBEAT] ", heartbeat_payload);
   }

   if(ENABLE_HTTP)
   {
      bool ok = SendHeartbeatHTTP(heartbeat_payload);

      if(!ok && PRINT_TO_LOG)
         Print("[RMMT] Heartbeat HTTP delivery failed");
   }


   // Phase 2:
   // - Send via WebRequest()
   // - Write to file
   // - Push to local exporter
}

// ==============================
// MQL5 Event Handlers
// ==============================
int OnInit()
{
   g_ea_start_time = TimeCurrent();

   EventSetTimer(HEARTBEAT_INTERVAL_SEC);

   Print("===========================================");
   Print(" Robo Monitoring MT - Heartbeat EA STARTED ");
   Print(" EA Name: ", MQLInfoString(MQL_PROGRAM_NAME));
   Print(" Version: 0.2.0 (HTTP Enabled)");
   Print(" Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
   Print(" Server : ", AccountInfoString(ACCOUNT_SERVER));
   Print("===========================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();

   Print("===========================================");
   Print(" Robo Monitoring MT - Heartbeat EA STOPPED ");
   Print(" Reason Code: ", getUninitReasonText(reason));
   // string reason_translated = EnumToString((ENUM_DEINIT_REASON)UninitializeReason(reason));
   // EnumToString((ENUM_DEINIT_REASON)UninitializeReason())=reason
   Print(" EA Uptime (sec): ", GetEAUptimeSeconds());
   Print("===========================================");
}

void OnTimer()
{
   SendHeartbeat();
}

void OnTick()
{
   // Intentionally empty
   // This EA does NOT trade
}
