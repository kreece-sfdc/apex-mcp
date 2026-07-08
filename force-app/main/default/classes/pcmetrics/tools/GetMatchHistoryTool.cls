public class GetMatchHistoryTool implements IMCPTool {

    public String getName()        { return 'get_match_history'; }
    public String getTitle()       { return 'Get Match History'; }
    public String getDescription() { return 'Returns the current Valorant match history log'; }
    public String getServerName()  { return 'PCMetrics'; }

    public Map<String, Object> getInputSchema() {
        return new Map<String, Object>{
            'type'                 => 'object',
            'additionalProperties' => false
        };
    }

    public Map<String, Object> call(Map<String, Object> arguments) {
        MatchHistoryResource res = new MatchHistoryResource();
        return new Map<String, Object>{
            'content' => new List<Object>{
                new Map<String, Object>{ 'type' => 'text', 'text' => res.getText() }
            },
            'isError' => false
        };
    }
}
