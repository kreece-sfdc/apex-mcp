@RestResource(urlMapping='/mymcpserver/mcp/*')
global class MyMCPServerMCPController {

    private static final String SERVER_NAME = 'MyMCPServer';

    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        if (!MCPUtil.validateProtocolVersion(req, res)) return;

        Map<String, Object> body = MCPUtil.parseBody(req, res);
        if (body == null) return;

        Object rpcId  = body.get('id');
        String method = (String) body.get('method');

        if (String.isBlank(method)) {
            MCPUtil.writeError(res, rpcId, -32600, 'Invalid Request: missing method');
            return;
        }

        if (method.startsWith('notifications/')) {
            res.statusCode = 202;
            return;
        }

        if (rpcId == null) {
            MCPUtil.writeError(res, null, -32600, 'Invalid Request: id required for requests');
            return;
        }

        Map<String, Object> params = body.containsKey('params')
            ? (Map<String, Object>) body.get('params')
            : new Map<String, Object>();

        if (method == 'initialize') {
            handleInitialize(res, rpcId);
        } else if (method == 'resources/list') {
            handleResourcesList(res, rpcId);
        } else if (method == 'resources/read') {
            Boolean raw = params.get('raw') == true;
            if (raw) {
                handleResourcesReadRaw(res, params);
            } else {
                handleResourcesRead(res, rpcId, params);
            }
        } else if (method == 'prompts/list') {
            handlePromptsList(res, rpcId);
        } else if (method == 'prompts/get') {
            handlePromptsGet(res, rpcId, params);
        } else if (method == 'tools/list') {
            handleToolsList(res, rpcId);
        } else if (method == 'tools/call') {
            handleToolsCall(res, rpcId, params);
        } else {
            MCPUtil.writeError(res, rpcId, -32601, 'Method not found: ' + method);
        }
    }

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        res.statusCode = 405;
        res.addHeader('Allow', 'POST');
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id'      => null,
            'error'   => new Map<String, Object>{
                'code'    => -32600,
                'message' => 'Use POST /services/apexrest/mymcpserver/mcp/ with a JSON-RPC body'
            }
        }));
    }

    private static void handleInitialize(RestResponse res, Object rpcId) {
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{
            'protocolVersion' => MCPUtil.SUPPORTED_PROTOCOL_VERSION,
            'capabilities'    => new Map<String, Object>{
                'resources' => new Map<String, Object>(),
                'prompts'   => new Map<String, Object>(),
                'tools'     => new Map<String, Object>()
            },
            'serverInfo' => new Map<String, Object>{
                'name'    => 'MyMCPServer',
                'version' => '1.0.0'
            }
        });
    }

    private static void handleResourcesList(RestResponse res, Object rpcId) {
        List<Map<String, Object>> resources = new List<Map<String, Object>>();
        for (MCP_Resource_Registry__mdt record : [
            SELECT Apex_Class_Name__c FROM MCP_Resource_Registry__mdt ORDER BY Label
        ]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPResource instance = (IMCPResource) t.newInstance();
                if (!SERVER_NAME.equals(instance.getServerName())) continue;
                resources.add(new Map<String, Object>{
                    'uri'         => instance.getUri(),
                    'name'        => instance.getName(),
                    'title'       => instance.getTitle(),
                    'description' => instance.getDescription(),
                    'mimeType'    => instance.getMimeType()
                });
            } catch (Exception e) { continue; }
        }
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{ 'resources' => resources });
    }

    private static void handleResourcesRead(RestResponse res, Object rpcId, Map<String, Object> params) {
        String uri = (String) params.get('uri');
        if (String.isBlank(uri)) {
            MCPUtil.writeError(res, rpcId, -32602, 'Missing required param: uri');
            return;
        }
        IMCPResource instance = findResource(uri);
        if (instance == null) {
            MCPUtil.writeError(res, rpcId, -32002, 'Resource not found: ' + uri);
            return;
        }
        Map<String, Object> content = new Map<String, Object>{
            'uri' => instance.getUri(), 'mimeType' => instance.getMimeType()
        };
        if (instance.getText() != null) { content.put('text', instance.getText()); }
        else if (instance.getBlob() != null) { content.put('blob', instance.getBlob()); }
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{ 'contents' => new List<Object>{ content } });
    }

    private static void handleResourcesReadRaw(RestResponse res, Map<String, Object> params) {
        String uri = (String) params.get('uri');
        if (String.isBlank(uri)) {
            res.statusCode = 400;
            res.addHeader('Content-Type', 'text/plain');
            res.responseBody = Blob.valueOf('Missing required param: uri');
            return;
        }
        IMCPResource instance = findResource(uri);
        if (instance == null) {
            res.statusCode = 404;
            res.addHeader('Content-Type', 'text/plain');
            res.responseBody = Blob.valueOf('Resource not found: ' + uri);
            return;
        }
        res.statusCode = 200;
        res.addHeader('Content-Type', instance.getMimeType());
        if (instance.getText() != null) { res.responseBody = Blob.valueOf(instance.getText()); }
        else if (instance.getBlob() != null) { res.responseBody = EncodingUtil.base64Decode(instance.getBlob()); }
        else { res.responseBody = Blob.valueOf(''); }
    }

    private static void handlePromptsList(RestResponse res, Object rpcId) {
        List<Map<String, Object>> prompts = new List<Map<String, Object>>();
        for (MCP_Prompt_Registry__mdt record : [
            SELECT Apex_Class_Name__c FROM MCP_Prompt_Registry__mdt ORDER BY Label
        ]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPPrompt instance = (IMCPPrompt) t.newInstance();
                if (!SERVER_NAME.equals(instance.getServerName())) continue;
                prompts.add(new Map<String, Object>{
                    'name'        => instance.getName(),
                    'title'       => instance.getTitle(),
                    'description' => instance.getDescription(),
                    'arguments'   => instance.getArguments()
                });
            } catch (Exception e) { continue; }
        }
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{ 'prompts' => prompts });
    }

    private static void handlePromptsGet(RestResponse res, Object rpcId, Map<String, Object> params) {
        String name = (String) params.get('name');
        if (String.isBlank(name)) {
            MCPUtil.writeError(res, rpcId, -32602, 'Missing required param: name');
            return;
        }
        IMCPPrompt instance = null;
        for (MCP_Prompt_Registry__mdt record : [SELECT Apex_Class_Name__c FROM MCP_Prompt_Registry__mdt]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPPrompt candidate = (IMCPPrompt) t.newInstance();
                if (!SERVER_NAME.equals(candidate.getServerName())) continue;
                if (name.equals(candidate.getName())) { instance = candidate; break; }
            } catch (Exception e) { continue; }
        }
        if (instance == null) {
            MCPUtil.writeError(res, rpcId, -32602, 'Unknown prompt: ' + name);
            return;
        }
        Map<String, String> resolvedArgs = new Map<String, String>();
        Map<String, Object> rawArgs = params.containsKey('arguments')
            ? (Map<String, Object>) params.get('arguments')
            : new Map<String, Object>();
        for (Map<String, Object> argDef : instance.getArguments()) {
            String argName = (String) argDef.get('name');
            Boolean required = argDef.get('required') == true;
            if (required && !rawArgs.containsKey(argName)) {
                MCPUtil.writeError(res, rpcId, -32602, 'Missing required argument: ' + argName);
                return;
            }
            if (rawArgs.containsKey(argName)) { resolvedArgs.put(argName, (String) rawArgs.get(argName)); }
        }
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{
            'description' => instance.getDescription(),
            'messages'    => instance.getMessages(resolvedArgs)
        });
    }

    private static void handleToolsList(RestResponse res, Object rpcId) {
        List<Map<String, Object>> tools = new List<Map<String, Object>>();
        for (MCP_Tool_Registry__mdt record : [
            SELECT Apex_Class_Name__c FROM MCP_Tool_Registry__mdt ORDER BY Label
        ]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPTool instance = (IMCPTool) t.newInstance();
                if (!SERVER_NAME.equals(instance.getServerName())) continue;
                tools.add(new Map<String, Object>{
                    'name'        => instance.getName(),
                    'title'       => instance.getTitle(),
                    'description' => instance.getDescription(),
                    'inputSchema' => instance.getInputSchema()
                });
            } catch (Exception e) { continue; }
        }
        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{ 'tools' => tools });
    }

    private static void handleToolsCall(RestResponse res, Object rpcId, Map<String, Object> params) {
        String name = (String) params.get('name');
        if (String.isBlank(name)) {
            MCPUtil.writeError(res, rpcId, -32602, 'Missing required param: name');
            return;
        }
        IMCPTool instance = null;
        for (MCP_Tool_Registry__mdt record : [SELECT Apex_Class_Name__c FROM MCP_Tool_Registry__mdt]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPTool candidate = (IMCPTool) t.newInstance();
                if (!SERVER_NAME.equals(candidate.getServerName())) continue;
                if (name.equals(candidate.getName())) { instance = candidate; break; }
            } catch (Exception e) { continue; }
        }
        if (instance == null) {
            MCPUtil.writeError(res, rpcId, -32602, 'Unknown tool: ' + name);
            return;
        }
        Map<String, Object> arguments = params.containsKey('arguments')
            ? (Map<String, Object>) params.get('arguments')
            : new Map<String, Object>();

        Map<String, Object> schema = instance.getInputSchema();
        List<Object> required = schema.containsKey('required')
            ? (List<Object>) schema.get('required')
            : new List<Object>();
        for (Object req : required) {
            String argName = (String) req;
            if (!arguments.containsKey(argName)) {
                MCPUtil.writeError(res, rpcId, -32602, 'Missing required argument: ' + argName);
                return;
            }
        }

        try {
            MCPUtil.writeSuccess(res, rpcId, instance.call(arguments));
        } catch (Exception e) {
            MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{
                'content' => new List<Object>{
                    new Map<String, Object>{ 'type' => 'text', 'text' => e.getMessage() }
                },
                'isError' => true
            });
        }
    }

    private static IMCPResource findResource(String uri) {
        for (MCP_Resource_Registry__mdt record : [SELECT Apex_Class_Name__c FROM MCP_Resource_Registry__mdt]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPResource instance = (IMCPResource) t.newInstance();
                if (!SERVER_NAME.equals(instance.getServerName())) continue;
                if (uri.equals(instance.getUri())) return instance;
            } catch (Exception e) { continue; }
        }
        return null;
    }
}
