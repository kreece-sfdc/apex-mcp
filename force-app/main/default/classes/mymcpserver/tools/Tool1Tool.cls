public class Tool1Tool implements IMCPTool {

    public String getName()        { return 'tool1'; }
    public String getTitle()       { return 'Tool 1'; }
    public String getDescription() { return 'Tool 1 Description'; }
    public String getServerName()  { return 'MyMCPServer'; }

    public Map<String, Object> getInputSchema() {
        return new Map<String, Object>{
            'type'                 => 'object',
            'additionalProperties' => false,
            'properties' => new Map<String, Object>{
                'name' => new Map<String, Object>{ 'type' => 'string', 'description' => 'the name of it' }
            },
            'required' => new List<Object>{ 'name' }
        };
    }

    public Map<String, Object> call(Map<String, Object> arguments) {
        return new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => '{"status":"ok","tool":"tool1","arguments":' + JSON.serialize(arguments) + '}' }
            },
            'isError' => false
        };
    }
}
