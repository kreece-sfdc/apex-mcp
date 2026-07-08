@RestResource(urlMapping='/mcp')
global class MCPServerController {

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

        if (method == 'servers/list') {
            handleServersList(res, rpcId);
        } else {
            MCPUtil.writeError(res, rpcId, -32601,
                'Method not found: ' + method + '. Use POST /services/apexrest/{serverUri} for resource operations.');
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
                'message' => 'Use POST with a JSON-RPC body. Supported method: servers/list'
            }
        }));
    }

    private static void handleServersList(RestResponse res, Object rpcId) {
        List<Map<String, Object>> servers = new List<Map<String, Object>>();

        for (MCP_Server_Registry__mdt record : [
            SELECT Apex_Class_Name__c FROM MCP_Server_Registry__mdt ORDER BY Label
        ]) {
            try {
                Type t = Type.forName(record.Apex_Class_Name__c);
                if (t == null) continue;
                IMCPServer instance = (IMCPServer) t.newInstance();
                servers.add(new Map<String, Object>{
                    'uri'         => instance.getUri(),
                    'name'        => instance.getName(),
                    'title'       => instance.getTitle(),
                    'description' => instance.getDescription(),
                    'mimeType'    => instance.getMimeType()
                });
            } catch (Exception e) {
                continue;
            }
        }

        MCPUtil.writeSuccess(res, rpcId, new Map<String, Object>{ 'servers' => servers });
    }
}
