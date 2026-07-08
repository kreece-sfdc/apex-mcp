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

### New MCP Server

To expose a second MCP server (e.g. for a different domain):

1. Create a new `@RestResource` Apex controller at a new URL (e.g. `/services/apexrest/myserver/mcp/`)
2. Set a unique `SERVER_NAME` constant in the controller (e.g. `'MyServer'`)
3. Implement tools/resources/prompts with `getServerName()` returning `'MyServer'` — they will be filtered to only appear on that server's endpoints
4. Add CMT records pointing to the new classes

The interfaces, CMT types, and `MCPUtil` are shared across all servers — no changes needed to the framework.

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
