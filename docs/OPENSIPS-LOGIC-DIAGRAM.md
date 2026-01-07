# OpenSIPS Configuration Logic Diagram

This document provides a visual representation of the routing logic in `opensips.cfg.template`.

## Main Request Flow

```mermaid
flowchart TD
    Start([SIP Request Received]) --> LogReq[Log Request]
    LogReq --> CheckMaxFwd{Max-Forwards Valid?}
    CheckMaxFwd -->|No| Reply483[Reply 483 Too Many Hops]
    CheckMaxFwd -->|Yes| CheckScanner{User-Agent Scanner?}
    CheckScanner -->|Yes| Drop[Drop Request]
    CheckScanner -->|No| CheckToTag{Has To-Tag? In-Dialog?}
    CheckToTag -->|Yes| RouteWithinDLG[route WITHINDLG]
    CheckToTag -->|No| CheckMethod{Method Allowed?}
    CheckMethod -->|No| Reply405[Reply 405 Method Not Allowed]
    CheckMethod -->|Yes| CheckCancel{"Method = CANCEL?"}
    CheckCancel -->|Yes| HandleCancel[Handle CANCEL]
    CheckCancel -->|No| CheckOptNotify{"Method = OPTIONS/NOTIFY?"}
    CheckOptNotify -->|Yes| HandleOptNotify[Handle OPTIONS/NOTIFY]
    CheckOptNotify -->|No| CheckRegister{"Method = REGISTER?"}
    CheckRegister -->|Yes| HandleRegister[Handle REGISTER]
    CheckRegister -->|No| RouteDomainCheck[route DOMAIN_CHECK]
    
    HandleCancel --> CheckTrans{Transaction Exists?}
    CheckTrans -->|Yes| RelayCancel[route RELAY]
    CheckTrans -->|No| Reply481[Reply 481 Call/Transaction Does Not Exist]
    
    HandleOptNotify --> CheckEndpointURI{Request-URI Looks Like Endpoint?}
    CheckEndpointURI -->|Yes| LookupEndpoint1[route ENDPOINT_LOOKUP]
    CheckEndpointURI -->|No| RouteDomainCheck
    LookupEndpoint1 --> FoundEndpoint1{Endpoint Found?}
    FoundEndpoint1 -->|Yes| BuildURI1[route BUILD_ENDPOINT_URI]
    FoundEndpoint1 -->|No| HandleOptNotifyFallback[Handle Fallback]
    BuildURI1 --> RelayOptNotify[route RELAY]
    HandleOptNotifyFallback --> RouteDomainCheck
    
    HandleRegister --> ExtractContact{Contact Header Exists?}
    ExtractContact -->|Yes| StoreEndpoint[Store Endpoint Location in Database]
    ExtractContact -->|No| LogWarning[Log Warning]
    StoreEndpoint --> RouteDomainCheck
    LogWarning --> RouteDomainCheck
    
    RouteDomainCheck --> CheckEndpointIP{"Request-URI Domain = IP?"}
    CheckEndpointIP -->|Yes| LookupEndpoint2[route ENDPOINT_LOOKUP]
    CheckEndpointIP -->|No| CheckDomainMatch{Domain Matches To?}
    CheckDomainMatch -->|No| Exit1[Exit]
    CheckDomainMatch -->|Yes| LookupDomain[Lookup Domain in Database]
    LookupDomain --> DomainFound{Domain Found?}
    DomainFound -->|No| Exit2[Exit]
    DomainFound -->|Yes| RouteToDispatcher[route TO_DISPATCHER]
    
    LookupEndpoint2 --> FoundEndpoint2{Endpoint Found?}
    FoundEndpoint2 -->|Yes| BuildURI2[route BUILD_ENDPOINT_URI]
    FoundEndpoint2 -->|No| Reply404[Reply 404 Endpoint Not Found]
    BuildURI2 --> RelayInvite[route RELAY]
    
    RouteToDispatcher --> SelectDispatcher{Healthy Asterisk Available?}
    SelectDispatcher -->|No| Reply503[Reply 503 Service Unavailable]
    SelectDispatcher -->|Yes| RecordRoute[Record-Route]
    RecordRoute --> RelayDispatcher[route RELAY]
    
    RelayCancel --> End1([End])
    RelayOptNotify --> End2([End])
    RelayInvite --> End3([End])
    RelayDispatcher --> End4([End])
    Reply483 --> End5([End])
    Reply405 --> End6([End])
    Reply481 --> End7([End])
    Reply404 --> End8([End])
    Reply503 --> End9([End])
    Drop --> End10([End])
    Exit1 --> End11([End])
    Exit2 --> End12([End])
    
    style Start fill:#90EE90
    style End1 fill:#FFB6C1
    style End2 fill:#FFB6C1
    style End3 fill:#FFB6C1
    style End4 fill:#FFB6C1
    style End5 fill:#FFB6C1
    style End6 fill:#FFB6C1
    style End7 fill:#FFB6C1
    style End8 fill:#FFB6C1
    style End9 fill:#FFB6C1
    style End10 fill:#FFB6C1
    style End11 fill:#FFB6C1
    style End12 fill:#FFB6C1
```

## Helper Routes

### ENDPOINT_LOOKUP

```mermaid
flowchart TD
    Start([route ENDPOINT_LOOKUP]) --> ValidateInput{lookup_user Empty?}
    ValidateInput -->|Yes| LogError[Log Error & Exit]
    ValidateInput -->|No| CheckAoR{AoR Provided?}
    CheckAoR -->|Yes| TryExactMatch[Try Exact AoR Match in Database]
    CheckAoR -->|No| TryUsernameMatch[Try Username-Only Match in Database]
    TryExactMatch --> FoundExact{Found?}
    FoundExact -->|Yes| SetSuccess[Set lookup_success=1]
    FoundExact -->|No| TryUsernameMatch
    TryUsernameMatch --> FoundUsername{Found?}
    FoundUsername -->|Yes| SetSuccess
    FoundUsername -->|No| SetFailure[Set lookup_success=0]
    SetSuccess --> ValidateEndpoint[route VALIDATE_ENDPOINT]
    ValidateEndpoint --> Return1([Return])
    SetFailure --> Return1
    LogError --> Exit1([Exit])
    
    style Start fill:#90EE90
    style Return1 fill:#87CEEB
    style Exit1 fill:#FFB6C1
```

### VALIDATE_ENDPOINT

```mermaid
flowchart TD
    Start([route VALIDATE_ENDPOINT]) --> CheckIP{endpoint_ip Valid?}
    CheckIP -->|No| LogError[Log Error & Return]
    CheckIP -->|Yes| CheckPort{endpoint_port Empty/Invalid?}
    CheckPort -->|Yes| SetDefaultPort[Set port = 5060]
    CheckPort -->|No| Return1([Return])
    SetDefaultPort --> Return1
    LogError --> Return1
    
    style Start fill:#90EE90
    style Return1 fill:#87CEEB
```

### BUILD_ENDPOINT_URI

```mermaid
flowchart TD
    Start([route BUILD_ENDPOINT_URI]) --> BuildDU["Build Destination URI: $du = sip:user@ip:port"]
    BuildDU --> ExtractDomain{Extract Domain from AoR}
    ExtractDomain --> DomainValid{Domain Valid & Not IP?}
    DomainValid -->|No| TryToHeader[Try To Header Domain]
    DomainValid -->|Yes| CheckAoRFormat{AoR Has Domain & Not IP?}
    TryToHeader --> ToDomainValid{To Domain Valid & Not IP?}
    ToDomainValid -->|Yes| UseToDomain[Set endpoint_domain from To]
    ToDomainValid -->|No| UseIP[Use IP in Request-URI: $ru = $du]
    CheckAoRFormat -->|Yes| UseAoR["Use AoR in Request-URI: $ru = sip:AoR"]
    CheckAoRFormat -->|No| CheckExtractedDomain{Extracted Domain Valid & Not IP?}
    CheckExtractedDomain -->|Yes| UseExtractedDomain["Use Extracted Domain: $ru = sip:user@domain"]
    CheckExtractedDomain -->|No| UseIP
    UseAoR --> Return1([Return])
    UseExtractedDomain --> Return1
    UseToDomain --> CheckAoRFormat
    UseIP --> Return1
    
    style Start fill:#90EE90
    style Return1 fill:#87CEEB
```

## Route Details

### route WITHINDLG (In-Dialog Requests)

```mermaid
flowchart TD
    Start([route WITHINDLG]) --> TryLooseRoute{"loose_route() Succeeds?"}
    TryLooseRoute -->|Yes| Relay1[route RELAY]
    TryLooseRoute -->|No| CheckACKPRACK{"Method = ACK/PRACK?"}
    CheckACKPRACK -->|Yes| CheckTrans1{Transaction Exists?}
    CheckACKPRACK -->|No| CheckBYE{"Method = BYE?"}
    CheckBYE -->|Yes| CheckTrans2{Transaction Exists?}
    CheckBYE -->|No| Reply404[Reply 404 Not Here]
    CheckTrans1 -->|Yes| TryTRelay{"t_relay() Succeeds?"}
    CheckTrans1 -->|No| Relay2[route RELAY - Try Anyway]
    TryTRelay -->|Yes| End1([Exit])
    TryTRelay -->|No| Relay3[route RELAY - Fallback]
    CheckTrans2 -->|Yes| Relay4[route RELAY]
    CheckTrans2 -->|No| Relay5[route RELAY - Try Anyway]
    Relay1 --> End2([Exit])
    Relay2 --> End3([Exit])
    Relay3 --> End4([Exit])
    Relay4 --> End5([Exit])
    Relay5 --> End6([Exit])
    Reply404 --> End7([Exit])
    
    style Start fill:#90EE90
    style End1 fill:#FFB6C1
    style End2 fill:#FFB6C1
    style End3 fill:#FFB6C1
    style End4 fill:#FFB6C1
    style End5 fill:#FFB6C1
    style End6 fill:#FFB6C1
    style End7 fill:#FFB6C1
```

### route DOMAIN_CHECK

```mermaid
flowchart TD
    Start([route DOMAIN_CHECK]) --> CheckDomainEmpty{Domain Empty?}
    CheckDomainEmpty -->|Yes| Exit1[Exit]
    CheckDomainEmpty -->|No| CheckEndpointIP{Request-URI Domain = IP?}
    CheckEndpointIP -->|Yes| ExtractUser[Extract Username]
    ExtractUser --> LookupEndpoint[route ENDPOINT_LOOKUP]
    LookupEndpoint --> FoundEndpoint{Endpoint Found?}
    FoundEndpoint -->|Yes| BuildURI[route BUILD_ENDPOINT_URI]
    FoundEndpoint -->|No| Reply404[Reply 404 Endpoint Not Found]
    BuildURI --> Relay[route RELAY]
    CheckEndpointIP -->|No| CheckDomainMatch{Domain Matches To Domain?}
    CheckDomainMatch -->|No| Exit2[Exit]
    CheckDomainMatch -->|Yes| LookupDomain[Lookup Domain in Database]
    LookupDomain --> DomainFound{Domain Found?}
    DomainFound -->|No| Exit3[Exit]
    DomainFound -->|Yes| RouteDispatcher[route TO_DISPATCHER]
    Relay --> End1([Exit])
    Reply404 --> End2([Exit])
    RouteDispatcher --> End3([Exit])
    Exit1 --> End4([Exit])
    Exit2 --> End5([Exit])
    Exit3 --> End6([Exit])
    
    style Start fill:#90EE90
    style End1 fill:#FFB6C1
    style End2 fill:#FFB6C1
    style End3 fill:#FFB6C1
    style End4 fill:#FFB6C1
    style End5 fill:#FFB6C1
    style End6 fill:#FFB6C1
```

### route TO_DISPATCHER

```mermaid
flowchart TD
    Start([route TO_DISPATCHER]) --> SelectDst{"ds_select_dst() Healthy Node?"}
    SelectDst -->|No| Reply503[Reply 503 Service Unavailable]
    SelectDst -->|Yes| RecordRoute[Add Record-Route Header]
    RecordRoute --> ArmFailure[t_on_failure]
    ArmFailure --> Relay{"t_relay() Succeeds?"}
    Relay -->|Yes| End1([Exit])
    Relay -->|No| Reply500[Reply 500 Internal Server Error]
    Reply503 --> End2([Exit])
    Reply500 --> End3([Exit])
    
    style Start fill:#90EE90
    style End1 fill:#FFB6C1
    style End2 fill:#FFB6C1
    style End3 fill:#FFB6C1
```

### route RELAY

```mermaid
flowchart TD
    Start([route RELAY]) --> CheckINVITE{"Method = INVITE?"}
    CheckINVITE -->|Yes| RecordRoute[Add Record-Route Header]
    CheckINVITE -->|No| CheckACKPRACK{"Method = ACK/PRACK/BYE/NOTIFY?"}
    CheckACKPRACK -->|Yes| CheckPrivateIP{Request-URI Domain = Private IP?}
    CheckACKPRACK -->|No| ArmFailure1[t_on_failure]
    CheckPrivateIP -->|Yes| LookupNATIP[Lookup Endpoint NAT IP from Database]
    CheckPrivateIP -->|No| ArmFailure1
    LookupNATIP --> FoundNATIP{NAT IP Found?}
    FoundNATIP -->|Yes| UpdateDU[Update $du with NAT IP]
    FoundNATIP -->|No| ArmFailure1
    UpdateDU --> ArmFailure1
    RecordRoute --> ArmFailure1
    ArmFailure1 --> CheckNOTIFY{"Method = NOTIFY/OPTIONS?"}
    CheckNOTIFY -->|Yes| LogTransaction[Log Transaction Creation]
    CheckNOTIFY -->|No| Relay{"t_relay() Succeeds?"}
    LogTransaction --> Relay
    Relay -->|Yes| End1([Exit])
    Relay -->|No| Reply500[Reply 500 Internal Server Error]
    Reply500 --> End2([Exit])
    
    style Start fill:#90EE90
    style End1 fill:#FFB6C1
    style End2 fill:#FFB6C1
```

## Response Handling

### onreply_route

```mermaid
flowchart TD
    Start([Response Received]) --> LogResponse[Log Response]
    LogResponse --> FixNATContact[fix_nated_contact - Fix Contact Header]
    FixNATContact --> CheckSDP{Content-Type = application/sdp?}
    CheckSDP -->|Yes| FixNATSDP["fix_nated_sdp('rewrite-media-ip') - Fix SDP IP"]
    CheckSDP -->|No| CheckOptNotify{"Method = OPTIONS/NOTIFY?"}
    FixNATSDP --> CheckOptNotify
    CheckOptNotify -->|Yes| LogOptNotify[Log OPTIONS/NOTIFY Response]
    CheckOptNotify -->|No| Check200{"Status = 200 OK with SDP?"}
    LogOptNotify --> Check200
    Check200 -->|Yes| LogSDP[Log SDP Details & Endpoint IPs]
    Check200 -->|No| CheckProvisional{100-199 Provisional?}
    CheckProvisional -->|Yes| Exit1[Exit - Let TM Handle]
    CheckProvisional -->|No| CheckSuccess{200-299 Success?}
    CheckSuccess -->|Yes| Exit2[Exit]
    CheckSuccess -->|No| CheckError{300+ Error?}
    CheckError -->|Yes| Exit3[Exit]
    CheckError -->|No| Exit4[Exit]
    LogSDP --> Exit5[Exit]
    
    style Start fill:#90EE90
    style Exit1 fill:#FFB6C1
    style Exit2 fill:#FFB6C1
    style Exit3 fill:#FFB6C1
    style Exit4 fill:#FFB6C1
    style Exit5 fill:#FFB6C1
```

### failure_route[1]

```mermaid
flowchart TD
    Start([Transaction Failure]) --> LogFailure[Log Failure Details]
    LogFailure --> CheckTimeout{"Status = 408 Timeout?"}
    CheckTimeout -->|Yes| LogTimeout[Log Timeout Details]
    CheckTimeout -->|No| End([Exit])
    LogTimeout --> End
    
    style Start fill:#90EE90
    style End fill:#FFB6C1
```

## Method-Specific Flows

### REGISTER Flow

```mermaid
flowchart TD
    Start([REGISTER Request]) --> ExtractAoR[Extract AoR from To Header]
    ExtractAoR --> GetSourceIP[Get Source IP/Port]
    GetSourceIP --> ExtractContact{Extract from Contact Header}
    ExtractContact --> ValidateIP{IP Valid?}
    ValidateIP -->|No| LogError[Log Error]
    ValidateIP -->|Yes| FixNATRegister[fix_nated_register - Fix Contact Header for NAT]
    FixNATRegister --> GetExpires[Get Expires Value]
    GetExpires --> StoreDB[Store in endpoint_locations Database]
    StoreDB --> RouteDomainCheck[Continue to DOMAIN_CHECK]
    LogError --> RouteDomainCheck
    
    style Start fill:#90EE90
    style RouteDomainCheck fill:#87CEEB
```

### OPTIONS/NOTIFY Flow (from Asterisk)

```mermaid
flowchart TD
    Start([OPTIONS/NOTIFY from Asterisk]) --> CheckEndpointURI{Request-URI Looks Like Endpoint?}
    CheckEndpointURI -->|No| RouteDomainCheck[Continue to DOMAIN_CHECK]
    CheckEndpointURI -->|Yes| ExtractUser[Extract Username]
    ExtractUser --> ExtractDomain[Extract Domain from To]
    ExtractDomain --> LookupEndpoint[route ENDPOINT_LOOKUP]
    LookupEndpoint --> Found{Endpoint Found?}
    Found -->|Yes| BuildURI[route BUILD_ENDPOINT_URI]
    Found -->|No| CheckMethod{"Method = OPTIONS?"}
    CheckMethod -->|Yes| Reply200[Reply 200 OK]
    CheckMethod -->|No| TryContact[Try Contact Header Fallback]
    TryContact --> ContactFound{Contact Valid?}
    ContactFound -->|Yes| RelayContact[route RELAY]
    ContactFound -->|No| Reply404[Reply 404 Not Found]
    BuildURI --> Relay[route RELAY]
    
    style Start fill:#90EE90
    style RouteDomainCheck fill:#87CEEB
```

### INVITE Flow (to Endpoint)

```mermaid
flowchart TD
    Start([INVITE Request]) --> CheckEndpointIP{Request-URI Domain = IP?}
    CheckEndpointIP -->|No| RouteDomainCheck[route DOMAIN_CHECK]
    CheckEndpointIP -->|Yes| ExtractUser[Extract Username]
    ExtractUser --> LookupEndpoint[route ENDPOINT_LOOKUP]
    LookupEndpoint --> Found{Endpoint Found?}
    Found -->|Yes| BuildURI[route BUILD_ENDPOINT_URI]
    Found -->|No| Reply404[Reply 404 Endpoint Not Found]
    BuildURI --> Relay[route RELAY]
    
    style Start fill:#90EE90
    style RouteDomainCheck fill:#87CEEB
```

## Key Decision Points

1. **In-Dialog Detection**: `has_totag()` - Routes to `WITHINDLG` if To-tag exists
2. **Method Validation**: Allows REGISTER, INVITE, ACK, BYE, CANCEL, OPTIONS, NOTIFY, SUBSCRIBE, PRACK
3. **Endpoint Detection**: Checks if Request-URI domain is an IP address (regex pattern)
4. **Domain Lookup**: Queries `sip_domains` table to find dispatcher setid
5. **Dispatcher Selection**: Uses `ds_select_dst()` to find healthy Asterisk backend
6. **Endpoint Lookup**: Queries `endpoint_locations` table for registered endpoint IP/port
7. **NAT Traversal**: Uses `nathelper` module to fix Contact headers and SDP in responses
8. **PRACK Support**: Handles PRACK requests for 100rel (reliable provisional responses)

## Database Tables Used

- **sip_domains**: Maps domain names to dispatcher set IDs
- **dispatcher**: Contains Asterisk backend destinations with health status
- **endpoint_locations**: Stores registered endpoint IP/port information

## Helper Route Dependencies

```
ENDPOINT_LOOKUP
  └─> VALIDATE_ENDPOINT

BUILD_ENDPOINT_URI
  (uses output from ENDPOINT_LOOKUP)
```

## Notes

- All routes use `exit;` to terminate processing
- Transaction module (`tm`) handles INVITE transaction state automatically
- Record-Route headers are added for requests going through OpenSIPS
- Health checks via dispatcher module send OPTIONS to Asterisk backends
- Endpoint locations are stored during REGISTER and used for direct routing
- **NAT Traversal**: `nathelper` module fixes Contact headers and SDP in responses
- **PRACK Support**: PRACK requests are handled in `WITHINDLG` route for 100rel support
- **NAT IP Lookup**: ACK, PRACK, BYE, and NOTIFY requests to endpoints behind NAT use database lookup for correct public IP

