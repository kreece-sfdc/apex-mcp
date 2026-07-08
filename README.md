# Apex MCP Server

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server built entirely in Salesforce Apex, exposed via an Apex REST endpoint. The goal was to explore whether a Salesforce org could act as an MCP server — serving tools, resources, and prompts to an AI client — using only native Apex and the platform's REST capabilities, without any middleware.

The proof-of-concept server (`PCMetrics`) exposes PC hardware metrics and Valorant match history data. It was connected to [Claude Code](https://claude.ai/code) as an MCP server to validate that all responses were accurate and protocol-compliant.

---

## Architecture

### How it works

Every MCP request is a JSON-RPC 2.0 POST to a single Apex REST endpoint:

```
POST /services/apexrest/pcmetrics/mcp/
Content-Type: application/json
Authorization: Bearer <access_token>
MCP-Protocol-Version: 2025-11-25

{ "jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {} }
```

The controller (`PCMetricsMCPController`) receives the request, parses the JSON-RPC method, and dispatches to the appropriate handler. Tools, resources, and prompts are not hardcoded — they are discovered at runtime by querying Custom Metadata Type registries, which map a record label to an Apex class name. The controller instantiates the class via `Type.forName()` and calls the interface methods.

### Interfaces

Each capability type has an interface that concrete classes implement:

**`IMCPTool`** — a callable action the AI can invoke:
```apex
public interface IMCPTool {
    String getName();
    String getTitle();
    String getDescription();
    Map<String, Object> getInputSchema();
    String getServerName();
    Map<String, Object> call(Map<String, Object> arguments);
}
```

**`IMCPResource`** — a readable data source (JSON, Markdown, binary):
```apex
public interface IMCPResource {
    String getUri();
    String getName();
    String getTitle();
    String getDescription();
    String getMimeType();
    String getText();   // for text content
    String getBlob();   // for base64-encoded binary
    String getServerName();
}
```

**`IMCPPrompt`** — a parameterized prompt template:
```apex
public interface IMCPPrompt {
    String getName();
    String getTitle();
    String getDescription();
    List<Map<String, Object>> getArguments();
    String getServerName();
    List<Map<String, Object>> getMessages(Map<String, String> args);
}
```

### Custom Metadata Type Registries

Three Custom Metadata Types act as the plugin registry:

| CMT API Name | Field | Purpose |
|---|---|---|
| `MCP_Tool_Registry__mdt` | `Apex_Class_Name__c` | Maps a label to an `IMCPTool` class |
| `MCP_Resource_Registry__mdt` | `Apex_Class_Name__c` | Maps a label to an `IMCPResource` class |
| `MCP_Prompt_Registry__mdt` | `Apex_Class_Name__c` | Maps a label to an `IMCPPrompt` class |

The controller queries these CMTs at runtime. Adding a new tool, resource, or prompt requires no controller changes — just a new Apex class and a new CMT record.

### Class Structure

```
force-app/main/default/classes/
  interfaces/         IMCPTool, IMCPResource, IMCPPrompt, IMCPServer
  core/               PCMetricsMCPController, MCPUtil
  pcmetrics/
    tools/            GetTemperaturesTool, GetMatchHistoryTool
    resources/        GPUCPUTempsResource, CPUSnapshotResource, MatchHistoryResource
    prompts/          AnalyzeHardwarePrompt
```

---

## Example Requests & Responses

### Initialize session

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"my-client","version":"1.0"}}}' \
  "https://<instance>.salesforce.com/services/apexrest/pcmetrics/mcp/"
```

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2025-11-25",
    "capabilities": { "tools": {}, "resources": {}, "prompts": {} },
    "serverInfo": { "name": "PCMetrics", "version": "1.0.0" }
  }
}
```

### Call a tool

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_temperatures","arguments":{}}}' \
  "https://<instance>.salesforce.com/services/apexrest/pcmetrics/mcp/"
```

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{
      "type": "text",
      "text": "{\"timestamp\":\"2026-07-07T21:00:00Z\",\"cpu\":{\"model\":\"AMD Ryzen 9 7950X\",\"temperature_c\":68,\"load_percent\":42},\"gpu\":{\"model\":\"NVIDIA RTX 4090\",\"temperature_c\":74,\"load_percent\":87,\"vram_used_mb\":18432,\"vram_total_mb\":24576}}"
    }],
    "isError": false
  }
}
```

### Get a prompt

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":3,"method":"prompts/get","params":{"name":"analyze_hardware","arguments":{"focus":"gpu"}}}' \
  "https://<instance>.salesforce.com/services/apexrest/pcmetrics/mcp/"
```

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "description": "Generate an analysis prompt for current PC hardware metrics",
    "messages": [{
      "role": "user",
      "content": {
        "type": "text",
        "text": "Analyze the following PC hardware metrics. Focus your analysis on GPU performance only.\n\nMetrics:\n{...}"
      }
    }]
  }
}
```

---

## Adding a New Server, Tool, Resource, or Prompt

### New MCP Server

A "server" in this framework is a named domain exposed at its own REST URL. The `MCPServerController` (at `/services/apexrest/mcp`) acts as a discovery endpoint — it responds to `servers/list` and returns every server registered in `MCP_Server_Registry__mdt`. Each individual server then has its own dedicated `@RestResource` controller that handles all MCP methods (tools, resources, prompts) for that domain.

**Step 1 — Implement `IMCPServer`**

```apex
public class MyServer implements IMCPServer {
    public String getUri()         { return 'myserver/mcp'; }
    public String getName()        { return 'MyServer'; }
    public String getTitle()       { return 'My Domain Server'; }
    public String getDescription() { return 'Exposes data from my domain.'; }
    public String getMimeType()    { return 'application/json'; }
}
```

`getUri()` must match the URL path of the dedicated REST controller you create next.

**Step 2 — Register in `MCP_Server_Registry__mdt`**

Create `force-app/main/default/customMetadata/MCP_Server_Registry.MyServer.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>My Server</label>
    <protected>false</protected>
    <values>
        <field>Apex_Class_Name__c</field>
        <value xsi:type="xsd:string">MyServer</value>
    </values>
</CustomMetadata>
```

This makes the server appear in `servers/list` responses from the discovery endpoint.

**Step 3 — Create a dedicated REST controller**

Each server needs its own `@RestResource` Apex class that handles MCP protocol methods. Copy `PCMetricsMCPController` as your starting point and change the `urlMapping` and `SERVER_NAME`:

```apex
@RestResource(urlMapping='/myserver/mcp/*')
global class MyServerMCPController {

    private static final String SERVER_NAME = 'MyServer';

    @HttpPost
    global static void doPost() {
        // identical dispatch logic to PCMetricsMCPController
        // MCPUtil, CMT queries, and all handler methods are reused as-is
    }
}
```

The controller queries `MCP_Tool_Registry__mdt`, `MCP_Resource_Registry__mdt`, and `MCP_Prompt_Registry__mdt` at runtime — it only returns items whose `getServerName()` matches `SERVER_NAME`, so tools/resources/prompts are automatically scoped to the correct server.

**Step 4 — Implement tools, resources, and prompts**

Follow the patterns below, returning `'MyServer'` from `getServerName()` on each class, and registering each with the appropriate CMT type.

**How `MCPServerController` (the discovery endpoint) works**

`/services/apexrest/mcp` handles one method: `servers/list`. It queries `MCP_Server_Registry__mdt`, instantiates each registered `IMCPServer` class via `Type.forName()`, and returns the server list. This lets a client discover all available servers and their endpoint URIs before connecting to any of them.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -H "MCP-Protocol-Version: 2025-11-25" \
  -d '{"jsonrpc":"2.0","id":1,"method":"servers/list","params":{}}' \
  "https://<instance>.salesforce.com/services/apexrest/mcp"
```

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "servers": [
      {
        "uri": "pcmetrics/mcp",
        "name": "PCMetrics",
        "title": "PC Hardware Metrics Server",
        "description": "Exposes live CPU, GPU, and memory metrics from a local PC.",
        "mimeType": "application/json"
      }
    ]
  }
}
```

The interfaces, CMT object definitions, and `MCPUtil` are shared across all servers — no changes to the framework are needed when adding a new server.

---

### New Tool

1. Create an Apex class implementing `IMCPTool`:

```apex
public class MyNewTool implements IMCPTool {
    public String getName()        { return 'my_tool'; }
    public String getTitle()       { return 'My Tool'; }
    public String getDescription() { return 'Does something useful'; }
    public String getServerName()  { return 'PCMetrics'; }

    public Map<String, Object> getInputSchema() {
        return new Map<String, Object>{
            'type' => 'object',
            'properties' => new Map<String, Object>{
                'param1' => new Map<String, Object>{ 'type' => 'string', 'description' => 'A parameter' }
            },
            'required' => new List<String>{ 'param1' }
        };
    }

    public Map<String, Object> call(Map<String, Object> arguments) {
        String param1 = (String) arguments.get('param1');
        return new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => 'Result: ' + param1 }
            },
            'isError' => false
        };
    }
}
```

2. Add a Custom Metadata record in `force-app/main/default/customMetadata/MCP_Tool_Registry.MyNewTool.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema">
    <label>My New Tool</label>
    <protected>false</protected>
    <values>
        <field>Apex_Class_Name__c</field>
        <value xsi:type="xsd:string">MyNewTool</value>
    </values>
</CustomMetadata>
```

3. Deploy both files. The controller picks it up automatically.

### New Resource

Same pattern — implement `IMCPResource`, add an `MCP_Resource_Registry__mdt` record pointing to the class name.

### New Prompt

Same pattern — implement `IMCPPrompt`, add an `MCP_Prompt_Registry__mdt` record pointing to the class name.

---

## Connecting to Claude Code

The server is connected to Claude Code via a stdio proxy (`scripts/mcp-proxy.js`) that translates Claude Code's newline-delimited JSON-RPC stdio transport into HTTP POSTs to the Apex endpoint.

Authentication uses OAuth2 Authorization Code + PKCE via an External Client App (ECA) deployed in the org. On first run, the proxy opens a browser authorization URL and saves a refresh token to `~/.sfdc-pcmetrics-tokens.json`. Subsequent connections use the stored refresh token silently.

**Claude Code config** (`~/.claude.json`, under the project entry):

```json
"pcmetrics": {
  "type": "stdio",
  "command": "node",
  "args": ["/path/to/apex-mcp/scripts/mcp-proxy.js"],
  "env": {
    "SFDC_INSTANCE_URL": "https://<instance>.salesforce.com",
    "SFDC_TARGET_ORG": "apex-mcp-scratch",
    "SFDC_MCP_PATH": "/services/apexrest/pcmetrics/mcp/",
    "SFDC_CLIENT_ID": "<eca-consumer-key>"
  }
}
```

**First-time auth** (run once in terminal):

```bash
SFDC_CLIENT_ID=<consumer-key> \
SFDC_INSTANCE_URL=https://<instance>.salesforce.com \
node scripts/mcp-proxy.js auth
```

---

## Current Limitations

**The server is stateless.** Every JSON-RPC POST is handled independently — there is no session tracking, no `MCP-Session-Id` header, and no server-side state between requests. The MCP spec (2025-11-25) defines a session lifecycle (initialize → notifications/initialized → subsequent requests with a session ID header), but this implementation accepts all requests without enforcing session state.

This works correctly with Claude Code today because the client manages the logical session on its end. Future work will add Phase 1 session support via AES-256 encrypted session tokens in the `MCP-Session-Id` response header (zero SOQL/DML, state lives inside the token itself), with a Phase 2 option to swap to `Cache.Org` (Platform Cache) for server-side session control.
