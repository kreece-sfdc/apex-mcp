public class MCPUtil {

    public static final String SUPPORTED_PROTOCOL_VERSION = '2025-11-25';
    private static final Set<String> ACCEPTED_PROTOCOL_VERSIONS = new Set<String>{
        '2025-11-25',
        '2025-06-18',
        '2025-03-26',
        '2024-11-05'
    };

    public static Boolean validateProtocolVersion(RestRequest req, RestResponse res) {
        String clientVersion = req.headers.get('mcp-protocol-version');
        // The client may send a comma-separated list (e.g. "2025-11-25, 2025-11-25") — check only the first value.
        if (!String.isBlank(clientVersion) && clientVersion.contains(',')) {
            clientVersion = clientVersion.substringBefore(',').trim();
        }
        if (String.isBlank(clientVersion) || ACCEPTED_PROTOCOL_VERSIONS.contains(clientVersion)) {
            return true;
        }
        res.statusCode = 400;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id'      => null,
            'error'   => new Map<String, Object>{
                'code'    => -32600,
                'message' => 'Unsupported protocol version',
                'data'    => new Map<String, Object>{
                    'supported' => new List<String>(ACCEPTED_PROTOCOL_VERSIONS),
                    'requested' => clientVersion
                }
            }
        }));
        return false;
    }

    public static Map<String, Object> parseBody(RestRequest req, RestResponse res) {
        // Salesforce decodes application/x-www-form-urlencoded bodies into req.params,
        // leaving requestBody empty. Reconstruct the JSON string from params in that case.
        String raw;
        if (req.requestBody != null && req.requestBody.size() > 0) {
            raw = req.requestBody.toString();
        } else if (!req.params.isEmpty()) {
            // The MCP SDK sends JSON without Content-Type, so Salesforce form-decodes it.
            // The JSON string ends up URL-encoded as the first (and only) param key.
            raw = req.params.keySet().iterator().next();
        }
        if (String.isBlank(raw)) {
            res.statusCode = 202;
            return null;
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            res.statusCode = 400;
            res.addHeader('Content-Type', 'application/json');
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'jsonrpc' => '2.0',
                'id'      => null,
                'error'   => new Map<String, Object>{ 'code' => -32700, 'message' => 'Parse error' }
            }));
            return null;
        }
    }

    public static void writeSuccess(RestResponse res, Object rpcId, Map<String, Object> result) {
        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.addHeader('MCP-Protocol-Version', SUPPORTED_PROTOCOL_VERSION);
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id'      => rpcId,
            'result'  => result
        }));
    }

    public static void writeError(RestResponse res, Object rpcId, Integer code, String message) {
        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id'      => rpcId,
            'error'   => new Map<String, Object>{ 'code' => code, 'message' => message }
        }));
    }
}