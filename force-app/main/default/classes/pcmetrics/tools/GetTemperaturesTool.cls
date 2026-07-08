public class GetTemperaturesTool implements IMCPTool {

    public String getName()        { return 'get_temperatures'; }
    public String getTitle()       { return 'Get Hardware Temperatures'; }
    public String getDescription() { return 'Returns current CPU and GPU temperature and load data'; }
    public String getServerName()  { return 'PCMetrics'; }

    public Map<String, Object> getInputSchema() {
        return new Map<String, Object>{
            'type'                 => 'object',
            'additionalProperties' => false
        };
    }

    public Map<String, Object> call(Map<String, Object> arguments) {
        GPUCPUTempsResource res = new GPUCPUTempsResource();
        return new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => res.getText() }
            },
            'isError' => false
        };
    }
}
